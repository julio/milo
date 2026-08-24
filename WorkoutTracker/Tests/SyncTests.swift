import XCTest
@testable import WorkoutTracker

/// Records performed writes; can fail a set number of times, transiently or
/// permanently.
final class MockSyncTransport: SyncTransport, @unchecked Sendable {
    private(set) var performed: [PendingWrite] = []
    var failuresRemaining = 0
    var failure: Error = URLError(.notConnectedToInternet)

    func perform(_ write: PendingWrite) async throws {
        await Task.yield()
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw failure
        }
        performed.append(write)
    }
}

func makeCache() -> DiskCache {
    DiskCache(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("milo-tests-\(UUID().uuidString)", isDirectory: true))
}

@MainActor
func makeEngine(transport: MockSyncTransport = MockSyncTransport(),
                cache: DiskCache? = nil,
                autoRetry: Bool = false) -> SyncEngine {
    SyncEngine(transport: transport, cache: cache ?? makeCache(),
               autoRetry: autoRetry, sleep: { _ in })
}

func someWrite(_ path: String = "set_completions") -> PendingWrite {
    PendingWrite(path: path, method: "DELETE", query: "day_id=eq.1",
                 body: nil, prefer: nil)
}

/// enqueue kicks a background flush; give it bounded room to finish so
/// asserts are deterministic whether the queue can drain or not.
@MainActor
func settle(_ engine: SyncEngine) async {
    for _ in 0..<1000 where engine.pendingCount > 0 {
        await Task.yield()
    }
    await engine.flush()
}

// MARK: - DiskCache

final class DiskCacheTests: XCTestCase {
    func testRoundTrip() {
        let cache = makeCache()
        cache.save([SetCompletion(dayId: 1, entryIndex: 2)], name: "things")

        let loaded: [SetCompletion]? = cache.load("things")

        XCTAssertEqual(loaded, [SetCompletion(dayId: 1, entryIndex: 2)])
    }

    func testLoadMissingFileIsNil() {
        let loaded: [SetCompletion]? = makeCache().load("nope")
        XCTAssertNil(loaded)
    }

    func testLoadCorruptFileIsNil() throws {
        let cache = makeCache()
        try FileManager.default.createDirectory(
            at: cache.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(
            to: cache.directory.appendingPathComponent("bad.json"))

        let loaded: [SetCompletion]? = cache.load("bad")

        XCTAssertNil(loaded)
    }

    func testUnencodableValueIsDropped() {
        let cache = makeCache()
        cache.save(Double.infinity, name: "inf")

        let loaded: Double? = cache.load("inf")

        XCTAssertNil(loaded)
    }

    func testUnwritableDirectoryIsSilent() {
        let cache = DiskCache(directory: URL(fileURLWithPath: "/dev/null/nope"))
        cache.save([1, 2], name: "x")

        let loaded: [Int]? = cache.load("x")

        XCTAssertNil(loaded)
    }
}

// MARK: - SyncEngine

@MainActor
final class SyncEngineTests: XCTestCase {
    func testEnqueueFlushesInOrder() async {
        let transport = MockSyncTransport()
        let engine = makeEngine(transport: transport)

        engine.enqueue(someWrite("a"))
        engine.enqueue(someWrite("b"))
        await settle(engine)

        XCTAssertEqual(transport.performed.map(\.path), ["a", "b"])
        XCTAssertEqual(engine.pendingCount, 0)
        XCTAssertNil(engine.syncError)
    }

    func testQueueSurvivesRelaunch() async {
        let cache = makeCache()
        let failing = MockSyncTransport()
        failing.failuresRemaining = .max
        let first = makeEngine(transport: failing, cache: cache)
        first.enqueue(someWrite("queued"))
        await first.flush()
        XCTAssertEqual(first.pendingCount, 1)

        let transport = MockSyncTransport()
        let second = makeEngine(transport: transport, cache: cache)
        XCTAssertEqual(second.pendingCount, 1)
        await second.flush()

        XCTAssertEqual(transport.performed.map(\.path), ["queued"])
        XCTAssertEqual(second.pendingCount, 0)
    }

    func testTransientFailureRetriesWithinFlush() async {
        let transport = MockSyncTransport()
        transport.failuresRemaining = 3
        let engine = makeEngine(transport: transport)

        engine.enqueue(someWrite())
        await settle(engine)

        XCTAssertEqual(engine.pendingCount, 0)
        XCTAssertEqual(transport.performed.count, 1)
    }

    func testTransientFailureGivesUpAndKeepsQueue() async {
        let transport = MockSyncTransport()
        transport.failuresRemaining = .max
        let engine = makeEngine(transport: transport)

        engine.enqueue(someWrite())
        await settle(engine)

        XCTAssertEqual(engine.pendingCount, 1)
        XCTAssertNil(engine.syncError)
    }

    func testAutoRetryEventuallyDrains() async {
        let transport = MockSyncTransport()
        transport.failuresRemaining = 6
        let engine = makeEngine(transport: transport, autoRetry: true)

        engine.enqueue(someWrite())
        await engine.flush()
        while engine.pendingCount > 0 {
            await Task.yield()
        }

        XCTAssertEqual(transport.performed.count, 1)
    }

