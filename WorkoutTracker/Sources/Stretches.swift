import Foundation
import Combine

/// The physical-therapist stretch routine: same six stretches every day,
/// rest days included, starting 16 August 2026.
enum StretchPlan {
    static let stretches = [
        "90/90 Hip Lift L Hip Pullback R Foot Lift Off",
        "Quad Stretch in Half Kneeling",
        "Plank on Gym Ball",
        "Bridges (Marches)",
        "Doorway Squats",
        "Lunge Glute Strategy Isometric Hold",
    ]

    static let startYear = 2026
    static let startMonth = 8
    static let startDay = 16

    static func isActive(year: Int, month: Int, day: Int) -> Bool {
        (year, month, day) >= (startYear, startMonth, startDay)
    }

    static func isActive(on date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return isActive(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Key used in the database's date column: "2026-08-16".
    static func dateKey(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return dateKey(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Dropped from the routine entirely. Kept in the list (not deleted)
    /// so historical completion indices stay stable.
    static let retired = ["90/90 Hip Lift L Hip Pullback R Foot Lift Off"]

    /// Skipped on strength-training days — the session already covers them.
    static let trainingDaySkips = ["Plank on Gym Ball", "Doorway Squats"]

    /// The stretches to do on a date: the routine minus retired ones, and
    /// minus the training-day skips on workout days. Original indices, so
    /// completion keys stay stable.
    static func activeIndices(year: Int, month: Int, day: Int) -> [Int] {
        let isTrainingDay = year == PlanDay.planYear && TrainingPlan.days.contains {
            $0.month == month && $0.day == day
        }
        return stretches.indices.filter {
            !retired.contains(stretches[$0])
                && !(isTrainingDay && trainingDaySkips.contains(stretches[$0]))
        }
    }

    static func activeIndices(on date: Date, calendar: Calendar = .current) -> [Int] {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return activeIndices(year: c.year!, month: c.month!, day: c.day!)
    }
}

struct StretchCompletion: Codable, Hashable {
    let date: String
    let stretchIndex: Int

    enum CodingKeys: String, CodingKey {
        case date
        case stretchIndex = "stretch_index"
    }
}

protocol StretchBackend: Sendable {
    func fetchStretchCompletions() async throws -> [StretchCompletion]
    func insert(_ completion: StretchCompletion) async throws
    func delete(_ completion: StretchCompletion) async throws
}

@MainActor
class StretchStore: ObservableObject {
    @Published var completions: Set<StretchCompletion> = []

    private let backend: StretchBackend
    private let sync: SyncEngine
    private let cache: DiskCache
    private let cacheName = "stretch-completions"

    convenience init() {
        self.init(backend: OfflineBackend(remote: SupabaseBackend(), engine: .shared),
                  sync: .shared, cache: .standard)
    }

    init(backend: StretchBackend, sync: SyncEngine, cache: DiskCache) {
        self.backend = backend
        self.sync = sync
        self.cache = cache
        completions = Set(cache.load(cacheName) ?? [StretchCompletion]())
    }

    /// Server state only replaces local state once nothing local is still
    /// waiting to sync; failures keep the cached copy (offline is normal).
    func refresh() async {
        guard let fetched = try? await backend.fetchStretchCompletions(),
              sync.pendingCount == 0 else { return }
        completions = Set(fetched)
        persist()
    }

    func isDone(dateKey: String, index: Int) -> Bool {
        completions.contains(StretchCompletion(date: dateKey, stretchIndex: index))
    }

    /// Applies instantly; the write syncs in the background.
    func toggle(dateKey: String, index: Int) async {
        let completion = StretchCompletion(date: dateKey, stretchIndex: index)
        if completions.contains(completion) {
            completions.remove(completion)
            try? await backend.delete(completion)
        } else {
            completions.insert(completion)
            try? await backend.insert(completion)
        }
        persist()
    }

    func doneCount(dateKey: String) -> Int {
        StretchPlan.stretches.indices
            .filter { isDone(dateKey: dateKey, index: $0) }
            .count
    }

    private func persist() {
        cache.save(Array(completions), name: cacheName)
    }
}

/// Combines training sets and stretches into one status per calendar day,
/// so the calendar answers "did I do everything that day?".
enum DayProgress {
    /// Everything trackable on a calendar day (training sets + stretches)
    /// and how much of it is done.
    static func counts(year: Int = PlanDay.planYear, month: Int, day: Int,
                       trainingCompletions: Set<SetCompletion>,
                       stretchCompletions: Set<StretchCompletion>) -> (done: Int, total: Int) {
        var total = 0
        var done = 0

        if year == PlanDay.planYear,
           let planDay = TrainingPlan.days.first(
               where: { $0.month == month && $0.day == day }) {
            let trackable = CompletionStore.trackableIndices(for: planDay)
            total += trackable.count
            done += trackable.filter {
                trainingCompletions.contains(
                    SetCompletion(dayId: planDay.id, entryIndex: $0))
            }.count
        }

        if StretchPlan.isActive(year: year, month: month, day: day) {
            let key = StretchPlan.dateKey(year: year, month: month, day: day)
            let indices = StretchPlan.activeIndices(year: year, month: month, day: day)
            total += indices.count
            done += indices.filter {
                stretchCompletions.contains(
                    StretchCompletion(date: key, stretchIndex: $0))
            }.count
        }

        return (done, total)
    }

    static func combinedStatus(year: Int = PlanDay.planYear, month: Int, day: Int,
                               trainingCompletions: Set<SetCompletion>,
                               stretchCompletions: Set<StretchCompletion>) -> DayStatus {
        let (done, total) = counts(
            year: year, month: month, day: day,
            trainingCompletions: trainingCompletions,
            stretchCompletions: stretchCompletions)

        if total == 0 { return .notInPlan }
        if done == 0 { return .pending }
        return done == total ? .complete : .partial
    }
}
