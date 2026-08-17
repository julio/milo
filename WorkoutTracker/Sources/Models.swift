import Foundation

struct Workout: Identifiable, Codable {
    let id: UUID
    let date: Date
    let name: String
    let duration: TimeInterval
    let exercises: [Exercise]

    init(id: UUID = UUID(), date: Date = Date(), name: String, duration: TimeInterval, exercises: [Exercise] = []) {
        self.id = id
        self.date = date
        self.name = name
        self.duration = duration
        self.exercises = exercises
    }
}

struct Exercise: Identifiable, Codable {
    let id: UUID
    let name: String
    let sets: Int
    let reps: Int
    let weight: Double?

    init(id: UUID = UUID(), name: String, sets: Int, reps: Int, weight: Double? = nil) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.weight = weight
    }
}

struct DailyStats: Identifiable {
    let id: UUID
    let date: Date
    let workoutCount: Int
    let totalDuration: TimeInterval

    var durationFormatted: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
