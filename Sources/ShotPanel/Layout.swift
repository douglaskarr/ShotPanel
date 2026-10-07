import AppKit

/// Sizes for the corner widget. The latest shot stays large enough to read
/// headings and controls. When several shots fit across the panel at that
/// height, they sit side by side with space between them.
struct Metrics: Equatable {
    var hero = CGSize(width: 460, height: 288)
    var footer: CGFloat = 44
    var minThumb: CGFloat = 140
    var maxThumb: CGFloat = 230
    var outerPad: CGFloat = 10
    var gap: CGFloat = 8
    var maxWidth: CGFloat = 1200
    var outerCorner: CGFloat = 22
    var innerCorner: CGFloat = 16

    var cardHeight: CGFloat { hero.height + footer }

    static let minPanel = NSSize(width: 280, height: 200)
    static let emptyPanel = NSSize(width: 300, height: 96)

    static func make(visible: CGRect) -> Metrics {
        var metrics = Metrics()
        metrics.maxWidth = max(320, visible.width - 32)
        if visible.width < 1280 || visible.height < 820 {
            metrics.hero = CGSize(width: 380, height: 240)
            metrics.maxThumb = 200
            metrics.minThumb = 120
        }
        if metrics.hero.width + metrics.outerPad * 2 > metrics.maxWidth {
            let width = metrics.maxWidth - metrics.outerPad * 2
            metrics.hero = CGSize(width: width, height: (width * 0.625).rounded())
        }
        return metrics
    }

    /// The window size for one screenshot at the current hero size.
    func defaultPanelSize() -> NSSize {
        NSSize(width: hero.width + outerPad * 2, height: cardHeight + outerPad * 2)
    }

    /// Grows or shrinks the photo area to fill a window the user resized.
    /// A vertical list keeps a taller bar so the shot details fit under the controls.
    func adopted(panel: NSSize, axis: CarouselFit.Axis) -> Metrics {
        var copy = self
        copy.footer = axis == .vertical ? ShotActions.stackFooter : ShotActions.barFooter
        let width = panel.width - outerPad * 2
        let height = panel.height - outerPad * 2 - copy.footer
        guard width >= 40, height >= 40 else { return copy }
        copy.hero = CGSize(width: width, height: height)
        return copy
    }

    func thumbWidth(for pixelSize: CGSize) -> CGFloat {
        let aspect = pixelSize.width / max(pixelSize.height, 1)
        return min(max((hero.height * aspect).rounded(), minThumb), maxThumb)
    }

    func panelSize(shots: [Shot], expanded: Bool) -> NSSize {
        if shots.isEmpty { return NSSize(width: 300, height: 96) }
        let height = cardHeight + outerPad * 2
        guard expanded, shots.count > 1 else {
            return NSSize(width: hero.width + outerPad * 2, height: height)
        }
        let natural = outerPad + olderWidth(shots: shots) + gap + hero.width + outerPad
        let width = min(max(natural, hero.width + outerPad * 2), maxWidth)
        return NSSize(width: width, height: height)
    }

    /// True when the open strip is wider than the screen and must scroll.
    func overflows(shots: [Shot]) -> Bool {
        guard shots.count > 1 else { return false }
        let natural = outerPad + olderWidth(shots: shots) + gap + hero.width + outerPad
        return natural > maxWidth + 0.5
    }

    func olderWidth(shots: [Shot]) -> CGFloat {
        let older = shots.dropFirst()
        var width = CGFloat(0)
        for (index, shot) in older.enumerated() {
            if index > 0 { width += gap }
            width += thumbWidth(for: shot.pixelSize)
        }
        return width
    }

    func stripWidth(shots: [Shot], expanded: Bool) -> CGFloat {
        guard expanded, shots.count > 1 else { return 0 }
        let panel = panelSize(shots: shots, expanded: expanded)
        return max(0, panel.width - outerPad * 2 - gap - hero.width)
    }
}

