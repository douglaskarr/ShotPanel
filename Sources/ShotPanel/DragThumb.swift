import AppKit
import SwiftUI

/// Copy and Delete, centered on the selected screenshot.
enum ShotActions {
    static let button = NSSize(width: 96, height: 28)
    static let deleteAll = NSSize(width: 124, height: 28)
    static let promptWidth: CGFloat = 96
    static let yes = NSSize(width: 72, height: 28)
    static let cancel = NSSize(width: 88, height: 28)
    static let gap: CGFloat = 8
    /// The Delete all row when shots are stacked. Details sit under it.
    static let controlsRow: CGFloat = 40
    static let stackFooter: CGFloat = 80
    static let barFooter: CGFloat = 44
    static let grip: CGFloat = 16

    struct Hit {
        var copy: NSRect
        var delete: NSRect
    }

    struct ConfirmHit {
        var yes: NSRect
        var cancel: NSRect
    }

    /// Yes and Cancel, centered on the selected shot.
    static func confirm(in frame: CGRect) -> ConfirmHit {
        let row = yes.width + gap + cancel.width
        let yesRect = NSRect(
            x: frame.midX - row / 2,
            y: frame.midY - yes.height / 2 + 10,
            width: yes.width,
            height: yes.height
        )
        return ConfirmHit(
            yes: yesRect,
            cancel: NSRect(x: yesRect.maxX + gap, y: yesRect.minY, width: cancel.width, height: cancel.height)
        )
    }

    struct Bar {
        var prompt = NSRect.zero
        var primary = NSRect.zero
        var cancel = NSRect.zero
        var grip = NSRect.zero
    }

    /// Footer controls. `footerTop` is the top of the bar in the same coordinates as the photos.
    /// Vertical centers Delete all, or Yes and Cancel, with the drag grip.
    static func bar(width: CGFloat, footerTop: CGFloat, footer: CGFloat, vertical: Bool, confirming: Bool) -> Bar {
        let rowHeight = vertical ? controlsRow : footer
        let buttonY = footerTop + (rowHeight - deleteAll.height) / 2
        let gripY = footerTop + (rowHeight - grip) / 2
        if vertical {
            if confirming {
                let cluster = yes.width + gap + cancel.width + gap + grip
                var x = (width - cluster) / 2
                let yesRect = NSRect(x: x, y: buttonY, width: yes.width, height: yes.height)
                x = yesRect.maxX + gap
                let cancelRect = NSRect(x: x, y: buttonY, width: cancel.width, height: cancel.height)
                x = cancelRect.maxX + gap
                return Bar(
                    primary: yesRect,
                    cancel: cancelRect,
                    grip: NSRect(x: x, y: gripY, width: grip, height: grip)
                )
            }
            let cluster = deleteAll.width + gap + grip
            let x = (width - cluster) / 2
            let deleteRect = NSRect(x: x, y: buttonY, width: deleteAll.width, height: deleteAll.height)
            return Bar(
                primary: deleteRect,
                grip: NSRect(x: deleteRect.maxX + gap, y: gripY, width: grip, height: grip)
            )
        }
        if confirming {
            let prompt = NSRect(x: 10, y: buttonY, width: promptWidth, height: deleteAll.height)
            let yesRect = NSRect(x: prompt.maxX + gap, y: buttonY, width: yes.width, height: yes.height)
            let cancelRect = NSRect(x: yesRect.maxX + gap, y: buttonY, width: cancel.width, height: cancel.height)
            return Bar(prompt: prompt, primary: yesRect, cancel: cancelRect)
        }
        return Bar(primary: NSRect(x: 10, y: buttonY, width: deleteAll.width, height: deleteAll.height))
    }

    /// Rects are in the same coordinates as `frame` (top-left origin, y downward).
    /// A short wide shot stacks the buttons. A very short one uses a smaller pair
    /// so Copy and Delete still land on every shot that is actually on screen.
    static func hit(in frame: CGRect) -> Hit? {
        if let hit = place(button, in: frame) { return hit }
        let compact = NSSize(width: min(button.width, max(72, frame.width - 8)), height: 22)
        return place(compact, in: frame)
    }

