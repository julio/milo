import SwiftUI

struct TrainingPlanView: View {
    @EnvironmentObject var completionStore: CompletionStore
    @State private var index = TrainingPlan.defaultIndex(for: Date())

    private var days: [PlanDay] { TrainingPlan.days }

    var body: some View {
        NavigationStack {
            TabView(selection: $index) {
                ForEach(days) { day in
                    PlanDayView(day: day)
                        .tag(day.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                navigationBar
            }
            .task {
                await completionStore.refresh()
            }
        }
    }

    private var navigationBar: some View {
        HStack {
            Button {
                withAnimation { index -= 1 }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 34))
            }
            .disabled(index == 0)

            Spacer()

            VStack(spacing: 2) {
                Text("Session \(index + 1) of \(days.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Today") {
                    withAnimation { index = TrainingPlan.defaultIndex(for: Date()) }
                }
                .font(.caption.weight(.semibold))
            }

            Spacer()

            Button {
                withAnimation { index += 1 }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 34))
            }
            .disabled(index == days.count - 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct PlanDayView: View {
    let day: PlanDay
    @EnvironmentObject var completionStore: CompletionStore
    private let maxes = TrainingMaxes.standard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let message = completionStore.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(spacing: 10) {
                    ForEach(Array(day.entries.enumerated()), id: \.offset) { index, entry in
                        PlanEntryRow(
                            entry: entry,
                            maxes: maxes,
                            isDone: completionStore.isDone(dayId: day.id, entryIndex: index)
                        ) {
                            Task {
                                await completionStore.toggle(dayId: day.id, entryIndex: index)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var doneCount: Int { completionStore.doneCount(for: day) }
    private var totalCount: Int { CompletionStore.trackableIndices(for: day).count }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(day.dateTitle)
                    .font(.title2.bold())
                Spacer()
                if day.isDeload {
                    Text("DELOAD")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.yellow.opacity(0.3))
                        .clipShape(Capsule())
                }
            }
            Text(day.label)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.tint)
            HStack {
                Text("Week \(day.week) · Cycle \(day.cycle), week \(day.weekOfCycle) of 4")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(doneCount)/\(totalCount) done")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(doneCount == totalCount ? .green : .secondary)
            }
            ProgressView(value: Double(doneCount), total: Double(totalCount))
                .tint(doneCount == totalCount ? .green : .accentColor)
        }
    }
}

struct PlanEntryRow: View {
    let entry: PlanEntry
    let maxes: TrainingMaxes
    let isDone: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if !entry.isSkipped {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isDone ? .green : .secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.exercise)
                        .font(.subheadline.weight(entry.exercise == "same lift" ? .regular : .semibold))
                        .foregroundStyle(entry.isSkipped ? .secondary : .primary)
                        .strikethrough(isDone && !entry.isSkipped)
                    Spacer()
                    Text(entry.setsReps)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(maxes.display(for: entry.weight))
                        .font(.subheadline.weight(.bold))
                        .frame(minWidth: 60, alignment: .trailing)
                }
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(isDone && !entry.isSkipped ? Color.green.opacity(0.12) : Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(entry.isSkipped ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            if !entry.isSkipped {
                onToggle()
            }
        }
    }
}

#Preview {
    TrainingPlanView()
        .environmentObject(CompletionStore())
}
