import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// FilterBarView (Plan 12-2 T4; META-05; D-12-CONTEXT-7) — the grid-page
// filter row (rides `SessionBrowserView`'s top safe-area inset, visually
// adjacent to the BrowserMode segmented control in the window toolbar).
//
// Three faces on one row (chips row appears only when chips are active):
//   • Quick Filter search box — filename OR keywords-ancestor hit; `/`
//     focuses, Esc clears (RESEARCH §4.3; a single any-group — pure
//     translation-layer consumption).
//   • Quick chips (the pre-filled predicates): ★≥3 / Pick / Reject /
//     Edited — toggle semantics, the highlight IS the active set.
//   • The「+」menu adds custom chips: rating ≥ N, color label = C, keyword /
//     camera / lens contains, ISO ≥ N, focal ≥ N, and the date-range sheet
//     (between). The `|` keyword separator is TYPED-BANNED at entry (the
//     12-1 MetadataService validation semantics — the apply button
//     disables on it).
//   • The sort menu (six whitelist keys × direction) — persisted by
//     SessionState through UserDefaults.
//
// Re-query orchestration lives in SessionState (each mutation schedules
// the debounced refresh through the App-root-injected closure) — this view
// carries NO reload logic.
// ─────────────────────────────────────────────────────────────────────────────

internal struct FilterBarView: View {

    @Environment(SessionState.self) private var sessionState

    /// Quick Filter focus (the `/` shortcut's target).
    @FocusState private var quickFilterFocused: Bool

