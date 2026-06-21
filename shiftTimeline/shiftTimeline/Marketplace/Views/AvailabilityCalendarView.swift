import SwiftUI

/// Vendor availability editor (E18). A month grid where the vendor taps days to
/// toggle manual unavailability. Days they're BOOKED on (a claimed Shift event)
/// are shown locked with the event title and can't be toggled — that's
/// verified-data busy. Entered from My Vendor Profile.
struct AvailabilityCalendarView: View {

    @Environment(\.availabilityService) private var service

    @State private var monthAnchor = AvailabilityCalendarView.startOfMonth(Date())
    @State private var manualDays: Set<String> = []
    @State private var bookedTitles: [String: String] = [:]
    @State private var isLoading = false
    @State private var working: Set<String> = []
    @State private var bookedAlertTitle: String?

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                monthHeader
                weekdayHeader
                grid
                legend
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background { ProBackground() }
        .navigationTitle(String(localized: "Availability"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: monthAnchor) { await load() }
        .alert(
            String(localized: "Booked"),
            isPresented: Binding(get: { bookedAlertTitle != nil }, set: { if !$0 { bookedAlertTitle = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "You're booked for \"\(bookedAlertTitle ?? "")\" that day. Booked Shift events are busy automatically."))
        }
    }

    // MARK: Header

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
            Spacer()
            Text(monthAnchor, format: .dateTime.month(.wide).year())
                .font(.headline)
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
        }
        .overlay(alignment: .trailing) {
            if isLoading { ProgressView().scaleEffect(0.7) }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 6) {
            ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Grid

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(gridCells.enumerated()), id: \.offset) { _, day in
                if let day { dayCell(day) }
                else { Color.clear.frame(height: 44) }
            }
        }
        .accessibilityIdentifier(AccessibilityID.Marketplace.availabilityGrid)
    }

    @ViewBuilder
    private func dayCell(_ date: Date) -> some View {
        let key = CalendarDay.string(from: date)
        let booked = bookedTitles[key]
        let isManual = manualDays.contains(key)
        let isBusy = booked != nil || isManual
        let dayNumber = calendar.component(.day, from: date)

        Button {
            handleTap(date: date, key: key, booked: booked, isManual: isManual)
        } label: {
            VStack(spacing: 2) {
                Text("\(dayNumber)")
                    .font(.subheadline.weight(isBusy ? .bold : .regular))
                    .foregroundStyle(cellTextColor(booked: booked != nil, manual: isManual))
                if booked != nil {
                    Image(systemName: "lock.fill").font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(cellBackground(booked: booked != nil, manual: isManual), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if working.contains(key) { ProgressView().scaleEffect(0.6) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(date: date, booked: booked, manual: isManual))
    }

    private func cellBackground(booked: Bool, manual: Bool) -> AnyShapeStyle {
        if booked { return AnyShapeStyle(ShiftPalette.accent.gradient) }
        if manual { return AnyShapeStyle(ShiftPalette.soft(ShiftPalette.accent)) }
        return AnyShapeStyle(ShiftPalette.soft(ShiftPalette.neutral))
    }

    private func cellTextColor(booked: Bool, manual: Bool) -> Color {
        if booked { return .white }
        if manual { return ShiftPalette.accent }
        return .primary
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: ShiftPalette.soft(ShiftPalette.accent), label: String(localized: "Busy"))
            legendItem(color: AnyShapeStyle(ShiftPalette.accent.gradient), label: String(localized: "Booked (locked)"))
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: some ShapeStyle, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 14, height: 14)
            Text(label)
        }
    }

    // MARK: Interaction

    private func handleTap(date: Date, key: String, booked: String?, isManual: Bool) {
        if let booked {
            bookedAlertTitle = booked            // locked — explain, don't toggle
            return
        }
        guard service != nil, !working.contains(key) else { return }
        Task { await toggle(date: date, key: key, currentlyManual: isManual) }
    }

    private func toggle(date: Date, key: String, currentlyManual: Bool) async {
        guard let service else { return }
        working.insert(key)
        defer { working.remove(key) }
        // Optimistic flip.
        if currentlyManual { manualDays.remove(key) } else { manualDays.insert(key) }
        do {
            if currentlyManual {
                try await service.clearBusy(date: date)
            } else {
                try await service.markBusy(date: date, note: nil)
            }
        } catch {
            // Revert on failure.
            if currentlyManual { manualDays.insert(key) } else { manualDays.remove(key) }
        }
    }

    // MARK: Data

    private func load() async {
        guard let service else { return }
        isLoading = true
        defer { isLoading = false }
        let (from, to) = monthBounds()
        let rows = (try? await service.calendar(from: from, to: to)) ?? []
        var manual: Set<String> = []
        var booked: [String: String] = [:]
        for row in rows {
            if row.isBooked {
                booked[row.busyDate] = row.eventTitle ?? String(localized: "Event")
            } else {
                manual.insert(row.busyDate)
            }
        }
        manualDays = manual
        bookedTitles = booked
    }

    // MARK: Calendar math

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = Self.startOfMonth(next)
        }
    }

    private func monthBounds() -> (Date, Date) {
        guard let range = calendar.range(of: .day, in: .month, for: monthAnchor),
              let last = calendar.date(byAdding: .day, value: range.count - 1, to: monthAnchor) else {
            return (monthAnchor, monthAnchor)
        }
        return (monthAnchor, last)
    }

    /// Leading blanks (nil) for the first-of-month weekday offset, then each day.
    private var gridCells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: monthAnchor) else { return [] }
        let weekday = calendar.component(.weekday, from: monthAnchor)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<range.count {
            cells.append(calendar.date(byAdding: .day, value: offset, to: monthAnchor))
        }
        return cells
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private func accessibilityLabel(date: Date, booked: String?, manual: Bool) -> String {
        let day = date.formatted(date: .complete, time: .omitted)
        if let booked { return String(localized: "\(day) — booked for \(booked)") }
        if manual { return String(localized: "\(day) — busy. Tap to mark available.") }
        return String(localized: "\(day) — available. Tap to mark busy.")
    }

    static func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }
}
