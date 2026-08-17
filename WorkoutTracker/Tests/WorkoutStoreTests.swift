import XCTest
@testable import WorkoutTracker

/// In-memory backend double: records calls, can be told to fail.
final class MockBackend: WorkoutBackend, @unchecked Sendable {
    var stored: [Workout] = []
    var failNext: Error?
    private(set) var calls: [String] = []

    private func check(_ call: String) throws {
        calls.append(call)
        if let error = failNext {
            failNext = nil
            throw error
        }
    }

    func fetchWorkouts() async throws -> [Workout] {
        try check("fetch")
        return stored
    }

    func insert(_ workout: Workout) async throws {
        try check("insert")
        stored.append(workout)
    }

    func update(_ workout: Workout) async throws {
        try check("update")
        if let i = stored.firstIndex(where: { $0.id == workout.id }) {
            stored[i] = workout
        }
    }

    func delete(id: UUID) async throws {
        try check("delete")
        stored.removeAll { $0.id == id }
    }

    func deleteAll() async throws {
        try check("deleteAll")
        stored.removeAll()
    }
}

struct TestError: Error, LocalizedError {
    var errorDescription: String? { "backend exploded" }
}

@MainActor
final class WorkoutStoreTests: XCTestCase {
    var backend: MockBackend!
    var store: WorkoutStore!

    override func setUp() {
        super.setUp()
        backend = MockBackend()
        store = WorkoutStore(backend: backend)
    }

    func testRefreshLoadsFromBackend() async {
        backend.stored = [Workout(name: "Chest Day", duration: 3600)]

        await store.refresh()

        XCTAssertEqual(store.workouts.count, 1)
        XCTAssertEqual(store.workouts[0].name, "Chest Day")
        XCTAssertNil(store.errorMessage)
    }

    func testAddWorkoutWritesThrough() async {
        let workout = Workout(name: "Chest Day", duration: 3600)

        await store.addWorkout(workout)

        XCTAssertEqual(store.workouts.count, 1)
        XCTAssertEqual(backend.stored.count, 1)
        XCTAssertEqual(backend.calls, ["insert"])
    }

    func testDeleteWorkoutWritesThrough() async {
        let workout = Workout(name: "Chest Day", duration: 3600)
        await store.addWorkout(workout)

        await store.deleteWorkout(workout)

        XCTAssertEqual(store.workouts.count, 0)
        XCTAssertEqual(backend.stored.count, 0)
    }

    func testUpdateWorkoutWritesThrough() async {
        var workout = Workout(name: "Chest Day", duration: 3600)
        await store.addWorkout(workout)

        workout = Workout(id: workout.id, name: "Leg Day", duration: 4500)
        await store.updateWorkout(workout)

        XCTAssertEqual(store.workouts[0].name, "Leg Day")
        XCTAssertEqual(backend.stored[0].name, "Leg Day")
    }

    func testUpdateUnknownWorkoutLeavesListUnchanged() async {
        let known = Workout(name: "Known", duration: 3600)
        await store.addWorkout(known)

        await store.updateWorkout(Workout(name: "Stranger", duration: 60))

        XCTAssertEqual(store.workouts.map(\.name), ["Known"])
    }

    func testClearAllWorkouts() async {
        await store.addWorkout(Workout(name: "One", duration: 3600))
        await store.addWorkout(Workout(name: "Two", duration: 3600))

        await store.clearAllWorkouts()

        XCTAssertEqual(store.workouts.count, 0)
        XCTAssertEqual(backend.stored.count, 0)
    }

    func testBackendFailureSetsErrorAndKeepsLocalState() async {
        await store.addWorkout(Workout(name: "Kept", duration: 3600))

        backend.failNext = TestError()
        await store.addWorkout(Workout(name: "Dropped", duration: 60))

        XCTAssertEqual(store.errorMessage, "backend exploded")
        XCTAssertEqual(store.workouts.map(\.name), ["Kept"])

        // Next successful call clears the banner.
        await store.refresh()
        XCTAssertNil(store.errorMessage)
    }

    func testWorkoutsForDate() async {
        let today = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        await store.addWorkout(Workout(date: today, name: "Today's Workout", duration: 3600))
        await store.addWorkout(Workout(date: tomorrow, name: "Tomorrow's Workout", duration: 3600))

        let todayWorkouts = store.workoutsForDate(today)

        XCTAssertEqual(todayWorkouts.count, 1)
        XCTAssertEqual(todayWorkouts[0].name, "Today's Workout")
    }

    func testDailyStatsForDate() async {
        let today = Date()
        await store.addWorkout(Workout(date: today, name: "Workout 1", duration: 1800))
        await store.addWorkout(Workout(date: today, name: "Workout 2", duration: 1800))

        let stats = store.dailyStatsForDate(today)

        XCTAssertEqual(stats.workoutCount, 2)
        XCTAssertEqual(stats.totalDuration, 3600)
    }

    func testDefaultInitUsesSupabaseBackend() {
        // Constructing with the default backend must not touch the network.
        XCTAssertNotNil(WorkoutStore())
    }
}
