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

    private let backend: CompletionBackend
    private let sync: SyncEngine
    private let cache: DiskCache
    private let cacheName = "set-completions"

    convenience init() {
        self.init(backend: OfflineBackend(remote: SupabaseBackend(), engine: .shared),
                  sync: .shared, cache: .standard)
    }

    init(backend: CompletionBackend, sync: SyncEngine, cache: DiskCache) {
        self.backend = backend
        self.sync = sync
        self.cache = cache
        completions = Set(cache.load(cacheName) ?? [SetCompletion]())
    }

    /// Server state only replaces local state once nothing local is still
    /// waiting to sync; failures keep the cached copy (offline is normal).
    func refresh() async {
        guard let fetched = try? await backend.fetchCompletions(),
              sync.pendingCount == 0 else { return }
        completions = Set(fetched)
        persist()
    }

    func isDone(dayId: Int, entryIndex: Int) -> Bool {
        completions.contains(SetCompletion(dayId: dayId, entryIndex: entryIndex))
    }

    /// Applies instantly; the write syncs in the background.
    func toggle(dayId: Int, entryIndex: Int) async {
        let completion = SetCompletion(dayId: dayId, entryIndex: entryIndex)
        if completions.contains(completion) {
            completions.remove(completion)
            try? await backend.delete(completion)
        } else {
            completions.insert(completion)
            try? await backend.insert(completion)
        }
        persist()
    }

    private func persist() {
        cache.save(Array(completions), name: cacheName)
    }

    /// Indices of a day's entries that count toward completion — everything
    /// except rows the plan itself skips (deload "Volume work").
    nonisolated static func trackableIndices(for day: PlanDay) -> [Int] {
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
