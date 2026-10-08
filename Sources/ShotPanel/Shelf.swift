import AppKit
import SwiftUI

struct Shot: Identifiable, Equatable {
    let path: String
    let url: URL
    let created: Date
    let pixelSize: CGSize
    var image: NSImage?
    var attempts: Int = 0
    /// Longest edge, in pixels, of the decoded thumbnail. Zero means none yet.
    var pixelBudget: CGFloat = 0
    var id: String { path }

    static func == (lhs: Shot, rhs: Shot) -> Bool {
        lhs.path == rhs.path
            && lhs.created == rhs.created
            && (lhs.image != nil) == (rhs.image != nil)
            && lhs.attempts == rhs.attempts
    }
}

/// The screenshots gathered in the corner widget.
@MainActor
final class Shelf: ObservableObject {
    @Published private(set) var shots: [Shot] = []
    @Published var expanded = false
    @Published private(set) var copiedPath: String?
    /// The shot whose name, time, and size are shown in the bottom bar.
    @Published private(set) var selectedPath: String?
    /// Delete was clicked on this shot. Yes and Cancel sit on the image.
    @Published private(set) var confirmingPath: String?
    /// Delete all was clicked. Yes and Cancel sit in the bottom bar.
    @Published private(set) var confirmingDeleteAll = false
    @Published private(set) var arrivedPath: String?
    /// Zero is the newest shot. Higher indexes are older.
    /// How far the row has slid. Zero shows the newest shot at the start.
    @Published private(set) var stripOffset: CGFloat = 0
    /// Horizontal is a row. Vertical stacks the same shots and swaps the window.
    @Published private(set) var axis = CarouselFit.Axis.horizontal
    @Published private(set) var metrics = Metrics()
    @Published private(set) var inboxOn = false
    /// True when new screenshots are still saved on the Desktop.
    @Published private(set) var watchesDesktop = true
    @Published private(set) var totalCount = 0
    /// The pointer is over the widget, including during screen sharing.
    @Published private(set) var pointerInside = false
    /// True after a click, so scroll arrows stay up without a trackpad swipe.
    @Published private(set) var windowIsKey = false
    /// The screenshot folder could not be listed. macOS is waiting on access.
    @Published private(set) var folderBlocked = false

    /// Every qualifying file, including ones past the display cap.
    private(set) var allURLs: [URL] = []

    private(set) var dragActive = false
    private(set) var repositioning = false
    var onLayout: (() -> Void)?
    var onNewShot: (() -> Void)?
    var onMinimize: (() -> Void)?
    var onReposition: ((NSPoint) -> Void)?
    var onRepositionEnd: (() -> Void)?
    var onResize: ((NSRect) -> Void)?
    var onResizeEnd: (() -> Void)?

    private var watcher: ScreenshotWatcher?
    private var seen = Set<String>()
    private var primed = false
    private var collapseTask: DispatchWorkItem?
    private var loadToken = 0
    private var copyToken = 0
    private var arriveToken = 0
    private var draggingPath: String?
    private var deferredRefresh = false
    private var panelSize: NSSize?
    /// The size the user left for each orientation, so switching back restores it.
    private var sizeForAxis: [String: NSSize] = [:]
    /// Saves the panel size after an orientation change. Preview leaves this unset.
    var onRememberSize: ((NSSize) -> Void)?
    private let displayCap = 40
    private static let axisKey = "shotpanel.listAxis"

    init() {
        if UserDefaults.standard.string(forKey: Self.axisKey) == CarouselFit.Axis.vertical.rawValue {
            axis = .vertical
        }
    }

    var currentShot: Shot? {
        guard !shots.isEmpty else { return nil }
        let page = carouselPage
        if let index = page.settled().first?.index ?? page.items.first?.index,
           shots.indices.contains(index) {
            return shots[index]
        }
        return shots[0]
    }

    /// The full row, shifted by the pointer, clipped by the panel.
    var carouselPage: CarouselFit.Page {
        CarouselFit.page(shots: shots, offset: stripOffset, size: metrics.hero, axis: axis)
    }

