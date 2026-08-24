import Foundation

/// One charted day for an exercise: the best set's estimated 1RM that day.
struct ProgressPoint: Identifiable, Equatable {
    let date: Date
    let week: Int
    let value: Double

    var id: Date { date }
}

/// An exercise's estimated-1RM history plus its week-1 reference line.
struct ExerciseSeries: Identifiable, Equatable {
    /// The plan's original name; display names come from renames.
    let exercise: String
    let points: [ProgressPoint]
    /// Best value from the earliest week with data (normally week 1).
    let baseline: Double

    var id: String { exercise }
    var latest: Double { points.last!.value }
    var delta: Double { latest - baseline }
}

enum ProgressData {
    /// The plan writes follow-up sets of a main lift as "same lift"; walk
    /// back to the named exercise so all sets group under it.
    static func resolvedExercise(day: PlanDay, entryIndex: Int) -> String {
        var index = entryIndex
        while index > 0 && day.entries[index].exercise == "same lift" {
            index -= 1
        }
        return day.entries[index].exercise
    }

    /// "Deadlift — volume" is the same movement as "Deadlift"; volume work
    /// charts with its main lift. Applies to all "<lift> — volume" rows.
    static func canonicalExercise(_ name: String) -> String {
        let suffix = " — volume"
        guard name.hasSuffix(suffix) else { return name }
        return String(name.dropLast(suffix.count))
    }

    /// Epley: what the set works out to as a single all-out rep. This is
    /// the number the charts plot — it folds weight and reps into one
    /// comparable strength measure.
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        weight * (1 + Double(reps) / 30)
    }

    /// One series per exercise with any logged weight on a rep-based row,
    /// ordered by first appearance in the plan. Each day contributes its
    /// best set's estimated 1RM (reps come from the plan's prescription).
    static func series(logs: [LogKey: ExerciseLog]) -> [ExerciseSeries] {
        var order: [String] = []
        var bestByDay: [String: [Int: Double]] = [:]
        for day in TrainingPlan.days {
            for index in day.entries.indices {
                guard let log = logs[LogKey(dayId: day.id, entryIndex: index)],
                      let weight = log.weight,
                      let reps = day.entries[index].repsPerSet else { continue }
                let value = estimatedOneRepMax(weight: weight, reps: reps)
                let name = canonicalExercise(resolvedExercise(day: day, entryIndex: index))
                if bestByDay[name] == nil {
                    order.append(name)
                }
                var days = bestByDay[name] ?? [:]
                days[day.id] = max(days[day.id] ?? -.infinity, value)
                bestByDay[name] = days
            }
        }
        return order.map { name in
            let byDay = bestByDay[name]!
            let points = TrainingPlan.days
                .filter { byDay[$0.id] != nil }
                .map { ProgressPoint(date: $0.date, week: $0.week, value: byDay[$0.id]!) }
            let firstWeek = points.map(\.week).min()!
            let baseline = points.filter { $0.week == firstWeek }.map(\.value).max()!
            return ExerciseSeries(exercise: name, points: points, baseline: baseline)
        }
    }
}
