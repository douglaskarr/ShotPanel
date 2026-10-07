import SwiftUI

struct ShelfRoot: View {
    @ObservedObject var shelf: Shelf
    var interactive = true

    var body: some View {
        widget
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    @ViewBuilder
    private var widget: some View {
        if shelf.currentShot != nil {
            HeroCard(shelf: shelf, interactive: interactive)
                .padding(shelf.metrics.outerPad)
                .background { widgetChrome }
                .overlay(alignment: .top) { edge(.top).frame(maxWidth: .infinity).frame(height: 14) }
                .overlay(alignment: .bottom) { edge(.bottom).frame(maxWidth: .infinity).frame(height: 14) }
                .overlay(alignment: .leading) { edge(.left).frame(maxHeight: .infinity).frame(width: 14) }
                .overlay(alignment: .trailing) { edge(.right).frame(maxHeight: .infinity).frame(width: 14) }
                .overlay(alignment: .topLeading) { corner([.top, .left]).frame(width: 22, height: 22) }
                .overlay(alignment: .topTrailing) { corner([.top, .right]).frame(width: 22, height: 22) }
                .overlay(alignment: .bottomLeading) { corner([.bottom, .left]).frame(width: 22, height: 22) }
                .overlay(alignment: .bottomTrailing) { corner([.bottom, .right]).frame(width: 22, height: 22) }
        } else {
            empty
        }
    }

    /// Edges and corners resize. The bottom bar still moves the panel, and a
    /// drag that starts on the photo still exports the file.
    @ViewBuilder
    private func edge(_ edges: ResizeEdges) -> some View {
        if interactive {
            ResizeSurface(edges: edges, shelf: shelf)
        }
    }

    @ViewBuilder
    private func corner(_ edges: ResizeEdges) -> some View {
        if interactive {
            ResizeSurface(edges: edges, shelf: shelf)
        }
    }

    private var empty: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("ShotPanel")
                    .font(.system(size: 13, weight: .semibold))
                Text(shelf.inboxOn ? "New screenshots land here" : (shelf.watchesDesktop ? "Watching the Desktop" : "Watching your screenshot folder"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: 300, height: 96)
        .background { widgetChrome }
        .overlay(alignment: .topLeading) { minimizeMark }
        .overlay {
            if interactive {
                MoveSurface(margin: 0, minimizeCorner: true, shelf: shelf)
            }
        }
    }

    private var minimizeMark: some View {
        Image(systemName: "minus")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Color.black.opacity(0.58), in: Circle())
            .overlay { Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5) }
            .padding(8)
    }

    private var widgetChrome: some View {
        RoundedRectangle(cornerRadius: shelf.metrics.outerCorner, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: shelf.metrics.outerCorner, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.32), lineWidth: 1)
            }
    }
}

private struct HeroCard: View {
    @ObservedObject var shelf: Shelf
    var interactive = true

