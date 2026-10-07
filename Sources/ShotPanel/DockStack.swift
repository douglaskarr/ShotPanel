import Darwin
import Foundation

/// Puts a ShotPanel stack in the Dock, immediately after Downloads and
/// therefore directly left of the Trash, while the group has screenshots.
///
/// The stack is a folder of hard links to those files. A hard link is a
/// second name for the same file, so the Dock shows the real image. Dragging
/// one to the Trash only moves that name. This watches for that and moves
/// the original to the Trash as well. The Dock is restarted only when the
/// tile is added, removed, or pointed at a different folder.
@MainActor
enum DockStack {
    private static let domain = "com.apple.dock" as CFString
    private static let othersKey = "persistent-others" as CFString
    private static let modKey = "mod-count" as CFString
    private static let label = "ShotPanel"

    private struct Entry {
        var source: String
        var inode: UInt64
    }

    private static var manifest: [String: Entry] = [:]
    private static var manifestLoaded = false
    private static var source: DispatchSourceFileSystemObject?
    private static var sourceFD: Int32 = -1
    private static var pending: DispatchWorkItem?
    private static var updating = false
    /// Set when the folder changes while a sync is writing links.
    private static var missedChange = false

    /// Shelf refreshes after a Dock drag has moved an original to the Trash.
    static var onFilesTrashed: (() -> Void)?

    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShotPanel", isDirectory: true)
    }

    static var stackFolder: URL {
        support.appendingPathComponent("Stack", isDirectory: true)
    }

    /// Matches the Dock stack to `files`. An empty list removes the tile.
    static func sync(files: [URL]) {
        loadManifest()
        try? FileManager.default.createDirectory(at: stackFolder, withIntermediateDirectories: true)
        let savedSearch = support.appendingPathComponent("ShotPanel.savedSearch")
        if FileManager.default.fileExists(atPath: savedSearch.path) {
            try? FileManager.default.removeItem(at: savedSearch)
        }
        updating = true
        var current = files
        let trashed = reclaimTrashedLinks(from: &current)
        writeLinks(for: current)
        updating = false
        ensureWatching()
        updateTile(visible: !current.isEmpty)
        if trashed > 0 {
            DispatchQueue.main.async { onFilesTrashed?() }
        }
        if missedChange {
            missedChange = false
            DispatchQueue.main.async { onFilesTrashed?() }
        }
    }

    /// A link that left the stack and is sitting in the Trash takes the
    /// original with it. A link that left any other way is recreated, so a
    /// drop on a folder does not destroy the screenshot.
    private static func reclaimTrashedLinks(from files: inout [URL]) -> Int {
        let present = Set(fileNames(in: stackFolder))
        var trashed = 0
        for (name, entry) in manifest where !present.contains(name) {
            manifest.removeValue(forKey: name)
            guard entry.inode != 0, FileManager.default.fileExists(atPath: entry.source) else { continue }
            guard inodeIsInTrash(entry.inode) else { continue }
            let source = URL(fileURLWithPath: entry.source)
            trash(source)
            guard !FileManager.default.fileExists(atPath: source.path) else { continue }
            files.removeAll { $0.path == source.path }
            trashed += 1
        }
        return trashed
    }

    private static func writeLinks(for files: [URL]) {
        var keep: [String: Entry] = [:]
        for url in files {
            let name = url.lastPathComponent
            guard name != ".DS_Store", !name.isEmpty else { continue }
            let dest = stackFolder.appendingPathComponent(name)
            if let existing = inode(dest), let source = inode(url), existing == source {
                keep[name] = Entry(source: url.path, inode: existing)
                continue
            }
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
            guard hardLink(from: url, to: dest), let linked = inode(dest) else {
                NSLog("ShotPanel: could not link \(url.path) into the Dock stack")
                continue
            }
            keep[name] = Entry(source: url.path, inode: linked)
        }
        for (name, _) in manifest where keep[name] == nil {
            let dest = stackFolder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
        }
        manifest = keep
        saveManifest()
    }

    private static func ensureWatching() {
        guard source == nil else { return }
        let fd = open(stackFolder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        sourceFD = fd
        let watch = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        watch.setEventHandler {
            if updating {
                missedChange = true
                return
            }
            pending?.cancel()
            let work = DispatchWorkItem {
                // A later sync trashes the original. Refreshing the shelf
                // builds that file list and calls sync.
                onFilesTrashed?()
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
        watch.setCancelHandler {
            if sourceFD >= 0 { close(sourceFD); sourceFD = -1 }
        }
        watch.resume()
        source = watch
    }

    private static func updateTile(visible: Bool) {
        CFPreferencesAppSynchronize(domain)
        guard let existing = CFPreferencesCopyAppValue(othersKey, domain) as? [NSDictionary] else {
            NSLog("ShotPanel: Dock preferences have no folder list; leaving the Dock alone")
            return
        }
        let ours = existing.filter(isOurs)
        let kept = existing.filter { !isOurs($0) }
        guard kept.count == existing.count - ours.count else { return }

        let target = URL(fileURLWithPath: stackFolder.path, isDirectory: true)
        if !visible {
            guard !ours.isEmpty else { return }
            commit(kept)
            return
        }
        if ours.count == 1, let only = ours.first, tilePath(only) == target.path, index(of: only, in: existing) == insertIndex(in: kept) {
            return
        }
        var next = kept
        next.insert(makeTile(target), at: insertIndex(in: kept))
        commit(next)
    }

    /// The slot directly right of Downloads. With only Downloads there, that
    /// is the slot directly left of the Trash.
    private static func insertIndex(in tiles: [NSDictionary]) -> Int {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].standardizedFileURL.path
        for (index, tile) in tiles.enumerated() where tilePath(tile) == downloads {
            return index + 1
        }
        return tiles.count
    }

    private static func index(of tile: NSDictionary, in tiles: [NSDictionary]) -> Int? {
        guard let path = tilePath(tile) else { return nil }
        return tiles.firstIndex { tilePath($0) == path }
    }

    private static func makeTile(_ folder: URL) -> NSDictionary {
        let fileData = NSDictionary(dictionary: [
            "_CFURLString": folder.absoluteString,
            "_CFURLStringType": 15,
        ])
        let tileData = NSDictionary(dictionary: [
            "arrangement": 3,
            "displayas": 1,
            "file-data": fileData,
            "file-label": label,
            "file-type": 2,
            "is-beta": false,
            "preferreditemsize": -1,
            "showas": 2,
        ])
        return NSDictionary(dictionary: [
            "tile-data": tileData,
            "tile-type": "directory-tile",
        ])
    }

    private static func commit(_ tiles: [NSDictionary]) {
        backupDockPreferences()
        CFPreferencesSetAppValue(othersKey, tiles as CFArray, domain)
        let mod = (CFPreferencesCopyAppValue(modKey, domain) as? NSNumber)?.intValue ?? 0
        CFPreferencesSetAppValue(modKey, NSNumber(value: mod + 1), domain)
        guard CFPreferencesAppSynchronize(domain) else {
            NSLog("ShotPanel: could not save the Dock stack")
            return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        proc.arguments = ["Dock"]
        do {
            try proc.run()
        } catch {
            NSLog("ShotPanel: could not refresh the Dock: \(error.localizedDescription)")
        }
    }

    private static func backupDockPreferences() {
        let backup = support.appendingPathComponent("com.apple.dock.before-shotpanel.plist")
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        let live = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.dock.plist")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: live, to: backup)
    }

    private static func isOurs(_ tile: NSDictionary) -> Bool {
        guard let path = tilePath(tile) else { return false }
        let root = support.standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }

    private static func tilePath(_ tile: NSDictionary) -> String? {
        guard let data = tile["tile-data"] as? NSDictionary,
              let file = data["file-data"] as? NSDictionary,
              let raw = file["_CFURLString"] as? String,
              let url = URL(string: raw) else { return nil }
        return url.standardizedFileURL.path
    }

    private static func fileNames(in folder: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }

    private static func inode(_ url: URL) -> UInt64? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let number = try? FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? NSNumber else {
            return nil
        }
        return number.uint64Value
    }

    private static func inodeIsInTrash(_ inode: UInt64) -> Bool {
        let trashes = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask)
        for trash in trashes {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: trash.path) else { continue }
            for name in names {
                if self.inode(trash.appendingPathComponent(name)) == inode { return true }
            }
        }
        return false
    }

    private static func hardLink(from source: URL, to dest: URL) -> Bool {
        source.withUnsafeFileSystemRepresentation { src in
            dest.withUnsafeFileSystemRepresentation { dst in
                guard let src, let dst else { return false }
                return link(src, dst) == 0
            }
        }
    }

    private static func trash(_ url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            NSLog("ShotPanel: could not trash \(url.path): \(error.localizedDescription)")
        }
    }

    private static var manifestURL: URL {
        support.appendingPathComponent("stack-manifest.plist")
    }

    private static func loadManifest() {
        guard !manifestLoaded else { return }
        manifestLoaded = true
        guard let data = try? Data(contentsOf: manifestURL),
              let raw = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: Any]] else {
            return
        }
        for (name, entry) in raw {
            guard let source = entry["source"] as? String else { continue }
            let inode = (entry["inode"] as? NSNumber)?.uint64Value ?? 0
            manifest[name] = Entry(source: source, inode: inode)
        }
    }

    private static func saveManifest() {
        var raw: [String: [String: Any]] = [:]
        for (name, entry) in manifest {
            raw[name] = ["source": entry.source, "inode": NSNumber(value: entry.inode)]
        }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: raw, format: .binary, options: 0) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
