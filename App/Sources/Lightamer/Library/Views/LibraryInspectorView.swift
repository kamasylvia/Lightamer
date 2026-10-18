import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// LibraryInspectorView (Plan M2-3-2 T2, KD-2) — the Album Inspector panel,
// the Alcedo `AlbumInspectorPanel` IA section-for-section:
//
//   LIBRARY OVERVIEW (the Total Photos card — filter-domain, live)
//   By Capture Date / By Camera Model / By Labels / By Lens   (click = fold)
//   ACTIVITY (the per-day bars — a bar click = the same date leg)
//   SEARCH FILTER (the typed currentFilterDescription + the breadcrumb)
//   SMART ALBUMS (evaluate(.library) member counts; click = album filter)
//
// The view carries ZERO business logic — every face is a LibraryInspectorModel
// call; every string is `String(localized:)`; every section carries a stable
// `library.inspector.*` accessibility identifier (the T2 marker family).
// ─────────────────────────────────────────────────────────────────────────────

struct LibraryInspectorView: View {

    /// The Inspector's logic face (the grid cursor + the query face ride
    /// inside it — the view never touches them directly).
    let model: LibraryInspectorModel
    /// The relink entry (T4 — nil hides the images action area; the sheet
    /// presentation itself lives in the host).
    var onRelinkRequested: () -> Void = {}

    // Plan M2-10-07 (KD-3, minimal radius): the AI analysis command area.
    // The host passes the key-absent face + the two command routes (the
    // sweeps + the confirm gate live in the host's coordinator).
    var aiNeedsSetup: Bool = false
    var onAIRating: () -> Void = {}
    var onAIDescription: () -> Void = {}

    static let panelWidth: CGFloat = 280

