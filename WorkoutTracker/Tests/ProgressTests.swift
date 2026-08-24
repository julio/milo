import XCTest
@testable import WorkoutTracker

final class ProgressTests: XCTestCase {
    // Day 0 (Aug 17, week 1) entries: 1 = "Back squat" set 1, 2-3 = "same
    // lift" (5 reps each), 4 = "Back squat — volume" (5 x 10),
    // 5 = "DB Romanian deadlift" (3 x 10), 7 = "Plank" (3 x 45 sec).
    // Day 3 (Aug 24, week 2) mirrors it.
    let squatDay1 = TrainingPlan.days[0]
    let squatDay2 = TrainingPlan.days[3]

    private func logs(_ entries: [ExerciseLog]) -> [LogKey: ExerciseLog] {
        Dictionary(uniqueKeysWithValues: entries.map {
            (LogKey(dayId: $0.dayId, entryIndex: $0.entryIndex), $0)
        })
    }

    // MARK: - Estimated 1RM

    func testEpleyFormula() {
        XCTAssertEqual(ProgressData.estimatedOneRepMax(weight: 300, reps: 0), 300)
        XCTAssertEqual(ProgressData.estimatedOneRepMax(weight: 100, reps: 5),
                       100 * (1 + 5.0 / 30), accuracy: 0.001)
        XCTAssertEqual(ProgressData.estimatedOneRepMax(weight: 90, reps: 10), 120,
                       accuracy: 0.001)
    }

    // MARK: - Name resolution

    func testResolvedExerciseWalksBackOverSameLift() {
        XCTAssertEqual(ProgressData.resolvedExercise(day: squatDay1, entryIndex: 1), "Back squat")
        XCTAssertEqual(ProgressData.resolvedExercise(day: squatDay1, entryIndex: 2), "Back squat")
        XCTAssertEqual(ProgressData.resolvedExercise(day: squatDay1, entryIndex: 3), "Back squat")
        XCTAssertEqual(ProgressData.resolvedExercise(day: squatDay1, entryIndex: 5), "DB Romanian deadlift")
    }

    func testCanonicalExerciseFoldsVolumeIntoMainLift() {
        XCTAssertEqual(ProgressData.canonicalExercise("Deadlift — volume"), "Deadlift")
        XCTAssertEqual(ProgressData.canonicalExercise("Back squat — volume"), "Back squat")
        XCTAssertEqual(ProgressData.canonicalExercise("Bench press — volume"), "Bench press")
        XCTAssertEqual(ProgressData.canonicalExercise("Back squat"), "Back squat")
        XCTAssertEqual(ProgressData.canonicalExercise("Plank"), "Plank")
    }

    // MARK: - Series building

    func testEmptyLogsMakeNoSeries() {
        XCTAssertEqual(ProgressData.series(logs: [:]), [])
    }

    func testDayChartsItsBestSetsEstimatedMax() {
        // Three squat sets of 5; the 115 top set carries the day.
        let series = ProgressData.series(logs: logs([
            ExerciseLog(dayId: squatDay1.id, entryIndex: 1, weight: 90, reps: 1),
            ExerciseLog(dayId: squatDay1.id, entryIndex: 2, weight: 100, reps: 1),
            ExerciseLog(dayId: squatDay1.id, entryIndex: 3, weight: 115, reps: 1),
        ]))

        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].exercise, "Back squat")
        XCTAssertEqual(series[0].id, "Back squat")
        XCTAssertEqual(series[0].points.count, 1)
        XCTAssertEqual(series[0].points[0].value,
                       ProgressData.estimatedOneRepMax(weight: 115, reps: 5))
        XCTAssertEqual(series[0].points[0].week, 1)
        XCTAssertEqual(series[0].points[0].date, squatDay1.date)
        XCTAssertEqual(series[0].points[0].id, squatDay1.date)
    }

    func testVolumeWorkChartsWithItsMainLiftButTopSetWins() {
        // Volume: 70 lb x 10 reps → ~93; top set: 115 x 5 → ~134.
        let series = ProgressData.series(logs: logs([
            ExerciseLog(dayId: squatDay1.id, entryIndex: 3, weight: 115, reps: 1),
            ExerciseLog(dayId: squatDay1.id, entryIndex: 4, weight: 70, reps: 5),
        ]))

        XCTAssertEqual(series.map(\.exercise), ["Back squat"])
        XCTAssertEqual(series[0].points[0].value,
                       ProgressData.estimatedOneRepMax(weight: 115, reps: 5))
    }

    func testVolumeOnlyDayStillChartsUnderMainLift() {
        let series = ProgressData.series(logs: logs([
            ExerciseLog(dayId: squatDay1.id, entryIndex: 4, weight: 70, reps: 5),
        ]))

        XCTAssertEqual(series.map(\.exercise), ["Back squat"])
        XCTAssertEqual(series[0].points[0].value,
                       ProgressData.estimatedOneRepMax(weight: 70, reps: 10))
    }

    func testBaselineAndDeltaAgainstWeekOne() {
        let series = ProgressData.series(logs: logs([
            ExerciseLog(dayId: squatDay1.id, entryIndex: 3, weight: 115, reps: 1),
            ExerciseLog(dayId: squatDay2.id, entryIndex: 3, weight: 125, reps: 1),
        ]))

        let week1 = ProgressData.estimatedOneRepMax(weight: 115, reps: 5)
        let week2 = ProgressData.estimatedOneRepMax(weight: 125, reps: 5)
        XCTAssertEqual(series[0].points.map(\.value), [week1, week2])
        XCTAssertEqual(series[0].baseline, week1)
        XCTAssertEqual(series[0].latest, week2)
        XCTAssertEqual(series[0].delta, week2 - week1, accuracy: 0.001)
    }

    func testBaselineFallsBackToEarliestLoggedWeek() {
        let series = ProgressData.series(logs: logs([
            ExerciseLog(dayId: squatDay2.id, entryIndex: 3, weight: 125, reps: 1),
        ]))

        XCTAssertEqual(series[0].baseline, series[0].latest)
        XCTAssertEqual(series[0].delta, 0)
    }

    func testWeightlessAndTimeBasedLogsAreSkipped() {
        let series = ProgressData.series(logs: logs([
            // Checked sets but no weight: nothing to estimate.
            ExerciseLog(dayId: squatDay1.id, entryIndex: 1, weight: nil, reps: 1),
            // Plank is seconds, not reps — no 1RM even with a weight.
            ExerciseLog(dayId: squatDay1.id, entryIndex: 7, weight: 25, reps: 3),
        ]))

        XCTAssertEqual(series, [])
    }

    func testSeriesOrderedByFirstAppearanceInPlan() {
        let series = ProgressData.series(logs: logs([
            ExerciseLog(dayId: squatDay1.id, entryIndex: 5, weight: 40, reps: 3),
            ExerciseLog(dayId: squatDay1.id, entryIndex: 1, weight: 90, reps: 1),
        ]))

        XCTAssertEqual(series.map(\.exercise), ["Back squat", "DB Romanian deadlift"])
    }

    func testLogsOutsideThePlanAreIgnored() {
        let series = ProgressData.series(logs: logs([
            ExerciseLog(dayId: 999, entryIndex: 1, weight: 90, reps: 1),
            ExerciseLog(dayId: squatDay1.id, entryIndex: 99, weight: 90, reps: 1),
        ]))

        XCTAssertEqual(series, [])
    }
}
