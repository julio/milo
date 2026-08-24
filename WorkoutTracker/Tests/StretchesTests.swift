import XCTest
@testable import WorkoutTracker

final class MockStretchBackend: StretchBackend, @unchecked Sendable {
    var stored: Set<StretchCompletion> = []
    var failNext: Error?
    private(set) var calls: [String] = []

    private func check(_ call: String) throws {
        calls.append(call)
        if let error = failNext {
            failNext = nil
            throw error
        }
    }

    func fetchStretchCompletions() async throws -> [StretchCompletion] {
        try check("fetch")
        return Array(stored)
    }

    func insert(_ completion: StretchCompletion) async throws {
        try check("insert")
        stored.insert(completion)
    }

    func delete(_ completion: StretchCompletion) async throws {
        try check("delete")
        stored.remove(completion)
    }
}

final class StretchPlanTests: XCTestCase {
    func testSixStretchesInPTOrder() {
        XCTAssertEqual(StretchPlan.stretches, [
            "90/90 Hip Lift L Hip Pullback R Foot Lift Off",
            "Quad Stretch in Half Kneeling",
            "Plank on Gym Ball",
            "Bridges (Marches)",
            "Doorway Squats",
            "Lunge Glute Strategy Isometric Hold",
        ])
    }

    func testActiveFromAugust16() {
        XCTAssertFalse(StretchPlan.isActive(year: 2026, month: 8, day: 15))
        XCTAssertTrue(StretchPlan.isActive(year: 2026, month: 8, day: 16))
        XCTAssertTrue(StretchPlan.isActive(year: 2026, month: 8, day: 17))
        XCTAssertTrue(StretchPlan.isActive(year: 2026, month: 9, day: 1))
        XCTAssertTrue(StretchPlan.isActive(year: 2027, month: 1, day: 1))
        XCTAssertFalse(StretchPlan.isActive(year: 2025, month: 12, day: 31))
    }

    func testIsActiveOnDate() {
        let calendar = Calendar.current
        let before = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 16))!
        XCTAssertFalse(StretchPlan.isActive(on: before))
        XCTAssertTrue(StretchPlan.isActive(on: start))
    }

    func testDateKeyFormat() {
        XCTAssertEqual(StretchPlan.dateKey(year: 2026, month: 8, day: 16), "2026-08-16")
        XCTAssertEqual(StretchPlan.dateKey(year: 2026, month: 11, day: 3), "2026-11-03")
        let date = Calendar.current.date(
            from: DateComponents(year: 2026, month: 9, day: 5))!
        XCTAssertEqual(StretchPlan.dateKey(for: date), "2026-09-05")
    }
}

@MainActor
final class StretchStoreTests: XCTestCase {
    var backend: MockStretchBackend!
    var store: StretchStore!
    let key = "2026-08-16"

    var cache: DiskCache!

    override func setUp() {
        super.setUp()
        backend = MockStretchBackend()
        cache = makeCache()
        store = StretchStore(backend: backend, sync: makeEngine(), cache: cache)
    }

    func testRefreshLoadsCompletions() async {
        backend.stored = [StretchCompletion(date: key, stretchIndex: 2)]

        await store.refresh()

        XCTAssertTrue(store.isDone(dateKey: key, index: 2))
        XCTAssertFalse(store.isDone(dateKey: key, index: 0))
    }

    func testStateSurvivesRelaunchViaCache() async {
        await store.toggle(dateKey: key, index: 3)

        let relaunched = StretchStore(
            backend: backend, sync: makeEngine(), cache: cache)

        XCTAssertTrue(relaunched.isDone(dateKey: key, index: 3))
    }

    func testRefreshFailureKeepsLocalState() async {
        await store.toggle(dateKey: key, index: 0)
        backend.failNext = TestError()

        await store.refresh()

        XCTAssertTrue(store.isDone(dateKey: key, index: 0))
    }

