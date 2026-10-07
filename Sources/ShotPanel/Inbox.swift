import Foundation

/// Where new screenshots are written while ShotPanel is running.
///
/// This is the same pair of settings as Options in Cmd-Shift-5: the save
/// folder, and the floating thumbnail. macOS 26 and earlier read `location`.
/// macOS 27 reads `location-screenshot` and ignores the old key, so both are
/// written. The previous values are put back when the option is turned off
/// or the app quits, so a closed ShotPanel does not swallow later shots.
enum Inbox {
    private static let domain = "com.apple.screencapture" as CFString
    private static let locationKey = "location" as CFString
    private static let screenshotLocationKey = "location-screenshot" as CFString
    private static let thumbnailKey = "show-thumbnail" as CFString

    private static let enabledKey = "shotpanel.inboxEnabled"
    private static let offeredKey = "shotpanel.inboxOffered"
    private static let savedKey = "shotpanel.inboxSavedSettings"

    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ShotPanel/Screenshots", isDirectory: true)
    }()

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var wasOffered: Bool {
        get { UserDefaults.standard.bool(forKey: offeredKey) }
        set { UserDefaults.standard.set(newValue, forKey: offeredKey) }
    }

    /// True when either screenshot-location key already points at our folder.
    static var isApplied: Bool {
        let ours = folder.standardizedFileURL
        for key in [screenshotLocationKey, locationKey] {
            guard let raw = CFPreferencesCopyAppValue(key, domain) as? String, !raw.isEmpty else { continue }
            let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL
            if url == ours { return true }
        }
        return false
    }

    /// The folder macOS is saving screenshots to right now, or the Desktop.
    static func currentSaveFolder() -> URL {
        CFPreferencesAppSynchronize(domain)
        let raw = (CFPreferencesCopyAppValue(screenshotLocationKey, domain) as? String)
            ?? (CFPreferencesCopyAppValue(locationKey, domain) as? String)
        if let raw, !raw.isEmpty {
            let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// Moves automatic screenshots from the folder macOS was using into the
    /// panel folder. Other files stay where they are. A same-volume move keeps
    /// the file's identity, so an existing Dock stack link still points at it.
    @MainActor
    static func adoptExistingScreenshots(from source: URL) {
        let origin = source.resolvingSymlinksInPath().standardizedFileURL
        let destRoot = folder.resolvingSymlinksInPath().standardizedFileURL
        guard origin.path != destRoot.path else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let watcher = ScreenshotWatcher(folder: source)
        for url in watcher.files() where watcher.isCandidate(url) {
            let dest = folder.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) { continue }
            do {
                try FileManager.default.moveItem(at: url, to: dest)
            } catch {
                NSLog("ShotPanel: could not move \(url.lastPathComponent) into the panel: \(error)")
            }
        }
    }

    static func apply() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A crash can leave the keys applied. Do not record our own folder as
        // the user's previous location.
        if !isApplied {
            var saved: [String: Any] = [:]
            if let value = CFPreferencesCopyAppValue(locationKey, domain) as? String {
                saved["location"] = value
            }
            if let value = CFPreferencesCopyAppValue(screenshotLocationKey, domain) as? String {
                saved["locationScreenshot"] = value
            }
            if let value = CFPreferencesCopyAppValue(thumbnailKey, domain) as? Bool {
                saved["thumbnail"] = value
            }
            UserDefaults.standard.set(saved, forKey: savedKey)
        }
        write(locationKey, folder.path)
        write(screenshotLocationKey, folder.path)
        write(thumbnailKey, false)
    }

    static func restore() {
        guard isApplied else {
            UserDefaults.standard.removeObject(forKey: savedKey)
            return
        }
        let saved = UserDefaults.standard.dictionary(forKey: savedKey)
        write(locationKey, saved?["location"])
        write(screenshotLocationKey, saved?["locationScreenshot"])
        write(thumbnailKey, saved?["thumbnail"])
        UserDefaults.standard.removeObject(forKey: savedKey)
    }

    /// A nil value removes the key, which returns it to the macOS default.
    private static func write(_ key: CFString, _ value: Any?) {
        CFPreferencesSetAppValue(key, value as CFPropertyList?, domain)
        CFPreferencesAppSynchronize(domain)
    }
}