/// Every screenshot in one row. The panel clips the row. When more shots
/// sit off the left or right, a sliver of the next one stays in view, faded.
enum CarouselFit {
    /// Space between side-by-side shots.
    static let gap: CGFloat = 12
    /// How much of the next shot stays visible when more shots are off that side.
    static let peek: CGFloat = 56

    struct Item: Identifiable, Equatable {
        var index: Int
        /// Photo rect in the image row. Origin is the top-left, y grows downward.
        var frame: CGRect
        /// A clipped neighbor, drawn lighter than the shots that fit.
        var isPeek = false
        var id: Int { index }
    }

    /// Horizontal runs left to right. Vertical stacks top to bottom.
    /// Newest stays at the start: the left edge, or the top.
    enum Axis: String {
        case horizontal
        case vertical
    }

    struct Page: Equatable {
        var items: [Item] = []
        var showsOlder = false
        var showsNewer = false
        var maxOffset: CGFloat = 0
        /// Offset after the sliver adjustment. Scrubbing starts from this.
        var appliedOffset: CGFloat = 0
        var viewport = CGSize.zero
        var axis = Axis.horizontal

        func onScreen() -> [Item] {
            let bounds = CGRect(origin: .zero, size: viewport)
            return items.filter { item in
                let hit = item.frame.intersection(bounds)
                return hit.width > 1 && hit.height > 1
            }
        }

        /// Shots that are mostly inside the panel, ignoring a thin sliver.
        func settled() -> [Item] {
            let bounds = CGRect(origin: .zero, size: viewport)
            let full = items.filter { item in
                let hit = item.frame.intersection(bounds)
                let along = axis == .vertical ? hit.height : hit.width
                let fullLength = axis == .vertical ? item.frame.height : item.frame.width
                return fullLength > 1 && along > fullLength * 0.55
            }
            return full.isEmpty ? onScreen() : full
        }
    }

    static func page(shots: [Shot], offset: CGFloat, size: CGSize, axis: Axis = .horizontal) -> Page {
        let mainSpan = axis == .horizontal ? size.width : size.height
        let crossSpan = axis == .horizontal ? size.height : size.width
        guard mainSpan > 1, crossSpan > 1, !shots.isEmpty else {
            return Page(viewport: size, axis: axis)
        }
        // Laid out along x, then turned upright when the list is vertical.
        var strip: [Item] = []
        var cursor: CGFloat = 0
        for index in shots.indices {
            let ratio = aspect(of: shots[index])
            let layoutRatio = axis == .horizontal ? ratio : 1 / max(ratio, 0.01)
            let natural = crossSpan * layoutRatio
            var itemMain = natural
            var itemCross = crossSpan
            var crossOrigin: CGFloat = 0
            if shots.count == 1, natural > mainSpan {
                itemMain = mainSpan
                itemCross = mainSpan / max(layoutRatio, 0.01)
                crossOrigin = (crossSpan - itemCross) / 2
            }
            strip.append(Item(
                index: index,
                frame: CGRect(x: cursor, y: crossOrigin, width: itemMain, height: itemCross)
            ))
            cursor += itemMain + gap
        }
        let content = strip.last?.frame.maxX ?? 0
        let maxOffset = max(0, content - mainSpan)
        let offset = nudged(offset, strip: strip, width: mainSpan, maxOffset: maxOffset)
        let bounds = CGRect(origin: .zero, size: size)
        let items = strip.map { item in
            var layout = item.frame
            layout.origin.x -= offset
            let frame = placed(layout, axis: axis)
            let shown = frame.intersection(bounds)
            let alongShown = axis == .vertical ? shown.height : shown.width
            let alongFull = axis == .vertical ? frame.height : frame.width
            let clipped = axis == .vertical
                ? (frame.minY < -0.5 || frame.maxY > size.height + 0.5)
                : (frame.minX < -0.5 || frame.maxX > size.width + 0.5)
            let peeking = clipped && alongShown > 1 && alongFull > 1 && alongShown < alongFull * 0.5
            return Item(index: item.index, frame: frame, isPeek: peeking)
        }
        let older: Bool
        let newer: Bool
        if axis == .vertical {
            older = items.contains { $0.frame.minY >= size.height - 1 }
                || items.contains { $0.isPeek && $0.frame.midY > size.height * 0.5 }
            newer = items.contains { $0.frame.maxY <= 1 }
                || items.contains { $0.isPeek && $0.frame.midY < size.height * 0.5 }
        } else {
            older = items.contains { $0.frame.minX >= size.width - 1 }
                || items.contains { $0.isPeek && $0.frame.midX > size.width * 0.5 }
            newer = items.contains { $0.frame.maxX <= 1 }
                || items.contains { $0.isPeek && $0.frame.midX < size.width * 0.5 }
        }
        return Page(
            items: items,
            showsOlder: older,
            showsNewer: newer,
            maxOffset: maxOffset,
            appliedOffset: offset,
            viewport: size,
            axis: axis
        )
    }