    func testToggleMarksAndUnmarks() async {
        await store.toggle(dateKey: key, index: 0)
        XCTAssertTrue(store.isDone(dateKey: key, index: 0))
        XCTAssertEqual(store.doneCount(dateKey: key), 1)

        await store.toggle(dateKey: key, index: 0)
        XCTAssertFalse(store.isDone(dateKey: key, index: 0))
        XCTAssertEqual(backend.calls, ["insert", "delete"])
    }

    func testDoneCountIsPerDay() async {
        await store.toggle(dateKey: key, index: 0)
        await store.toggle(dateKey: key, index: 1)
        await store.toggle(dateKey: "2026-08-17", index: 0)

        XCTAssertEqual(store.doneCount(dateKey: key), 2)
        XCTAssertEqual(store.doneCount(dateKey: "2026-08-17"), 1)
        XCTAssertEqual(store.doneCount(dateKey: "2026-08-18"), 0)
    }

    func testToggleIsOptimisticEvenIfBackendFails() async {
        backend.failNext = TestError()

        await store.toggle(dateKey: key, index: 0)

        XCTAssertTrue(store.isDone(dateKey: key, index: 0))
    }

    func testDefaultInitUsesSupabaseBackend() {
        XCTAssertNotNil(StretchStore())
    }
}

final class DayProgressTests: XCTestCase {
    func stretchSet(_ key: String, _ indices: [Int]) -> Set<StretchCompletion> {
        Set(indices.map { StretchCompletion(date: key, stretchIndex: $0) })
    }

    func trainingSet(_ dayId: Int, _ indices: [Int]) -> Set<SetCompletion> {
        Set(indices.map { SetCompletion(dayId: dayId, entryIndex: $0) })
    }

    func testCountsOnRestDayAreStretchesOnly() {
        let counts = DayProgress.counts(
            month: 8, day: 16, trainingCompletions: [],
            stretchCompletions: stretchSet("2026-08-16", [0, 1]))
        XCTAssertEqual(counts.done, 2)
        XCTAssertEqual(counts.total, 6)
    }

    func testCountsOnTrainingDayIncludeBoth() {
        // Training days trim the stretch list to 4.
        let counts = DayProgress.counts(
            month: 8, day: 17,
            trainingCompletions: trainingSet(0, [0, 1, 2]),
            stretchCompletions: stretchSet("2026-08-17", [0]))
        XCTAssertEqual(counts.done, 4)
        XCTAssertEqual(counts.total, 9 + 4)
    }

    func testTrainingDaysSkipPlankOnBallAndDoorwaySquats() {
        // Aug 17 is a training day: indices 2 and 4 drop out.
        XCTAssertEqual(StretchPlan.activeIndices(year: 2026, month: 8, day: 17),
                       [0, 1, 3, 5])
        // Aug 16 is a rest day, and 2027 has no plan: full list.
        XCTAssertEqual(StretchPlan.activeIndices(year: 2026, month: 8, day: 16),
                       [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(StretchPlan.activeIndices(year: 2027, month: 8, day: 17),
                       [0, 1, 2, 3, 4, 5])

        let calendar = Calendar.current
        let trainingDay = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 17))!
        XCTAssertEqual(StretchPlan.activeIndices(on: trainingDay), [0, 1, 3, 5])
    }

    func testSkippedStretchCompletionsDoNotCountOnTrainingDays() {
        let counts = DayProgress.counts(
            month: 8, day: 17,
            trainingCompletions: [],
            stretchCompletions: stretchSet("2026-08-17", [2, 4]))
        XCTAssertEqual(counts.done, 0)
    }

    func testCountsBeforeEverythingAreZero() {
        let counts = DayProgress.counts(
            month: 8, day: 10, trainingCompletions: [], stretchCompletions: [])
        XCTAssertEqual(counts.total, 0)
        XCTAssertEqual(counts.done, 0)
    }

    func testDayBeforeEverythingIsNotInPlan() {
        XCTAssertEqual(DayProgress.combinedStatus(
            month: 8, day: 10, trainingCompletions: [], stretchCompletions: []),
            .notInPlan)
    }

