import Foundation
import Combine

@MainActor
class WorkoutStore: ObservableObject {
    @Published var workouts: [Workout] = []
    @Published var errorMessage: String?

    private let backend: WorkoutBackend

    init(backend: WorkoutBackend = SupabaseBackend()) {
        self.backend = backend
    }

    func refresh() async {
        await run {
            workouts = try await backend.fetchWorkouts()
        }
    }

    func addWorkout(_ workout: Workout) async {
        await run {
            try await backend.insert(workout)
            workouts.append(workout)
        }
    }

    func deleteWorkout(_ workout: Workout) async {
        await run {
            try await backend.delete(id: workout.id)
            workouts.removeAll { $0.id == workout.id }
        }
    }

    func updateWorkout(_ workout: Workout) async {
        await run {
            try await backend.update(workout)
            if let index = workouts.firstIndex(where: { $0.id == workout.id }) {
                workouts[index] = workout
            }
        }
    }

    func clearAllWorkouts() async {
        await run {
            try await backend.deleteAll()
            workouts.removeAll()
        }
    }

    func workoutsForDate(_ date: Date) -> [Workout] {
        let calendar = Calendar.current
        return workouts.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func dailyStatsForDate(_ date: Date) -> DailyStats {
        let dayWorkouts = workoutsForDate(date)
        let totalDuration = dayWorkouts.reduce(0) { $0 + $1.duration }
        return DailyStats(id: UUID(), date: date, workoutCount: dayWorkouts.count, totalDuration: totalDuration)
    }

    /// Runs a backend operation, clearing or setting the error banner. On
    /// failure the in-memory list is left untouched so nothing vanishes.
    private func run(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
