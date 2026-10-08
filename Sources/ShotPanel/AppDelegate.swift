import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let shelf = Shelf()
    private var panel: ShelfPanel!
    private var hover: HoverRoot!
    private var status: NSStatusItem!
    private var menu: NSMenu!
    private var anchorScreen: NSScreen?
    /// Bottom-right corner of the widget, in screen coordinates. Expansion
    /// grows up and to the left so this corner stays where the user put it.
    private var anchorMaxX: CGFloat?
    private var anchorMinY: CGFloat?
    private var hasCustomPlacement = false
    private var userHidden = false
    private var hiddenForFullScreen = false
    private var layingOut = false
    /// False until the folder permission and the login question are finished.
    private var started = false

    private static let maxXKey = "shotpanel.anchorMaxX"
    private static let minYKey = "shotpanel.anchorMinY"
    private static let widthKey = "shotpanel.panelWidth"
    private static let heightKey = "shotpanel.panelHeight"

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Watching for screenshots")
        ProcessInfo.processInfo.disableSuddenTermination()
        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        installStatusItem()
        // Be the front app before the first look at the Desktop, so the
        // system permission question is the window in front. A remote
        // session can still draw that question only on the Mac itself.
        NSApp.activate()
        guard LaunchGate.pass() else {
            NSApp.terminate(nil)
            return
        }
        started = true

        hover = HoverRoot(shelf: shelf)
        hover.onHover = { [weak self] inside in
            MainActor.assumeIsolated { self?.shelf.pointer(inside: inside) }
        }
        panel = ShelfPanel(root: hover)
        panel.delegate = self
        anchorScreen = ShelfPanel.screenUnderPointer()
        if UserDefaults.standard.object(forKey: Self.maxXKey) != nil {
            anchorMaxX = CGFloat(UserDefaults.standard.double(forKey: Self.maxXKey))
            anchorMinY = CGFloat(UserDefaults.standard.double(forKey: Self.minYKey))
            hasCustomPlacement = true
        }
        if UserDefaults.standard.object(forKey: Self.widthKey) != nil {
            let width = CGFloat(UserDefaults.standard.double(forKey: Self.widthKey))
            let height = CGFloat(UserDefaults.standard.double(forKey: Self.heightKey))
            if width >= Metrics.minPanel.width, height >= Metrics.minPanel.height {
                shelf.setPanelSize(NSSize(width: width, height: height))
            }
        }

        shelf.onLayout = { [weak self] in self?.relayout(animated: true) }
        shelf.onRememberSize = { size in
            UserDefaults.standard.set(Double(size.width), forKey: Self.widthKey)
            UserDefaults.standard.set(Double(size.height), forKey: Self.heightKey)
        }
        shelf.onNewShot = { [weak self] in self?.revealNewShot() }
        shelf.onMinimize = { [weak self] in self?.minimize() }
        shelf.onReposition = { [weak self] origin in self?.move(to: origin) }
        shelf.onRepositionEnd = { [weak self] in self?.commitPlacement() }
        shelf.onResize = { [weak self] frame in self?.resize(to: frame) }
        shelf.onResizeEnd = { [weak self] in self?.commitSize() }
        shelf.boot()

        observeSpaces()
        installKeyMonitor()
        applyMetrics()
        relayout(animated: false)
        applyVisibility()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated { self?.offerIfNeeded() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if Inbox.isEnabled { Inbox.restore() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard started else { return false }
        showPanel()
        return false
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        relayout(animated: false)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        shelf.setWindowKey(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        shelf.setWindowKey(false)
    }

    /// Command-Q works once the panel is clicked. The menu bar icon stays
    /// available when the panel is not the front window.
    private func installMainMenu() {
        let appMenu = NSMenu()
        let quit = NSMenuItem(title: "Quit ShotPanel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quit)
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let main = NSMenu()
        main.addItem(appItem)
        NSApp.mainMenu = main
    }

    private func installStatusItem() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "ShotPanel")
        image?.isTemplate = true
        status.button?.image = image
        status.button?.title = "ShotPanel"
        status.button?.imagePosition = .imageLeading
        status.button?.toolTip = "ShotPanel"
        menu = NSMenu()
        menu.delegate = self
        status.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        guard started else {
            let quit = NSMenuItem(title: "Quit ShotPanel", action: #selector(quit), keyEquivalent: "q")
            quit.target = self
            menu.addItem(quit)
            return
        }
        let inbox = NSMenuItem(
            title: "Keep Screenshots off the Desktop",
            action: #selector(toggleInbox),
            keyEquivalent: ""
        )
        inbox.target = self
        inbox.state = shelf.inboxOn ? .on : .off
        menu.addItem(inbox)

        let tucked = userHidden || panel.isMiniaturized
        let visibility = NSMenuItem(
            title: tucked ? "Show Panel" : "Hide Panel",
            action: #selector(toggleHidden),
            keyEquivalent: ""
        )
        visibility.target = self
        menu.addItem(visibility)

        let minimize = NSMenuItem(title: "Minimize", action: #selector(minimizeFromMenu), keyEquivalent: "m")
        minimize.target = self
        minimize.isEnabled = !panel.isMiniaturized && !userHidden
        menu.addItem(minimize)

        menu.addItem(.separator())
        let delete = NSMenuItem(
            title: "Delete All Screenshots",
            action: #selector(deleteAll),
            keyEquivalent: ""
        )
        delete.target = self
        delete.isEnabled = shelf.totalCount > 0
        menu.addItem(delete)

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isOn ? .on : .off
        menu.addItem(login)

        if DockStack.needsDockReload {
            menu.addItem(.separator())
            let dock = NSMenuItem(
                title: "Show Screenshots in the Dock",
                action: #selector(reloadDockFromMenu),
                keyEquivalent: ""
            )
            dock.target = self
            menu.addItem(dock)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ShotPanel", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// Arrow keys move the row. A remote session often has a pointer and no swipe.
    private func installKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            let older: Bool?
            switch event.keyCode {
            case 123, 126: older = false
            case 124, 125: older = true
            default: older = nil
            }
            guard let older else { return event }
            let before = self.shelf.carouselPage.appliedOffset
            self.shelf.step(older: older)
            return self.shelf.carouselPage.appliedOffset == before ? event : nil
        }
    }

    @objc private func reloadDockFromMenu() {
        let alert = NSAlert()
        alert.messageText = "Reload the Dock to show screenshots?"
        alert.informativeText = "ShotPanel adds a folder beside the Trash. Reloading the Dock can gather windows from your other desktops onto this one."
        alert.addButton(withTitle: "Reload the Dock")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            DockStack.reloadDock()
        }
    }

    @objc private func toggleInbox() {
        shelf.setInbox(!shelf.inboxOn)
    }

    @objc private func toggleHidden() {
        if panel.isMiniaturized || userHidden {
            showPanel()
            return
        }
        userHidden = true
        panel.orderOut(nil)
    }

    @objc private func minimizeFromMenu() {
        minimize()
    }

    @objc private func deleteAll() {
        shelf.armDeleteAll()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func toggleLogin() {
        if LoginItem.isOn {
            LoginItem.disable()
            return
        }
        switch LoginItem.enable() {
        case .enabled:
            break
        case .needsApproval:
            let alert = NSAlert()
            alert.messageText = "Allow ShotPanel in Login Items"
            alert.informativeText = "macOS needs a confirmation in System Settings → General → Login Items. That pane is open."
            alert.addButton(withTitle: "OK")
            SMAppService.openSystemSettingsLoginItems()
            alert.runModal()
        case .failed(let message):
            let alert = NSAlert()
            alert.messageText = "ShotPanel could not open at login"
            alert.informativeText = "\(message) Move ShotPanel into the Applications folder, then choose Open at Login again."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func observeSpaces() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    @objc private func screenChanged() {
        if let anchorScreen, !NSScreen.screens.contains(where: { $0.frame == anchorScreen.frame }) {
            self.anchorScreen = NSScreen.main
            if !hasCustomPlacement {
                anchorMaxX = nil
                anchorMinY = nil
            }
        }
        applyMetrics()
        relayout(animated: false)
        applyVisibility()
    }

    @objc private func spaceChanged() {
        applyVisibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            MainActor.assumeIsolated { self?.applyVisibility() }
        }
    }

    private func revealNewShot() {
        // A new shot shows a panel the user only hid. One they minimized into
        // the Dock stays there until they click it.
        guard !panel.isMiniaturized else { return }
        if userHidden {
            userHidden = false
            applyVisibility()
        }
        applyMetrics()
        relayout(animated: true)
    }

    private func showPanel() {
        userHidden = false
        hiddenForFullScreen = false
        if panel.isMiniaturized {
            panel.deminiaturize(nil)
        }
        panel.makeKeyAndOrderFront(nil)
        relayout(animated: false)
    }

    private func minimize() {
        guard !panel.isMiniaturized else { return }
        userHidden = false
        if !panel.isVisible { panel.orderFrontRegardless() }
        panel.miniaturize(nil)
    }

    private func move(to origin: NSPoint) {
        guard !layingOut else { return }
        let size = panel.frame.size
        let clamped = clampedOrigin(origin, size: size)
        panel.setFrameOrigin(clamped)
        anchorMaxX = panel.frame.maxX
        anchorMinY = panel.frame.minY
        anchorScreen = screen(containing: panel.frame) ?? anchorScreen
    }

    private func commitPlacement() {
        hasCustomPlacement = true
        anchorMaxX = panel.frame.maxX
        anchorMinY = panel.frame.minY
        UserDefaults.standard.set(Double(panel.frame.maxX), forKey: Self.maxXKey)
        UserDefaults.standard.set(Double(panel.frame.minY), forKey: Self.minYKey)
    }

    private func resize(to frame: NSRect) {
        guard !layingOut else { return }
        panel.setFrame(frame, display: true)
        anchorMaxX = panel.frame.maxX
        anchorMinY = panel.frame.minY
        anchorScreen = screen(containing: panel.frame) ?? anchorScreen
        shelf.setPanelSize(panel.frame.size)
    }

    private func commitSize() {
        hasCustomPlacement = true
        commitPlacement()
        let size = panel.frame.size
        shelf.setPanelSize(size)
        UserDefaults.standard.set(Double(size.width), forKey: Self.widthKey)
        UserDefaults.standard.set(Double(size.height), forKey: Self.heightKey)
    }

    private func offerIfNeeded() {
        guard !Inbox.wasOffered, !shelf.inboxOn, !shelf.folderBlocked else { return }
        let alert = NSAlert()
        alert.messageText = "Keep screenshots in ShotPanel?"
        alert.informativeText = "Screenshots already in your screenshot folder move into the panel. New ones skip the Desktop while ShotPanel is open. The floating thumbnail is turned off, and your previous save location comes back when you quit. If macOS asks to read the Desktop, choose Allow. That question can show on the Mac itself during screen sharing. Quit from the ShotPanel menu, the menu bar icon, or with Command-Q."
        alert.addButton(withTitle: "Keep Desktop Clear")
        alert.addButton(withTitle: "Not Now")
        Inbox.wasOffered = true
        if alert.runModal() == .alertFirstButtonReturn {
            shelf.setInbox(true)
        }
    }

    private func applyMetrics() {
        guard let screen = anchorScreen ?? screen(containing: panel?.frame ?? .zero) ?? ShelfPanel.screenUnderPointer() else { return }
        shelf.updateMetrics(Metrics.make(visible: screen.visibleFrame))
    }

    private func relayout(animated: Bool) {
        guard !layingOut, let panel, !panel.isMiniaturized, !shelf.repositioning else { return }
        layingOut = true
        defer { layingOut = false }
        guard let screen = anchorScreen ?? ShelfPanel.screenUnderPointer() else { return }
        let visible = screen.visibleFrame
        let size = shelf.layoutSize()
        let populated = shelf.currentShot != nil
        let floorW = populated ? Metrics.minPanel.width : Metrics.emptyPanel.width
        let floorH = populated ? Metrics.minPanel.height : Metrics.emptyPanel.height
        let width = min(max(size.width, floorW), max(floorW, visible.width - 8))
        let height = min(max(size.height, floorH), max(floorH, visible.height - 8))
        shelf.fitDisplay(to: NSSize(width: width, height: height))
        let maxX = anchorMaxX ?? (visible.maxX - 16)
        let minY = anchorMinY ?? (visible.minY + 16)
        var frame = NSRect(x: maxX - width, y: minY, width: width, height: height)
        frame = clamped(frame, to: visible)
        guard panel.frame.integral != frame.integral else {
            if frame.contains(NSEvent.mouseLocation) { shelf.cancelCollapse() }
            return
        }
        if animated && panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        if frame.contains(NSEvent.mouseLocation) { shelf.cancelCollapse() }
    }

    private func applyVisibility() {
        guard let panel, !panel.isMiniaturized else { return }
        let screen = anchorScreen ?? screen(containing: panel.frame) ?? ShelfPanel.screenUnderPointer()
        let fullScreen = screen.map { FullScreen.isActive(on: $0) } ?? false
        if fullScreen {
            if panel.isVisible {
                hiddenForFullScreen = true
                panel.orderOut(nil)
            }
            return
        }
        if hiddenForFullScreen {
            hiddenForFullScreen = false
        }
        let show = !userHidden
        if show {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    private func screen(containing frame: NSRect) -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.first { $0.frame.intersects(frame) }
    }

    /// Keeps a grabbed edge on the display the window is crossing.
    private func clampedOrigin(_ origin: NSPoint, size: NSSize) -> NSPoint {
        let proposed = NSRect(origin: origin, size: size)
        let screen = screen(containing: proposed) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return origin }
        let minX = visible.minX - size.width + 80
        let maxX = visible.maxX - 80
        let minY = visible.minY
        let maxY = visible.maxY - min(40, size.height)
        return NSPoint(x: min(max(origin.x, minX), maxX), y: min(max(origin.y, minY), maxY))
    }

    private func clamped(_ frame: NSRect, to visible: NSRect) -> NSRect {
        var frame = frame
        if frame.width > visible.width { frame.size.width = visible.width }
        if frame.height > visible.height { frame.size.height = visible.height }
        if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
        if frame.minX < visible.minX { frame.origin.x = visible.minX }
        if frame.minY < visible.minY { frame.origin.y = visible.minY }
        if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
        return frame
    }
}
