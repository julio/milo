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

    private let backend: RenameBackend
    private let sync: SyncEngine
    private let cache: DiskCache
    private let cacheName = "renames"

    convenience init() {
        self.init(backend: OfflineBackend(remote: SupabaseBackend(), engine: .shared),
                  sync: .shared, cache: .standard)
    }

    init(backend: RenameBackend, sync: SyncEngine, cache: DiskCache) {
        self.backend = backend
        self.sync = sync
        self.cache = cache
        let cached: [ExerciseRename] = cache.load(cacheName) ?? []
        renames = Dictionary(uniqueKeysWithValues: cached.map { ($0.original, $0.custom) })
    }

    /// Server state only replaces local state once nothing local is still
    /// waiting to sync; failures keep the cached copy (offline is normal).
    func refresh() async {
        guard let fetched = try? await backend.fetchRenames(),
              sync.pendingCount == 0 else { return }
        renames = Dictionary(uniqueKeysWithValues: fetched.map { ($0.original, $0.custom) })
        persist()
    }

    func displayName(for original: String) -> String {
        renames[original] ?? original
    }

    /// Saves a custom name, applying instantly; the write syncs in the
    /// background. An empty name or the original name clears the override
    /// instead of storing a no-op row.
    func rename(original: String, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == original {
            renames[original] = nil
            try? await backend.deleteRename(original: original)
        } else {
            renames[original] = trimmed
            try? await backend.upsert(ExerciseRename(original: original, custom: trimmed))
        }
        persist()
    }

    private func persist() {
        cache.save(renames.map { ExerciseRename(original: $0.key, custom: $0.value) },
                   name: cacheName)
    }
}
