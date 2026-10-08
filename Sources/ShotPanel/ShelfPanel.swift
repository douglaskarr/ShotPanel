import AppKit
import SwiftUI

/// Borderless window the user can drag and minimize into the Dock.
/// It floats over normal windows. Full screen spaces are hidden separately
/// so a video is left alone.
final class ShelfPanel: NSWindow {
    init(root: HoverRoot) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.borderless, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "ShotPanel"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        // Stay on the desktop the user is already on. Joining every space
        // pulls them out of the one they were using and shows every window.
        collectionBehavior = [.moveToActiveSpace]
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        isMovable = true
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        contentView = root
        root.frame = contentLayoutRect
        root.autoresizingMask = [.width, .height]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Borderless windows only reach the Dock when this bit is set, and the
    /// app has to be active or macOS drops the miniaturize.
    override func miniaturize(_ sender: Any?) {
        styleMask.insert(.miniaturizable)
        NSApp.activate()
        super.miniaturize(sender)
    }

    static func screenUnderPointer() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

/// Watches the pointer for the whole widget, including the gaps between shots.
final class HoverRoot: NSView {
    let host: NSHostingView<ShelfRoot>
    var onHover: (Bool) -> Void = { _ in }

    init(shelf: Shelf) {
        host = NSHostingView(rootView: ShelfRoot(shelf: shelf))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        host.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        // Resizing the panel resets the tracking area and can report an exit
        // while the pointer is still over the widget. Trust the frame.
        if window?.frame.contains(NSEvent.mouseLocation) == true { return }
        onHover(false)
    }
}

/// Drags the window from its padding, or from the whole empty widget.
/// Clicks in the middle fall through to the screenshots.
struct MoveSurface: NSViewRepresentable {
    var margin: CGFloat
    var minimizeCorner: Bool
    let shelf: Shelf

    func makeNSView(context: Context) -> MoveSurfaceView {
        MoveSurfaceView()
    }

    func updateNSView(_ view: MoveSurfaceView, context: Context) {
        view.margin = margin
        view.minimizeCorner = minimizeCorner
        view.onMinimize = { shelf.minimize() }
        view.onBegin = { shelf.beginReposition() }
        view.onMove = { shelf.reposition(to: $0) }
        view.onEnd = { shelf.endReposition() }
        view.menuProvider = { shelf.panelMenu(for: nil) }
    }
}

final class MoveSurfaceView: NSView {
    var margin: CGFloat = 10
    var minimizeCorner = false
    var onMinimize: () -> Void = {}
    var onBegin: () -> Void = {}
    var onMove: (NSPoint) -> Void = { _ in }
    var onEnd: () -> Void = {}
    var menuProvider: () -> NSMenu = { NSMenu() }

    private var drag = PointerDrag()
    private var pressingMinimize = false

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if minimizeCorner, minimizeRect.contains(local) { return self }
        let inner = bounds.insetBy(dx: margin, dy: margin)
        if margin > 0, inner.contains(local) { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pressingMinimize = minimizeCorner && minimizeRect.contains(point)
        guard !pressingMinimize else { return }
        drag.begin(in: window)
        onBegin()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !pressingMinimize, let origin = drag.origin() else { return }
        onMove(origin)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if pressingMinimize, minimizeRect.contains(point) {
            pressingMinimize = false
            onMinimize()
            return
        }
        pressingMinimize = false
        guard drag.isTracking else { return }
        drag.clear()
        onEnd()
    }

    override func rightMouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(menuProvider(), with: event, for: self)
    }

    override func resetCursorRects() {
        if margin <= 0 {
            addCursorRect(bounds, cursor: .openHand)
            return
        }
        addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: margin), cursor: .openHand)
        addCursorRect(NSRect(x: 0, y: bounds.height - margin, width: bounds.width, height: margin), cursor: .openHand)
        addCursorRect(NSRect(x: 0, y: 0, width: margin, height: bounds.height), cursor: .openHand)
        addCursorRect(NSRect(x: bounds.width - margin, y: 0, width: margin, height: bounds.height), cursor: .openHand)
    }

    private var minimizeRect: NSRect {
        NSRect(x: 8, y: 8, width: 26, height: 26)
    }
}

/// Which edges of the panel a drag should pull.
struct ResizeEdges: OptionSet {
    let rawValue: Int
    static let left = ResizeEdges(rawValue: 1 << 0)
    static let right = ResizeEdges(rawValue: 1 << 1)
    static let bottom = ResizeEdges(rawValue: 1 << 2)
    static let top = ResizeEdges(rawValue: 1 << 3)
}