    func testRestDayWithStretchesOnly() {
        // Aug 16: stretches active, no training session.
        XCTAssertEqual(DayProgress.combinedStatus(
            month: 8, day: 16, trainingCompletions: [], stretchCompletions: []),
            .pending)
        XCTAssertEqual(DayProgress.combinedStatus(
            month: 8, day: 16, trainingCompletions: [],
            stretchCompletions: stretchSet("2026-08-16", [0, 1])),
            .partial)
        XCTAssertEqual(DayProgress.combinedStatus(
            month: 8, day: 16, trainingCompletions: [],
            stretchCompletions: stretchSet("2026-08-16", Array(0..<6))),
            .complete)
    }

    func testTrainingDayNeedsBothToComplete() {
        // Aug 17 = plan day 0 with 9 trackable sets + 4 active stretches
        // (checking all 6 still completes; the extra two just don't count).
        let allSets = trainingSet(0, Array(0..<9))
        let allStretches = stretchSet("2026-08-17", Array(0..<6))

        XCTAssertEqual(DayProgress.combinedStatus(
            month: 8, day: 17, trainingCompletions: allSets,
            stretchCompletions: []),
            .partial)
        XCTAssertEqual(DayProgress.combinedStatus(
            month: 8, day: 17, trainingCompletions: [],
            stretchCompletions: allStretches),
            .partial)
        XCTAssertEqual(DayProgress.combinedStatus(
            month: 8, day: 17, trainingCompletions: allSets,
            stretchCompletions: allStretches),
            .complete)
    }

    func testStretchesFromOtherDaysDoNotLeak() {
        let wrongDay = stretchSet("2026-08-18", Array(0..<6))
        XCTAssertEqual(DayProgress.combinedStatus(
            month: 8, day: 16, trainingCompletions: [],
            stretchCompletions: wrongDay),
            .pending)
    }

    func testDifferentYearHasNoTrainingComponent() {
        // Aug 17, 2027: not a plan year, but stretches are still active.
        XCTAssertEqual(DayProgress.combinedStatus(
            year: 2027, month: 8, day: 17,
            trainingCompletions: trainingSet(0, Array(0..<9)),
            stretchCompletions: stretchSet("2027-08-17", Array(0..<6))),
            .complete)
    }
}

final class SupabaseStretchBackendTests: XCTestCase {
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

    func testFetchRequestAndDecoding() async throws {
        transport.responseData = Data(#"[{"date":"2026-08-16","stretch_index":4}]"#.utf8)

        let completions = try await backend.fetchStretchCompletions()

        XCTAssertEqual(lastRequest.url?.absoluteString,
                       "https://example.supabase.co/rest/v1/stretch_completions?select=date,stretch_index")
        XCTAssertEqual(completions, [StretchCompletion(date: "2026-08-16", stretchIndex: 4)])
    }

    func testInsertRequest() async throws {
        try await backend.insert(StretchCompletion(date: "2026-08-16", stretchIndex: 4))

        XCTAssertEqual(lastRequest.httpMethod, "POST")
        XCTAssertEqual(lastRequest.url?.absoluteString,
                       "https://example.supabase.co/rest/v1/stretch_completions")
        let body = try JSONSerialization.jsonObject(with: lastRequest.httpBody!) as! [String: Any]
        XCTAssertEqual(body["date"] as? String, "2026-08-16")
        XCTAssertEqual(body["stretch_index"] as? Int, 4)
    }

    func testDeleteRequest() async throws {
        try await backend.delete(StretchCompletion(date: "2026-08-16", stretchIndex: 4))

        XCTAssertEqual(lastRequest.httpMethod, "DELETE")
        XCTAssertEqual(lastRequest.url?.absoluteString,
                       "https://example.supabase.co/rest/v1/stretch_completions?date=eq.2026-08-16&stretch_index=eq.4")
    }
}
