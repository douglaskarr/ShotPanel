import AppKit
import SwiftUI

/// Renders the widget to PNG files so the layout can be checked without
/// screen-recording permission. `ShotPanel --preview /path`
enum PreviewDump {
    @MainActor
    static func run(directory: String) {
        let folder = URL(
            fileURLWithPath: ("~/Library/Application Support/ShotPanel/Screenshots" as NSString).expandingTildeInPath,
            isDirectory: true
        )
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )) ?? []
        let shelf = Shelf()
        shelf.updateMetrics(Metrics.make(visible: NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1920, height: 970)))
        shelf.loadPreview(urls)
        let out = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        shelf.expanded = false
        write(shelf, to: out.appendingPathComponent("collapsed.png"))
        shelf.expanded = true
        write(shelf, to: out.appendingPathComponent("expanded.png"))
        write(shelf, to: out.appendingPathComponent("armed.png"))
        shelf.loadPreview([])
        write(shelf, to: out.appendingPathComponent("empty.png"))

        let samples = writeSamples()
        shelf.loadPreview(samples)
        shelf.scrub(by: -180)
        write(shelf, to: out.appendingPathComponent("carousel.png"))
        shelf.setPanelSize(NSSize(width: 760, height: 500))
        write(shelf, to: out.appendingPathComponent("large.png"))
        shelf.loadPreview(samples)
        shelf.setPanelSize(NSSize(width: 1200, height: 360))
        if let shot = shelf.shots.first { shelf.select(shot) }
        write(shelf, to: out.appendingPathComponent("wide.png"))
        if let shot = shelf.shots.first { shelf.armDelete(shot) }
        write(shelf, to: out.appendingPathComponent("confirm.png"))
        shelf.cancelDelete()
        shelf.setAxis(.vertical, persist: false)
        shelf.setPanelSize(NSSize(width: 280, height: 480))
        if shelf.shots.count > 1 { shelf.select(shelf.shots[1]) }
        let page = shelf.carouselPage
        for item in page.items {
            fputs("vertical item \(item.index) \(NSStringFromRect(item.frame)) peek \(item.isPeek)\n", stderr)
        }
        write(shelf, to: out.appendingPathComponent("vertical.png"))
        shelf.setAxis(.horizontal, persist: false)
        shelf.setPanelSize(NSSize(width: 1200, height: 360))
        if let shot = shelf.shots.first { shelf.select(shot) }
        shelf.scrub(by: -180)
        write(shelf, to: out.appendingPathComponent("wide-step.png"))
        shelf.loadPreview(samples)
        shelf.setPanelSize(NSSize(width: 544, height: 224))
        write(shelf, to: out.appendingPathComponent("peek.png"))
        shelf.scrub(by: -4000)
        write(shelf, to: out.appendingPathComponent("peek-end.png"))
        exerciseAxes(out)
        fputs("Wrote previews to \(out.path)\n", stderr)
    }

    /// Switches a short wide panel to vertical and back, and checks that every
    /// on-screen shot can take a click, including ones past the first.
    @MainActor
    private static func exerciseAxes(_ out: URL) {
        let samples = writeAspects()
        let shelf = Shelf()
        shelf.loadPreview(samples)
        shelf.setPanelSize(NSSize(width: 786, height: 200))
        var failures: [String] = []
        func check(_ label: String) {
            let page = shelf.carouselPage
            let visible = page.onScreen().filter { !$0.isPeek }
            if visible.count < 2 {
                failures.append("\(label): expected at least two shots on screen, got \(visible.count)")
            }
            for item in visible {
                guard shelf.shots.indices.contains(item.index) else { continue }
                let shot = shelf.shots[item.index]
                guard let hit = ShotActions.hit(in: item.frame) else {
                    failures.append("\(label): no Copy/Delete on \(shot.url.lastPathComponent) \(NSStringFromRect(item.frame))")
                    continue
                }
                if !item.frame.contains(NSPoint(x: hit.copy.midX, y: hit.copy.midY))
                    || !item.frame.contains(NSPoint(x: hit.delete.midX, y: hit.delete.midY)) {
                    failures.append("\(label): buttons fall outside \(shot.url.lastPathComponent)")
                }
                let bounds = CGRect(origin: .zero, size: page.viewport)
                let shown = item.frame.intersection(bounds)
                let center = NSPoint(x: shown.midX, y: shown.midY)
                let owner = page.onScreen().last { $0.frame.contains(center) }
                if owner?.index != item.index {
                    failures.append("\(label): click on \(shot.url.lastPathComponent) hits \(owner?.index ?? -1)")
                }
            }
            let width = shelf.metrics.hero.width
            let footer = shelf.metrics.footer
            let bar = ShotActions.bar(
                width: width,
                footerTop: 0,
                footer: footer,
                vertical: shelf.axis == .vertical,
                confirming: false
            )
            if bar.primary.maxX > width + 0.5 || bar.primary.minX < -0.5 {
                failures.append("\(label): Delete all sits outside the bar")
            }
        }
        check("horizontal")
        if shelf.shots.count > 1 { shelf.select(shelf.shots[1]) }
        write(shelf, to: out.appendingPathComponent("axis-h-select.png"))
        if shelf.shots.count > 1 { shelf.armDelete(shelf.shots[1]) }
        write(shelf, to: out.appendingPathComponent("axis-h-confirm.png"))
        shelf.cancelDelete()
        shelf.armDeleteAll()
        write(shelf, to: out.appendingPathComponent("axis-h-all.png"))
        shelf.cancelDeleteAll()
        let horizontal = shelf.layoutSize()
        shelf.setAxis(.vertical, persist: false)
        if shelf.layoutSize().width < Metrics.minPanel.width - 0.5 {
            failures.append("vertical width \(shelf.layoutSize().width) is under the minimum")
        }
        check("vertical")
        if shelf.shots.count > 1 { shelf.select(shelf.shots[1]) }
        write(shelf, to: out.appendingPathComponent("axis-v-select.png"))
        if shelf.shots.count > 1 { shelf.armDelete(shelf.shots[1]) }
        write(shelf, to: out.appendingPathComponent("axis-v-confirm.png"))
        shelf.cancelDelete()
        shelf.armDeleteAll()
        write(shelf, to: out.appendingPathComponent("axis-v-all.png"))
        shelf.cancelDeleteAll()
        let vertical = shelf.layoutSize()
        shelf.setAxis(.horizontal, persist: false)
        if shelf.layoutSize() != horizontal {
            failures.append("back to horizontal is \(NSStringFromSize(shelf.layoutSize())), wanted \(NSStringFromSize(horizontal))")
        }
        check("horizontal again")
        if shelf.shots.count > 2 { shelf.select(shelf.shots[2]) }
        write(shelf, to: out.appendingPathComponent("axis-h-back.png"))
        shelf.setAxis(.vertical, persist: false)
        if shelf.layoutSize() != vertical {
            failures.append("back to vertical is \(NSStringFromSize(shelf.layoutSize())), wanted \(NSStringFromSize(vertical))")
        }
        check("vertical again")
        failures.append(contentsOf: probeClicks(shelf))
        shelf.setAxis(.horizontal, persist: false)
        if shelf.shots.count > 1 { shelf.select(shelf.shots[1]) }
        failures.append(contentsOf: probeClicks(shelf))
        if failures.isEmpty {
            fputs("axis exercise ok\n", stderr)
        } else {
            for line in failures { fputs("FAIL \(line)\n", stderr) }
        }
    }

    /// Points over the second and third shots must reach the row, not the image view.
    @MainActor
    private static func probeClicks(_ shelf: Shelf) -> [String] {
        let size = shelf.layoutSize()
        let host = NSHostingView(rootView: ShelfRoot(shelf: shelf, interactive: true))
        let window = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.orderBack(nil)
        for _ in 0..<8 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.04))
            host.layoutSubtreeIfNeeded()
        }
        var failures = clickFailures(shelf, host: host, window: window, label: "\(shelf.axis)")
        // A later size, as if the user dragged a corner. The second shot has
        // to stay under the cursor after the photos move.
        let resized = NSSize(width: max(320, size.width * 0.62), height: max(240, size.height * 1.35))
        shelf.setPanelSize(resized)
        window.setContentSize(resized)
        host.frame = NSRect(origin: .zero, size: resized)
        for _ in 0..<8 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.04))
            host.layoutSubtreeIfNeeded()
        }
        failures.append(contentsOf: clickFailures(shelf, host: host, window: window, label: "\(shelf.axis) resized"))
        if let card = findCards(in: host).first {
            let kept = card.bounds.size
            card.setBoundsSize(NSSize(width: kept.width * 1.7, height: kept.height * 1.4))
            failures.append(contentsOf: clickFailures(shelf, host: host, window: window, label: "\(shelf.axis) scaled"))
            card.setBoundsSize(kept)
        }
        window.orderOut(nil)
        return failures
    }

    @MainActor
    private static func clickFailures(_ shelf: Shelf, host: NSView, window: NSWindow, label: String) -> [String] {
        let cards = findCards(in: host)
        if cards.isEmpty { return ["\(label): no click row was installed"] }
        let size = shelf.layoutSize()
        let pad = shelf.metrics.outerPad
        let page = shelf.carouselPage
        var failures: [String] = []
        for item in page.onScreen().filter({ !$0.isPeek }).prefix(3) {
            let shown = item.frame.intersection(CGRect(origin: .zero, size: page.viewport))
            let topX = pad + shown.midX
            let topY = pad + shown.midY
            let windowPoint = NSPoint(x: topX, y: size.height - topY)
            let hit = window.contentView?.hitTest(windowPoint)
            let hitName = hit.map { String(describing: type(of: $0)) } ?? "nil"
            let path = cards.first?.path(atWindowPoint: windowPoint)
            let shot = shelf.shots.indices.contains(item.index) ? shelf.shots[item.index].url.lastPathComponent : "?"
            if path != shelf.shots[item.index].path {
                failures.append("\(label): click \(shot) -> \(path ?? "nil") via \(hitName)")
            }
        }
        return failures
    }

    @MainActor
    private static func findCards(in view: NSView) -> [CardView] {
        var found: [CardView] = []
        if let card = view as? CardView, card.hero { found.append(card) }
        for sub in view.subviews { found.append(contentsOf: findCards(in: sub)) }
        return found
    }

    /// Solid shots in the same proportions as a tall capture, a wide one, and a display.
    @MainActor
    private static func writeAspects() -> [URL] {
        let folder = URL(fileURLWithPath: "/tmp/shotpanel-axes", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let specs: [(String, NSColor, CGFloat, CGFloat)] = [
            ("tall", .systemOrange, 692, 520),
            ("wide", .systemTeal, 894, 346),
            ("display", .systemIndigo, 1920, 1080),
            ("older", .systemPurple, 1920, 1080),
        ]
        return specs.map { name, color, width, height in
            let url = folder.appendingPathComponent("\(name).png")
            let image = NSImage(size: NSSize(width: width, height: height))
            image.lockFocus()
            color.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
            image.unlockFocus()
            if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
            }
            return url
        }
    }

    /// Three solid shots so the carousel and a resized panel can be checked
    /// without using the Desktop.
    @MainActor
    private static func writeSamples() -> [URL] {
        let folder = URL(fileURLWithPath: "/tmp/shotpanel-carousel", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let colors: [(String, NSColor)] = [
            ("blue", .systemBlue),
            ("green", .systemGreen),
            ("red", .systemRed),
        ]
        return colors.map { name, color in
            let url = folder.appendingPathComponent("\(name).png")
            let image = NSImage(size: NSSize(width: 640, height: 400))
            image.lockFocus()
            color.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 640, height: 400)).fill()
            image.unlockFocus()
            if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
            }
            return url
        }
    }

    @MainActor
    private static func write(_ shelf: Shelf, to url: URL) {
        let size = shelf.layoutSize()
        let view = ShelfRoot(shelf: shelf, interactive: false)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            fputs("Could not render \(url.lastPathComponent)\n", stderr)
            return
        }
        try? png.write(to: url)
        fputs("\(url.lastPathComponent) \(Int(size.width))x\(Int(size.height))\n", stderr)
    }
}