/// A strip or corner that resizes the window. Interior clicks are not this view.
struct ResizeSurface: NSViewRepresentable {
    var edges: ResizeEdges
    let shelf: Shelf

    func makeNSView(context: Context) -> ResizeSurfaceView {
        ResizeSurfaceView()
    }

    func updateNSView(_ view: ResizeSurfaceView, context: Context) {
        view.edges = edges
        view.onBegin = { shelf.beginResize() }
        view.onResize = { shelf.resize(to: $0) }
        view.onEnd = { shelf.endResize() }
        view.menuProvider = { shelf.panelMenu(for: nil) }
        view.vertical = shelf.axis == .vertical
    }
}

final class ResizeSurfaceView: NSView {
    var edges: ResizeEdges = []
    var onBegin: () -> Void = {}
    var onResize: (NSRect) -> Void = { _ in }
    var onEnd: () -> Void = {}
    var menuProvider: () -> NSMenu = { NSMenu() }
    /// A stacked list grows taller only, unless the drag is a plain side edge.
    var vertical = false

    private var startMouse: NSPoint?
    private var startFrame: NSRect?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startFrame = window?.frame
        onBegin()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let frame = resizedFrame() else { return }
        onResize(frame)
    }

    override func mouseUp(with event: NSEvent) {
        guard startMouse != nil else { return }
        if let frame = resizedFrame() { onResize(frame) }
        startMouse = nil
        startFrame = nil
        onEnd()
    }

    override func rightMouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(menuProvider(), with: event, for: self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: resizeCursor)
    }

    private var resizeCursor: NSCursor {
        if #available(macOS 15, *) {
            return NSCursor.frameResize(position: resizePosition, directions: [.inward, .outward])
        }
        if edges.contains(.left) || edges.contains(.right), !edges.contains(.top), !edges.contains(.bottom) {
            return .resizeLeftRight
        }
        if edges.contains(.top) || edges.contains(.bottom), !edges.contains(.left), !edges.contains(.right) {
            return .resizeUpDown
        }
        return .crosshair
    }

    @available(macOS 15, *)
    private var resizePosition: NSCursor.FrameResizePosition {
        switch (edges.contains(.top), edges.contains(.bottom), edges.contains(.left), edges.contains(.right)) {
        case (true, _, true, _): return .topLeft
        case (true, _, _, true): return .topRight
        case (_, true, true, _): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .top
        case (_, true, _, _): return .bottom
        case (_, _, true, _): return .left
        default: return .right
        }
    }

    /// The grabbed edge follows the pointer. The opposite edge stays put.
    private func resizedFrame() -> NSRect? {
        guard let startMouse, let start = startFrame else { return nil }
        let now = NSEvent.mouseLocation
        let dx = now.x - startMouse.x
        let dy = now.y - startMouse.y
        var width = start.width
        var height = start.height
        let alongStack = vertical && (edges.contains(.top) || edges.contains(.bottom))
        if !alongStack, edges.contains(.right) { width = start.width + dx }
        if !alongStack, edges.contains(.left) { width = start.width - dx }
        if edges.contains(.top) { height = start.height + dy }
        if edges.contains(.bottom) { height = start.height - dy }
        let limit = window?.screen?.visibleFrame ?? start
        width = min(max(width, Metrics.minPanel.width), max(Metrics.minPanel.width, limit.width - 8))
        height = min(max(height, Metrics.minPanel.height), max(Metrics.minPanel.height, limit.height - 8))
        let x = edges.contains(.left) ? start.maxX - width : start.origin.x
        let y = edges.contains(.bottom) ? start.maxY - height : start.origin.y
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

/// Remembers where the pointer and the window were when a drag started.
struct PointerDrag {
    private var startMouse: NSPoint?
    private var startOrigin: NSPoint?
    var isTracking: Bool { startMouse != nil }

    mutating func begin(in window: NSWindow?) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin
    }

    func origin() -> NSPoint? {
        guard let startMouse, let startOrigin else { return nil }
        let now = NSEvent.mouseLocation
        return NSPoint(x: startOrigin.x + now.x - startMouse.x, y: startOrigin.y + now.y - startMouse.y)
    }

    mutating func clear() {
        startMouse = nil
        startOrigin = nil
    }
}
