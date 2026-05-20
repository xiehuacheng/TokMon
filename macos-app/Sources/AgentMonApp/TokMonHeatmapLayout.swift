import Foundation

struct TokMonHeatmapLayout: Equatable {
  struct Week: Equatable, Identifiable {
    let id: Int
    let cells: [TokMonHeatmapDay?]

    var weekIndex: Int { id }
  }

  struct MonthLabel: Equatable, Identifiable {
    let weekIndex: Int
    let label: String

    var id: String { "\(weekIndex):\(label)" }
  }

  struct WeekdayLabel: Equatable, Identifiable {
    let weekdayIndex: Int
    let label: String

    var id: Int { weekdayIndex }
  }

  struct Metrics: Equatable {
    let cellSize: CGFloat
    let gap: CGFloat
    let labelWidth: CGFloat
    let usedWidth: CGFloat
  }

  let weeks: [Week]
  let monthLabels: [MonthLabel]
  let weekdayLabels: [WeekdayLabel]

  init(days: [TokMonHeatmapDay], calendar: Calendar = .current) {
    let parsedDays = TokMonHeatmapLayout.parsedDays(days, calendar: calendar)
    guard let firstDate = parsedDays.first?.date else {
      weeks = []
      monthLabels = []
      weekdayLabels = TokMonHeatmapLayout.defaultWeekdayLabels
      return
    }

    let weekStart = TokMonHeatmapLayout.startOfWeek(for: firstDate, calendar: calendar)
    var weekCells: [[TokMonHeatmapDay?]] = []
    var labels: [MonthLabel] = []
    var labeledMonths = Set<String>()

    for parsedDay in parsedDays {
      let weekIndex = TokMonHeatmapLayout.weekOffset(from: weekStart, to: parsedDay.date, calendar: calendar)
      let weekdayIndex = TokMonHeatmapLayout.weekdayIndex(for: parsedDay.date, calendar: calendar)

      while weekCells.count <= weekIndex {
        weekCells.append(Array(repeating: nil, count: 7))
      }
      weekCells[weekIndex][weekdayIndex] = parsedDay.day

      let monthKey = TokMonHeatmapLayout.monthKey(for: parsedDay.date, calendar: calendar)
      if calendar.component(.day, from: parsedDay.date) == 1, !labeledMonths.contains(monthKey) {
        labels.append(MonthLabel(
          weekIndex: weekIndex,
          label: TokMonHeatmapLayout.monthLabel(for: parsedDay.date, calendar: calendar),
        ))
        labeledMonths.insert(monthKey)
      }
    }

    weeks = weekCells.enumerated().map { index, cells in
      Week(id: index, cells: cells)
    }
    monthLabels = labels
    weekdayLabels = TokMonHeatmapLayout.defaultWeekdayLabels
  }

  private static let defaultWeekdayLabels = [
    WeekdayLabel(weekdayIndex: 1, label: "Mon"),
    WeekdayLabel(weekdayIndex: 3, label: "Wed"),
    WeekdayLabel(weekdayIndex: 5, label: "Fri"),
  ]

  private static func parsedDays(
    _ days: [TokMonHeatmapDay],
    calendar: Calendar,
  ) -> [(day: TokMonHeatmapDay, date: Date)] {
    return days.compactMap { day in
      dateComponents(from: day.day, calendar: calendar).flatMap { components in
        calendar.date(from: components).map { (day, calendar.startOfDay(for: $0)) }
      }
    }
    .sorted { $0.date < $1.date }
  }

  private static func dateComponents(from day: String, calendar: Calendar) -> DateComponents? {
    guard day.count == 10,
          day[day.index(day.startIndex, offsetBy: 4)] == "-",
          day[day.index(day.startIndex, offsetBy: 7)] == "-" else {
      return nil
    }
    let yearText = day.prefix(4)
    let monthStart = day.index(day.startIndex, offsetBy: 5)
    let dayStart = day.index(day.startIndex, offsetBy: 8)
    guard let year = Int(yearText),
          let month = Int(day[monthStart..<day.index(monthStart, offsetBy: 2)]),
          let dayNumber = Int(day[dayStart..<day.endIndex]),
          (1...12).contains(month),
          (1...31).contains(dayNumber) else {
      return nil
    }
    return DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: year, month: month, day: dayNumber)
  }

  private static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
    calendar.date(
      byAdding: .day,
      value: -weekdayIndex(for: date, calendar: calendar),
      to: calendar.startOfDay(for: date),
    ) ?? date
  }

  private static func weekOffset(from start: Date, to date: Date, calendar: Calendar) -> Int {
    max(0, (calendar.dateComponents([.day], from: start, to: date).day ?? 0) / 7)
  }

  private static func weekdayIndex(for date: Date, calendar: Calendar) -> Int {
    (calendar.component(.weekday, from: date) + 5) % 7
  }

  private static func monthKey(for date: Date, calendar: Calendar) -> String {
    let year = calendar.component(.year, from: date)
    let month = calendar.component(.month, from: date)
    return "\(year)-\(month)"
  }

  private static func monthLabel(for date: Date, calendar: Calendar) -> String {
    let month = calendar.component(.month, from: date)
    return monthLabels.indices.contains(month - 1) ? monthLabels[month - 1] : ""
  }

  private static let monthLabels = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

  static func metrics(
    availableWidth: CGFloat,
    weekCount: Int,
    labelWidth: CGFloat,
    minimumCellSize: CGFloat = 3,
    maximumCellSize: CGFloat = 8,
  ) -> Metrics {
    let normalizedWeekCount = max(weekCount, 1)
    let gap: CGFloat = 1
    let availableForCells = max(availableWidth - labelWidth - CGFloat(normalizedWeekCount - 1) * gap, minimumCellSize)
    let rawCellSize = availableForCells / CGFloat(normalizedWeekCount)
    let cellSize = min(max(rawCellSize, minimumCellSize), maximumCellSize)
    let usedWidth = labelWidth + CGFloat(normalizedWeekCount) * cellSize + CGFloat(normalizedWeekCount - 1) * gap
    return Metrics(cellSize: cellSize, gap: gap, labelWidth: labelWidth, usedWidth: usedWidth)
  }
}