    func testPermanentFailureDropsWriteAndSurfacesError() async {
        let transport = MockSyncTransport()
        transport.failuresRemaining = 1
        transport.failure = SupabaseError.badStatus(code: 422, body: "bad row")
        let engine = makeEngine(transport: transport)

        engine.enqueue(someWrite("dropped"))
        await settle(engine)

        XCTAssertEqual(engine.pendingCount, 0)
        XCTAssertTrue(transport.performed.isEmpty)
        XCTAssertEqual(engine.syncError, "Supabase returned 422: bad row")

        // The next successful write clears the banner.
        engine.enqueue(someWrite("kept"))
        await settle(engine)

        XCTAssertEqual(transport.performed.map(\.path), ["kept"])
        XCTAssertNil(engine.syncError)
    }

    func testConcurrentFlushRunsOnce() async {
        let transport = MockSyncTransport()
        let engine = makeEngine(transport: transport)
        engine.enqueue(someWrite())

        async let first: Void = engine.flush()
        async let second: Void = engine.flush()
        _ = await (first, second)

        XCTAssertEqual(transport.performed.count, 1)
    }

    func testIsPermanent() {
        XCTAssertTrue(SyncEngine.isPermanent(SupabaseError.badStatus(code: 400, body: "")))
        XCTAssertTrue(SyncEngine.isPermanent(SupabaseError.badStatus(code: 422, body: "")))
        XCTAssertFalse(SyncEngine.isPermanent(SupabaseError.badStatus(code: 408, body: "")))
        XCTAssertFalse(SyncEngine.isPermanent(SupabaseError.badStatus(code: 429, body: "")))
        XCTAssertFalse(SyncEngine.isPermanent(SupabaseError.badStatus(code: 500, body: "")))
        XCTAssertFalse(SyncEngine.isPermanent(URLError(.timedOut)))
    }

    func testSharedEngineExists() {
        XCTAssertNotNil(SyncEngine.shared)
    }

    func testEngineWithDefaultSleepRetriesAndFlushes() async {
        let transport = MockSyncTransport()
        transport.failuresRemaining = 1
        let engine = SyncEngine(transport: transport, cache: makeCache())

        engine.enqueue(someWrite())
        // The real backoff sleeps ~2s before the retry succeeds.
        let deadline = Date().addingTimeInterval(10)
        while transport.performed.isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(transport.performed.count, 1)
        XCTAssertEqual(engine.pendingCount, 0)
    }

    func testDefaultSleepWaits() async {
        let start = Date()
        await SyncEngine.defaultSleep(0.02)
        XCTAssertGreaterThan(Date().timeIntervalSince(start), 0.01)
    }
}

// MARK: - OfflineBackend

@MainActor
final class OfflineBackendTests: XCTestCase {
    var syncTransport: MockSyncTransport!
    var engine: SyncEngine!
    var remoteTransport: MockTransport!
    var backend: OfflineBackend!

    override func setUp() {
        super.setUp()
        syncTransport = MockSyncTransport()
        engine = makeEngine(transport: syncTransport)
        remoteTransport = MockTransport()
        backend = OfflineBackend(
            remote: SupabaseBackend(
                baseURL: URL(string: "https://example.supabase.co")!,
                anonKey: "test-key", transport: remoteTransport),
            engine: engine)
    }

    private func drained() async -> [PendingWrite] {
        await settle(engine)
        return syncTransport.performed
    }

    func testReadsPassThroughToRemote() async throws {
        _ = try await backend.fetchCompletions()
        _ = try await backend.fetchStretchCompletions()
        _ = try await backend.fetchRenames()
        _ = try await backend.fetchLogs()

        XCTAssertEqual(
            remoteTransport.requests.compactMap { $0.url?.path() },
            ["/rest/v1/set_completions", "/rest/v1/stretch_completions",
             "/rest/v1/exercise_renames", "/rest/v1/exercise_logs"])
    }

    func testWritesQueueInsteadOfHittingTheNetwork() async throws {
        try await backend.insert(SetCompletion(dayId: 1, entryIndex: 2))
        try await backend.delete(SetCompletion(dayId: 1, entryIndex: 2))
        try await backend.insert(StretchCompletion(date: "2026-08-23", stretchIndex: 0))
        try await backend.delete(StretchCompletion(date: "2026-08-23", stretchIndex: 0))
        try await backend.upsert(ExerciseRename(original: "Plank", custom: "Board"))
        try await backend.deleteRename(original: "Plank")
        try await backend.upsertLog(ExerciseLog(dayId: 1, entryIndex: 2, weight: 95, reps: 1))
        try await backend.deleteLog(dayId: 1, entryIndex: 2)

        XCTAssertTrue(remoteTransport.requests.isEmpty)
        let writes = await drained()
        XCTAssertEqual(writes.map(\.path),
                       ["set_completions", "set_completions",
                        "stretch_completions", "stretch_completions",
                        "exercise_renames", "exercise_renames",
                        "exercise_logs", "exercise_logs"])
        XCTAssertEqual(writes.map(\.method),
                       ["POST", "DELETE", "POST", "DELETE",
                        "POST", "DELETE", "POST", "DELETE"])
        // Inserts must be replay-safe.
        for write in writes where write.method == "POST" {
            XCTAssertEqual(write.prefer, "resolution=merge-duplicates")
        }
    }

    func testQueuedWritesMatchTheDirectRequests() async throws {
        try await backend.upsertLog(ExerciseLog(dayId: 3, entryIndex: 4, weight: 100, reps: 2))
        let writes = await drained()

        let body = try JSONSerialization.jsonObject(
            with: writes[0].body!) as! [String: Any]
        XCTAssertEqual(body["day_id"] as? Int, 3)
        XCTAssertEqual(body["weight"] as? Double, 100)

        try await backend.deleteRename(original: "a b")
        let deletes = await drained()
        XCTAssertEqual(deletes.last?.query, "original=eq.a%20b")
    }
}
