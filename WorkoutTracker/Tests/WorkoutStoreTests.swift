import XCTest
@testable import WorkoutTracker

@MainActor
final class WorkoutStoreTests: XCTestCase {
    var store: WorkoutStore!
    var testFileURL: URL!

    override func setUp() {
        super.setUp()
        testFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        store = WorkoutStore(fileURL: testFileURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testFileURL)
        super.tearDown()
    }

    func testAddWorkout() {
        let workout = Workout(name: "Chest Day", duration: 3600)
        store.addWorkout(workout)
        XCTAssertEqual(store.workouts.count, 1)
        XCTAssertEqual(store.workouts[0].name, "Chest Day")
    }

    func testDeleteWorkout() {
        let workout = Workout(name: "Chest Day", duration: 3600)
        store.addWorkout(workout)
        store.deleteWorkout(workout)
        XCTAssertEqual(store.workouts.count, 0)
    }

    func testUpdateWorkout() {
        var workout = Workout(name: "Chest Day", duration: 3600)
        store.addWorkout(workout)
        workout = Workout(id: workout.id, name: "Leg Day", duration: 4500)
        store.updateWorkout(workout)
        XCTAssertEqual(store.workouts[0].name, "Leg Day")
        XCTAssertEqual(store.workouts[0].duration, 4500)
    }

    func testWorkoutsForDate() {
        let today = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let todayWorkout = Workout(date: today, name: "Today's Workout", duration: 3600)
        let tomorrowWorkout = Workout(date: tomorrow, name: "Tomorrow's Workout", duration: 3600)
        store.addWorkout(todayWorkout)
        store.addWorkout(tomorrowWorkout)
        let todayWorkouts = store.workoutsForDate(today)
        XCTAssertEqual(todayWorkouts.count, 1)
        XCTAssertEqual(todayWorkouts[0].name, "Today's Workout")
    }

    func testDailyStatsForDate() {
        let today = Date()
        let workout1 = Workout(date: today, name: "Workout 1", duration: 1800)
        let workout2 = Workout(date: today, name: "Workout 2", duration: 1800)
        store.addWorkout(workout1)
        store.addWorkout(workout2)
        let stats = store.dailyStatsForDate(today)
        XCTAssertEqual(stats.workoutCount, 2)
        XCTAssertEqual(stats.totalDuration, 3600)
    }

    func testClearAllWorkouts() {
        let workout1 = Workout(name: "Workout 1", duration: 3600)
        let workout2 = Workout(name: "Workout 2", duration: 3600)
        store.addWorkout(workout1)
        store.addWorkout(workout2)
        XCTAssertEqual(store.workouts.count, 2)
        store.clearAllWorkouts()
        XCTAssertEqual(store.workouts.count, 0)
    }

    func testPersistence() {
        let workout = Workout(name: "Persisted Workout", duration: 3600)
        store.addWorkout(workout)
        let newStore = WorkoutStore(fileURL: testFileURL)
        XCTAssertEqual(newStore.workouts.count, 1)
        XCTAssertEqual(newStore.workouts[0].name, "Persisted Workout")
    }

    func testEmptyPersistenceFile() {
        let newStore = WorkoutStore(fileURL: testFileURL)
        XCTAssertEqual(newStore.workouts.count, 0)
    }
}