    /// "2–4 of 7", or "2 of 7" when a single shot fills the row.
    var pageLabel: String {
        let shownItems = carouselPage.settled()
        guard let first = shownItems.first, let last = shownItems.last, shots.count > 1 else { return "" }
        let shown = totalCount > shots.count ? "\(shots.count)+" : "\(shots.count)"
        if first.index == last.index { return "\(first.index + 1) of \(shown)" }
        return "\(first.index + 1)–\(last.index + 1) of \(shown)"
    }

    /// Loads files into the widget without touching screenshot settings.
    /// Used by the `--preview` render path.
    func loadPreview(_ urls: [URL]) {
        watcher?.stop()
        watcher = nil
        primed = true
        let images = urls.filter { ["png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "webp"].contains($0.pathExtension.lowercased()) }
        allURLs = images.sorted { created($0) > created($1) }
        totalCount = allURLs.count
        shots = allURLs.map { url in
            Shot(
                path: url.path,
                url: url,
                created: created(url),
                pixelSize: ImageThumb.pixelSize(url: url),
                image: ImageThumb.make(url: url, maxPixel: 900)
            )
        }
        if shots.isEmpty { expanded = false }
        selectedPath = nil
        confirmingPath = nil
        confirmingDeleteAll = false
        stripOffset = 0
    }

    /// Remembers a size the user dragged to, and scales the photo to fit it.
    func setPanelSize(_ size: NSSize) {
        panelSize = size
        sizeForAxis[axis.rawValue] = size
        let next = metrics.adopted(panel: size, axis: axis)
        if next != metrics { metrics = next }
        clampOffset()
        noteVisibility()
    }

    /// Scales the photo to the window without changing the saved size.
    func fitDisplay(to size: NSSize) {
        guard !shots.isEmpty else { return }
        let next = metrics.adopted(panel: size, axis: axis)
        if next != metrics { metrics = next }
        clampOffset()
        noteVisibility()
    }

    func boot() {
        inboxOn = Inbox.isEnabled
        if inboxOn {
            let source = Inbox.currentSaveFolder()
            Inbox.apply()
            Inbox.adoptExistingScreenshots(from: source)
            startWatch(folder: Inbox.folder)
        } else {
            startWatch(folder: Inbox.currentSaveFolder())
        }
    }

    func setInbox(_ on: Bool) {
        Inbox.wasOffered = true
        if on {
            let source = Inbox.currentSaveFolder()
            Inbox.isEnabled = true
            Inbox.apply()
            Inbox.adoptExistingScreenshots(from: source)
            inboxOn = true
            startWatch(folder: Inbox.folder)
        } else {
            Inbox.restore()
            Inbox.isEnabled = false
            inboxOn = false
            startWatch(folder: Inbox.currentSaveFolder())
        }
    }

    func updateMetrics(_ metrics: Metrics) {
        var next = metrics
        if let panelSize, !shots.isEmpty {
            next = next.adopted(panel: panelSize, axis: axis)
        }
        guard next != self.metrics else { return }
        self.metrics = next
    }

    func layoutSize() -> NSSize {
        if shots.isEmpty {
            return folderBlocked ? NSSize(width: 360, height: 128) : Metrics.emptyPanel
        }
        return panelSize ?? metrics.defaultPanelSize()
    }

    func pointer(inside: Bool) {
        guard pointerInside != inside else { return }
        pointerInside = inside
    }

    func setWindowKey(_ key: Bool) {
        guard windowIsKey != key else { return }
        windowIsKey = key
    }

    /// Moves the row when a swipe or scroll wheel is not available.
    /// Older goes toward the far end. Newer returns toward the latest shot.
    func step(older: Bool) {
        let page = carouselPage
        guard page.maxOffset > 0 else { return }
        let span = axis == .horizontal ? metrics.hero.width : metrics.hero.height
        let hop = max(120, span * 0.72)
        if older {
            let remaining = page.maxOffset - page.appliedOffset
            guard page.showsOlder, remaining > 1 else { return }
            scrub(by: -min(hop, remaining))
        } else {
            guard page.showsNewer, page.appliedOffset > 1 else { return }
            scrub(by: min(hop, page.appliedOffset))
        }
    }

    /// Slides the list with the pointer. A move along the list carries the
    /// shots that way, so the ones behind the finger come into view.
    func scrub(by dx: CGFloat) {
        guard dx != 0 else { return }
        let page = carouselPage
        guard page.maxOffset > 0 else { return }
        let proposed = page.appliedOffset - dx
        let next = CarouselFit.page(shots: shots, offset: proposed, size: metrics.hero, axis: axis).appliedOffset
        guard abs(next - stripOffset) > 0.2 else { return }
        stripOffset = next
        noteVisibility()
    }

    private func clampOffset() {
        let next = carouselPage.appliedOffset
        if abs(next - stripOffset) > 0.5 { stripOffset = next }
    }

    func beginReposition() {
        repositioning = true
        collapseTask?.cancel()
    }

    func reposition(to origin: NSPoint) {
        onReposition?(origin)
    }

    func endReposition() {
        repositioning = false
        onRepositionEnd?()
    }

    func beginResize() {
        repositioning = true
    }

    func resize(to frame: NSRect) {
        onResize?(frame)
    }

    func endResize() {
        repositioning = false
        onResizeEnd?()
    }

    func minimize() {
        onMinimize?()
    }

    func cancelCollapse() {
        collapseTask?.cancel()
    }

    func select(_ shot: Shot) {
        confirmingPath = nil
        confirmingDeleteAll = false
        selectedPath = shot.path
    }

    func clearSelection() {
        confirmingPath = nil
        confirmingDeleteAll = false
        selectedPath = nil
    }

    /// Shows Yes and Cancel on this screenshot.
    func armDelete(_ shot: Shot) {
        confirmingDeleteAll = false
        selectedPath = shot.path
        confirmingPath = shot.path
    }

    func cancelDelete() {
        confirmingPath = nil
    }

    func commitDelete() {
        guard let path = confirmingPath, let shot = shot(path: path) else {
            confirmingPath = nil
            return
        }
        confirmingPath = nil
        trash(shot)
    }

    func armDeleteAll() {
        guard totalCount > 0 else { return }
        confirmingPath = nil
        confirmingDeleteAll = true
    }

    func cancelDeleteAll() {
        confirmingDeleteAll = false
    }

    func commitDeleteAll() {
        confirmingDeleteAll = false
        deleteAll()
    }

    func copy(_ shot: Shot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var writers: [NSPasteboardWriting] = []
        if let image = NSImage(contentsOf: shot.url) {
            writers.append(image)
        }
        writers.append(shot.url as NSURL)
        pasteboard.writeObjects(writers)
        copiedPath = shot.path
        copyToken += 1
        let token = copyToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.copyToken == token else { return }
                self.copiedPath = nil
            }
        }
    }

