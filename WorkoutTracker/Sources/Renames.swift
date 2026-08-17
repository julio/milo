import Foundation
import Combine

/// A user-chosen display name for an exercise, keyed by the plan's original
/// name so one rename applies to every occurrence.
struct ExerciseRename: Codable, Hashable {
    let original: String
    let custom: String
}

protocol RenameBackend: Sendable {
    func fetchRenames() async throws -> [ExerciseRename]
    func upsert(_ rename: ExerciseRename) async throws
    func deleteRename(original: String) async throws
}

@MainActor
class RenameStore: ObservableObject {
    @Published var renames: [String: String] = [:]
    @Published var errorMessage: String?

    private let backend: RenameBackend

    init(backend: RenameBackend = SupabaseBackend()) {
        self.backend = backend
    }

    func refresh() async {
        await run {
            let fetched = try await backend.fetchRenames()
            renames = Dictionary(uniqueKeysWithValues: fetched.map { ($0.original, $0.custom) })
        }
    }

    func displayName(for original: String) -> String {
        renames[original] ?? original
    }

    /// Saves a custom name. An empty name or the original name clears the
    /// override instead of storing a no-op row.
    func rename(original: String, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        await run {
            if trimmed.isEmpty || trimmed == original {
                try await backend.deleteRename(original: original)
                renames[original] = nil
            } else {
                try await backend.upsert(ExerciseRename(original: original, custom: trimmed))
                renames[original] = trimmed
            }
        }
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
