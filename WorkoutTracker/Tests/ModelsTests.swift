import XCTest
@testable import WorkoutTracker

final class ModelsTests: XCTestCase {
    func testWorkoutInitialization() {
        let exercises = [
            Exercise(name: "Push-ups", sets: 3, reps: 10),
            Exercise(name: "Bench Press", sets: 4, reps: 8, weight: 185)
        ]
        let workout = Workout(name: "Chest Day", duration: 3600, exercises: exercises)
        XCTAssertEqual(workout.name, "Chest Day")
        XCTAssertEqual(workout.duration, 3600)
        XCTAssertEqual(workout.exercises.count, 2)
        XCTAssertNotNil(workout.id)
    }

    func testWorkoutDefaultValues() {
        let workout = Workout(name: "Default Workout", duration: 1800)
        XCTAssertEqual(workout.name, "Default Workout")
        XCTAssertEqual(workout.duration, 1800)
        XCTAssertEqual(workout.exercises.count, 0)
        XCTAssertNotNil(workout.id)
    }

    func testExerciseInitialization() {
        let exercise = Exercise(name: "Squat", sets: 5, reps: 5, weight: 315)
        XCTAssertEqual(exercise.name, "Squat")
        XCTAssertEqual(exercise.sets, 5)
        XCTAssertEqual(exercise.reps, 5)
        XCTAssertEqual(exercise.weight, 315)
        XCTAssertNotNil(exercise.id)
    }

    func testExerciseOptionalWeight() {
        let exercise = Exercise(name: "Pull-ups", sets: 3, reps: 10)
        XCTAssertEqual(exercise.name, "Pull-ups")
        XCTAssertNil(exercise.weight)
    }

    func testDailyStatsInitialization() {
        let today = Date()
        let stats = DailyStats(id: UUID(), date: today, workoutCount: 2, totalDuration: 3600)
        XCTAssertEqual(stats.workoutCount, 2)
        XCTAssertEqual(stats.totalDuration, 3600)
    }

    func testDailyStatsDurationFormatting() {
        let today = Date()
        let statsMinutes = DailyStats(id: UUID(), date: today, workoutCount: 1, totalDuration: 1800)
        XCTAssertEqual(statsMinutes.durationFormatted, "30m")
        let statsHours = DailyStats(id: UUID(), date: today, workoutCount: 1, totalDuration: 5400)
        XCTAssertEqual(statsHours.durationFormatted, "1h 30m")
        let statsJustHours = DailyStats(id: UUID(), date: today, workoutCount: 1, totalDuration: 7200)
        XCTAssertEqual(statsJustHours.durationFormatted, "2h 0m")
    }

    func testWorkoutCoding() {
        let exercises = [Exercise(name: "Bench Press", sets: 4, reps: 8)]
        let workout = Workout(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789012")!,
            name: "Test Workout",
            duration: 3600,
            exercises: exercises
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try? encoder.encode(workout)
        XCTAssertNotNil(data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedWorkout = try? decoder.decode(Workout.self, from: data!)
        XCTAssertNotNil(decodedWorkout)
        XCTAssertEqual(decodedWorkout?.name, "Test Workout")
        XCTAssertEqual(decodedWorkout?.exercises.count, 1)
    }

    func testExerciseCoding() {
        let exercise = Exercise(
            id: UUID(uuidString: "87654321-4321-4321-4321-210987654321")!,
            name: "Deadlift",
            sets: 3,
            reps: 5,
            weight: 405
        )
        let encoder = JSONEncoder()
        let data = try? encoder.encode(exercise)
        XCTAssertNotNil(data)
        let decoder = JSONDecoder()
        let decodedExercise = try? decoder.decode(Exercise.self, from: data!)
        XCTAssertNotNil(decodedExercise)
        XCTAssertEqual(decodedExercise?.name, "Deadlift")
        XCTAssertEqual(decodedExercise?.weight, 405)
    }

    func testWorkoutIdentifiable() {
        let workout1 = Workout(name: "Workout 1", duration: 3600)
        let workout2 = Workout(name: "Workout 2", duration: 3600)
        XCTAssertNotEqual(workout1.id, workout2.id)
    }

    func testExerciseIdentifiable() {
        let exercise1 = Exercise(name: "Exercise 1", sets: 3, reps: 10)
        let exercise2 = Exercise(name: "Exercise 2", sets: 3, reps: 10)
        XCTAssertNotEqual(exercise1.id, exercise2.id)
    }
}