    func open(_ shot: Shot) {
        NSWorkspace.shared.open(shot.url)
    }

    func reveal(_ shot: Shot) {
        NSWorkspace.shared.activateFileViewerSelecting([shot.url])
    }

    func trash(_ shot: Shot) {
        moveToTrash(shot.url)
        shots.removeAll { $0.path == shot.path }
        allURLs.removeAll { $0.path == shot.path }
        totalCount = allURLs.count
        if selectedPath == shot.path { selectedPath = nil }
        if confirmingPath == shot.path { confirmingPath = nil }
        clampOffset()
        if shots.isEmpty {
            expanded = false
            stripOffset = 0
        }
        onLayout?()
        syncDock()
    }

    func deleteAll() {
        let urls = allURLs
        for url in urls { moveToTrash(url) }
        shots = []
        allURLs = []
        totalCount = 0
        expanded = false
        selectedPath = nil
        confirmingPath = nil
        confirmingDeleteAll = false
        stripOffset = 0
        onLayout?()
        syncDock()
    }

    func dragStarted(path: String) {
        dragActive = true
        draggingPath = path
        collapseTask?.cancel()
    }

    func dragEnded(operation: NSDragOperation) {
        let path = draggingPath
        dragActive = false
        draggingPath = nil
        if operation.contains(.delete), let path, let url = urlForPath(path) {
            moveToTrash(url)
        }
        if !pointerInside {
            expanded = false
        }
        onLayout?()
        deferredRefresh = false
        // Finder finishes a move a moment after the drag ends.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func shot(path: String?) -> Shot? {
        guard let path else { return nil }
        return shots.first { $0.path == path }
    }

