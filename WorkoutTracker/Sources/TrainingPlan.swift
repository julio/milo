import Foundation

enum Lift: String, Codable, CaseIterable {
    case squat, bench, dead
}

enum WeightSpec: Equatable {
    case none
    case percent(lift: Lift, cycle: Int, pct: Double)
}

struct PlanEntry: Equatable {
    let exercise: String
    let setsReps: String
    let weight: WeightSpec
    let note: String
    let isSkipped: Bool

    /// One checkbox per set. "Set 1 — 5 reps" is a single set → 1 box;
    /// "N x M" is N sets → N boxes ("3 x 10" → 3, "3 x 45 sec" → 3).
    /// Time-only rows ("5 min" treadmill) have none.
    var checkCount: Int? {
        let tokens = setsReps.split(separator: " ").map(String.init)
        if let index = tokens.firstIndex(of: "reps"), index > 0,
           Int(tokens[index - 1]) != nil {
            return 1
        }
        if let index = tokens.firstIndex(of: "x"), index > 0 {
            return Int(tokens[index - 1])
        }
        return nil
    }

    /// Rows with something countable take a weight/checkbox log; time-only
    /// cardio like the treadmill has nothing sensible to log.
    var isLoggable: Bool { checkCount != nil }

    /// Timed holds ("3 x 45 sec" planks) are bodyweight — no weight to log.
    var takesWeight: Bool {
        !setsReps.split(separator: " ").map(String.init).contains("sec")
    }

    /// Reps per set when the row is rep-based ("Set 1 — 5 reps" → 5,
    /// "3 x 10" → 10); time and distance rows have none. Feeds the
    /// estimated-1RM math, which needs the reps behind the weight.
    var repsPerSet: Int? {
        let tokens = setsReps.split(separator: " ").map(String.init)
        if let index = tokens.firstIndex(of: "reps"), index > 0 {
            return Int(tokens[index - 1])
        }
        if let index = tokens.firstIndex(of: "x"), index > 0,
           index + 1 == tokens.count - 1 {
            return Int(tokens[index + 1])
        }
        return nil
    }
}

struct PlanDay: Identifiable, Equatable {
    let id: Int
    let weekday: String
    let month: Int
    let day: Int
    let week: Int
    let cycle: Int
    let weekOfCycle: Int
    let label: String
    let isDeload: Bool
    let entries: [PlanEntry]

    static let planYear = 2026

    var date: Date {
        var components = DateComponents()
        components.year = Self.planYear
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }

    var dateTitle: String {
        "\(weekday), \(date.formatted(.dateTime.month(.wide).day()))"
    }
}

/// The three base numbers from the plan's setup box. Each cycle adds a fixed
/// increment per lift, and every prescribed weight is a percentage of that
/// cycle's training max, rounded to the nearest 5 lb.
struct TrainingMaxes: Equatable {
    var squat: Double
    var bench: Double
    var dead: Double

    static let cycleAdd: [Lift: Double] = [.squat: 10, .bench: 5, .dead: 10]
    static let standard = TrainingMaxes(squat: 135, bench: 155, dead: 225)

    func base(for lift: Lift) -> Double {
        switch lift {
        case .squat: return squat
        case .bench: return bench
        case .dead: return dead
        }
    }

    func weight(lift: Lift, cycle: Int, pct: Double) -> Int {
        let tm = base(for: lift) + Double(cycle - 1) * Self.cycleAdd[lift]!
        return Int((tm * pct / 100 / 5).rounded()) * 5
    }

    /// The prescribed weight for a plan row, when it has one.
    func plannedWeight(for spec: WeightSpec) -> Double? {
        switch spec {
        case .none:
            return nil
        case .percent(let lift, let cycle, let pct):
            return Double(weight(lift: lift, cycle: cycle, pct: pct))
        }
    }

    /// Display string for a plan entry's weight column ("145 lb" or "—").
    func display(for spec: WeightSpec) -> String {
        switch spec {
        case .none:
            return "—"
        case .percent(let lift, let cycle, let pct):
            return "\(weight(lift: lift, cycle: cycle, pct: pct)) lb"
        }
    }
}

enum TrainingPlan {
    static var days: [PlanDay] { TrainingPlanData.days }

    /// Index of the session to show first: today's session if there is one,
    /// otherwise the next upcoming one, otherwise the last (plan finished).
    static func defaultIndex(for date: Date, calendar: Calendar = .current) -> Int {
        let target = calendar.startOfDay(for: date)
        if let index = days.firstIndex(where: { $0.date >= target }) {
            return index
        }
        return days.count - 1
    }

    /// The training session on a calendar date, if that date is one of the
    /// plan's 39 sessions.
    static func day(for date: Date, calendar: Calendar = .current) -> PlanDay? {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard c.year == PlanDay.planYear else { return nil }
        return days.first { $0.month == c.month && $0.day == c.day }
    }
}
