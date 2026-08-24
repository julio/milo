import XCTest
@testable import WorkoutTracker

final class MockLogBackend: LogBackend, @unchecked Sendable {
    var stored: [ExerciseLog] = []
    var failNext: Error?
    private(set) var upserts: [ExerciseLog] = []
    private(set) var deletes: [(dayId: Int, entryIndex: Int)] = []

    private func failIfAsked() throws {
        if let error = failNext {
            failNext = nil
            throw error
        }
    }

    func fetchLogs() async throws -> [ExerciseLog] {
        try failIfAsked()
        return stored
    }

    func upsertLog(_ log: ExerciseLog) async throws {
        try failIfAsked()
        upserts.append(log)
    }

    func deleteLog(dayId: Int, entryIndex: Int) async throws {
        try failIfAsked()
        deletes.append((dayId, entryIndex))
    }
}

@MainActor
final class LogStoreTests: XCTestCase {
    var backend: MockLogBackend!
    var store: LogStore!

    override func setUp() {
        super.setUp()
        backend = MockLogBackend()
        store = LogStore(backend: backend)
    }

    func testDefaultInitUsesSupabase() {
        XCTAssertNotNil(LogStore())
    }

    func testRefreshKeysLogsByDayAndEntry() async {
        backend.stored = [
            ExerciseLog(dayId: 0, entryIndex: 1, weight: 90, reps: 5),
            ExerciseLog(dayId: 3, entryIndex: 2, weight: nil, reps: 12),
        ]

        await store.refresh()

        XCTAssertEqual(store.logs.count, 2)
        XCTAssertEqual(store.log(dayId: 0, entryIndex: 1)?.weight, 90)
        XCTAssertEqual(store.log(dayId: 3, entryIndex: 2)?.reps, 12)
        XCTAssertNil(store.log(dayId: 9, entryIndex: 9))
        XCTAssertNil(store.errorMessage)
    }

    func testRefreshFailureSetsError() async {
        backend.failNext = TestError()

        await store.refresh()

        XCTAssertEqual(store.errorMessage, "backend exploded")
        XCTAssertTrue(store.logs.isEmpty)
    }

    func testSaveUpserts() async {
        await store.save(dayId: 0, entryIndex: 1, weight: 95, reps: 5)

        XCTAssertEqual(backend.upserts,
                       [ExerciseLog(dayId: 0, entryIndex: 1, weight: 95, reps: 5)])
        XCTAssertEqual(store.log(dayId: 0, entryIndex: 1)?.weight, 95)
        XCTAssertNil(store.errorMessage)
    }

    func testSaveRepsOnlyUpserts() async {
        await store.save(dayId: 0, entryIndex: 7, weight: nil, reps: 45)

        XCTAssertEqual(store.log(dayId: 0, entryIndex: 7),
                       ExerciseLog(dayId: 0, entryIndex: 7, weight: nil, reps: 45))
    }

    func testSaveUnchangedValueSendsNothing() async {
        await store.save(dayId: 0, entryIndex: 1, weight: 95, reps: 5)
        await store.save(dayId: 0, entryIndex: 1, weight: 95, reps: 5)

        XCTAssertEqual(backend.upserts.count, 1)
    }

    func testSaveBothNilDeletesExisting() async {
        await store.save(dayId: 0, entryIndex: 1, weight: 95, reps: 5)

        await store.save(dayId: 0, entryIndex: 1, weight: nil, reps: nil)

        XCTAssertEqual(backend.deletes.count, 1)
        XCTAssertEqual(backend.deletes[0].dayId, 0)
        XCTAssertEqual(backend.deletes[0].entryIndex, 1)
        XCTAssertNil(store.log(dayId: 0, entryIndex: 1))
    }

    func testSaveBothNilWithNoExistingLogSendsNothing() async {
        await store.save(dayId: 0, entryIndex: 1, weight: nil, reps: nil)

        XCTAssertTrue(backend.deletes.isEmpty)
        XCTAssertTrue(backend.upserts.isEmpty)
    }

    func testSaveFailureKeepsStateAndSetsError() async {
        backend.failNext = TestError()

        await store.save(dayId: 0, entryIndex: 1, weight: 95, reps: 5)

        XCTAssertEqual(store.errorMessage, "backend exploded")
        XCTAssertNil(store.log(dayId: 0, entryIndex: 1))
    }

    func testDeleteFailureKeepsStateAndSetsError() async {
        await store.save(dayId: 0, entryIndex: 1, weight: 95, reps: 5)
        backend.failNext = TestError()

        await store.save(dayId: 0, entryIndex: 1, weight: nil, reps: nil)

        XCTAssertEqual(store.errorMessage, "backend exploded")
        XCTAssertNotNil(store.log(dayId: 0, entryIndex: 1))
    }

    // MARK: - Single-set rows log through the done toggle