    private static func place(_ button: NSSize, in frame: CGRect) -> Hit? {
        let across = button.width * 2 + gap
        if frame.width >= across + 8, frame.height >= button.height + 8 {
            let x = frame.minX + (frame.width - across) / 2
            let y = frame.minY + (frame.height - button.height) / 2
            let copy = NSRect(x: x, y: y, width: button.width, height: button.height)
            return Hit(copy: copy, delete: NSRect(x: copy.maxX + gap, y: y, width: button.width, height: button.height))
        }
        let stacked = button.height * 2 + gap
        guard frame.width >= button.width + 8, frame.height >= stacked + 4 else { return nil }
        let x = frame.minX + (frame.width - button.width) / 2
        let y = frame.minY + (frame.height - stacked) / 2
        let copy = NSRect(x: x, y: y, width: button.width, height: button.height)
        return Hit(copy: copy, delete: NSRect(x: x, y: copy.maxY + gap, width: button.width, height: button.height))
    }
}

/// Clear cover over the row. Click selects a screenshot, double-click opens
/// it, and a drag of the selected shot hands the file to another app.
struct CardControl: NSViewRepresentable {
    let allowsDeleteAll: Bool
    let shelf: Shelf

    func makeNSView(context: Context) -> CardView {
        let view = CardView()
        configure(view)
        return view
    }

    func updateNSView(_ view: CardView, context: Context) {
        configure(view)
    }

    /// The row covers the whole card. A fitting size of zero would leave
    /// every shot past the first one without a click target.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CardView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    private func configure(_ view: CardView) {
        let shelf = shelf
        let allowsDeleteAll = allowsDeleteAll
        view.sync = { [weak view] in
            guard let view else { return }
            CardControl.apply(shelf, allowsDeleteAll: allowsDeleteAll, to: view)
        }
        view.sync()
    }

    private static func apply(_ shelf: Shelf, allowsDeleteAll: Bool, to view: CardView) {
        let page = shelf.carouselPage
        view.hero = true
        view.allowsDeleteAll = allowsDeleteAll
        view.targets = page.onScreen().compactMap { item in
            guard shelf.shots.indices.contains(item.index) else { return nil }
            let shot = shelf.shots[item.index]
            let frame = item.frame
            return CardView.ShotTarget(
                path: shot.path,
                url: shot.url,
                image: shot.image,
                frame: frame
            )
        }
        view.onCopy = { [weak view] in
            guard let shot = shelf.shot(path: view?.activePath) else { return }
            shelf.select(shot)
        }
        view.onCopyImage = { [weak view] in
            guard let shot = shelf.shot(path: view?.activePath) else { return }
            shelf.copy(shot)
        }
        view.onClearSelection = { shelf.clearSelection() }
        if let selected = view.targets.first(where: { $0.path == shelf.selectedPath }),
           let hit = ShotActions.hit(in: selected.frame) {
            view.hasActions = true
            view.actionCopy = hit.copy
            view.actionDelete = hit.delete
        } else {
            view.hasActions = false
        }
        view.selectedPath = shelf.selectedPath
        view.confirmingSelection = shelf.confirmingPath != nil
        view.footerHeight = shelf.metrics.footer
        view.hasConfirm = false
        if let selected = view.targets.first(where: { $0.path == shelf.selectedPath }),
           shelf.confirmingPath == selected.path {
            let confirm = ShotActions.confirm(in: selected.frame)
            view.actionYes = confirm.yes
            view.actionCancel = confirm.cancel
            view.hasConfirm = true
        }
        view.onCommitShot = { shelf.commitDelete() }
        view.onCancelShot = { shelf.cancelDelete() }
        view.onOpen = { [weak view] in
            guard let shot = shelf.shot(path: view?.activePath) else { return }
            shelf.open(shot)
        }
        view.onTrash = { [weak view] in
            guard let shot = shelf.shot(path: view?.activePath) else { return }
            shelf.armDelete(shot)
        }
        view.onDeleteAll = { shelf.armDeleteAll() }
        view.onCommitAll = { shelf.commitDeleteAll() }
        view.onCancelAll = { shelf.cancelDeleteAll() }
        view.confirmingDeleteAll = shelf.confirmingDeleteAll
        view.onDragStart = { [weak view] in
            guard let path = view?.activePath else { return }
            shelf.dragStarted(path: path)
        }
        view.onDragEnd = { shelf.dragEnded(operation: $0) }
        view.onMoveStart = { shelf.beginReposition() }
        view.onMove = { shelf.reposition(to: $0) }
        view.onMoveEnd = { shelf.endReposition() }
        view.onMinimize = { shelf.minimize() }
        view.vertical = shelf.axis == .vertical
        view.alignHitArea()
        view.onScrub = { shelf.scrub(by: $0) }
        view.onStepOlder = { shelf.step(older: true) }
        view.onStepNewer = { shelf.step(older: false) }
        view.arrowsVisible = shelf.pointerInside || shelf.windowIsKey
        view.showsOlder = page.showsOlder
        view.showsNewer = page.showsNewer
        view.menuProvider = { [weak view] in
            shelf.panelMenu(for: shelf.shot(path: view?.activePath))
        }
    }
}

