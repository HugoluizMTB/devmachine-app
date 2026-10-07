import SwiftUI
import DevmachineCore

enum WidgetLevelColor {
    static func color(_ level: WidgetLevel) -> Color {
        switch level {
        case .ok: return .green
        case .warn: return .orange
        case .bad: return .red
        case .neutral: return Color.dmMuted
        }
    }
}

private struct ValueErrorText: View {
    let error: any Error
    let density: WidgetDensity

    var body: some View {
        SourceErrorView(state: SourceErrorPresentation.state(title: "This value cannot be shown", error: error), density: density)
    }
}

struct NumberWidgetView: View {
    let view: WidgetView
    let output: SourceOutput
    let density: WidgetDensity

    var body: some View {
        switch Result(catching: { try ValueExtraction.number(from: output, view: view) }) {
        case let .success(number) where view.hideZero && number == 0:
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .success(number):
            Text(verbatim: NumberText.format(number, format: view.format, unit: view.unit))
                .font(.dm(density == .full ? 44 : 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failure(error):
            ValueErrorText(error: error, density: density)
        }
    }
}

struct GaugeWidgetView: View {
    let view: WidgetView
    let output: SourceOutput
    let density: WidgetDensity
    @Environment(\.dmMetrics) private var m

    var body: some View {
        switch Result(catching: { try ValueExtraction.number(from: output, view: view) }) {
        case let .success(number):
            let model = GaugeModel(value: number, view: view)
            let color = WidgetLevelColor.color(model.level)
            if density == .full {
                GaugeRing(model: model, color: color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: m.space.sm) {
                    Text(verbatim: model.label)
                        .font(.dm(20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    DMProgressBar(done: Int((model.fraction * 100).rounded()), total: 100, fillColor: color, barHeight: 6, cornerRadius: 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        case let .failure(error):
            ValueErrorText(error: error, density: density)
        }
    }
}

/// Sized from the space it gets, so the ring never draws past a large card.
private struct GaugeRing: View {
    let model: GaugeModel
    let color: Color
    @Environment(\.dmMetrics) private var m

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = max(m.pt(6), side * 0.08)
            ZStack {
                Circle()
                    .stroke(Color.dmDivider, lineWidth: line)
                Circle()
                    .trim(from: 0, to: model.fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(verbatim: model.label)
                    .font(.dm(28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .padding(.horizontal, line * 1.5)
            }
            .padding(line / 2)
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StatusWidgetView: View {
    let view: WidgetView
    let output: SourceOutput
    let density: WidgetDensity
    @Environment(\.dmMetrics) private var m

    var body: some View {
        switch Result(catching: { try StatusModel.make(output: output, view: view) }) {
        case let .success(model):
            HStack(spacing: m.space.sm) {
                Circle()
                    .fill(WidgetLevelColor.color(model.level))
                    .frame(width: m.pt(density == .full ? 14 : 10), height: m.pt(density == .full ? 14 : 10))
                Text(verbatim: model.label)
                    .font(.dm(density == .full ? 22 : 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        case let .failure(error):
            ValueErrorText(error: error, density: density)
        }
    }
}

struct SparklineWidgetView: View {
    let view: WidgetView
    let output: SourceOutput
    let history: [SparklinePoint]
    let density: WidgetDensity
    @Environment(\.dmMetrics) private var m

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.xs) {
            if let latest = Self.latest(history: history, output: output, view: view) {
                Text(verbatim: NumberText.format(latest, format: view.format, unit: view.unit))
                    .font(.dm(density == .full ? 22 : 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            SparklineShape(values: history.map(\.value), top: view.max)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }
}

extension SparklineWidgetView {
    static func latest(history: [SparklinePoint], output: SourceOutput, view: WidgetView) -> Double? {
        history.last?.value ?? (try? ValueExtraction.number(from: output, view: view))
    }
}

private struct SparklineShape: Shape {
    let values: [Double]
    let top: Double?

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let low = min(0, values.min() ?? 0)
        let high = max(top ?? values.max() ?? 1, low + 1e-9)
        for (index, value) in values.enumerated() {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = rect.maxY - rect.height * CGFloat((min(value, high) - low) / (high - low))
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}
