import Foundation
import Combine

/// One write waiting to reach Supabase, replayable verbatim after a crash
/// or offline stretch. Every write is idempotent (upserts merge duplicates,
/// deletes of absent rows are no-ops), so replays are safe.
struct PendingWrite: Codable, Equatable {
    let path: String
    let method: String
    let query: String?
    let body: Data?
    let prefer: String?
}

/// Executes queued writes: SupabaseBackend in the app, a mock in tests.
protocol SyncTransport: Sendable {
    func perform(_ write: PendingWrite) async throws
}

/// Tiny JSON-file persistence for store state and the pending queue, so the
/// app is fully usable offline and across launches.
struct DiskCache: Sendable {
    let directory: URL

    static let standard = DiskCache(
        directory: FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MiloCache", isDirectory: true))

    func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, name: String) {
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }

    private func url(_ name: String) -> URL {
        directory.appendingPathComponent(name + ".json")
    }
}

/// Queues writes locally and pushes them to Supabase in the background, so
/// the UI never waits on the network. Transient failures back off and
/// retry; permanent (4xx) failures drop the write and surface the error.
@MainActor
final class SyncEngine: ObservableObject {
    @Published private(set) var pendingCount = 0
    @Published private(set) var syncError: String?

    static let shared = SyncEngine(
        transport: SupabaseBackend(), cache: .standard, autoRetry: true)

    private var queue: [PendingWrite] {
        didSet {
            pendingCount = queue.count
            cache.save(queue, name: "pending-writes")
        }
    }
    private let transport: SyncTransport
    private let cache: DiskCache
    private let autoRetry: Bool
    private let sleep: (TimeInterval) async -> Void
    private var flushing = false

    static func defaultSleep(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    init(transport: SyncTransport, cache: DiskCache, autoRetry: Bool = false,
         sleep: @escaping (TimeInterval) async -> Void = SyncEngine.defaultSleep) {
        self.transport = transport
        self.cache = cache
        self.autoRetry = autoRetry
        self.sleep = sleep
        let stored: [PendingWrite]? = cache.load("pending-writes")
        queue = stored ?? []
        pendingCount = queue.count
    }

    func enqueue(_ write: PendingWrite) {
        queue.append(write)
        Task { await flush() }
    }

    /// Pushes queued writes in order. Gives up after a few transient
    /// failures (autoRetry re-kicks later); the queue survives either way.
    func flush() async {
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }
        var attempts = 0
        while let next = queue.first {
            do {
                try await transport.perform(next)
                queue.removeFirst()
                syncError = nil
                attempts = 0
            } catch {
                if Self.isPermanent(error) {
                    queue.removeFirst()
                    syncError = error.localizedDescription
                    attempts = 0
                } else {
                    attempts += 1
                    guard attempts < 5 else {
                        if autoRetry {
                            Task { [weak self] in
                                await self?.sleep(30)
                                await self?.flush()
                            }
                        }
                        return
                    }
                    await sleep(TimeInterval(1 << attempts))
                }
            }
        }
    }

    /// A 4xx (bar timeouts and rate limits) will never succeed on retry.
    static func isPermanent(_ error: Error) -> Bool {
        guard case SupabaseError.badStatus(let code, _) = error else { return false }
        return (400..<500).contains(code) && code != 408 && code != 429
    }
}

extension SupabaseBackend: SyncTransport {}

/// The app's backend: reads pass through to Supabase; writes apply
/// instantly via the local queue and sync in the background.
struct OfflineBackend {
    let remote: SupabaseBackend
    let engine: SyncEngine

    @MainActor
    private func enqueue(_ write: PendingWrite) {
        engine.enqueue(write)
    }
}

extension OfflineBackend: CompletionBackend {
    func fetchCompletions() async throws -> [SetCompletion] {
        try await remote.fetchCompletions()
    }

    func insert(_ completion: SetCompletion) async throws {
        await enqueue(try SupabaseBackend.write(inserting: completion))
    }

    func delete(_ completion: SetCompletion) async throws {
        await enqueue(SupabaseBackend.write(deleting: completion))
    }
}

extension OfflineBackend: StretchBackend {
    func fetchStretchCompletions() async throws -> [StretchCompletion] {
        try await remote.fetchStretchCompletions()
    }

    func insert(_ completion: StretchCompletion) async throws {
        await enqueue(try SupabaseBackend.write(inserting: completion))
    }

    func delete(_ completion: StretchCompletion) async throws {
        await enqueue(SupabaseBackend.write(deleting: completion))
    }
}

extension OfflineBackend: RenameBackend {
    func fetchRenames() async throws -> [ExerciseRename] {
        try await remote.fetchRenames()
    }

    func upsert(_ rename: ExerciseRename) async throws {
        await enqueue(try SupabaseBackend.write(upserting: rename))
    }

    func deleteRename(original: String) async throws {
        await enqueue(SupabaseBackend.write(deletingRename: original))
    }
}

extension OfflineBackend: LogBackend {
    func fetchLogs() async throws -> [ExerciseLog] {
        try await remote.fetchLogs()
    }

    func upsertLog(_ log: ExerciseLog) async throws {
        await enqueue(try SupabaseBackend.write(upserting: log))
    }

    func deleteLog(dayId: Int, entryIndex: Int) async throws {
        await enqueue(SupabaseBackend.write(deletingLogDayId: dayId, entryIndex: entryIndex))
    }
}
