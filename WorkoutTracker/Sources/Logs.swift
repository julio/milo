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
    @Published var errorMessage: String?

    private let backend: LogBackend

    init(backend: LogBackend = SupabaseBackend()) {
        self.backend = backend
    }

    func refresh() async {
        await run {
            let fetched = try await backend.fetchLogs()
            logs = Dictionary(uniqueKeysWithValues: fetched.map {
                (LogKey(dayId: $0.dayId, entryIndex: $0.entryIndex), $0)
            })
        }
    }

    func log(dayId: Int, entryIndex: Int) -> ExerciseLog? {
        logs[LogKey(dayId: dayId, entryIndex: entryIndex)]
    }

    /// Saves what was actually lifted. Clearing both fields deletes the row;
    /// an unchanged value is not re-sent.
    func save(dayId: Int, entryIndex: Int, weight: Double?, reps: Int?) async {
        let key = LogKey(dayId: dayId, entryIndex: entryIndex)
        await run {
            if weight == nil && reps == nil {
                guard logs[key] != nil else { return }
                try await backend.deleteLog(dayId: dayId, entryIndex: entryIndex)
                logs[key] = nil
            } else {
                let log = ExerciseLog(
                    dayId: dayId, entryIndex: entryIndex, weight: weight, reps: reps)
                guard logs[key] != log else { return }
                try await backend.upsertLog(log)
                logs[key] = log
            }
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

    private func run(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
