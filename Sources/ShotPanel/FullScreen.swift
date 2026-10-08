import AppKit

// The window server reports the Space on each display. A full screen Space
// is type 4. The calls are private, take no permission, and have stayed put
// for years. If they are missing, the panel just stays where it is.
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> CFArray

enum FullScreen {
    private static let fullScreenSpaceType = 4

    static func isActive(on screen: NSScreen) -> Bool {
        guard let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]],
              !displays.isEmpty else { return false }

        let entry: [String: Any]?
        if displays.count == 1 {
            entry = displays.first
        } else {
            let uuid = uuidString(for: screen)
            entry = displays.first { ($0["Display Identifier"] as? String) == uuid }
        }
        let current = entry?["Current Space"] as? [String: Any]
        return (current?["type"] as? Int) == fullScreenSpaceType
    }

    /// Desktops across all displays. Unknown answers as more than one, so a
    /// Dock reload is skipped when it might pull every desktop's windows here.
    static func spaceCount() -> Int {
        guard let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] else {
            return 2
        }
        let count = displays.reduce(0) { sum, display in
            sum + ((display["Spaces"] as? [Any])?.count ?? 0)
        }
        return count > 0 ? count : 2
    }

    private static func uuidString(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
