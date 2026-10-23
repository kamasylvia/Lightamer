import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// CullFaceModel (Plan LUMEN-B T4/T5/T6, X7) — the cull face's logic model:
// the row set under review, the selection index (+ the compare candidate),
// the rating write leg, the burst-group jumps and the hint-bar payload.
//
// SHAPE: @MainActor @Observable (the WorkspaceModel/LibraryGridModel face) —
// all routing state is main-thread state; the VIEW never decodes (the
// CullViewLoader actor supplies planes off-body). The rating write leg is
// an injected closure (the host binds LibraryStore.setMetadataMarks — the
// plan-pinned :455 single-batch write); tests inject counters.
//
// KEYBINDINGS (X7, T5 — the table IS the single source; the view maps keys
// through `CullKeymap.action(for:)` — never scattered switch arms):
//   G = back to library · D = open in the editor · 0-5 = stars ·
//   P/X/U = pick/reject/unflag · 6-9 = colour labels ·
//   A = advance-after-rating (the header toggle) · C = compare ·
//   F = face boxes · ←→ = step · ↑↓ = burst-group jumps (single) /
//   promote + candidate switching (compare).
// ─────────────────────────────────────────────────────────────────────────────

/// One cull-table row: the library projection + the resolved source URL +
/// the analysis annotations this face consumes (the LUMEN-A products — the
/// annotation carries the burst/blurry/best faces, the raw row carries the
/// sharpness score and the absolute eyes-closed verdict).
struct CullEntry: Identifiable, Equatable {
    let row: LibraryImageRow
    let url: URL?
    /// BurstAnnotator output (nil = un-annotated row).
    let annotation: BurstAnnotation?
    /// The analysis sharpness score (nil = un-analysed).
    let sharpness: Double?
    /// The absolute eyes-closed verdict (nil = un-analysed).
    let eyesClosed: Bool?
    /// The LIVE mark projection (seeded from the row; the model's write leg
    /// refreshes these — the header/filmstrip read them, never a re-query;
    /// LibraryImageRow's memberwise init is internal, so the marks live
    /// HERE, not in a rebuilt row).
    var rating: Int64?
    var colorLabel: Int64?
    var flag: Int64?

    var id: Int64 { row.id }
    var name: String { row.filename ?? row.fileStem ?? "?" }
}

/// The keymap table (T5's 表驱动 face — the tests sweep it).
enum CullKeymap: Equatable {
    enum Action: Equatable {
        case backToLibrary
        case openEditor
        case rating(Int)
        case pick
        case reject
        case unflag
        case colorLabel(Int)
        case toggleAdvance
        case toggleCompare
        case toggleFaces
        case step(Int)
        case candidateSwitchSide
        case promote
        case jumpBurst(Int)
    }

    /// Character keys → actions (X7's钉死 pair: G/D first — G = the Lumen
    /// Esc-G back-to-library mapping, D = the Enter-develop mapping).
    static func action(for character: String) -> Action? {
        switch character {
        case "g", "G": return .backToLibrary
        case "d", "D": return .openEditor
        case "0", "1", "2", "3", "4", "5":
            return .rating(Int(character) ?? 0)
        case "p", "P": return .pick
        case "x", "X": return .reject
        case "u", "U": return .unflag
        case "6": return .colorLabel(1)
        case "7": return .colorLabel(2)
        case "8": return .colorLabel(3)
        case "9": return .colorLabel(4)
        case "a", "A": return .toggleAdvance
        case "c", "C": return .toggleCompare
        case "f", "F": return .toggleFaces
        default: return nil
        }
    }
}

@MainActor
@Observable
final class CullFaceModel {

    // MARK: - Table state

    private(set) var entries: [CullEntry]
    private(set) var index: Int
    /// The compare candidate (valid while `compare` is on).
    private(set) var candidate: Int
    private(set) var compare = false
    /// Which side takes the rating keys (true = the right/candidate pane).
    private(set) var activeRight = false
    /// 评级后前进 (the A toggle — the write leg auto-advances when on).
    var advanceAfterRating = false
    /// The face-boxes overlay (the F toggle).
    var showFaces = true

    /// The rating write leg (the host binds LibraryStore.setMetadataMarks;
    /// tests inject a recorder).
    var writeLeg: (@Sendable (_ imageID: Int64, _ rating: Int64?, _ colorLabel: Int64?, _ flag: Int64?) async -> Void)?

    /// The editor-entry route (the D key — the host binds WorkspaceModel
    /// .openEditor + closeCull).
    var openEditorRoute: ((Int64) -> Void)?
    /// The back route (the G key — the host binds WorkspaceModel.closeCull).
    var backRoute: (() -> Void)?

    init(entries: [CullEntry], anchorID: Int64?) {
        self.entries = entries
        let anchor = entries.firstIndex { $0.id == anchorID } ?? 0
        self.index = anchor
        self.candidate = min(anchor + 1, max(entries.count - 1, 0))
    }

    // MARK: - Rows / projection

    var current: CullEntry? {
        entries.indices.contains(index) ? entries[index] : nil
    }