struct ThumbControl: NSViewRepresentable {
    let shot: Shot
    let shelf: Shelf

    func makeNSView(context: Context) -> CardView {
        let view = CardView()
        configure(view)
        return view
    }

    func updateNSView(_ view: CardView, context: Context) {
        configure(view)
    }

    private func configure(_ view: CardView) {
        let shot = shot
        let shelf = shelf
        view.url = shot.url
        view.image = shot.image
        view.hero = false
        view.allowsDeleteAll = false
        view.toolTip = shot.url.lastPathComponent
        view.onCopy = { shelf.copy(shot) }
        view.onOpen = { shelf.open(shot) }
        view.onTrash = { shelf.armDelete(shot) }
        view.onDeleteAll = {}
        view.onDragStart = { shelf.dragStarted(path: shot.path) }
        view.onDragEnd = { shelf.dragEnded(operation: $0) }
        view.menuProvider = { shelf.menu(for: shot) }
    }
}

final class CardView: NSView, NSDraggingSource {
    struct ShotTarget {
        var path: String
        var url: URL
        var image: NSImage?
        var frame: NSRect
    }

    var url: URL?
    var image: NSImage?
    var targets: [ShotTarget] = []
    var activePath: String?
    var hero = false
    var allowsDeleteAll = false
    var onCopy: () -> Void = {}
    var onCopyImage: () -> Void = {}
    var onClearSelection: () -> Void = {}
    var hasActions = false
    var selectedPath: String?
    var actionCopy = NSRect.zero
    var actionDelete = NSRect.zero
    var onOpen: () -> Void = {}
    var onTrash: () -> Void = {}
    var onDeleteAll: () -> Void = {}
    var onCommitAll: () -> Void = {}
    var onCancelAll: () -> Void = {}
    var onCommitShot: () -> Void = {}
    var onCancelShot: () -> Void = {}
    var confirmingDeleteAll = false
    var hasConfirm = false
    var actionYes = NSRect.zero
    var actionCancel = NSRect.zero
    /// Yes and Cancel are on the image, so the Copy and Delete rects must not
    /// take the click while that question is up.
    var confirmingSelection = false
    var onDragStart: () -> Void = {}
    var onDragEnd: (NSDragOperation) -> Void = { _ in }
    var onMoveStart: () -> Void = {}
    var onMove: (NSPoint) -> Void = { _ in }
    var onMoveEnd: () -> Void = {}
    var onMinimize: () -> Void = {}
    /// The list runs top to bottom, so scroll and slide follow that direction.
    var vertical = false
    /// Reloads photo frames from the shelf. A resize moves the pictures before
    /// this view's cached frames catch up, so every click reloads them.
    var sync: () -> Void = {}
    var onScrub: (CGFloat) -> Void = { _ in }
    var onStepOlder: () -> Void = {}
    var onStepNewer: () -> Void = {}
    /// Scroll arrows are drawn while the pointer is over the panel or it is key.
    var arrowsVisible = false
    var showsOlder = false
    var showsNewer = false
    var menuProvider: () -> NSMenu = { NSMenu() }

    private enum Press { case none, card, deleteAll, commitAll, cancelAll, commitShot, cancelShot, minimize, move, copyShot, deleteShot, clearSelection, scrub, stepOlder, stepNewer, cancelled }
    private var press: Press = .none
    private var downPoint: NSPoint?
    /// A drag that starts on a photo exports that one file. The row slides
    /// only from a press in the gap, or from a scroll.
    private var dragExports = false
    private var pressedPhoto = false
    private var startedDrag = false
    private var activeImage: NSImage?
    private var activeFrame: NSRect?
    private var lastScrubX: CGFloat?
    private var windowDrag = PointerDrag()