    /// Layout space uses x as the list direction. Vertical turns that into y.
    private static func placed(_ layout: CGRect, axis: Axis) -> CGRect {
        guard axis == .vertical else { return layout }
        return CGRect(x: layout.minY, y: layout.minX, width: layout.height, height: layout.width)
    }

    /// Keeps a sliver of the next shot on any side that still has more.
    static func nudged(_ offset: CGFloat, strip: [Item], width: CGFloat, maxOffset: CGFloat) -> CGFloat {
        guard maxOffset > 0, width > peek * 2 else { return min(max(0, offset), maxOffset) }
        var offset = min(max(0, offset), maxOffset)
        if strip.contains(where: { $0.frame.minX >= width + offset - 1 }) {
            offset = revealRight(offset, strip: strip, width: width, maxOffset: maxOffset)
        }
        if strip.contains(where: { $0.frame.maxX <= offset + 1 }) {
            offset = min(offset, keepLeft(offset, strip: strip, width: width))
        }
        return min(max(0, offset), maxOffset)
    }

    /// Pulls the following shot in until `peek` points of it are inside the panel.
    private static func revealRight(_ offset: CGFloat, strip: [Item], width: CGFloat, maxOffset: CGFloat) -> CGFloat {
        let viewRight = width + offset
        if let crossing = strip.first(where: { $0.frame.minX < viewRight && $0.frame.maxX > viewRight }) {
            let visible = min(crossing.frame.maxX, viewRight) - max(crossing.frame.minX, offset)
            guard visible < peek else { return offset }
            return min(max(offset, crossing.frame.minX + peek - width), maxOffset)
        }
        guard let next = strip.first(where: { $0.frame.minX >= viewRight - 0.5 }) else { return offset }
        return min(max(offset, next.frame.minX - (width - peek)), maxOffset)
    }

    /// Leaves `peek` points of the previous shot inside the left edge.
    private static func keepLeft(_ offset: CGFloat, strip: [Item], width: CGFloat) -> CGFloat {
        let viewLeft = offset
        if let crossing = strip.last(where: { $0.frame.minX < viewLeft && $0.frame.maxX > viewLeft }) {
            let visible = crossing.frame.maxX - viewLeft
            guard visible < peek else { return offset }
            return min(offset, crossing.frame.maxX - peek)
        }
        guard let previous = strip.last(where: { $0.frame.maxX <= viewLeft + 0.5 }) else { return offset }
        return min(offset, previous.frame.maxX - peek)
    }

    private static func aspect(of shot: Shot) -> CGFloat {
        if shot.pixelSize.width > 1, shot.pixelSize.height > 1 {
            return shot.pixelSize.width / shot.pixelSize.height
        }
        if let image = shot.image, image.size.height > 1 {
            return image.size.width / max(image.size.height, 1)
        }
        return 16 / 9
    }
}
