import SwiftUI
import Charts

public struct UsageDailyChartView: View {
    public let daily: [DayTokens]

    public init(daily: [DayTokens]) {
        self.daily = daily
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
            .foregroundStyle(UsagePalette.accent)
        }
        .chartXAxis {
            AxisMarks { value in
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