    func menu(for shot: Shot) -> NSMenu {
        panelMenu(for: shot)
    }

    /// Right-click on the widget. A shot adds its own commands. Horizontal
    /// and Vertical swap the window's width and height.
    func panelMenu(for shot: Shot?) -> NSMenu {
        let menu = NSMenu()
        if let shot {
            menu.addItem(ClosureMenuItem("Copy") { [weak self] in self?.copy(shot) })
            menu.addItem(ClosureMenuItem("Open") { [weak self] in self?.open(shot) })
            menu.addItem(ClosureMenuItem("Show in Finder") { [weak self] in self?.reveal(shot) })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Move to Trash") { [weak self] in self?.armDelete(shot) })
            menu.addItem(.separator())
        }
        menu.addItem(axisItem("Horizontal", axis: .horizontal))
        menu.addItem(axisItem("Vertical", axis: .vertical))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Quit ShotPanel") { NSApp.terminate(nil) })
        return menu
    }

    /// Stacks the shots the other way and exchanges the panel's width and height.
    /// The bottom-right corner stays where it is, and the info bar stays at the bottom.
    func setAxis(_ next: CarouselFit.Axis, persist: Bool = true) {
        guard next != axis else { return }
        let current = panelSize ?? metrics.defaultPanelSize()
        sizeForAxis[axis.rawValue] = current
        axis = next
        if persist {
            UserDefaults.standard.set(next.rawValue, forKey: Self.axisKey)
        }
        let fallback = NSSize(
            width: max(Metrics.minPanel.width, current.height),
            height: max(Metrics.minPanel.height, current.width)
        )
        let size = sizeForAxis[next.rawValue] ?? fallback
        panelSize = size
        let adopted = metrics.adopted(panel: size, axis: next)
        if adopted != metrics { metrics = adopted }
        stripOffset = 0
        clampOffset()
        noteVisibility(force: true)
        if persist { onRememberSize?(size) }
        onLayout?()
    }

    private func axisItem(_ title: String, axis: CarouselFit.Axis) -> NSMenuItem {
        let item = ClosureMenuItem(title) { [weak self] in self?.setAxis(axis) }
        item.state = self.axis == axis ? .on : .off
        return item
    }

    private static func canRead(_ folder: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
    }

    private func startWatch(folder: URL) {
        watcher?.stop()
        primed = false
        seen.removeAll()
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .standardizedFileURL.path
        watchesDesktop = folder.standardizedFileURL.path == desktop
        folderBlocked = !Self.canRead(folder)
        NSLog("ShotPanel watching \(folder.path)")
        let watcher = ScreenshotWatcher(folder: folder)
        watcher.onChange = { [weak self] in self?.refresh() }
        self.watcher = watcher
        watcher.start()
    }

