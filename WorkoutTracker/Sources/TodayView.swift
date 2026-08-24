import SwiftUI

/// One screen per calendar day: the training session (if any) followed by
/// the daily stretch routine, with a single combined progress bar.
struct TodayView: View {
    @EnvironmentObject var completionStore: CompletionStore
    @EnvironmentObject var stretchStore: StretchStore
    @EnvironmentObject var renameStore: RenameStore
    @EnvironmentObject var logStore: LogStore
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
                                let liftName = ProgressData.canonicalExercise(
                                    ProgressData.resolvedExercise(day: day, entryIndex: index))
                                PlanEntryRow(
                                    entry: entry,
                                    displayName: renameStore.displayName(for: liftName),
                                    maxes: maxes,
                                    isDone: completionStore.isDone(dayId: day.id, entryIndex: index),
                                    onToggle: {
                                        Task {
                                            await completionStore.toggle(dayId: day.id, entryIndex: index)
                                        }
                                    },
                                    onRename: { newName in
                                        Task {
                                            await renameStore.rename(original: liftName, to: newName)
                                        }
                                    },
                                    log: logStore.log(dayId: day.id, entryIndex: index),
                                    onLog: { weight, reps in
                                        Task {
                                            await logStore.save(
                                                dayId: day.id, entryIndex: index,
                                                weight: weight, reps: reps)
                                        }
                                    })
                            }
                        }
                    }

                    if stretchesActive {
                        sectionTitle("Stretches", systemImage: "figure.cooldown")
                        VStack(spacing: 10) {
                            ForEach(StretchPlan.stretches.indices, id: \.self) { index in
                                StretchRow(
                                    name: renameStore.displayName(for: StretchPlan.stretches[index]),
                                    isDone: stretchStore.isDone(dateKey: dateKey, index: index),
                                    onToggle: {
                                        Task {
                                            await stretchStore.toggle(dateKey: dateKey, index: index)
                                        }
                                    },
                                    onRename: { newName in
                                        Task {
                                            await renameStore.rename(
                                                original: StretchPlan.stretches[index], to: newName)
                                        }
                                    })
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
            .scrollDismissesKeyboard(.immediately)
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                navigationBar
            }
            .task {
                await completionStore.refresh()
                await stretchStore.refresh()
                await renameStore.refresh()
                await logStore.refresh()
            }
            .refreshable {
                await completionStore.refresh()
                await stretchStore.refresh()
                await renameStore.refresh()
                await logStore.refresh()
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil)
                    }
                }
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
        ForEach([completionStore.errorMessage, stretchStore.errorMessage,
                 renameStore.errorMessage, logStore.errorMessage].compactMap { $0 },
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

/// The exercise name: a Text normally, an inline TextField after a
/// long-press. Submit saves the rename; losing focus cancels.
struct EditableName: View {
    let name: String
    let font: Font
    let onRename: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        if isEditing {
            TextField("Exercise name", text: $draft)
                .font(font)
                .focused($focused)
                .onSubmit {
                    focused = false
                    isEditing = false
                    onRename(draft)
                }
                .onChange(of: focused) { _, nowFocused in
                    if !nowFocused { isEditing = false }
                }
        } else {
            Text(name)
                .font(font)
                .onLongPressGesture {
                    draft = name
                    isEditing = true
                    focused = true
                }
        }
    }
}

struct PlanEntryRow: View {
    let entry: PlanEntry
    let displayName: String
    let maxes: TrainingMaxes
    let isDone: Bool
    let onToggle: () -> Void
    let onRename: (String) -> Void
    let log: ExerciseLog?
    let onLog: (Double?, Int?) -> Void

    var body: some View {
        HStack(spacing: 12) {
            if !entry.isSkipped {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isDone ? .green : .secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    EditableName(
                        name: displayName,
                        font: .subheadline.weight(entry.exercise == "same lift" ? .regular : .semibold),
                        onRename: onRename)
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
                if !entry.isSkipped && entry.isLoggable {
                    LogFields(
                        log: log,
                        plannedWeight: maxes.plannedWeight(for: entry.weight),
                        plannedReps: entry.plannedReps,
                        repCountable: entry.isRepCountable,
                        onLog: onLog)
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

/// Inline capture of what was actually lifted. The weight field starts
/// prefilled with the plan's prescription and commits when focus leaves it.
/// Rep-counting rows show one checkbox per prescribed rep; time/distance
/// rows keep a quantity field instead.
struct LogFields: View {
    let log: ExerciseLog?
    let plannedWeight: Double?
    let plannedReps: Int?
    let repCountable: Bool
    let onLog: (Double?, Int?) -> Void

    @State private var weightText = ""
    @State private var repsText = ""
    @FocusState private var focusedField: Field?

    enum Field { case weight, reps }

    private var repsDone: Int { log?.reps ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                TextField("lb", text: $weightText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .weight)
                    .frame(width: 56)
                if !repCountable {
                    TextField("reps", text: $repsText)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .reps)
                        .frame(width: 48)
                }
                Spacer()
            }
            if repCountable, let plannedReps {
                RepChecks(
                    total: plannedReps,
                    done: min(repsDone, plannedReps),
                    onChange: { count in
                        onLog(LogStore.parseWeight(weightText),
                              count == 0 ? nil : count)
                    })
            }
        }
        .font(.caption)
        .textFieldStyle(.roundedBorder)
        .onAppear(perform: load)
        .onChange(of: log) { _, _ in load() }
        .onChange(of: focusedField) { _, nowFocused in
            if nowFocused == nil { commit() }
        }
        // Swallow taps between the fields so they don't toggle the row done.
        .onTapGesture {}
    }

    private func load() {
        if let log {
            weightText = LogStore.weightText(log.weight)
            repsText = LogStore.repsText(log.reps)
        } else {
            weightText = LogStore.weightText(plannedWeight)
            repsText = repCountable ? "" : LogStore.repsText(plannedReps)
        }
    }

    private func commit() {
        let reps = repCountable
            ? (repsDone == 0 ? nil : repsDone)
            : LogStore.parseReps(repsText)
        onLog(LogStore.parseWeight(weightText), reps)
    }
}

/// One checkbox per prescribed rep, filled left to right. Tapping a box
/// counts up to it; tapping the last checked box takes that rep back.
struct RepChecks: View {
    let total: Int
    let done: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Image(systemName: index < done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(index < done ? .green : .secondary)
                    .onTapGesture {
                        onChange(index + 1 == done ? index : index + 1)
                    }
            }
            Spacer()
        }
    }
}

struct StretchRow: View {
    let name: String
    let isDone: Bool
    let onToggle: () -> Void
    let onRename: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24))
                .foregroundStyle(isDone ? .green : .secondary)
            EditableName(name: name, font: .subheadline.weight(.semibold),
                         onRename: onRename)
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
        .environmentObject(RenameStore())
        .environmentObject(LogStore())
}