    var body: some View {
        let metrics = shelf.metrics
        let page = shelf.carouselPage
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                ForEach(page.items) { item in
                    if shelf.shots.indices.contains(item.index) {
                        // Offset draws the shot in place, but the shifted view
                        // sits above the row and would swallow the click. The
                        // row selects every shot, including ones past the first.
                        shotCell(shelf.shots[item.index], frame: item.frame, peek: item.isPeek)
                            .offset(x: item.frame.minX, y: item.frame.minY)
                            .allowsHitTesting(false)
                    }
                }
                minimizeMark
                    .allowsHitTesting(false)
            }
            .frame(width: metrics.hero.width, height: metrics.hero.height, alignment: .topLeading)
            .clipped()
            .allowsHitTesting(false)
            footer
                .frame(width: metrics.hero.width, height: metrics.footer)
        }
        .overlay(alignment: .topLeading) {
            if interactive {
                CardControl(allowsDeleteAll: true, shelf: shelf)
                    .frame(
                        width: metrics.hero.width,
                        height: metrics.hero.height + metrics.footer,
                        alignment: .topLeading
                    )
            }
        }
        .overlay(alignment: .topLeading) {
            // Drawn only. CardView owns the clicks, so this layer cannot
            // cover the shots stacked under the first one.
            photoActions
                .allowsHitTesting(false)
        }
    }

    /// Copy and Delete, in front of the row. Each capsule owns its own clicks.
    @ViewBuilder
    private var photoActions: some View {
        let page = shelf.carouselPage
        if let item = page.items.first(where: { item in
            guard shelf.shots.indices.contains(item.index), !item.isPeek else { return false }
            return shelf.shots[item.index].path == shelf.selectedPath
        }),
           let hit = ShotActions.hit(in: item.frame) {
            let shot = shelf.shots[item.index]
            ZStack(alignment: .topLeading) {
                if shelf.confirmingPath == shot.path {
                    confirmActions(shot, in: item.frame)
                } else {
                    photoButton(
                        shot,
                        title: shelf.copiedPath == shot.path ? "Copied" : "Copy",
                        symbol: "doc.on.doc",
                        fill: .white,
                        ink: .black,
                        frame: hit.copy,
                        onClick: { shelf.copy(shot) }
                    )
                    photoButton(
                        shot,
                        title: "Delete",
                        symbol: "trash",
                        fill: .red,
                        ink: .white,
                        frame: hit.delete,
                        onClick: { shelf.armDelete(shot) }
                    )
                }
            }
        }
    }

    /// “Are you sure?” with Yes and Cancel, centered on the selected shot.
    private func confirmActions(_ shot: Shot, in frame: CGRect) -> some View {
        let hit = ShotActions.confirm(in: frame)
        let yes = hit.yes
        let cancel = hit.cancel
        let row = yes.width + 8 + cancel.width
        return ZStack(alignment: .topLeading) {
            Text("Are you sure?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: row, height: 18)
                .offset(x: yes.minX, y: yes.minY - 24)
                .allowsHitTesting(false)
            photoButton(shot, title: "Yes", symbol: "trash", fill: .red, ink: .white, frame: yes) {
                shelf.commitDelete()
            }
            photoButton(shot, title: "Cancel", symbol: "xmark", fill: .white, ink: .black, frame: cancel) {
                shelf.cancelDelete()
            }
        }
    }

    private func photoButton(
        _ shot: Shot,
        title: String,
        symbol: String,
        fill: Color,
        ink: Color,
        frame: CGRect,
        onClick: @escaping () -> Void
    ) -> some View {
        actionButton(title, symbol: symbol, fill: fill, ink: ink)
            .frame(width: frame.width, height: frame.height)
            .overlay {
                if interactive {
                    ActionCatcher(
                        url: shot.url,
                        image: shot.image,
                        onClick: onClick,
                        onDragStart: { shelf.dragStarted(path: shot.path) },
                        onDragEnd: { shelf.dragEnded(operation: $0) }
                    )
                }
            }
            .offset(x: frame.minX, y: frame.minY)
    }

    private func shotCell(_ shot: Shot, frame: CGRect, peek: Bool) -> some View {
        ZStack {
            Color.black.opacity(0.22)
            if let nsImage = shot.image {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if shot.attempts >= 4 {
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(peek ? 0.05 : 0.14), lineWidth: 1)
        }
        .overlay {
            if !peek {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        Color.accentColor,
                        lineWidth: shelf.selectedPath == shot.path || shelf.arrivedPath == shot.path ? 2.5 : 0
                    )
            }
        }
        .overlay {
            if !peek { selectionActions(shot, frame: frame) }
        }
        .opacity(peek ? 0.38 : 1)
    }

    @ViewBuilder
    private func selectionActions(_ shot: Shot, frame: CGRect) -> some View {
        if shelf.selectedPath == shot.path,
           ShotActions.hit(in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height)) != nil {
            Color.black.opacity(0.42)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .allowsHitTesting(false)
        }
    }

    private func actionButton(_ title: String, symbol: String, fill: Color, ink: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(fill, in: Capsule())
    }

    @ViewBuilder
    private var footer: some View {
        if shelf.axis == .vertical {
            verticalFooter
        } else {
            horizontalFooter
        }
    }

    /// Delete all and the drag grip, centered, with the selected shot's facts underneath.
    private var verticalFooter: some View {
        let width = shelf.metrics.hero.width
        let footer = shelf.metrics.footer
        let layout = ShotActions.bar(
            width: width,
            footerTop: 0,
            footer: footer,
            vertical: true,
            confirming: shelf.confirmingDeleteAll
        )
        return ZStack(alignment: .topLeading) {
            if shelf.confirmingDeleteAll {
                actionButton("Yes", symbol: "trash", fill: .red, ink: .white)
                    .frame(width: layout.primary.width, height: layout.primary.height)
                    .offset(x: layout.primary.minX, y: layout.primary.minY)
                actionButton("Cancel", symbol: "xmark", fill: Color.primary.opacity(0.08), ink: .primary)
                    .frame(width: layout.cancel.width, height: layout.cancel.height)
                    .offset(x: layout.cancel.minX, y: layout.cancel.minY)
            } else {
                actionButton("Delete all", symbol: "trash", fill: .red, ink: .white)
                    .frame(width: layout.primary.width, height: layout.primary.height)
                    .offset(x: layout.primary.minX, y: layout.primary.minY)
            }
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: layout.grip.width, height: layout.grip.height)
                .offset(x: layout.grip.minX, y: layout.grip.minY)
            verticalDetails
                .frame(width: max(0, width - 16), height: 32, alignment: .center)
                .offset(x: 8, y: ShotActions.controlsRow + 2)
        }
        .frame(width: width, height: footer, alignment: .topLeading)
        .background(Color.primary.opacity(0.06))
    }

    @ViewBuilder
    private var verticalDetails: some View {
        if shelf.confirmingDeleteAll {
            Text("Are you sure?")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        } else if let shot = shelf.shots.first(where: { $0.path == shelf.selectedPath }) {
            let pixels = shot.pixelSize.width > 1 && shot.pixelSize.height > 1
                ? "\(Int(shot.pixelSize.width))×\(Int(shot.pixelSize.height))"
                : nil
            VStack(spacing: 1) {
                HStack(spacing: 6) {
                    if shelf.copiedPath == shot.path {
                        Text("Copied")
                            .fontWeight(.semibold)
                    }
                    Text(shot.url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 6) {
                    Text(shot.created.formatted(date: .abbreviated, time: .shortened))
                    if let pixels { Text(pixels) }
                    if let bytes = fileSize(shot.url) { Text(bytes) }
                }
                .lineLimit(1)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary)
        }
    }

    private var horizontalFooter: some View {
        let visible = shelf.carouselPage.settled().compactMap { item -> Shot? in
            guard shelf.shots.indices.contains(item.index) else { return nil }
            return shelf.shots[item.index]
        }
        let copied = visible.contains { $0.path == shelf.copiedPath }
        return HStack(spacing: 8) {
            if shelf.confirmingDeleteAll {
                Text("Are you sure?")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: ShotActions.promptWidth, alignment: .leading)
                actionButton("Yes", symbol: "trash", fill: .red, ink: .white)
                    .frame(width: ShotActions.yes.width, height: ShotActions.yes.height)
                actionButton("Cancel", symbol: "xmark", fill: Color.primary.opacity(0.08), ink: .primary)
                    .frame(width: ShotActions.cancel.width, height: ShotActions.cancel.height)
            } else {
                actionButton("Delete all", symbol: "trash", fill: .red, ink: .white)
                    .frame(width: ShotActions.deleteAll.width, height: ShotActions.deleteAll.height)
                    .layoutPriority(2)
            }
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .layoutPriority(2)
            Spacer(minLength: 0)
            if shelf.shots.count > 1 {
                Text(shelf.pageLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            if let shot = shelf.shots.first(where: { $0.path == shelf.selectedPath }) {
                if shelf.copiedPath == shot.path {
                    Text("Copied")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize()
                }
                shotFacts(shot)
            } else if copied {
                Text("Copied")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            } else if visible.count == 1, let shot = visible.first {
                Text(shot.created.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(Color.primary.opacity(0.06))
    }

    /// Name, then when it was taken, then pixel size, then file size.
    private func shotFacts(_ shot: Shot) -> some View {
        let pixels = shot.pixelSize.width > 1 && shot.pixelSize.height > 1
            ? "\(Int(shot.pixelSize.width))×\(Int(shot.pixelSize.height))"
            : nil
        let name = Text(shot.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
        let when = Text(shot.created.formatted(date: .abbreviated, time: .shortened)).lineLimit(1)
        let bytes = fileSize(shot.url)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                name
                when
                if let pixels { Text(pixels).lineLimit(1) }
                if let bytes { Text(bytes).lineLimit(1) }
            }
            HStack(spacing: 8) {
                name
                when
                if let bytes { Text(bytes).lineLimit(1) }
            }
            HStack(spacing: 8) { name; when }
            name
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.primary)
    }

    private func fileSize(_ url: URL) -> String? {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        guard let bytes, bytes > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private var minimizeMark: some View {
        Image(systemName: "minus")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Color.black.opacity(0.58), in: Circle())
            .overlay { Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5) }
            .padding(8)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }

}