    var footerHeight: CGFloat = 44
    private let deleteButton = ShotActions.deleteAll
    private let discardSize: CGFloat = 26
    private let discardInset: CGFloat = 8

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        alignHitArea()
    }

    override func layout() {
        super.layout()
        alignHitArea()
    }

    /// The click area has to match the photos. A resize can leave this view
    /// scaled, so a point over the second shot lands in the old coordinates.
    func alignHitArea() {
        let size = frame.size
        guard size.width > 1, size.height > 1 else { return }
        if bounds.size != size || bounds.origin != .zero {
            bounds = NSRect(origin: .zero, size: size)
        }
    }

    private func eventPoint(_ event: NSEvent) -> NSPoint {
        sync()
        alignHitArea()
        return convert(event.locationInWindow, from: nil)
    }

    /// The photo row. The footer under it moves the window.
    private var imageRow: NSRect {
        NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - footerHeight))
    }

    /// A finger on a Magic Mouse, or a trackpad scroll along the list, slides it.
    /// Moving the pointer without touching does not.
    override func scrollWheel(with event: NSEvent) {
        guard hero, imageRow.contains(eventPoint(event)) else { return }
        var along = vertical ? event.scrollingDeltaY : event.scrollingDeltaX
        let across = vertical ? event.scrollingDeltaX : event.scrollingDeltaY
        if !event.hasPreciseScrollingDeltas { along *= 16 }
        guard abs(along) > 0.15, abs(along) >= abs(across) else { return }
        onScrub(along)
    }

    override func mouseDown(with event: NSEvent) {
        let point = eventPoint(event)
        lastScrubX = nil
        startedDrag = false
        windowDrag.clear()
        downPoint = point
        dragExports = false
        pressedPhoto = false
        let photo = photo(at: point)
        if hero, minimizeRect.contains(point) {
            press = .minimize
            return
        }
        if hero, arrowsVisible, showsNewer, arrowRect(older: false).insetBy(dx: -6, dy: -6).contains(point) {
            press = .stepNewer
            return
        }
        if hero, arrowsVisible, showsOlder, arrowRect(older: true).insetBy(dx: -6, dy: -6).contains(point) {
            press = .stepOlder
            return
        }
        if allowsDeleteAll, confirmingDeleteAll, yesRect.insetBy(dx: -4, dy: -4).contains(point) {
            press = .commitAll
            return
        }
        if allowsDeleteAll, confirmingDeleteAll, cancelRect.insetBy(dx: -4, dy: -4).contains(point) {
            press = .cancelAll
            return
        }
        if allowsDeleteAll, !confirmingDeleteAll, deleteRect.insetBy(dx: -4, dy: -4).contains(point) {
            press = .deleteAll
            return
        }
        // A short click must stay a click; only a real drag picks the file up.
        // While “Are you sure?” is on this shot, those rects stay quiet so
        // another photo can be chosen and Yes or Cancel can take the click.
        let asking = confirmingSelection && photo?.path == selectedPath
        if let photo, asking, hasConfirm, hit(actionYes, point) {
            remember(photo)
            pressedPhoto = true
            dragExports = true
            press = .commitShot
            return
        }
        if let photo, asking, hasConfirm, hit(actionCancel, point) {
            remember(photo)
            pressedPhoto = true
            press = .cancelShot
            return
        }
        if let photo, !asking, photo.path == selectedPath, hasActions, hit(actionCopy, point) {
            remember(photo)
            pressedPhoto = true
            dragExports = true
            press = .copyShot
            return
        }
        if let photo, !asking, photo.path == selectedPath, hasActions, hit(actionDelete, point) {
            remember(photo)
            pressedPhoto = true
            dragExports = true
            press = .deleteShot
            return
        }
        if let photo {
            remember(photo)
            pressedPhoto = true
            let chosen = photo.path == selectedPath
            dragExports = true
            if !asking, chosen, hasActions, actionCopy.contains(point) {
                press = .copyShot
                return
            }
            if !asking, chosen, hasActions, actionDelete.contains(point) {
                press = .deleteShot
                return
            }
            if event.clickCount == 2 {
                press = .none
                downPoint = nil
                onOpen()
                return
            }
            press = .card
            if !chosen { onCopy() }
            return
        }
        if hero, footerRect.contains(point) {
            // Double-click the bar to minimize, the same way a title bar does.
            if event.clickCount == 2 {
                press = .none
                downPoint = nil
                onMinimize()
                return
            }
            press = .move
            return
        }
        if targets.isEmpty {
            if event.clickCount == 2 {
                press = .none
                downPoint = nil
                onOpen()
                return
            }
            press = .card
            return
        }
        let imageHeight = max(0, bounds.height - footerHeight)
        press = point.y < imageHeight ? .clearSelection : .none
    }

    /// A few points of slop, so the click lands on the capsule the user sees.
    private func hit(_ rect: NSRect, _ point: NSPoint) -> Bool {
        rect.insetBy(dx: -8, dy: -8).contains(point)
    }

    private func remember(_ target: ShotTarget) {
        activePath = target.path
        activeImage = target.image
        activeFrame = target.frame
        url = target.url
        image = target.image
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint else { return }
        let point = eventPoint(event)
        if press == .move {
            if !windowDrag.isTracking {
                windowDrag.begin(in: window)
                onMoveStart()
            }
            if let origin = windowDrag.origin() { onMove(origin) }
            return
        }
        if press == .scrub {
            // Sliding the row must not turn into a file drop. A pointer that
            // slips onto the Desktop would move a shot out from under the stack.
            guard imageRow.contains(point) else { return }
            if let last = lastScrubX {
                let step = (vertical ? point.y : point.x) - last
                if abs(step) >= 0.5 { onScrub(step) }
            }
            lastScrubX = vertical ? point.y : point.x
            return
        }
        let dx = point.x - start.x
        let dy = point.y - start.y
        let distance = hypot(dx, dy)
        let onButton = press == .copyShot || press == .deleteShot || press == .commitShot || press == .cancelShot || press == .deleteAll || press == .commitAll || press == .cancelAll || press == .stepOlder || press == .stepNewer
        guard distance > (onButton ? 22 : 8) else { return }
        if press == .deleteAll || press == .commitAll || press == .cancelAll || press == .cancelShot || press == .minimize || press == .stepOlder || press == .stepNewer {
            press = .cancelled
            return
        }
        // Copy and Delete sit in the middle of the selected shot. A drag
        // that starts there still picks the file up.
        if dragExports, press == .card || press == .copyShot || press == .deleteShot || press == .commitShot {
            beginFileDrag(with: event)
            return
        }
        let along = vertical ? dy : dx
        let across = vertical ? dx : dy
        if press == .card || press == .clearSelection, abs(along) > abs(across) {
            press = .scrub
            lastScrubX = vertical ? point.y : point.x
            onScrub(along)
            return
        }
        if press == .card {
            beginFileDrag(with: event)
        }
    }

    private func beginFileDrag(with event: NSEvent) {
        guard press == .card || press == .scrub || press == .copyShot || press == .deleteShot || press == .commitShot,
              !startedDrag, let url else { return }
        startedDrag = true
        press = .none
        lastScrubX = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(activeFrame ?? imageFrame(), contents: activeImage ?? image)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        onDragStart()
    }

    override func mouseUp(with event: NSEvent) {
        let point = eventPoint(event)
        let action = press
        let moved = windowDrag.isTracking
        let distance = downPoint.map { hypot(point.x - $0.x, point.y - $0.y) } ?? 0
        press = .none
        downPoint = nil
        lastScrubX = nil
        dragExports = false
        windowDrag.clear()
        if moved {
            onMoveEnd()
            return
        }
        guard !startedDrag else { return }
        // A short slide is still a click, so the buttons follow the photo.
        if action == .scrub, distance < 14, let photo = photo(at: point) {
            remember(photo)
            onCopy()
            return
        }
        switch action {
        case .minimize where minimizeRect.contains(point):
            onMinimize()
        case .copyShot where distance < 22:
            onCopyImage()
        case .deleteShot where distance < 22:
            onTrash()
        case .deleteAll where distance < 22:
            onDeleteAll()
        case .commitAll where distance < 22:
            onCommitAll()
        case .cancelAll where distance < 22:
            onCancelAll()
        case .commitShot where distance < 22:
            onCommitShot()
        case .cancelShot where distance < 22:
            onCancelShot()
        case .stepOlder where distance < 14:
            onStepOlder()
        case .stepNewer where distance < 14:
            onStepNewer()
        case .clearSelection where distance < 8:
            onClearSelection()
        case .card:
            if let photo = photo(at: point) {
                remember(photo)
            }
            onCopy()
        case .scrub:
            break
        default:
            break
        }
    }

    override func resetCursorRects() {
        if hero {
            addCursorRect(footerRect, cursor: .openHand)
            addCursorRect(minimizeRect, cursor: .arrow)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = eventPoint(event)
        if let target = photo(at: point) {
            remember(target)
        } else {
            activePath = nil
        }
        NSMenu.popUpContextMenu(menuProvider(), with: event, for: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // Apps take a copy and the shot stays. Finder takes a move, so a
        // folder keeps the file and it leaves the panel. Delete is the Trash.
        context == .outsideApplication ? [.copy, .move, .delete] : []
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        startedDrag = false
        downPoint = nil
        press = .none
        onDragEnd(operation)
    }

    override func accessibilityLabel() -> String? { "Screenshot" }
    override func isAccessibilityElement() -> Bool { true }

    private var minimizeRect: NSRect {
        NSRect(x: discardInset, y: discardInset, width: discardSize, height: discardSize)
    }

    /// Matches the chevron drawn on that edge of the photo row.
    private func arrowRect(older: Bool) -> NSRect {
        let side: CGFloat = 28
        let heroHeight = max(0, bounds.height - footerHeight)
        if vertical {
            let x = (bounds.width - side) / 2
            let y = older ? heroHeight - side - 8 : 8
            return NSRect(x: x, y: y, width: side, height: side)
        }
        let y = (heroHeight - side) / 2
        let x = older ? bounds.width - side - 8 : 8
        return NSRect(x: x, y: y, width: side, height: side)
    }

    private var footerRect: NSRect {
        NSRect(x: 0, y: bounds.height - footerHeight, width: bounds.width, height: footerHeight)
    }

    /// The photo drawn on top wins when frames overlap.
    private func photo(at point: NSPoint) -> ShotTarget? {
        targets.last(where: { $0.frame.contains(point) })
    }

    /// Which shot contains a window point. Used to check clicks in both orientations.
    func path(atWindowPoint point: NSPoint) -> String? {
        sync()
        alignHitArea()
        return photo(at: convert(point, from: nil))?.path
    }

    private var barLayout: ShotActions.Bar {
        ShotActions.bar(
            width: bounds.width,
            footerTop: bounds.height - footerHeight,
            footer: footerHeight,
            vertical: vertical,
            confirming: confirmingDeleteAll
        )
    }

    private var deleteRect: NSRect { barLayout.primary }

    /// Yes, beside “Are you sure?” in the bottom bar.
    private var yesRect: NSRect { barLayout.primary }

    private var cancelRect: NSRect { barLayout.cancel }

    /// Drag preview matches the photo, not the footer bar.
    private func imageFrame() -> NSRect {
        let areaHeight = hero ? max(0, bounds.height - footerHeight) : bounds.height
        let area = NSRect(x: 0, y: 0, width: bounds.width, height: areaHeight)
        guard let size = image?.size, size.width > 0, size.height > 0 else { return area }
        let scale = min(area.width / size.width, area.height / size.height)
        let width = size.width * scale
        let height = size.height * scale
        return NSRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
    }
}

/// Transparent cover exactly as large as the Copy or Delete capsule.
/// A click runs that action. A longer drag still exports the file.
struct ActionCatcher: NSViewRepresentable {
    var url: URL
    var image: NSImage?
    var onClick: () -> Void
    var onDragStart: () -> Void
    var onDragEnd: (NSDragOperation) -> Void

    func makeNSView(context: Context) -> ActionCatcherView {
        let view = ActionCatcherView()
        configure(view)
        return view
    }

    func updateNSView(_ view: ActionCatcherView, context: Context) {
        configure(view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ActionCatcherView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? ShotActions.button.width, height: proposal.height ?? ShotActions.button.height)
    }

    private func configure(_ view: ActionCatcherView) {
        view.url = url
        view.preview = image
        view.onClick = onClick
        view.onDragStart = onDragStart
        view.onDragEnd = onDragEnd
    }
}

final class ActionCatcherView: NSView, NSDraggingSource {
    var url: URL?
    var preview: NSImage?
    var onClick: () -> Void = {}
    var onDragStart: () -> Void = {}
    var onDragEnd: (NSDragOperation) -> Void = { _ in }
    private var down: NSPoint?
    private var dragging = false

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        down = convert(event.locationInWindow, from: nil)
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down, let url, !dragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - down.x, point.y - down.y) > 18 else { return }
        dragging = true
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: preview)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        onDragStart()
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let distance = down.map { hypot(point.x - $0.x, point.y - $0.y) } ?? 0
        down = nil
        guard !dragging, distance < 18 else { return }
        onClick()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .delete] : []
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        dragging = false
        down = nil
        onDragEnd(operation)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func fire() { handler() }
}
