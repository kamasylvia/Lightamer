import AppKit
import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// SessionBrowserView (Plan 09-03 T5) — the GRID mode: a LazyVGrid of cells
// over the index-driven collection (RESEARCH §5.4).
//
// Cell four-piece contract: thumbnail (memory/disk/queued tiers through the
// provider; placeholder gradient until a thumb lands — progressive ingest
// rows show it FIRST), edited badge, orphan badge (placeholder cell, no
// thumbnail work — there is no original to decode), and the rating-star
// overlay (LAYOUT ONLY — Phase 12 (META-05) fills the data; pinned here so
// the layout ships ahead of the feature).
//
// L010: identifiers only — `browser.cell.<pathhash>` is the stable row id
// (FNV-1a hex via ThumbnailPath.hash, never an index); the four-piece
// anchors ride `.thumbnail/.edited/.orphan/.rating` suffixes. No container
// labels (the L010 swallow trap).
// ─────────────────────────────────────────────────────────────────────────────

internal struct SessionBrowserView: View {

    internal enum BrowserIdentifiers {
        static let grid = "browser.grid"
        static let modeGrid = "browser.mode.grid"
        static let modeSingle = "browser.mode.single"
        static let modeCulling = "browser.mode.culling"

        /// Stable per-row id (the ThumbnailPath hex — identical to the disk
        /// thumb's file stem; L010 stable id, never an index).
        static func cell(_ pathHash: String) -> String { "browser.cell.\(pathHash)" }
    }

    /// The collection model (rows + selection data face).
    let model: SessionBrowserModel
    /// The thumbnail provider (nil = no open session / not yet wired).
    let thumbnailProvider: SessionThumbnailProvider?
    /// Double-click: open the image in the SINGLE mode through the EXISTING
    /// `EditorState.load` chain (same window — L012). The mode flip is the
    /// caller's (ContentView owns the segmented state).
    let onOpenInEditor: (URL) -> Void
    /// The session root (cell URL assembly).
    let sessionRoot: URL?

    private static let columns = [GridItem(.adaptive(minimum: 168, maximum: 260), spacing: 10)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Self.columns, spacing: 10) {
                ForEach(model.rows) { row in
                    SessionBrowserCell(
                        row: row,
                        thumbnailProvider: thumbnailProvider,
                        isSelected: model.selectedPaths.contains(row.relPath),
                        onClick: { command, shift in
                            model.handleClick(row.relPath, commandPressed: command, shiftPressed: shift)
                        },
                        onDoubleClick: {
                            guard !row.orphanSidecar, let root = sessionRoot else { return }
                            onOpenInEditor(root.appendingPathComponent(row.relPath))
                        }
                    )
                    .accessibilityIdentifier(BrowserIdentifiers.cell(row.pathHash))
                    .contextMenu {
                        // HIST-05 (9-4) menu stubs — the ACTIONS land with
                        // the copy/paste data face; v1 keeps the menu shape
                        // with disabled items (the plan's placeholder rule).
                        Button(String(localized: "browser_menu_copy_adjustments")) {}
                            .disabled(true)
                        Button(String(localized: "browser_menu_paste")) {}
                            .disabled(true)
                        Button(String(localized: "browser_menu_paste_partial")) {}
                            .disabled(true)
                        Divider()
                        Button(String(localized: "browser_menu_flag")) {}
                            .disabled(true) // Phase 12 (META-05) placeholder
                    }
                }
            }
            .padding(12)
        }
        .accessibilityIdentifier(BrowserIdentifiers.grid)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The cell — thumbnail + edited/orphan badges + the rating overlay shell.
// ─────────────────────────────────────────────────────────────────────────────

private struct SessionBrowserCell: View {

    let row: SessionBrowserModel.Row
    let thumbnailProvider: SessionThumbnailProvider?
    let isSelected: Bool
    let onClick: (_ command: Bool, _ shift: Bool) -> Void
    let onDoubleClick: () -> Void

    /// The resolved thumb (nil = placeholder gradient).
    @State private var thumbnail: CGImage?
    /// The relPath this @State resolved for (row reuse in LazyVGrid swaps
    /// the row under a RECYCLED cell view — the fetch task must not paint
    /// the previous row's thumb).
    @State private var resolvedFor: String?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.18))
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .transition(.opacity)
                } else if row.orphanSidecar {
                    // Orphan placeholder: a dashed void — there is NO
                    // original to decode (never enqueue thumbnail work).
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        .foregroundColor(.orange.opacity(0.7))
                        .aspectRatio(3.0 / 2.0, contentMode: .fit)
                }
                VStack {
                    HStack(spacing: 4) {
                        if row.hasEdits {
                            badge("E", color: .blue, id: "edited")
                        }
                        if row.orphanSidecar {
                            badge("?", color: .orange, id: "orphan")
                        }
                        if row.dirty {
                            badge("…", color: .yellow, id: "dirty")
                        }
                        Spacer()
                    }
                    Spacer()
                    // Rating overlay — LAYOUT ONLY (Phase 12 fills the
                    // data; META-05). Five star shells, dimmed, bottom-left.
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { _ in
                            Image(systemName: "star")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(cellIdentifier + ".rating")
                }
                .padding(6)
            }
            .aspectRatio(3.0 / 2.0, contentMode: .fit)
            Text(row.filename)
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleClick() }
        .onTapGesture {
            // The data face owns the semantics (model.handleClick); the
            // modifiers ride NSEvent's current flags (SwiftUI tap gestures
            // drop them).
            let flags = NSEvent.modifierFlags
            onClick(flags.contains(.command), flags.contains(.shift))
        }
        .task(id: row.relPath) {
            // LAZY fetch (visible: true — the visible cell jumps the queue).
            // Orphan rows NEVER enqueue work.
            guard !row.orphanSidecar else { return }
            if resolvedFor == row.relPath, thumbnail != nil { return }
            resolvedFor = row.relPath
            let image = await thumbnailProvider?.thumbnail(for: row.relPath, visible: true)
            // A stale answer (the row moved on / cancelled teardown) never
            // paints.
            if resolvedFor == row.relPath {
                withAnimation(.easeIn(duration: 0.15)) { thumbnail = image }
            }
        }
    }

    private var cellIdentifier: String {
        "browser.cell." + row.pathHash
    }

    private func badge(_ text: String, color: Color, id: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(color))
            .accessibilityIdentifier(cellIdentifier + "." + id)
    }
}
