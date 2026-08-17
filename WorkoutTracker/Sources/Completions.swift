import Foundation
import Combine

/// One completed set: a plan day (0-38) and the entry's position in that day.
struct SetCompletion: Codable, Hashable {
    let dayId: Int
    let entryIndex: Int

    enum CodingKeys: String, CodingKey {
        case dayId = "day_id"
        case entryIndex = "entry_index"
    }
}

protocol CompletionBackend: Sendable {
    func fetchCompletions() async throws -> [SetCompletion]
    func insert(_ completion: SetCompletion) async throws
    func delete(_ completion: SetCompletion) async throws
}

/// How much of a plan day's work is done.
enum DayStatus: Equatable {
    case notInPlan
    case pending
    case partial
    case complete
}

@MainActor
class CompletionStore: ObservableObject {
    @Published var completions: Set<SetCompletion> = []
    @Published var errorMessage: String?

    private let backend: CompletionBackend

    init(backend: CompletionBackend = SupabaseBackend()) {
        self.backend = backend
    }

    func refresh() async {
        await run {
            completions = Set(try await backend.fetchCompletions())
        }
    }

    func isDone(dayId: Int, entryIndex: Int) -> Bool {
        completions.contains(SetCompletion(dayId: dayId, entryIndex: entryIndex))
    }

    func toggle(dayId: Int, entryIndex: Int) async {
        let completion = SetCompletion(dayId: dayId, entryIndex: entryIndex)
        await run {
            if completions.contains(completion) {
                try await backend.delete(completion)
                completions.remove(completion)
            } else {
                try await backend.insert(completion)
                completions.insert(completion)
            }
        }
    }

    /// Indices of a day's entries that count toward completion — everything
    /// except rows the plan itself skips (deload "Volume work").
    static func trackableIndices(for day: PlanDay) -> [Int] {
        day.entries.indices.filter { !day.entries[$0].isSkipped }
    }

    func doneCount(for day: PlanDay) -> Int {
        Self.trackableIndices(for: day)
            .filter { isDone(dayId: day.id, entryIndex: $0) }
            .count
    }

    func status(for day: PlanDay) -> DayStatus {
        let done = doneCount(for: day)
        if done == 0 { return .pending }
        return done == Self.trackableIndices(for: day).count ? .complete : .partial
    }

    /// Status for a calendar cell; rest days are .notInPlan.
    func status(month: Int, day: Int) -> DayStatus {
        guard let planDay = TrainingPlan.days.first(
            where: { $0.month == month && $0.day == day }) else {
            return .notInPlan
        }
        return status(for: planDay)
    }

    private func run(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Month-grid math for the calendar screen, kept out of the view for tests.
enum PlanCalendar {
    struct Month: Identifiable, Equatable {
        let year: Int
        let month: Int
        var id: Int { year * 100 + month }

        func title(calendar: Calendar = .current) -> String {
            let date = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
            return date.formatted(.dateTime.month(.wide).year())
        }
    }

    /// The months the plan spans, in order.
    static func months() -> [Month] {
        var seen: [Month] = []
        for day in TrainingPlan.days {
            let month = Month(year: PlanDay.planYear, month: day.month)
            if seen.last != month {
                seen.append(month)
            }
        }
        return seen
    }

    /// Cells for a month grid: leading nils to align the first day with its
    /// weekday column, then the day numbers.
    static func grid(_ month: Month, calendar: Calendar = .current) -> [Int?] {
        let first = calendar.date(
            from: DateComponents(year: month.year, month: month.month, day: 1))!
        let dayCount = calendar.range(of: .day, in: .month, for: first)!.count
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + (1...dayCount).map { $0 }
    }

    /// Short weekday symbols in the calendar's display order.
    static func weekdayHeaders(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(start + $0) % 7] }
    }
}
