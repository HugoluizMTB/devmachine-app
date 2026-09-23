import SwiftUI
import Charts

enum UsageDailyChartLabels {
    static func visibleDates(in daily: [DayTokens], limit: Int = 7) -> [String] {
        guard !daily.isEmpty, limit > 0 else { return [] }
        guard daily.count > limit else { return daily.map(\.date) }
        guard limit > 1 else { return [daily.last!.date] }

        let lastIndex = daily.count - 1
        return (0..<limit).map { position in
            let fraction = Double(position) / Double(limit - 1)
            return daily[Int((fraction * Double(lastIndex)).rounded())].date
        }
    }
}

public struct UsageDailyChartView: View {
    public let daily: [DayTokens]
    public let accent: Color

    public init(daily: [DayTokens], accent: Color) {
        self.daily = daily
        self.accent = accent
    }

    public init(daily: [DayTokens]) {
        self.init(daily: daily, accent: UsagePalette.accent)
    }

    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f
    }()

    private static func weekdayLabel(_ ymd: String) -> String {
        guard let date = Self.ymd.date(from: ymd) else { return ymd }
        return weekday.string(from: date)
    }

    public var body: some View {
        Chart(daily) { day in
            BarMark(
                x: .value("Day", day.date),
                y: .value("Tokens", day.tokens)
            )
            .foregroundStyle(accent)
        }
        .chartXAxis {
            AxisMarks(values: UsageDailyChartLabels.visibleDates(in: daily)) { value in
                AxisValueLabel {
                    if let ymd = value.as(String.self) {
                        Text(verbatim: Self.weekdayLabel(ymd))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let tokens = value.as(Double.self) {
                        Text(verbatim: UsageFormat.tokens(Int64(tokens)))
                    }
                }
            }
        }
        .frame(height: 140)
    }
}
