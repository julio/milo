import XCTest
@testable import WorkoutTracker

final class MockCompletionBackend: CompletionBackend, @unchecked Sendable {
    var stored: Set<SetCompletion> = []
    var failNext: Error?
    private(set) var calls: [String] = []

    private func check(_ call: String) throws {
        calls.append(call)
        if let error = failNext {
            failNext = nil
            throw error
        }
    }

    func fetchCompletions() async throws -> [SetCompletion] {
        try check("fetch")
        return Array(stored)
    }

    func insert(_ completion: SetCompletion) async throws {
        try check("insert")
        stored.insert(completion)
    }

    func delete(_ completion: SetCompletion) async throws {
        try check("delete")
        stored.remove(completion)
    }
}

@MainActor
final class CompletionStoreTests: XCTestCase {
    var backend: MockCompletionBackend!
    var store: CompletionStore!
    let day = TrainingPlan.days[0]        // 9 entries, none skipped
    let deloadDay = TrainingPlan.days[9]  // week 4 deload, one skipped entry

    override func setUp() {
        super.setUp()
        backend = MockCompletionBackend()
        store = CompletionStore(backend: backend)
    }

    func testRefreshLoadsCompletions() async {
        backend.stored = [SetCompletion(dayId: 0, entryIndex: 1)]

        await store.refresh()

        XCTAssertTrue(store.isDone(dayId: 0, entryIndex: 1))
        XCTAssertFalse(store.isDone(dayId: 0, entryIndex: 2))
        XCTAssertNil(store.errorMessage)
    }

    func testToggleMarksAndUnmarks() async {
        await store.toggle(dayId: 0, entryIndex: 1)
        XCTAssertTrue(store.isDone(dayId: 0, entryIndex: 1))
        XCTAssertEqual(backend.stored.count, 1)

        await store.toggle(dayId: 0, entryIndex: 1)
        XCTAssertFalse(store.isDone(dayId: 0, entryIndex: 1))
        XCTAssertEqual(backend.stored.count, 0)
        XCTAssertEqual(backend.calls, ["insert", "delete"])
    }

    func testToggleFailureKeepsStateAndSetsError() async {
        backend.failNext = TestError()

        await store.toggle(dayId: 0, entryIndex: 1)

        XCTAssertFalse(store.isDone(dayId: 0, entryIndex: 1))
        XCTAssertEqual(store.errorMessage, "backend exploded")

        await store.toggle(dayId: 0, entryIndex: 1)
        XCTAssertTrue(store.isDone(dayId: 0, entryIndex: 1))
        XCTAssertNil(store.errorMessage)
    }

    func testTrackableIndicesExcludeSkippedRows() {
        XCTAssertEqual(CompletionStore.trackableIndices(for: day).count,
                       day.entries.count)
        let deloadTrackable = CompletionStore.trackableIndices(for: deloadDay)
        XCTAssertEqual(deloadTrackable.count, deloadDay.entries.count - 1)
        let skippedIndex = deloadDay.entries.firstIndex(where: \.isSkipped)!
        XCTAssertFalse(deloadTrackable.contains(skippedIndex))
    }

    func testDayStatusProgression() async {
        XCTAssertEqual(store.status(for: day), .pending)

        await store.toggle(dayId: day.id, entryIndex: 0)
        XCTAssertEqual(store.status(for: day), .partial)
        XCTAssertEqual(store.doneCount(for: day), 1)

        for index in CompletionStore.trackableIndices(for: day) {
            if !store.isDone(dayId: day.id, entryIndex: index) {
                await store.toggle(dayId: day.id, entryIndex: index)
            }
        }
        XCTAssertEqual(store.status(for: day), .complete)
    }

    func testDeloadDayCompleteIgnoresSkippedRow() async {
        for index in CompletionStore.trackableIndices(for: deloadDay) {
            await store.toggle(dayId: deloadDay.id, entryIndex: index)
        }
        XCTAssertEqual(store.status(for: deloadDay), .complete)
    }

    func testStatusByMonthDay() async {
        XCTAssertEqual(store.status(month: 8, day: 17), .pending)
        XCTAssertEqual(store.status(month: 8, day: 18), .notInPlan)
        XCTAssertEqual(store.status(month: 2, day: 1), .notInPlan)

        await store.toggle(dayId: 0, entryIndex: 0)
        XCTAssertEqual(store.status(month: 8, day: 17), .partial)
    }

