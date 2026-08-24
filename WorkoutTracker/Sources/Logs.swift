import Foundation
import Combine

/// Actual performance for one plan entry: the weight used and reps done.
/// Keyed by plan day and entry position, same as completions.
struct ExerciseLog: Codable, Hashable {
    let dayId: Int
    let entryIndex: Int
    let weight: Double?
    let reps: Int?

    enum CodingKeys: String, CodingKey {
        case dayId = "day_id"
        case entryIndex = "entry_index"
        case weight, reps
    }

    // Explicit nulls, so an upsert clears a column the user emptied instead
    // of merge-duplicates silently keeping the old value.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dayId, forKey: .dayId)
        try container.encode(entryIndex, forKey: .entryIndex)
        try container.encode(weight, forKey: .weight)
        try container.encode(reps, forKey: .reps)
    }
}

struct LogKey: Hashable {
    let dayId: Int
    let entryIndex: Int
}

protocol LogBackend: Sendable {
    func fetchLogs() async throws -> [ExerciseLog]
    func upsertLog(_ log: ExerciseLog) async throws
    func deleteLog(dayId: Int, entryIndex: Int) async throws
}

@MainActor
class LogStore: ObservableObject {
    @Published var logs: [LogKey: ExerciseLog] = [:]

    private let backend: LogBackend
    private let sync: SyncEngine
    private let cache: DiskCache
    private let cacheName = "exercise-logs"

    convenience init() {
        self.init(backend: OfflineBackend(remote: SupabaseBackend(), engine: .shared),
                  sync: .shared, cache: .standard)
    }

    init(backend: LogBackend, sync: SyncEngine, cache: DiskCache) {
        self.backend = backend
        self.sync = sync
        self.cache = cache
        let cached: [ExerciseLog] = cache.load(cacheName) ?? []
        logs = Dictionary(uniqueKeysWithValues: cached.map {
            (LogKey(dayId: $0.dayId, entryIndex: $0.entryIndex), $0)
        })
    }

    /// Server state only replaces local state once nothing local is still
    /// waiting to sync; failures keep the cached copy (offline is normal).
    func refresh() async {
        guard let fetched = try? await backend.fetchLogs(),
              sync.pendingCount == 0 else { return }
        logs = Dictionary(uniqueKeysWithValues: fetched.map {
            (LogKey(dayId: $0.dayId, entryIndex: $0.entryIndex), $0)
        })
        persist()
    }

    func log(dayId: Int, entryIndex: Int) -> ExerciseLog? {
        logs[LogKey(dayId: dayId, entryIndex: entryIndex)]
    }

    /// Saves what was actually lifted, applying instantly; the write syncs
    /// in the background. Clearing both fields deletes the row; an
    /// unchanged value is not re-sent.
    func save(dayId: Int, entryIndex: Int, weight: Double?, reps: Int?) async {
        let key = LogKey(dayId: dayId, entryIndex: entryIndex)
        if weight == nil && reps == nil {
            guard logs[key] != nil else { return }
            logs[key] = nil
            try? await backend.deleteLog(dayId: dayId, entryIndex: entryIndex)
        } else {
            let log = ExerciseLog(
                dayId: dayId, entryIndex: entryIndex, weight: weight, reps: reps)
            guard logs[key] != log else { return }
            logs[key] = log
            try? await backend.upsertLog(log)
        }
        persist()
    }

    private func persist() {
        cache.save(Array(logs.values), name: cacheName)
    }

    /// A single-set row logs through its done toggle: done writes the weight
    /// (kept if already customized) with the set counted; undone clears it.
    func setDone(_ done: Bool, dayId: Int, entryIndex: Int, plannedWeight: Double?) async {
        if done {
            let weight = log(dayId: dayId, entryIndex: entryIndex)?.weight ?? plannedWeight
            await save(dayId: dayId, entryIndex: entryIndex, weight: weight, reps: 1)
        } else {
            await save(dayId: dayId, entryIndex: entryIndex, weight: nil, reps: nil)
        }
    }

    // Lenient parsing/formatting for the tiny inline fields.

    static func parseWeight(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces))
    }

    /// "135", not "135.0", for whole numbers.
    static func weightText(_ weight: Double?) -> String {
        guard let weight else { return "" }
        return weight == weight.rounded() ? String(Int(weight)) : String(weight)
    }

}