    // M7-5-01 (D-M7-5-4 face ⑩): the rating face's gate — the AI-analysis
    // command area (the AI 评片 rating writes) goes inert while the agent
    // holds the control (the filter/browsing sections stay untouched —
    // the preserved faces).
    @Environment(AgentControlCoordinator.self) private var agentControl

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                overviewSection
                groupSection(.captureDate)
                groupSection(.camera)
                groupSection(.labels)
                groupSection(.lens)
                activitySection
                filterSection
                actionsSection
                aiSection
                smartAlbumsSection
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Self.panelWidth)
        .frame(maxHeight: .infinity)
        .background(ThemeTokens.cardSurface)
        .overlay(
            Rectangle()
                .fill(ThemeTokens.cardBorder)
                .frame(width: 1),
            alignment: .leading)
        .accessibilityIdentifier("library.inspector")
    }

    // MARK: - LIBRARY OVERVIEW

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(String(
                localized: "library_inspector_overview",
                defaultValue: "LIBRARY OVERVIEW"))
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(model.overviewCount)")
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(ThemeTokens.textPrimary)
                Text(String(
                    localized: "library_inspector_total_photos",
                    defaultValue: "Total Photos"))
                    .font(.caption)
                    .foregroundStyle(ThemeTokens.textSecondary)
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(ThemeTokens.cardBorder.opacity(0.4)))
        }
        .accessibilityIdentifier("library.inspector.overview")
    }

    // MARK: - The four group sections

    private func groupSection(_ key: LibraryGroupKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(headerTitle(key))
            let rows = model.groups[key] ?? []
            if rows.isEmpty {
                Text(String(
                    localized: "library_inspector_group_empty",
                    defaultValue: "No data for this grouping"))
                    .font(.caption)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, payload in
                groupRow(key, payload)
            }
        }
        .accessibilityIdentifier("library.inspector.group.\(key.rawValue)")
    }

    private func groupRow(_ key: LibraryGroupKey, _ payload: LibraryGroupCount) -> some View {
        let active = model.arms.contains { isActiveArm(key, payload, $0) }
        let inert = key == .labels && payload.rating == nil
        return Button {
            Task { await model.toggle(group: key, payload: payload) }
        } label: {
            HStack {
                Text(verbatim: payload.label)
                    .font(.callout)
                    .foregroundStyle(
                        active ? ThemeTokens.accent : ThemeTokens.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(verbatim: "\(payload.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(inert)
        .opacity(inert ? 0.5 : 1)
        .accessibilityIdentifier(
            "library.inspector.row.\(key.rawValue).\(payload.label)")
    }

    /// The active-arm read: the row's typed payload matches a folded arm.
    private func isActiveArm(
        _ key: LibraryGroupKey, _ payload: LibraryGroupCount,
        _ arm: LibraryInspectorModel.FilterArm
    ) -> Bool {
        switch key {
        case .captureDate:
            return arm.source == .day(payload.day ?? "")
        case .camera:
            return arm.source == .camera(
                make: payload.cameraMake, model: payload.cameraModel)
        case .labels:
            guard let rating = payload.rating else { return false }
            return arm.source == .rating(rating)
        case .lens:
            return arm.source == .lens(payload.lensModel)
        }
    }

    // MARK: - ACTIVITY

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(String(
                localized: "library_inspector_activity",
                defaultValue: "ACTIVITY"))
            if model.activity.isEmpty {
                Text(String(
                    localized: "library_inspector_activity_empty",
                    defaultValue: "No dated photos in this collection"))
                    .font(.caption)
                    .foregroundStyle(ThemeTokens.textSecondary)
            } else {
                let peak = max(model.activity.map(\.count).max() ?? 1, 1)
                ScrollView(.horizontal) {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(model.activity, id: \.day) { entry in
                            VStack(spacing: 2) {
                                Rectangle()
                                    .fill(
                                        model.arms.contains {
                                            $0.source == .day(entry.day)
                                        }
                                        ? ThemeTokens.accent
                                        : ThemeTokens.cardBorder)
                                    .frame(
                                        width: 14,
                                        height: max(
                                            4, 48 * CGFloat(entry.count) / CGFloat(peak)))
                                Text(verbatim: shortDay(entry.day))
                                    .font(.system(size: 8))
                                    .foregroundStyle(ThemeTokens.textSecondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Task { await model.toggleActivityDay(entry.day) }
                            }
                            .accessibilityIdentifier(
                                "library.inspector.activity.\(entry.day)")
                            .accessibilityLabel(Text(verbatim: "\(entry.day): \(entry.count)"))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
        .accessibilityIdentifier("library.inspector.activity")
    }

    // MARK: - SEARCH FILTER

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                sectionHeader(String(
                    localized: "library_inspector_filter",
                    defaultValue: "SEARCH FILTER"))
                Spacer()
                if !(model.filterDescription?.isEmpty ?? true) {
                    Button {
                        Task { await model.clearFilter() }
                    } label: {
                        Text(String(
                            localized: "library_inspector_filter_clear",
                            defaultValue: "Clear"))
                            .font(.caption2)
                    }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("library.inspector.filter.clear")
                }
            }
            if let description = model.filterDescription, description.isEmpty {
                Text(String(
                    localized: "library_inspector_filter_none",
                    defaultValue: "No active filter"))
                    .font(.caption)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
            if let description = model.filterDescription {
                // The breadcrumb: one chip per folded arm (per-arm retreat).
                if !model.arms.isEmpty {
                    FlowLikeChips(arms: model.arms) { index in
                        Task { await model.removeArm(at: index) }
                    }
                }
                // The typed description, verbatim (the plan's SEARCH FILTER
                // rendering source — no re-parsing).
                ForEach(Array(description.ftsTerms.enumerated()), id: \.offset) { _, term in
                    filterLine(
                        String(localized: "library_inspector_filter_text",
                               defaultValue: "Text"),
                        verbatim: term)
                }
                ForEach(Array(description.structuredTerms.enumerated()), id: \.offset) { _, term in
                    filterLine(structuredTitle(term), verbatim: structuredSpelling(term))
                }
                if let range = description.dateRange {
                    filterLine(
                        String(localized: "library_inspector_filter_dates",
                               defaultValue: "Dates"),
                        verbatim: dateSpelling(range))
                }
            }
        }
        .accessibilityIdentifier("library.inspector.filter")
    }

    private func filterLine(_ title: String, verbatim: String) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: title)
                .font(.caption2)
                .foregroundStyle(ThemeTokens.textSecondary)
            Text(verbatim: verbatim)
                .font(.caption)
                .foregroundStyle(ThemeTokens.textPrimary)
                .lineLimit(1)
            Spacer()
        }
    }

    // MARK: - The images action area (Plan M2-3-2 T4, M2LIB-07③ entry)

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(String(
                localized: "library_inspector_actions",
                defaultValue: "ACTIONS"))
            Button {
                onRelinkRequested()
            } label: {
                Label(
                    String(
                        localized: "library_inspector_relink",
                        defaultValue: "Relink Missing…"),
                    systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ThemeTokens.accent)
            .disabled(model.selectedCount == 0)
            .accessibilityIdentifier("library.inspector.relink")
            if model.selectedCount > 0 {
                Text(String(
                    localized: "library_inspector_relink_hint",
                    defaultValue: "\(model.selectedCount) selected"))
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
        }
        .accessibilityIdentifier("library.inspector.actions")
    }

    // MARK: - AI ANALYSIS (Plan M2-10-07 T3, KD-3)

    /// The image-domain AI commands, the actions area's tail (the plan's
    /// 「图片域操作区尾」): 「AI 评片…」 through the confirm gate (the OQ-11-A
    /// face) and 「AI 描述」 straight to the queue (no confirm — the
    /// description rows are derived data, not user-authored stars). A
    /// missing key renders the guidance row INSTEAD of the commands
    /// (点 = 打开 ACA 设置页 — the SettingsDeepLink route).
    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(String(
                localized: "library_inspector_ai",
                defaultValue: "AI ANALYSIS"))
            if aiNeedsSetup {
                HStack(spacing: 6) {
                    Text(String(
                        localized: "library_inspector_ai_needs_setup",
                        defaultValue: "Configure a provider first"))
                        .font(.caption)
                        .foregroundStyle(ThemeTokens.textSecondary)
                    Spacer()
                    SettingsLink {
                        Text(String(
                            localized: "library_inspector_ai_open_settings",
                            defaultValue: "Open Settings…"))
                            .font(.caption)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        SettingsDeepLink.pendingPage = .advancedContentAnalysis
                    })
                    .accessibilityIdentifier("library.inspector.aiSetup")
                }
            } else {
                Button {
                    onAIRating()
                } label: {
                    Label(
                        String(localized: "library_inspector_ai_rating",
                               defaultValue: "AI Rate…"),
                        systemImage: "star")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ThemeTokens.accent)
                .disabled(model.selectedCount == 0)
                .accessibilityIdentifier("library.inspector.aiRating")
                Button {
                    onAIDescription()
                } label: {
                    Label(
                        String(localized: "library_inspector_ai_description",
                               defaultValue: "AI Describe"),
                        systemImage: "text.bubble")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ThemeTokens.accent)
                .disabled(model.selectedCount == 0)
                .accessibilityIdentifier("library.inspector.aiDescription")
            }
        }
        .accessibilityIdentifier("library.inspector.ai")
        // M7-5-01 face ⑩: the agent-held clause (disable-not-unmount).
        .disabled(agentControl.holdsControl)
    }

    // MARK: - SMART ALBUMS

    private var smartAlbumsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(String(
                localized: "library_inspector_smart_albums",
                defaultValue: "SMART ALBUMS"))
            if model.smartAlbumsUnavailable {
                Text(String(
                    localized: "library_inspector_smart_unavailable",
                    defaultValue: "Open a project to evaluate smart albums"))
                    .font(.caption)
                    .foregroundStyle(ThemeTokens.textSecondary)
            } else if model.smartAlbumRows.isEmpty {
                Text(String(
                    localized: "library_inspector_smart_empty",
                    defaultValue: "No smart albums defined"))
                    .font(.caption)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
            ForEach(model.smartAlbumRows) { album in
                let active = model.arms.contains {
                    $0.source == .smartAlbum(id: album.id)
                }
                Button {
                    Task { await model.toggleSmartAlbum(album) }
                } label: {
                    HStack {
                        Image(systemName: "gearshape.circle")
                            .foregroundStyle(
                                active ? ThemeTokens.accent : ThemeTokens.textSecondary)
                        Text(verbatim: album.name)
                            .font(.callout)
                            .foregroundStyle(
                                active ? ThemeTokens.accent : ThemeTokens.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        if let count = model.smartAlbumMemberCounts[album.id] {
                            Text(verbatim: "\(count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(ThemeTokens.textSecondary)
                        }
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("library.inspector.smart.\(album.id)")
            }
        }
        .accessibilityIdentifier("library.inspector.smartalbums")
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(verbatim: title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ThemeTokens.textSecondary)
            .textCase(.uppercase)
    }

    private func headerTitle(_ key: LibraryGroupKey) -> String {
        switch key {
        case .captureDate:
            return String(
                localized: "library_inspector_group_capturedate",
                defaultValue: "By Capture Date")
        case .camera:
            return String(
                localized: "library_inspector_group_camera",
                defaultValue: "By Camera Model")
        case .labels:
            return String(
                localized: "library_inspector_group_labels",
                defaultValue: "By Labels")
        case .lens:
            return String(
                localized: "library_inspector_group_lens",
                defaultValue: "By Lens")
        }
    }

    private func shortDay(_ day: String) -> String {
        String(day.suffix(5))  // MM-DD under a YYYY-MM-DD day
    }

    private func structuredTitle(_ term: StructuredTerm) -> String {
        switch term.field {
        case .iso:
            return String(
                localized: "library_inspector_filter_iso", defaultValue: "ISO")
        case .aperture:
            return String(
                localized: "library_inspector_filter_aperture",
                defaultValue: "Aperture")
        case .focalLength:
            return String(
                localized: "library_inspector_filter_focal",
                defaultValue: "Focal")
        default:
            return term.field.rawValue
        }
    }

    private func structuredSpelling(_ term: StructuredTerm) -> String {
        switch term.constraint {
        case .equals(let v): return "= \(v)"
        case .greaterThan(let v): return "> \(v)"
        case .greaterThanOrEqual(let v): return "≥ \(v)"
        case .lessThan(let v): return "< \(v)"
        case .lessThanOrEqual(let v): return "≤ \(v)"
        case .between(let lower, let upper): return "\(lower)–\(upper)"
        }
    }

    private func dateSpelling(_ range: ClosedRange<Date>) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return "\(formatter.string(from: range.lowerBound)) – "
            + formatter.string(from: range.upperBound)
    }
}

/// The arm chips row (the breadcrumb): one removable chip per folded arm —
/// a plain wrapping HStack is enough at the panel's fixed 280pt width.
private struct FlowLikeChips: View {
    let arms: [LibraryInspectorModel.FilterArm]
    let onRemove: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(arms.enumerated()), id: \.offset) { index, arm in
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.caption2)
                        .foregroundStyle(ThemeTokens.accent)
                    Text(verbatim: Self.chipLabel(arm))
                        .font(.caption2)
                        .foregroundStyle(ThemeTokens.textPrimary)
                        .lineLimit(1)
                    Button {
                        onRemove(index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(ThemeTokens.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library.inspector.chip.\(index)")
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(ThemeTokens.cardBorder.opacity(0.4)))
            }
        }
    }

    static func chipLabel(_ arm: LibraryInspectorModel.FilterArm) -> String {
        switch arm.source {
        case .day(let day): return day
        case .camera(let make, let model):
            return [make, model].compactMap { $0 }.joined(separator: " ")
        case .rating(let rating): return "\(rating)★"
        case .lens(let lens): return lens ?? "?"
        case .smartAlbum: return "smart album"
        }
    }
}