    func testDefaultInitUsesSupabaseBackend() {
        XCTAssertNotNil(CompletionStore())
    }
}

final class PlanCalendarTests: XCTestCase {
    var sundayFirst: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1
        return c
    }

    var mondayFirst: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    func testMonthsSpanAugustThroughNovember() {
        let months = PlanCalendar.months()
        XCTAssertEqual(months.map(\.month), [8, 9, 10, 11])
        XCTAssertTrue(months.allSatisfy { $0.year == 2026 })
    }

    func testMonthIdsAreUniqueAndOrdered() {
        let ids = PlanCalendar.months().map(\.id)
        XCTAssertEqual(ids, ids.sorted())
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testMonthTitle() {
        let title = PlanCalendar.Month(year: 2026, month: 8).title(calendar: sundayFirst)
        XCTAssertTrue(title.contains("August"))
        XCTAssertTrue(title.contains("2026"))
    }

    func testGridAugust2026SundayStart() {
        // Aug 1 2026 is a Saturday: 6 leading blanks with a Sunday-first week.
        let grid = PlanCalendar.grid(.init(year: 2026, month: 8), calendar: sundayFirst)
        XCTAssertEqual(grid.prefix(6).compactMap { $0 }, [])
        XCTAssertEqual(grid[6], 1)
        XCTAssertEqual(grid.count, 6 + 31)
        XCTAssertEqual(grid.last, 31)
    }

    func testGridAugust2026MondayStart() {
        // Monday-first week: Saturday is column 5, so 5 leading blanks.
        let grid = PlanCalendar.grid(.init(year: 2026, month: 8), calendar: mondayFirst)
        XCTAssertEqual(grid[5], 1)
        XCTAssertEqual(grid.count, 5 + 31)
    }

    func testGridNovember2026() {
        // Nov 1 2026 is a Sunday: no leading blanks, 30 days.
        let grid = PlanCalendar.grid(.init(year: 2026, month: 11), calendar: sundayFirst)
        XCTAssertEqual(grid.first, 1)
        XCTAssertEqual(grid.count, 30)
    }

    func testWeekdayHeaders() {
        XCTAssertEqual(PlanCalendar.weekdayHeaders(calendar: sundayFirst).count, 7)
        XCTAssertEqual(PlanCalendar.weekdayHeaders(calendar: sundayFirst).first, "S")
        XCTAssertEqual(PlanCalendar.weekdayHeaders(calendar: mondayFirst).first, "M")
    }
}

final class SupabaseCompletionBackendTests: XCTestCase {
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

    func testFetchCompletionsRequestAndDecoding() async throws {
        transport.responseData = Data(#"[{"day_id":3,"entry_index":7}]"#.utf8)

        let completions = try await backend.fetchCompletions()

        XCTAssertEqual(lastRequest.httpMethod, "GET")
        XCTAssertEqual(lastRequest.url?.absoluteString,
                       "https://example.supabase.co/rest/v1/set_completions?select=day_id,entry_index")
        XCTAssertEqual(completions, [SetCompletion(dayId: 3, entryIndex: 7)])
    }

    func testInsertCompletionRequest() async throws {
        try await backend.insert(SetCompletion(dayId: 3, entryIndex: 7))

        XCTAssertEqual(lastRequest.httpMethod, "POST")
        XCTAssertEqual(lastRequest.url?.absoluteString,
                       "https://example.supabase.co/rest/v1/set_completions")
        let body = try JSONSerialization.jsonObject(with: lastRequest.httpBody!) as! [String: Int]
        XCTAssertEqual(body, ["day_id": 3, "entry_index": 7])
    }

    func testDeleteCompletionRequest() async throws {
        try await backend.delete(SetCompletion(dayId: 3, entryIndex: 7))

        XCTAssertEqual(lastRequest.httpMethod, "DELETE")
        XCTAssertEqual(lastRequest.url?.absoluteString,
                       "https://example.supabase.co/rest/v1/set_completions?day_id=eq.3&entry_index=eq.7")
    }
}
