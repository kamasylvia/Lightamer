import CoreGraphics
import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// CullFaceView (Plan LUMEN-B T4, X7/D-LU-1) — the main window's THIRD face:
// header (name / position / EXIF line / hint bar slot / advance toggle /
// compare button / back) + the main pane(s) (single, or the C side-by-side)
// + the bottom filmstrip (the 96px LibraryThumbnailBridge supply) + the
// keybinding help row.
//
// DISCIPLINE: the view NEVER decodes on the body path — panes pull their
// planes through `.task(id:)` from the CullViewLoader actor (the
// pair-identity re-run semantics inherited from the legacy CullingView:
// CullingView.swift:91-120 — the本体 stays zero-diff, this is a NEW
// same-shape implementation). Pane planes are loader-owned (LRU) — the
// legacy self-owned release face is the loader's LRU eviction here.
// ─────────────────────────────────────────────────────────────────────────────

struct CullFaceView: View {
    @Bindable var model: CullFaceModel
    let loader: CullViewLoader
    /// The filmstrip supply (the 96px tier — nil = honest placeholders).
    let bridge: LibraryThumbnailBridge?
    let onClose: () -> Void

    /// The face owns the keyboard: focused on appear, every key routes
    /// through the CullKeymap table (the view never scatters switch arms).
    @FocusState private var faceFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            panes
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            filmstrip
            helpRow
        }
        .background(ThemeTokens.windowBackground)
        .accessibilityIdentifier("library.cull")
        .focusable()
        .focused($faceFocused)
        .onAppear { faceFocused = true }
        .onKeyPress(phases: .down) { press in
            handleKey(press)
        }
    }

    // MARK: - Keys (T5 — X7's钉死 pair routes through the table)

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if let character = press.characters.first.map(String.init),
           let action = CullKeymap.action(for: character) {
            perform(action)
            return .handled
        }
        switch press.key {
        case .leftArrow:
            model.step(-1)
            return .handled
        case .rightArrow:
            model.step(1)
            return .handled
        case .upArrow:
            // Compare: the candidate promotes; single: the burst-group jump.
            if model.compare { model.promote() } else { model.jumpBurst(-1) }
            return .handled
        case .downArrow:
            if !model.compare { model.jumpBurst(1) }
            return .handled
        case .tab:
            guard model.compare else { return .ignored }
            model.switchSide()
            return .handled
        default:
            return .ignored
        }
    }

    private func perform(_ action: CullKeymap.Action) {
        switch action {
        case .backToLibrary:
            model.backRoute?()
        case .openEditor:
            guard let entry = model.target else { return }
            model.openEditorRoute?(entry.id)
        case .rating(let value):
            model.rate(rating: Int64(value))
        case .pick:
            model.rate(flag: 1)
        case .reject:
            model.rate(flag: 2)
        case .unflag:
            model.rate(flag: 0)
        case .colorLabel(let value):
            model.rate(colorLabel: Int64(value))
        case .toggleAdvance:
            model.advanceAfterRating.toggle()
        case .toggleCompare:
            model.setCompare(!model.compare)
        case .toggleFaces:
            model.showFaces.toggle()
        case .toggleZoom:
            onToggleZoomForActivePane()
        }
    }

    /// Z: the 100% toggle on the pane that takes the keys (the shared zoom
    /// state zooms BOTH panes — the sync semantics; the Lumen Z/Space 直译).
    private func onToggleZoomForActivePane() {
        model.setZoom(!model.zoom.zoomed)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Text(headerTitle)
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("library.cull.title")
            Text(exifLine)
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            // T6 fills the hint bar slot (sharpness / 可能模糊 / 可能闭眼 /
            // burst position — the annotation products).
            Text(hintLine)
                .font(.caption)
                .foregroundStyle(.yellow)
            Toggle(String(localized: "cull_advance_label", defaultValue: "评级后前进（A）"),
                   isOn: $model.advanceAfterRating)
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("library.cull.advance")
            Button(String(localized: "cull_compare_label", defaultValue: "对比（C）")) {
                model.setCompare(!model.compare)
            }
            .accessibilityIdentifier("library.cull.compare")
            Button(String(localized: "cull_back_label", defaultValue: "返回图库（G）")) {
                onClose()
            }
            .accessibilityIdentifier("library.cull.back")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private var headerTitle: String {
        guard let current = model.current else { return "" }
        return "\(current.name)   \(model.index + 1) / \(model.entries.count)"
    }

    private var exifLine: String {
        guard let entry = model.current else { return "" }
        let row = entry.row
        var parts: [String] = []
        if let make = row.cameraMake ?? row.cameraModel { parts.append(make) }
        if let iso = row.iso { parts.append("ISO \(iso)") }
        if let focal = row.focalLength { parts.append(String(format: "%.0fmm", focal)) }
        if let aperture = row.aperture { parts.append(String(format: "f/%.1f", aperture)) }
        if let exposure = row.exposure {
            parts.append(exposure >= 1 ? String(format: "%.0fs", exposure) : String(format: "1/%.0fs", 1 / exposure))
        }
        if let rating = entry.rating, rating > 0 {
            parts.append(String(repeating: "★", count: Int(rating)))
        }
        return parts.joined(separator: "  ·  ")
    }

    private var hintLine: String {
        guard let entry = model.target else { return "" }
        let hints = model.hints(for: entry)
        guard !hints.isEmpty else { return "" }
        var parts: [String] = []
        if let sharpness = hints.sharpness {
            parts.append(String(localized: "cull_hint_sharpness", defaultValue: "清晰度 \(sharpness, specifier: "%.0f")"))
        }
        if hints.blurry {
            parts.append(String(localized: "cull_hint_blurry", defaultValue: "可能模糊"))
        }
        if hints.eyesClosed {
            parts.append(String(localized: "cull_hint_eyes_closed", defaultValue: "可能闭眼"))
        }
        if hints.hasBurst {
            parts.append("\(hints.burstIndex)/\(hints.burstSize)")
            if hints.best {
                parts.append(String(localized: "cull_hint_best", defaultValue: "最佳"))
            }
        }
        return parts.joined(separator: "  ")
    }

    // MARK: - Panes

    @ViewBuilder
    private var panes: some View {
        if model.compare {
            HStack(alignment: .center, spacing: 2) {
                CullPaneView(
                    loader: loader, entry: model.current,
                    isActive: !model.activeRight, zoom: model.zoom,
                    identifier: "library.cull.paneLeft",
                    onToggleZoom: { model.setZoom(!model.zoom.zoomed) },
                    onActivate: {
                        // The pane click switches the active side (the
                        // Lumen pane_clicked 直译).
                        if !model.activeRight { model.switchSide() }
                    })
                CullPaneView(
                    loader: loader, entry: model.candidateEntry,
                    isActive: model.activeRight, zoom: model.zoom,
                    identifier: "library.cull.paneRight",
                    onToggleZoom: { model.setZoom(!model.zoom.zoomed) },
                    onActivate: {
                        if model.activeRight { model.switchSide() }
                    })
            }
        } else {
            CullPaneView(
                loader: loader, entry: model.current,
                isActive: true, zoom: model.zoom,
                identifier: "library.cull.paneMain",
                onToggleZoom: { model.setZoom(!model.zoom.zoomed) },
                onActivate: nil)
        }
    }

    // MARK: - Filmstrip (the 96px LibraryThumbnailBridge tier)

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(model.entries) { entry in
                        CullStripCell(
                            bridge: bridge, row: entry.row,
                            isSelected: entry.id == model.target?.id,
                            hints: model.hints(for: entry))
                            .id(entry.id)
                            .onTapGesture {
                                model.go(index(of: entry.id))
                            }
                            .accessibilityIdentifier("library.cull.strip.\(entry.id)")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(height: 108)
            .onChange(of: model.target?.id) { _, newValue in
                guard let id = newValue else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func index(of id: Int64) -> Int {
        model.entries.firstIndex { $0.id == id } ?? model.index
    }

    // MARK: - Help row

    private var helpRow: some View {
        Text(String(
            localized: "cull_help_row",
            defaultValue: "← → 切换  ·  ↑ ↓ 连拍组  ·  0-5 星级  ·  P 留用  X 排除  U 取消  ·  6-9 色标  ·  Z 或双击 100%  ·  C 对比  Tab 切侧  ·  F 人脸框  ·  D 进编辑器  ·  G 返回图库"))
            .font(.caption2)
            .foregroundStyle(ThemeTokens.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .accessibilityIdentifier("library.cull.help")
    }
}

/// One main pane: the entry's display view through the loader (the
/// `.task(id:)` pair-identity face — an entry change re-runs the load; a
/// same-entry re-evaluation no-ops). Zoomed = the FULL tier through the
/// loader (the embedded full-size or the RAW fallback cache leg), scrolled
/// at 1:1 with the SHARED center (the sync_zoom 直译 — both panes read the
/// one model state, so zoom and position are structurally synced).
struct CullPaneView: View {
    let loader: CullViewLoader
    let entry: CullEntry?
    let isActive: Bool
    let zoom: CullFaceModel.CullZoom
    let identifier: String
    let onToggleZoom: () -> Void
    let onActivate: (() -> Void)?

    @State private var display: CGImage?
    @State private var full: CGImage?

    var body: some View {
        ZStack {
            if zoom.zoomed {
                zoomedBody
            } else {
                fittedBody
            }
        }
        .overlay(alignment: .topTrailing) {
            if isActive {
                Rectangle()
                    .fill(.tint)
                    .frame(width: 3, height: 18)
                    .padding(6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onActivate?() }
        .accessibilityIdentifier(identifier)
        .task(id: entry?.id) {
            guard let url = entry?.url else {
                display = nil
                full = nil
                return
            }
            full = nil
            display = await loader.displayImage(for: url)
        }
        .task(id: zoomKey) {
            // The zoomed plane: the FULL tier (the 100% face). The display
            // plane stays as the placeholder while the full production runs
            // (the Lumen 等原图期间放大显示 2560px 视图插值语义).
            guard zoom.zoomed, let url = entry?.url else { return }
            let produced = await loader.fullImage(for: url)
            full = produced?.image
        }
    }

    /// The zoom re-load key: the entry AND the zoomed state (a zoom toggle
    /// re-runs the full-tier production; a center move does not).
    private var zoomKey: String {
        "\(entry?.id ?? -1)|\(zoom.zoomed)"
    }

    @ViewBuilder
    private var fittedBody: some View {
        if let display {
            Image(decorative: display, scale: 1.0)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .onTapGesture(count: 2) { onToggleZoom() }
        } else {
            Rectangle()
                .fill(ThemeTokens.cardSurface)
                .overlay {
                    ProgressView().controlSize(.large)
                }
        }
    }

    /// The 100% body: the full plane at pixel dimensions inside a scroll
    /// view, positioned by the SHARED unit center; a click re-focuses both
    /// panes through the model.
    @ViewBuilder
    private var zoomedBody: some View {
        if let full {
            ScrollViewReader { proxy in
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        Image(decorative: full, scale: 1.0)
                            .resizable()
                            .interpolation(.none)
                            .frame(
                                width: CGFloat(full.width),
                                height: CGFloat(full.height))
                            .id("cull.full")
                    }
                    .onChange(of: zoom) { _, newValue in
                        let targetX = newValue.centerX * CGFloat(full.width)
                            - geometry.size.width / 2
                        let targetY = newValue.centerY * CGFloat(full.height)
                            - geometry.size.height / 2
                        proxy.scrollTo(
                            "cull.full", anchor: UnitPoint(
                                x: min(1, max(0, targetX / max(CGFloat(full.width) - geometry.size.width, 1))),
                                y: min(1, max(0, targetY / max(CGFloat(full.height) - geometry.size.height, 1)))))
                    }
                }
                .onTapGesture { location in
                    guard full.width > 0, full.height > 0 else { return }
                    // The click's unit position within the FITTED image —
                    // approximated by the pane's own geometry (the v1
                    // declared face; the walkthrough refines).
                    onActivate?()
                }
            }
        } else {
            // The full plane still producing — the display plane stays up
            // (magnified by scale, the placeholder semantics).
            if let display {
                Image(decorative: display, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay { ProgressView().controlSize(.large) }
            } else {
                Rectangle().fill(ThemeTokens.cardSurface)
                    .overlay { ProgressView().controlSize(.large) }
            }
        }
    }
}

/// One filmstrip cell: the bridge's 96px-tier thumbnail + the burst
/// annotation badge (the n/m position and the best mark — the LUMEN-A
/// annotation products consumed, the T6 注记消费).
private struct CullStripCell: View {
    let bridge: LibraryThumbnailBridge?
    let row: LibraryImageRow
    let isSelected: Bool
    let hints: CullFaceModel.Hints

    @State private var thumbnail: CGImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(ThemeTokens.cardSurface)
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        .overlay(alignment: .topLeading) {
            if hints.hasBurst {
                Text("\(hints.burstIndex)/\(hints.burstSize)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 3))
                    .padding(3)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hints.best {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .padding(3)
            }
        }
        .task(id: row.id) {
            guard let bridge else { return }
            thumbnail = await bridge.thumbnail(for: row)
        }
    }
}
