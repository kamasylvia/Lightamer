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
                    isActive: !model.activeRight,
                    identifier: "library.cull.paneLeft")
                CullPaneView(
                    loader: loader, entry: model.candidateEntry,
                    isActive: model.activeRight,
                    identifier: "library.cull.paneRight")
            }
        } else {
            CullPaneView(
                loader: loader, entry: model.current,
                isActive: true,
                identifier: "library.cull.paneMain")
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
                            isSelected: entry.id == model.target?.id)
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
            defaultValue: "← → 切换  ·  ↑ ↓ 连拍组  ·  0-5 星级  ·  P 留用  X 排除  U 取消  ·  6-9 色标  ·  C 对比  Tab 切侧  ·  F 人脸框  ·  D 进编辑器  ·  G 返回图库"))
            .font(.caption2)
            .foregroundStyle(ThemeTokens.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .accessibilityIdentifier("library.cull.help")
    }
}

/// One main pane: the entry's display view through the loader (the
/// `.task(id:)` pair-identity face — an entry change re-runs the load; a
/// same-entry re-evaluation no-ops).
struct CullPaneView: View {
    let loader: CullViewLoader
    let entry: CullEntry?
    let isActive: Bool
    let identifier: String

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(ThemeTokens.cardSurface)
                    .overlay {
                        ProgressView().controlSize(.large)
                    }
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
        .accessibilityIdentifier(identifier)
        .task(id: entry?.id) {
            guard let url = entry?.url else { image = nil; return }
            let produced = await loader.displayImage(for: url)
            image = produced
        }
    }
}

/// One filmstrip cell: the bridge's 96px-tier thumbnail.
private struct CullStripCell: View {
    let bridge: LibraryThumbnailBridge?
    let row: LibraryImageRow
    let isSelected: Bool

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
        .task(id: row.id) {
            guard let bridge else { return }
            thumbnail = await bridge.thumbnail(for: row)
        }
    }
}
