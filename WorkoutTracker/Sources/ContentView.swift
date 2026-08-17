import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: WorkoutStore
    @State private var selectedDate = Date()
    @State private var showingNewWorkout = false

    var dailyStats: DailyStats {
        store.dailyStatsForDate(selectedDate)
    }

    var todayWorkouts: [Workout] {
        store.workoutsForDate(selectedDate)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .padding()
                .background(Color(.systemGray6))

                ScrollView {
                    VStack(spacing: 16) {
                        StatsCard(stats: dailyStats)

                        if todayWorkouts.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "dumbbell.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                Text("No workouts yet")
                                    .font(.headline)
                                Text("Tap the + button to add one")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(todayWorkouts) { workout in
                                    WorkoutRow(workout: workout)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }

                Spacer()
            }
            .navigationTitle("Workouts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingNewWorkout = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                    }
                }
            }
            .sheet(isPresented: $showingNewWorkout) {
                NewWorkoutSheet(isPresented: $showingNewWorkout)
                    .environmentObject(store)
            }
        }
    }
}

struct StatsCard: View {
    let stats: DailyStats

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workouts")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("\(stats.workoutCount)")
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total Duration")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(stats.durationFormatted)
                        .font(.title2)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct WorkoutRow: View {
    let workout: Workout
    @EnvironmentObject var store: WorkoutStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.name)
                        .font(.headline)
                    Text("\(workout.exercises.count) exercises")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatDuration(workout.duration))
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(workout.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }

            if !workout.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(workout.exercises.prefix(2)) { exercise in
                        Text("• \(exercise.name) - \(exercise.sets)×\(exercise.reps)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    if workout.exercises.count > 2 {
                        Text("• +\(workout.exercises.count - 2) more")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .contextMenu {
            Button(role: .destructive) {
                store.deleteWorkout(workout)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

struct NewWorkoutSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var store: WorkoutStore
    @State private var workoutName = ""
    @State private var duration: TimeInterval = 3600

    var body: some View {
        NavigationStack {
            Form {
                TextField("Workout Name", text: $workoutName)

                Section("Duration") {
                    Stepper(
                        "Duration: \(formatDuration(duration))",
                        value: $duration,
                        in: 60...(8 * 3600),
                        step: 300
                    )
                }
            }
            .navigationTitle("New Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let workout = Workout(name: workoutName, duration: duration)
                        store.addWorkout(workout)
                        isPresented = false
                    }
                    .disabled(workoutName.isEmpty)
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

#Preview {
    ContentView()
        .environmentObject(WorkoutStore())
}
