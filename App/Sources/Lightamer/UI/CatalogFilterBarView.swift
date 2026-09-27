import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// CatalogFilterBarView (Plan 16-2 T3; D-16-CONTEXT-5⑥) — the filter row over
// the CROSS-SESSION grid. The 12-2 `FilterBarView` face (chips + Quick
// Filter + sort menu) rides the CATALOG model instead of SessionState — the
// predicate GROUP structures are the same model with zero changes, and the
// translation goes through the 16-1 `FilterDomain.catalog` dispatch inside
// the store. The session grid's filter state is never touched (the
// Sessions-mode byte-equivalence red line; execution decision: a dedicated
// view bound to the catalog model, no shared mutable filter state).
//
// Catalog-domain notes:
//   • the sort menu whitelists the catalog-serviceable keys ONLY
//     (captureDate / rating / filename — the expression-index set; anything
//     else is a typed store error by design);
//   • Quick Filter filename/dir contains = case-sensitive startsWith in the
//     catalog domain (the 16-1 downgrade under case_sensitive_like; RQ-16-
//     16①) — the hint line says so while the field is non-empty.
// ─────────────────────────────────────────────────────────────────────────────

internal struct CatalogFilterBarView: View {

    let model: CatalogBrowserModel

    /// The catalog-serviceable sort whitelist (the v1 pin).
    private static let sortKeys: [FilterSortKey] = [.captureDate, .rating, .filename]

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
                if model.hasActiveFilter {
                    clearButton
                }
            }
            if !model.filterChips.isEmpty {
                chipsRow
            }
            // The catalog-domain Quick Filter semantics hint (RQ-16-16①):
            // visible exactly while the field carries text.
            if !model.quickFilterText.isEmpty {
                Text("catalog_filter_quick_hint")
                    .font(.caption2)
                    .foregroundStyle(LightamerColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("catalog.filter.quickhint")
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
                .accessibilityIdentifier("catalog.filter.textentry")
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
                    get: { model.quickFilterText },
                    set: { model.setQuickFilterText($0) })
            )
            .textFieldStyle(.plain)
            .font(.callout)
            .accessibilityIdentifier("catalog.filter.quickfield")
            if !model.quickFilterText.isEmpty {
                Button {
                    model.setQuickFilterText("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(LightamerColors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("catalog.filter.quickclear")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.06)))
        .frame(maxWidth: 240)
    }

    // MARK: - Quick chips (the same four pre-filled predicates)

    private var quickChips: some View {
        HStack(spacing: 4) {
            chipButton(
                FilterPredicateGroup.Rule(
                    field: .rating, op: .gte, value: .int(3)),
                labelKey: "filter_chip_rating_3", id: "catalog.filter.chip.rating3")
            chipButton(
                FilterPredicateGroup.Rule(
                    field: .flag, op: .eq, value: .int(1)),
                labelKey: "filter_chip_pick", id: "catalog.filter.chip.pick")
            chipButton(
                FilterPredicateGroup.Rule(
                    field: .flag, op: .eq, value: .int(2)),
                labelKey: "filter_chip_reject", id: "catalog.filter.chip.reject")
            chipButton(
                FilterPredicateGroup.Rule(
                    field: .hasEdits, op: .eq, value: .int(1)),
                labelKey: "filter_chip_edited", id: "catalog.filter.chip.edited")
        }
    }

    private func chipButton(
        _ rule: FilterPredicateGroup.Rule,
        labelKey: String, id: String
    ) -> some View {
        let active = model.filterChips.contains(rule)
        return Button {
            model.toggleChip(rule)
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

    // MARK: - Active chips row

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(
                    Array(model.filterChips.enumerated()), id: \.offset
                ) { _, rule in
                    activeChip(rule)
                }
            }
            .padding(.vertical, 1)
        }
        .accessibilityIdentifier("catalog.filter.chipsrow")
    }

    private func activeChip(_ rule: FilterPredicateGroup.Rule) -> some View {
        HStack(spacing: 4) {
            Text(FilterBarView.chipLabel(for: rule))
                .font(.caption)
                .lineLimit(1)
            Button {
                model.removeChip(rule)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("catalog.filter.chip.remove.\(rule.field.rawValue)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.accentColor.opacity(0.25)))
        .accessibilityIdentifier("catalog.filter.chip.\(rule.field.rawValue)")
    }

    // MARK: - Add menu (the 12-2 structure verbatim)

    private var addButton: some View {
        Menu {
            Menu(String(localized: "filter_menu_rating")) {
                ForEach(1...5, id: \.self) { n in
                    Button("\(n)") {
                        model.toggleChip(
                            .init(field: .rating, op: .gte, value: .int(n)))
                    }
                }
            }
            Menu(String(localized: "filter_menu_color_label")) {
                ForEach(0...6, id: \.self) { n in
                    Button("\(n)") {
                        model.toggleChip(
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
                        model.toggleChip(
                            .init(field: .iso, op: .gte, value: .int(n)))
                    }
                }
            }
            Menu(String(localized: "filter_menu_focal")) {
                ForEach([24.0, 35.0, 50.0, 85.0, 200.0], id: \.self) { v in
                    Button("\(Int(v)) mm") {
                        model.toggleChip(
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
        .accessibilityIdentifier("catalog.filter.add")
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
        model.toggleChip(
            .init(field: field, op: .contains, value: .text(text)))
    }

    // MARK: - Date range sheet

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
                    model.toggleChip(rule)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }

    private struct DateRangeBounds {
        var lower: Date
        var upper: Date
    }
    @State private var dateRangeBounds = DateRangeBounds(
        lower: Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Date(),
        upper: Date())

    // MARK: - Sort menu (the catalog-serviceable whitelist)

    private var sortMenu: some View {
        HStack(spacing: 2) {
            Picker(String(localized: "sort_menu_label"), selection: Binding(
                get: { model.activeSort.key },
                set: { model.setSort(FilterSort(key: $0, ascending: model.activeSort.ascending)) }
            )) {
                ForEach(Self.sortKeys, id: \.self) { key in
                    Text(String(localized: Self.sortLabel(for: key))).tag(key)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 130)
            .accessibilityIdentifier("catalog.filter.sortpicker")

            Button {
                model.setSort(
                    FilterSort(
                        key: model.activeSort.key,
                        ascending: !model.activeSort.ascending))
            } label: {
                Image(systemName: model.activeSort.ascending
                    ? "arrow.up" : "arrow.down")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("catalog.filter.sortdirection")
        }
    }

    private static func sortLabel(for key: FilterSortKey) -> String.LocalizationValue {
        switch key {
        case .filename: "sort_key_filename"
        case .rating: "sort_key_rating"
        case .captureDate: "sort_key_capture_date"
        case .iso, .focalLength, .scanEpoch: "sort_key_filename"
        }
    }

    // MARK: - Clear

    private var clearButton: some View {
        Button {
            model.clearFilters()
        } label: {
            Image(systemName: "xmark.circle")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("catalog.filter.clear")
    }
}
