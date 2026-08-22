import SwiftUI
import Charts

/// One line chart per exercise, charting the best logged set per day against
/// a dashed week-1 baseline. A segmented control switches between weight and
/// reps — one axis per chart, never two scales.
struct ProgressTabView: View {
    @EnvironmentObject var logStore: LogStore
    @EnvironmentObject var renameStore: RenameStore
    @State private var metric: ProgressMetric = .weight

    private var series: [ExerciseSeries] {
        ProgressData.series(metric: metric, logs: logStore.logs)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Metric", selection: $metric) {
                        ForEach(ProgressMetric.allCases) { metric in
                            Text(metric.rawValue).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)

                    if let message = logStore.errorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if series.isEmpty {
                        Text("No \(metric.rawValue.lowercased()) logged yet.\nEnter what you lift on the Today tab.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else {
                        ForEach(series) { series in
                            SeriesCard(
                                series: series, metric: metric,
                                title: renameStore.displayName(for: series.exercise))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await logStore.refresh()
                await renameStore.refresh()
            }
            .refreshable {
                await logStore.refresh()
                await renameStore.refresh()
            }
        }
    }
}

struct SeriesCard: View {
    let series: ExerciseSeries
    let metric: ProgressMetric
    let title: String

    private var deltaText: String {
        let sign = series.delta >= 0 ? "+" : "−"
        return "\(sign)\(LogStore.weightText(abs(series.delta))) \(metric.unit) vs wk 1"
    }

    private var deltaColor: Color {
        if series.delta > 0 { return .green }
        if series.delta < 0 { return .orange }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(deltaText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(deltaColor)
            }

            Chart {
                RuleMark(y: .value("Week 1", series.baseline))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .annotation(position: .bottomLeading, spacing: 2) {
                        Text("wk 1")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                ForEach(series.points) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value(metric.rawValue, point.value))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value(metric.rawValue, point.value))
                        .symbolSize(40)
                }
                .foregroundStyle(Color.accentColor)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxisLabel(metric.unit)
            .frame(height: 150)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    ProgressTabView()
        .environmentObject(LogStore())
        .environmentObject(RenameStore())
}