    func testSetDoneLogsPlannedWeightAndOneSet() async {
        await store.setDone(true, dayId: 0, entryIndex: 1, plannedWeight: 90)

        XCTAssertEqual(store.log(dayId: 0, entryIndex: 1),
                       ExerciseLog(dayId: 0, entryIndex: 1, weight: 90, reps: 1))
    }

    func testSetDoneKeepsCustomizedWeight() async {
        await store.save(dayId: 0, entryIndex: 1, weight: 95, reps: nil)

        await store.setDone(true, dayId: 0, entryIndex: 1, plannedWeight: 90)

        XCTAssertEqual(store.log(dayId: 0, entryIndex: 1)?.weight, 95)
        XCTAssertEqual(store.log(dayId: 0, entryIndex: 1)?.reps, 1)
    }

    func testSetDoneWithoutWeightStillCountsTheSet() async {
        await store.setDone(true, dayId: 0, entryIndex: 7, plannedWeight: nil)

        XCTAssertEqual(store.log(dayId: 0, entryIndex: 7),
                       ExerciseLog(dayId: 0, entryIndex: 7, weight: nil, reps: 1))
    }

    func testSetUndoneClearsTheLog() async {
        await store.setDone(true, dayId: 0, entryIndex: 1, plannedWeight: 90)

        await store.setDone(false, dayId: 0, entryIndex: 1, plannedWeight: 90)

        XCTAssertNil(store.log(dayId: 0, entryIndex: 1))
        XCTAssertEqual(backend.deletes.count, 1)
    }

    // MARK: - Parsing and formatting

    func testParseWeight() {
        XCTAssertEqual(LogStore.parseWeight("135"), 135)
        XCTAssertEqual(LogStore.parseWeight(" 132.5 "), 132.5)
        XCTAssertNil(LogStore.parseWeight(""))
        XCTAssertNil(LogStore.parseWeight("heavy"))
    }

    func testWeightText() {
        XCTAssertEqual(LogStore.weightText(nil), "")
        XCTAssertEqual(LogStore.weightText(135), "135")
        XCTAssertEqual(LogStore.weightText(132.5), "132.5")
    }

}

// MARK: - Codable shape

final class ExerciseLogCodableTests: XCTestCase {
    func testDecodesSnakeCaseRowWithNulls() throws {
        let json = Data("""
        [{"day_id":2,"entry_index":4,"weight":null,"reps":10}]
        """.utf8)

        let logs = try JSONDecoder().decode([ExerciseLog].self, from: json)

        XCTAssertEqual(logs, [ExerciseLog(dayId: 2, entryIndex: 4, weight: nil, reps: 10)])
    }

    func testEncodesExplicitNullsSoUpsertClearsColumns() throws {
        let data = try JSONEncoder().encode(
            ExerciseLog(dayId: 2, entryIndex: 4, weight: 145, reps: nil))
        let object = try JSONSerialization.jsonObject(
            with: data, options: []) as! [String: Any]

        XCTAssertEqual(object["day_id"] as? Int, 2)
        XCTAssertEqual(object["entry_index"] as? Int, 4)
        XCTAssertEqual(object["weight"] as? Double, 145)
        XCTAssertTrue(object["reps"] is NSNull)
    }
}

// MARK: - Supabase request building

final class LogBackendRequestTests: XCTestCase {
    var transport: MockTransport!
    var backend: SupabaseBackend!

    override func setUp() {
        super.setUp()
        transport = MockTransport()
        backend = SupabaseBackend(
            baseURL: URL(string: "https://example.supabase.co")!,
            anonKey: "test-key", transport: transport)
    }

    var lastRequest: URLRequest { transport.requests.last! }

    func testFetchLogsRequest() async throws {
        _ = try await backend.fetchLogs()

        XCTAssertEqual(lastRequest.httpMethod, "GET")
        XCTAssertEqual(lastRequest.url?.absoluteString,
                       "https://example.supabase.co/rest/v1/exercise_logs?select=day_id,entry_index,weight,reps")
    }

    func testUpsertLogRequest() async throws {
        try await backend.upsertLog(ExerciseLog(dayId: 1, entryIndex: 3, weight: 100, reps: 5))

        XCTAssertEqual(lastRequest.httpMethod, "POST")
        XCTAssertEqual(lastRequest.url?.absoluteString,
                       "https://example.supabase.co/rest/v1/exercise_logs")
        XCTAssertEqual(lastRequest.value(forHTTPHeaderField: "Prefer"),
                       "resolution=merge-duplicates")
        let body = try JSONSerialization.jsonObject(
            with: lastRequest.httpBody!) as! [String: Any]
        XCTAssertEqual(body["day_id"] as? Int, 1)
        XCTAssertEqual(body["weight"] as? Double, 100)
    }

    func testDeleteLogRequestFiltersByKey() async throws {
        try await backend.deleteLog(dayId: 1, entryIndex: 3)

        XCTAssertEqual(lastRequest.httpMethod, "DELETE")
        XCTAssertEqual(lastRequest.url?.absoluteString,
                       "https://example.supabase.co/rest/v1/exercise_logs?day_id=eq.1&entry_index=eq.3")
    }
}
