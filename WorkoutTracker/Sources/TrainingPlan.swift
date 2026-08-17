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
    static let standard = TrainingMaxes(squat: 225, bench: 155, dead: 275)

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
