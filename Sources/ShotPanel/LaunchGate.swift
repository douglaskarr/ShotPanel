import AppKit
import ServiceManagement

/// Asks for the screenshot folder, then about opening at login, before the
/// panel or the Dock exist. macOS raises its own permission question only
/// when this process reads the folder, so that read waits until Continue.
enum LaunchGate {
    private static let allowedKey = "shotpanel.launchAllowed"
    private static let loginAskedKey = "shotpanel.loginAsked"

    /// False when the user quit rather than allow access. The panel stays unbuilt.
    @MainActor
    static func pass() -> Bool {
        if !UserDefaults.standard.bool(forKey: allowedKey) {
            guard grantAccess() else { return false }
        }
        if !UserDefaults.standard.bool(forKey: loginAskedKey) {
            askToStartAtLogin()
        }
        return true
    }

    @MainActor
    private static func grantAccess() -> Bool {
        while true {
            let ask = NSAlert()
            ask.messageText = "Allow ShotPanel to read your screenshots?"
            ask.informativeText = "ShotPanel stays closed until macOS lets it read the folder where screenshots are saved. Choose Continue, then choose Allow. During screen sharing, that question can appear on the Mac itself."
            ask.addButton(withTitle: "Continue")
            ask.addButton(withTitle: "Quit")
            if ask.runModal() != .alertFirstButtonReturn { return false }

            let folder = Inbox.configuredSaveFolder()
            switch list(folder) {
            case .granted:
                UserDefaults.standard.set(true, forKey: allowedKey)
                return true
            case .missing:
                if !retry(
                    "ShotPanel can't find that folder",
                    "Screenshots are set to save in \(folder.path). Choose Try Again after that folder is available, or Quit."
                ) { return false }
            case .denied:
                if !retry(
                    "ShotPanel still can't read that folder",
                    "Choose Allow on the macOS question. If you don't see it, check the Mac's own display. The folder is \(folder.path)."
                ) { return false }
            }
        }
    }

    @MainActor
    private static func retry(_ title: String, _ detail: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Quit")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private enum Listing {
        case granted
        case missing
        case denied
    }

    private static func list(_ folder: URL) -> Listing {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            return .granted
        } catch let error as NSError {
            if error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError {
                return .missing
            }
            return .denied
        }
    }

    @MainActor
    private static func askToStartAtLogin() {
        let alert = NSAlert()
        alert.messageText = "Start ShotPanel when you log in?"
        alert.informativeText = "ShotPanel can open at login so new screenshots leave the Desktop. You can change this later from the ShotPanel menu."
        alert.addButton(withTitle: "Start at Login")
        alert.addButton(withTitle: "Not Now")
        let start = alert.runModal() == .alertFirstButtonReturn
        UserDefaults.standard.set(true, forKey: loginAskedKey)
        guard start else { return }
        switch LoginItem.enable() {
        case .enabled:
            break
        case .needsApproval:
            let follow = NSAlert()
            follow.messageText = "Allow ShotPanel in Login Items"
            follow.informativeText = "macOS needs a confirmation in System Settings → General → Login Items. That pane is open."
            follow.addButton(withTitle: "OK")
            SMAppService.openSystemSettingsLoginItems()
            follow.runModal()
        case .failed(let message):
            let follow = NSAlert()
            follow.messageText = "ShotPanel could not open at login"
            follow.informativeText = "\(message) Move ShotPanel into the Applications folder, then choose Open at Login from the ShotPanel menu."
            follow.addButton(withTitle: "OK")
            follow.runModal()
        }
    }
}

enum LoginItem {
    enum Result {
        case enabled
        case needsApproval
        case failed(String)
    }

    static var isOn: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func enable() -> Result {
        let service = SMAppService.mainApp
        if service.status == .enabled { return .enabled }
        do {
            try service.register()
        } catch {
            return .failed(error.localizedDescription)
        }
        if service.status == .requiresApproval {
            return .needsApproval
        }
        return .enabled
    }

    static func disable() {
        try? SMAppService.mainApp.unregister()
    }
}
