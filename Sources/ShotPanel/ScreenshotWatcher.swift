import Darwin
import Foundation

/// Notices screenshots macOS writes on its own.
/// The file keeps the automatic name (`Screenshot …` or `Screen Shot …`) and
/// the screen-capture tag. A renamed shot, or any other image on the Desktop,
/// stays where it is and is left out of the group. macOS saves these on the
/// Desktop unless the screenshot options point somewhere else.
@MainActor
final class ScreenshotWatcher {
    let folder: URL
    var onChange: (() -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "webp"]

    init(folder: URL) {
        self.folder = folder
    }

    func start() {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("ShotPanel: cannot watch \(folder.path)")
            onChange?()
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )
        src.setEventHandler { [weak self] in self?.schedule() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        onChange?()
    }

    func stop() {
        pending?.cancel()
        source?.cancel()
        source = nil
    }

    func files() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    func isCandidate(_ url: URL) -> Bool {
        guard Self.extensions.contains(url.pathExtension.lowercased()) else { return false }
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        if values?.isRegularFile == false { return false }
        // screencapture writes the tag and the automatic name together.
        return isScreenCapture(url) && hasAutomaticName(url)
    }

    /// `Screenshot 2026-10-04 at 1.11.04 PM`, including the narrow space
    /// macOS puts before AM/PM. The older `Screen Shot …` name counts too.
    private func hasAutomaticName(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let pattern = #"^(Screenshot|Screen Shot) \d{4}-\d{2}-\d{2} at \d{1,2}\.\d{2}\.\d{2}( (AM|PM))?$"#
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange?() }
        pending = work
        // The capture service writes a temp file and renames it into place.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func isScreenCapture(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
        }
    }
}