    // Custom-chip entry sheets (one alert face per text kind + the date
    // range sheet).
    private enum TextEntryKind: String, Identifiable {
        case keyword, camera, lens
        var id: String { rawValue }
    }
    @State private var textEntry: TextEntryKind?
    @State private var textEntryValue = ""
    @State private var dateRangeRequested = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                quickFilterField
                quickChips
                addButton
                sortMenu
                if sessionState.hasActiveFilter {
                    clearButton
                }
            }
            if !sessionState.filterChips.isEmpty {
                chipsRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .sheet(isPresented: $dateRangeRequested) { dateRangeSheet }
        .alert(
            textEntryTitle,
            isPresented: Binding(
                get: { textEntry != nil },
                set: { if !$0 { textEntry = nil } })
        ) {
            TextField(
                String(localized: "filter_text_entry_placeholder"),
                text: $textEntryValue)
                .accessibilityIdentifier("filter.textentry")
            Button(String(localized: "alert_ok")) { commitTextEntry() }
                .disabled(textEntryValue.contains("|"))
            Button(String(localized: "alert_cancel"), role: .cancel) {
                textEntry = nil
            }
        } message: {
            Text("filter_text_entry_hint")
        }
    }

    // MARK: - Quick Filter field

    private var quickFilterField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(LightamerColors.textSecondary)
                .font(.caption)
            TextField(
                String(localized: "filter_quick_placeholder"),
                text: Binding(
                    get: { sessionState.quickFilterText },
                    set: { sessionState.setQuickFilterText($0) })
            )
            .textFieldStyle(.plain)
            .font(.callout)
            .focused($quickFilterFocused)
            .accessibilityIdentifier("filter.quickfield")
            if !sessionState.quickFilterText.isEmpty {
                Button {
                    sessionState.setQuickFilterText("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(LightamerColors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("filter.quickclear")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.06)))
        .frame(maxWidth: 240)
        .onExitCommand {
            // Esc clears the text AND drops focus.
            if !sessionState.quickFilterText.isEmpty {
                sessionState.setQuickFilterText("")
            }
            quickFilterFocused = false
        }
        .overlay(alignment: .leading) {
            // `/` focuses the field (Nitro-style keyboard drive). The
            // button is invisible; the shortcut carries the semantics.
            Button {
                quickFilterFocused = true
            } label: {
                Color.clear.contentShape(Rectangle())
            }
            .keyboardShortcut("/")
            .buttonStyle(.plain)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Quick chips (pre-filled predicates)

    private var quickChips: some View {
        HStack(spacing: 4) {
            chipButton(
                FilterPredicateGroup.Rule(
                    field: .rating, op: .gte, value: .int(3)),
                labelKey: "filter_chip_rating_3", id: "filter.chip.rating3")
            chipButton(
                FilterPredicateGroup.Rule(
                    field: .flag, op: .eq, value: .int(1)),
                labelKey: "filter_chip_pick", id: "filter.chip.pick")
            chipButton(
                FilterPredicateGroup.Rule(
                    field: .flag, op: .eq, value: .int(2)),
                labelKey: "filter_chip_reject", id: "filter.chip.reject")
            chipButton(
                FilterPredicateGroup.Rule(
                    field: .hasEdits, op: .eq, value: .int(1)),
                labelKey: "filter_chip_edited", id: "filter.chip.edited")
        }
    }

    /// One toggle chip: present in the chip set = active (highlighted).
    private func chipButton(
        _ rule: FilterPredicateGroup.Rule,
        labelKey: String, id: String
    ) -> some View {
        let active = sessionState.filterChips.contains(rule)
        return Button {
            sessionState.toggleChip(rule)
        } label: {
            Text(String(localized: String.LocalizationValue(labelKey)))
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(
                        active ? Color.accentColor.opacity(0.85)
                            : Color.primary.opacity(0.06)))
                .foregroundStyle(active ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // MARK: - Active chips row (the two-way projection)

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(
                    Array(sessionState.filterChips.enumerated()), id: \.offset
                ) { _, rule in
                    activeChip(rule)
                }
            }
            .padding(.vertical, 1)
        }
        .accessibilityIdentifier("filter.chipsrow")
    }

    private func activeChip(_ rule: FilterPredicateGroup.Rule) -> some View {
        HStack(spacing: 4) {
            Text(Self.chipLabel(for: rule))
                .font(.caption)
                .lineLimit(1)
            Button {
                sessionState.removeChip(rule)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("filter.chip.remove.\(rule.field.rawValue)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.accentColor.opacity(0.25)))
        .accessibilityIdentifier("filter.chip.\(rule.field.rawValue)")
    }

    /// The chip display spelling (zh/en through the catalog — every label
    /// goes through `String(localized:)` interpolation so the key with its
    /// format specifier is looked up; the raw value rides the argument so
    /// the chip is honest about its predicate).
    static func chipLabel(for rule: FilterPredicateGroup.Rule) -> String {
        switch rule.field {
        case .rating:
            if case .int(let v) = rule.value {
                return String(localized: "filter_chip_rating \(v)")
            }
        case .colorLabel:
            if case .int(let v) = rule.value {
                return String(localized: "filter_chip_color \(v)")
            }
        case .flag:
            if case .int(let v) = rule.value {
                return String(
                    localized: String.LocalizationValue(
                        v == 1 ? "filter_chip_pick" : "filter_chip_reject"))
            }
        case .hasEdits:
            return String(localized: "filter_chip_edited")
        case .keywords:
            if case .text(let v) = rule.value {
                return String(localized: "filter_chip_keyword \(v)")
            }
        case .cameraMake:
            if case .text(let v) = rule.value {
                return String(localized: "filter_chip_camera \(v)")
            }
        case .lensModel:
            if case .text(let v) = rule.value {
                return String(localized: "filter_chip_lens \(v)")
            }
        case .iso:
            if case .int(let v) = rule.value {
                return String(localized: "filter_chip_iso \(v)")
            }
        case .focalLength:
            if case .double(let v) = rule.value {
                return String(localized: "filter_chip_focal \(Int(v))")
            }
        case .captureDate:
            return String(localized: "filter_chip_daterange")
        default:
            break
        }
        return rule.field.rawValue
    }

    // MARK: - Add menu

    private var addButton: some View {
        Menu {
            Menu(String(localized: "filter_menu_rating")) {
                ForEach(1...5, id: \.self) { n in
                    Button("\(n)") {
                        sessionState.toggleChip(
                            .init(field: .rating, op: .gte, value: .int(n)))
                    }
                }
            }
            Menu(String(localized: "filter_menu_color_label")) {
                ForEach(0...6, id: \.self) { n in
                    Button("\(n)") {
                        sessionState.toggleChip(
                            .init(field: .colorLabel, op: .eq, value: .int(n)))
                    }
                }
            }
            Button(String(localized: "filter_menu_keyword")) {
                openTextEntry(.keyword)
            }
            Button(String(localized: "filter_menu_camera")) {
                openTextEntry(.camera)
            }
            Button(String(localized: "filter_menu_lens")) {
                openTextEntry(.lens)
            }
            Menu(String(localized: "filter_menu_iso")) {
                ForEach([100, 200, 400, 800, 1600, 3200], id: \.self) { n in
                    Button("\(n)") {
                        sessionState.toggleChip(
                            .init(field: .iso, op: .gte, value: .int(n)))
                    }
                }
            }
            Menu(String(localized: "filter_menu_focal")) {
                ForEach([24.0, 35.0, 50.0, 85.0, 200.0], id: \.self) { v in
                    Button("\(Int(v)) mm") {
                        sessionState.toggleChip(
                            .init(field: .focalLength, op: .gte, value: .double(v)))
                    }
                }
            }
            Button(String(localized: "filter_menu_daterange")) {
                dateRangeRequested = true
            }
        } label: {
            Image(systemName: "plus.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("filter.add")
    }

    private func openTextEntry(_ kind: TextEntryKind) {
        textEntryValue = ""
        textEntry = kind
    }

    private var textEntryTitle: String {
        switch textEntry {
        case .keyword: String(localized: "filter_menu_keyword")
        case .camera: String(localized: "filter_menu_camera")
        case .lens: String(localized: "filter_menu_lens")
        case nil: ""
        }
    }

    private func commitTextEntry() {
        let kind = textEntry
        let text = textEntryValue.trimmingCharacters(in: .whitespaces)
        textEntry = nil
        guard !text.isEmpty, !text.contains("|") else { return }
        let field: FilterField
        switch kind {
        case .camera: field = .cameraMake
        case .lens: field = .lensModel
        default: field = .keywords
        }
        sessionState.toggleChip(
            .init(field: field, op: .contains, value: .text(text)))
    }

    // MARK: - Date range sheet (between)

    private var dateRangeSheet: some View {
        VStack(spacing: 16) {
            Text("filter_daterange_title")
                .font(.headline)
            DatePicker(
                String(localized: "filter_daterange_from"),
                selection: Binding(
                    get: { dateRangeBounds.lower },
                    set: { dateRangeBounds = DateRangeBounds(lower: $0, upper: dateRangeBounds.upper) }
                ),
                displayedComponents: .date)
            DatePicker(
                String(localized: "filter_daterange_to"),
                selection: Binding(
                    get: { dateRangeBounds.upper },
                    set: { dateRangeBounds = DateRangeBounds(lower: dateRangeBounds.lower, upper: $0) }
                ),
                in: ...Date(),
                displayedComponents: .date)
            HStack {
                Button(String(localized: "alert_cancel"), role: .cancel) {
                    dateRangeRequested = false
                }
                Button(String(localized: "filter_daterange_apply")) {
                    let rule = FilterPredicateGroup.Rule(
                        field: .captureDate, op: .between,
                        value: .doubleRange(
                            lower: dateRangeBounds.lower.timeIntervalSince1970,
                            upper: dateRangeBounds.upper.timeIntervalSince1970 + 86_399))
                    dateRangeRequested = false
                    sessionState.toggleChip(rule)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }

    /// The sheet's bound pair (default: the last 365 days).
    private struct DateRangeBounds {
        var lower: Date
        var upper: Date
    }
    @State private var dateRangeBounds = DateRangeBounds(
        lower: Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Date(),
        upper: Date())

    // MARK: - Sort menu

    private var sortMenu: some View {
        HStack(spacing: 2) {
            Picker(String(localized: "sort_menu_label"), selection: Binding(
                get: { sessionState.sort.key },
                set: { sessionState.setSort(FilterSort(key: $0, ascending: sessionState.sort.ascending)) }
            )) {
                ForEach(FilterSortKey.allCases, id: \.self) { key in
                    Text(String(localized: Self.sortLabel(for: key))).tag(key)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 130)
            .accessibilityIdentifier("filter.sortpicker")

            Button {
                sessionState.setSort(
                    FilterSort(
                        key: sessionState.sort.key,
                        ascending: !sessionState.sort.ascending))
            } label: {
                Image(systemName: sessionState.sort.ascending
                    ? "arrow.up" : "arrow.down")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("filter.sortdirection")
        }
    }

    private static func sortLabel(for key: FilterSortKey) -> String.LocalizationValue {
        switch key {
        case .filename: "sort_key_filename"
        case .rating: "sort_key_rating"
        case .captureDate: "sort_key_capture_date"
        case .iso: "sort_key_iso"
        case .focalLength: "sort_key_focal_length"
        case .scanEpoch: "sort_key_scan_epoch"
        }
    }

    // MARK: - Clear

    private var clearButton: some View {
        Button {
            sessionState.clearFilters()
        } label: {
            Image(systemName: "xmark.circle")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filter.clear")
    }
}
