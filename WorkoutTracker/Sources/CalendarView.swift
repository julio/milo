import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var completionStore: CompletionStore
    @State private var monthIndex = CalendarView.initialMonthIndex()

    private let months = PlanCalendar.months()

    static func initialMonthIndex() -> Int {
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        let months = PlanCalendar.months()
        return months.firstIndex {
            $0.year == now.year && $0.month == now.month
        } ?? 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                monthPicker
                weekdayHeader
                monthGrid
                legend
                Spacer()
            }
            .padding()
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await completionStore.refresh()
            }
            .refreshable {
                await completionStore.refresh()
            }
        }
    }

    private var month: PlanCalendar.Month { months[monthIndex] }

    private var monthPicker: some View {
        HStack {
            Button {
                withAnimation { monthIndex -= 1 }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(monthIndex == 0)

            Spacer()
            Text(month.title())
                .font(.headline)
            Spacer()

            Button {
                withAnimation { monthIndex += 1 }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(monthIndex == months.count - 1)
        }
        .padding(.horizontal, 8)
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(PlanCalendar.weekdayHeaders(), id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
            ForEach(Array(PlanCalendar.grid(month).enumerated()), id: \.offset) { _, day in
                if let day {
                    DayCell(day: day, status: completionStore.status(month: month.month, day: day))
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            LegendDot(color: .green, label: "Done")
            LegendDot(color: .orange, label: "Partial")
            LegendDot(color: Color(.systemGray4), label: "Planned")
        }
        .padding(.top, 8)
    }
}

struct DayCell: View {
    let day: Int
    let status: DayStatus

    private var fill: Color {
        switch status {
        case .complete: return .green
        case .partial: return .orange
        case .pending: return Color(.systemGray4)
        case .notInPlan: return .clear
        }
    }

    var body: some View {
        Text("\(day)")
            .font(.subheadline.weight(status == .notInPlan ? .regular : .bold))
            .foregroundStyle(status == .notInPlan ? Color.secondary :
                             status == .pending ? Color.primary : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Circle().fill(fill).frame(width: 36, height: 36))
    }
}

struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    CalendarView()
        .environmentObject(CompletionStore())
}