    private func refresh() {
        if dragActive {
            deferredRefresh = true
            return
        }
        guard let watcher else { return }
        let qualifying = watcher.files().filter { watcher.isCandidate($0) }
        allURLs = qualifying.sorted { created($0) > created($1) }
        totalCount = allURLs.count
        let capped = Array(allURLs.prefix(displayCap))
        let previous = Dictionary(uniqueKeysWithValues: shots.map { ($0.path, $0) })
        let next: [Shot] = capped.map { url in
            if var existing = previous[url.path] {
                existing = Shot(
                    path: url.path,
                    url: url,
                    created: created(url),
                    pixelSize: existing.pixelSize == .zero ? ImageThumb.pixelSize(url: url) : existing.pixelSize,
                    image: existing.image,
                    attempts: existing.attempts,
                    pixelBudget: existing.pixelBudget
                )
                return existing
            }
            return Shot(
                path: url.path,
                url: url,
                created: created(url),
                pixelSize: ImageThumb.pixelSize(url: url),
                image: nil
            )
        }
        let fresh = next.filter { !seen.contains($0.path) }
        seen.formUnion(next.map(\.path))
        // Drop paths that left, but keep the seen set from growing forever.
        if seen.count > 500 {
            seen = Set(next.map(\.path))
        }
        shots = next
        if let selectedPath, !shots.contains(where: { $0.path == selectedPath }) {
            self.selectedPath = nil
        }
        if primed, !fresh.isEmpty {
            stripOffset = 0
        } else {
            clampOffset()
        }
        if shots.isEmpty {
            expanded = false
            stripOffset = 0
        }
        noteVisibility(force: true)
        onLayout?()
        if primed, !fresh.isEmpty {
            arrivedPath = fresh[0].path
            arriveToken += 1
            let token = arriveToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.arriveToken == token else { return }
                    self.arrivedPath = nil
                }
            }
            onNewShot?()
        }
        primed = true
        syncDock()
    }

    /// The Dock stack is the same files as the widget. A drag from that stack
    /// into the Trash reports back through the folder watcher, which lands here.
    private func syncDock() {
        guard watcher != nil else { return }
        DockStack.onFilesTrashed = { [weak self] in self?.refresh() }
        DockStack.sync(files: allURLs)
    }

    /// Indexes on screen the last time images were queued. A resize that
    /// still shows the same shots does not decode them again.
    private var lastVisible = Set<Int>()

    /// Shots on screen are decoded large enough to stay sharp. One shot to
    /// either side is ready for the next scroll.
    private func noteVisibility(force: Bool = false) {
        let visible = Set(carouselPage.onScreen().map(\.index))
        let changed = force || visible != lastVisible
        lastVisible = visible
        guard changed else { return }
        for index in visible where shots.indices.contains(index) {
            let budget = shots[index].pixelBudget
            if budget > 0, budget < 1800 {
                shots[index].image = nil
                shots[index].attempts = 0
                shots[index].pixelBudget = 0
            }
        }
        loadMissingImages()
    }

    private func loadMissingImages() {
        let visible = lastVisible
        let lo = (visible.min() ?? 0) - 1
        let hi = (visible.max() ?? 0) + 1
        let jobs = shots.enumerated().compactMap { index, shot -> (String, URL, CGFloat)? in
            guard shot.image == nil, shot.attempts < 4 else { return nil }
            let pixels: CGFloat = (lo...hi).contains(index) ? 2200 : 700
            return (shot.path, shot.url, pixels)
        }
        guard !jobs.isEmpty else { return }
        loadToken += 1
        let token = loadToken
        DispatchQueue.global(qos: .userInitiated).async { [jobs] in
            var made: [String: NSImage] = [:]
            var budgets: [String: CGFloat] = [:]
            var failed: Set<String> = []
            for job in jobs {
                if let image = ImageThumb.make(url: job.1, maxPixel: job.2) {
                    made[job.0] = image
                    budgets[job.0] = job.2
                } else {
                    failed.insert(job.0)
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    self?.store(made, budgets: budgets, failed: failed, token: token)
                }
            }
        }
    }

    private func store(_ images: [String: NSImage], budgets: [String: CGFloat], failed: Set<String>, token: Int) {
        guard token == loadToken else { return }
        var next = shots
        var changed = false
        for index in next.indices {
            let path = next[index].path
            if next[index].image == nil, let image = images[path] {
                next[index].image = image
                next[index].pixelBudget = budgets[path] ?? 0
                changed = true
            } else if failed.contains(path) {
                next[index].attempts += 1
                changed = true
            }
        }
        if changed { shots = next }
        let waiting = shots.contains { $0.image == nil && $0.attempts < 4 }
        guard waiting else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            MainActor.assumeIsolated { self?.loadMissingImages() }
        }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.pointerInside, !self.dragActive, !self.repositioning, self.expanded else { return }
                self.expanded = false
                self.onLayout?()
            }
        }
        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
    }

    private func urlForPath(_ path: String) -> URL? {
        if let shot = shots.first(where: { $0.path == path }) { return shot.url }
        return allURLs.first { $0.path == path }
    }

    private func created(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate ?? .distantPast
    }

    private func moveToTrash(_ url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            NSLog("ShotPanel: could not trash \(url.path): \(error.localizedDescription)")
        }
    }
}
