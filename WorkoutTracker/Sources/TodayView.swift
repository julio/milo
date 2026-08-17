import SwiftUI

/// One screen per calendar day: the training session (if any) followed by
/// the daily stretch routine, with a single combined progress bar.
struct TodayView: View {
    @EnvironmentObject var completionStore: CompletionStore
    @EnvironmentObject var stretchStore: StretchStore
    @State private var selectedDate = Date()

    private let maxes = TrainingMaxes.standard

    private var planDay: PlanDay? { TrainingPlan.day(for: selectedDate) }
    private var dateKey: String { StretchPlan.dateKey(for: selectedDate) }
    private var stretchesActive: Bool { StretchPlan.isActive(on: selectedDate) }

    private var counts: (done: Int, total: Int) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
        return DayProgress.counts(
            year: c.year!, month: c.month!, day: c.day!,
            trainingCompletions: completionStore.completions,
            stretchCompletions: stretchStore.completions)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    errorBanners

                    if let day = planDay {
                        sectionTitle("Workout", systemImage: "dumbbell.fill")
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

                    if stretchesActive {
                        sectionTitle("Stretches", systemImage: "figure.cooldown")
                        VStack(spacing: 10) {
                            ForEach(StretchPlan.stretches.indices, id: \.self) { index in
                                StretchRow(
                                    name: StretchPlan.stretches[index],
                                    isDone: stretchStore.isDone(dateKey: dateKey, index: index)
                                ) {
                                    Task {
                                        await stretchStore.toggle(dateKey: dateKey, index: index)
                                    }
                                }
                            }
                        }
                    }

                    if planDay == nil && !stretchesActive {
                        Text("Nothing scheduled")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                }
                .padding()
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                navigationBar
            }
            .task {
                await completionStore.refresh()
                await stretchStore.refresh()
            }
            .refreshable {
                await completionStore.refresh()
                await stretchStore.refresh()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.title2.bold())
                Spacer()
                if planDay?.isDeload == true {
                    Text("DELOAD")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.yellow.opacity(0.3))
                        .clipShape(Capsule())
                }
            }
            if let day = planDay {
                Text(day.label)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.tint)
                Text("Week \(day.week) · Cycle \(day.cycle), week \(day.weekOfCycle) of 4")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if stretchesActive {
                Text("REST DAY")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            if counts.total > 0 {
                HStack {
                    Spacer()
                    Text("\(counts.done)/\(counts.total) done")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(counts.done == counts.total ? .green : .secondary)
                }
                ProgressView(value: Double(counts.done), total: Double(counts.total))
                    .tint(counts.done == counts.total ? .green : .accentColor)
            }
        }
    }

    @ViewBuilder
    private var errorBanners: some View {
        ForEach([completionStore.errorMessage, stretchStore.errorMessage].compactMap { $0 },
                id: \.self) { message in
            Text(message)
                .font(.caption)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .padding(.top, 4)
    }

    private var navigationBar: some View {
        HStack {
            Button {
                withAnimation {
                    selectedDate = Calendar.current.date(
                        byAdding: .day, value: -1, to: selectedDate)!
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 34))
            }

            Spacer()

            Button("Today") {
                withAnimation { selectedDate = Date() }
            }
            .font(.caption.weight(.semibold))

            Spacer()

            Button {
                withAnimation {
                    selectedDate = Calendar.current.date(
                        byAdding: .day, value: 1, to: selectedDate)!
                }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 34))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(.bar)
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

struct StretchRow: View {
    let name: String
    let isDone: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24))
                .foregroundStyle(isDone ? .green : .secondary)
            Text(name)
                .font(.subheadline.weight(.semibold))
                .strikethrough(isDone)
            Spacer()
        }
        .padding(12)
        .background(isDone ? Color.green.opacity(0.12) : Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }
}

#Preview {
    TodayView()
        .environmentObject(CompletionStore())
        .environmentObject(StretchStore())
}