    var candidateEntry: CullEntry? {
        entries.indices.contains(candidate) ? entries[candidate] : nil
    }

    /// The pane that takes the rating keys (compare + activeRight → the
    /// candidate; otherwise the select).
    var target: CullEntry? {
        compare && activeRight ? candidateEntry : current
    }

    // MARK: - Navigation

    /// Step the selection (clamped — the Lumen go() 直译); in compare the
    /// arrows move the CANDIDATE instead.
    func go(_ target: Int) {
        guard !entries.isEmpty else { return }
        let clamped = max(0, min(target, entries.count - 1))
        if compare {
            guard clamped != index else { return }
            candidate = clamped
        } else {
            index = clamped
        }
    }

    func step(_ delta: Int) {
        go((compare ? candidate : index) + delta)
    }

    // MARK: - Compare state machine (T6's C pane — the model half)

    /// C: enter compare (candidate = the neighbour; the right side takes
    /// the keys first), leave compare (the candidate becomes the select if
    /// the right side held it — the Lumen set_compare 直译).
    func setCompare(_ on: Bool) {
        guard on != compare else { return }
        guard on == false || entries.count >= 2 else { return }
        compare = on
        if on {
            candidate = index + 1 < entries.count ? index + 1 : max(index - 1, 0)
            activeRight = true
        } else {
            if activeRight { index = candidate }
            activeRight = false
        }
    }

    /// Tab: which side takes the keys.
    func switchSide() {
        guard compare else { return }
        activeRight.toggle()
    }

    /// ↑ in compare: the candidate is promoted to the select.
    func promote() {
        guard compare else { return }
        let target = candidate
        candidate = index
        index = target
    }

    // MARK: - Rating (T5's write leg — the plan pins setMetadataMarks)

    /// Write one mark component and (when the A toggle is on) advance.
    /// A nil component = leave untouched; a repeated colour label clears.
    func rate(
        rating: Int64? = nil, colorLabel: Int64? = nil, flag: Int64? = nil
    ) {
        guard let entry = target else { return }
        var writeRating = rating
        var writeLabel = colorLabel
        var writeFlag = flag
        // The toggle faces: re-pressing the same star clears it (the Lumen
        // label toggle 同形); U writes the unflag (0).
        if let rating, entry.rating == rating { writeRating = 0 }
        if let colorLabel, entry.colorLabel == colorLabel { writeLabel = 0 }
        let imageID = entry.id
        let leg = writeLeg
        Task {
            await leg?(imageID, writeRating, writeLabel, writeFlag)
        }
        if advanceAfterRating {
            if compare {
                go(candidate + 1)
            } else {
                go(index + 1)
            }
        }
    }

    /// The local projection refresh after a write (the marks move — the
    /// filmstrip/header read THIS face, not a re-query).
    func applyWrittenMarks(
        imageID: Int64, rating: Int64?, colorLabel: Int64?, flag: Int64?
    ) {
        guard let position = entries.firstIndex(where: { $0.id == imageID }) else { return }
        if let rating { entries[position].rating = rating }
        if let colorLabel { entries[position].colorLabel = colorLabel }
        if let flag { entries[position].flag = flag }
    }

    // MARK: - Burst-group jumps (T6 — Lumen jump_burst 直译)

    /// ↑↓ between burst groups: walk to the previous/next row OUTSIDE the
    /// current group; stepping BACKWARD lands on the group's FIRST frame.
    /// Not in a group → plain stepping.
    func jumpBurst(_ direction: Int) {
        guard entries.indices.contains(index) else { return }
        let group = entries[index].annotation?.burst ?? 0
        guard group > 0 else {
            step(direction)
            return
        }
        var position = index
        while entries.indices.contains(position + direction) {
            position += direction
            let other = entries[position].annotation?.burst ?? 0
            if other != group {
                if direction < 0 && other > 0 {
                    // Land on the previous group's first frame.
                    while entries.indices.contains(position - 1),
                          entries[position - 1].annotation?.burst == other {
                        position -= 1
                    }
                }
                go(position)
                return
            }
        }
    }

    // MARK: - Hints (T6's hint-bar payload — the 表驱动 mapper)

    /// The hint payload for one entry: the sharpness score, the 可能模糊 /
    /// 可能闭眼 verdicts and the burst position (the LUMEN-A annotation
    /// products consumed; the 组相对 blurry leg rides the annotation).
    struct Hints: Equatable {
        var sharpness: Double?
        var blurry: Bool
        var eyesClosed: Bool
        var burstIndex: Int
        var burstSize: Int
        var best: Bool

        var hasBurst: Bool { burstIndex > 0 && burstSize > 1 }
        var isEmpty: Bool {
            sharpness == nil && !blurry && !eyesClosed && !best && !hasBurst
        }
    }

    func hints(for entry: CullEntry) -> Hints {
        Hints(
            sharpness: entry.sharpness,
            blurry: entry.annotation?.blurry ?? false,
            eyesClosed: entry.eyesClosed ?? false,
            burstIndex: entry.annotation?.burstIndex ?? 0,
            burstSize: entry.annotation?.burstSize ?? 0,
            best: entry.annotation?.best ?? false)
    }
}
