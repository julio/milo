import SwiftUI
import Charts

/// One line chart per exercise: the best set's estimated 1RM per day,
/// against a dashed week-1 baseline.
struct ProgressTabView: View {
    @EnvironmentObject var logStore: LogStore
    @EnvironmentObject var renameStore: RenameStore
    @EnvironmentObject var syncEngine: SyncEngine

    private var series: [ExerciseSeries] {
        ProgressData.series(logs: logStore.logs)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SyncStatusBar()

                    if series.isEmpty {
                        Text("Nothing logged yet.\nEnter what you lift on the Today tab.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else {
                        Text("Estimated one-rep max (lb), best set per day")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(series) { series in
                            SeriesCard(
                                series: series,
                                title: renameStore.displayName(for: series.exercise))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await syncEngine.flush()
                await logStore.refresh()
                await renameStore.refresh()
            }
            .refreshable {
                await syncEngine.flush()
                await logStore.refresh()
                await renameStore.refresh()
            }
        }
    }
}

struct SeriesCard: View {
    let series: ExerciseSeries
    let title: String

    private var deltaText: String {
        let sign = series.delta >= 0 ? "+" : "−"
        return "\(sign)\(Int(abs(series.delta).rounded())) lb vs wk 1"
    }

    private var deltaColor: Color {
        if series.delta > 0 { return .green }
        if series.delta < 0 { return .orange }
        return .secondary
    }

    // Fixed yy/MM/dd regardless of locale ordering.
    static let axisFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yy/MM/dd"
        return formatter
    }()

    // Padded so a single logged day still spans several days — otherwise
    // the automatic axis subdivides one day into hours.
    private var xDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let first = calendar.date(byAdding: .day, value: -2, to: series.points.first!.date)!
        let last = calendar.date(byAdding: .day, value: 2, to: series.points.last!.date)!
        return first...last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(series.latest.rounded())) lb")
                        .font(.title3.bold())
                    Text(deltaText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(deltaColor)
                }
            }

            Chart {
                // The dashed week-1 baseline; the delta badge above the
                // chart names it, so it carries no label of its own.
                RuleMark(y: .value("Week 1", series.baseline))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary.opacity(0.5))
                ForEach(series.points) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Est. 1RM", point.value))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Est. 1RM", point.value))
                        .symbolSize(40)
                }
                .foregroundStyle(Color.accentColor)
            }
            .chartXScale(domain: xDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(Self.axisFormatter.string(from: date))
                        }
                    }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
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
        .environmentObject(SyncEngine.shared)
}
