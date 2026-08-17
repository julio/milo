import Foundation
import Combine

@MainActor
class WorkoutStore: ObservableObject {
    @Published var workouts: [Workout] = []

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? WorkoutStore.defaultFileURL
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        load()
    }

    func addWorkout(_ workout: Workout) {
        workouts.append(workout)
        save()
    }

    func deleteWorkout(_ workout: Workout) {
        workouts.removeAll { $0.id == workout.id }
        save()
    }

    func updateWorkout(_ workout: Workout) {
        if let index = workouts.firstIndex(where: { $0.id == workout.id }) {
            workouts[index] = workout
            save()
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

    func clearAllWorkouts() {
        workouts.removeAll()
        save()
    }

    private func save() {
        do {
            let data = try encoder.encode(workouts)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save workouts: \(error)")
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            workouts = try decoder.decode([Workout].self, from: data)
        } catch {
            workouts = []
        }
    }

    static var defaultFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("workouts.json")
    }
}
