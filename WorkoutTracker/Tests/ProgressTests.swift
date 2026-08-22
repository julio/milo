import XCTest
@testable import WorkoutTracker

final class ProgressTests: XCTestCase {
    // Day 0 (Aug 17, week 1) entries: 1 = "Back squat" set 1, 2-3 = "same
    // lift", 4 = "Back squat — volume", 5 = "DB Romanian deadlift", 7 = "Plank".
    // Day 3 (Aug 24, week 2) mirrors it.
    let squatDay1 = TrainingPlan.days[0]
    let squatDay2 = TrainingPlan.days[3]

    private func logs(_ entries: [ExerciseLog]) -> [LogKey: ExerciseLog] {
        Dictionary(uniqueKeysWithValues: entries.map {
            (LogKey(dayId: $0.dayId, entryIndex: $0.entryIndex), $0)
        })
    }

    // MARK: - Metric

    func testMetricUnitsAndIds() {
        XCTAssertEqual(ProgressMetric.weight.unit, "lb")
        XCTAssertEqual(ProgressMetric.reps.unit, "reps")
        XCTAssertEqual(ProgressMetric.weight.id, "Weight")
        XCTAssertEqual(ProgressMetric.allCases.count, 2)
    }

    func testValueOfLogPerMetric() {
        let log = ExerciseLog(dayId: 0, entryIndex: 1, weight: 90, reps: 5)
        XCTAssertEqual(ProgressData.value(of: log, for: .weight), 90)
        XCTAssertEqual(ProgressData.value(of: log, for: .reps), 5)

        let bare = ExerciseLog(dayId: 0, entryIndex: 1, weight: nil, reps: nil)
        XCTAssertNil(ProgressData.value(of: bare, for: .weight))
        XCTAssertNil(ProgressData.value(of: bare, for: .reps))
    }

    // MARK: - "same lift" resolution

    func testResolvedExerciseWalksBackOverSameLift() {
        XCTAssertEqual(ProgressData.resolvedExercise(day: squatDay1, entryIndex: 1), "Back squat")
        XCTAssertEqual(ProgressData.resolvedExercise(day: squatDay1, entryIndex: 2), "Back squat")
        XCTAssertEqual(ProgressData.resolvedExercise(day: squatDay1, entryIndex: 3), "Back squat")
        XCTAssertEqual(ProgressData.resolvedExercise(day: squatDay1, entryIndex: 5), "DB Romanian deadlift")
    }

    // MARK: - Series building

    func testEmptyLogsMakeNoSeries() {
        XCTAssertEqual(ProgressData.series(metric: .weight, logs: [:]), [])
    }

    func testSetsOfOneLiftCollapseToBestOfDay() {
        let series = ProgressData.series(metric: .weight, logs: logs([
            ExerciseLog(dayId: squatDay1.id, entryIndex: 1, weight: 90, reps: 5),
            ExerciseLog(dayId: squatDay1.id, entryIndex: 2, weight: 100, reps: 5),
            ExerciseLog(dayId: squatDay1.id, entryIndex: 3, weight: 115, reps: 5),
        ]))

        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].exercise, "Back squat")
        XCTAssertEqual(series[0].points.map(\.value), [115])
        XCTAssertEqual(series[0].points[0].week, 1)
        XCTAssertEqual(series[0].points[0].date, squatDay1.date)
        XCTAssertEqual(series[0].id, "Back squat")
    }

    func testBaselineAndDeltaAgainstWeekOne() {
        let series = ProgressData.series(metric: .weight, logs: logs([
            ExerciseLog(dayId: squatDay1.id, entryIndex: 3, weight: 115, reps: 5),
            ExerciseLog(dayId: squatDay2.id, entryIndex: 3, weight: 125, reps: 5),
        ]))

        XCTAssertEqual(series[0].points.map(\.value), [115, 125])
        XCTAssertEqual(series[0].baseline, 115)
        XCTAssertEqual(series[0].latest, 125)
        XCTAssertEqual(series[0].delta, 10)
    }

    func testBaselineFallsBackToEarliestLoggedWeek() {
        let series = ProgressData.series(metric: .weight, logs: logs([
            ExerciseLog(dayId: squatDay2.id, entryIndex: 3, weight: 125, reps: 5),
        ]))

        XCTAssertEqual(series[0].baseline, 125)
        XCTAssertEqual(series[0].delta, 0)
    }

    func testRepsMetricSkipsWeightOnlyLogsAndConverts() {
        let series = ProgressData.series(metric: .reps, logs: logs([
            ExerciseLog(dayId: squatDay1.id, entryIndex: 1, weight: 90, reps: nil),
            ExerciseLog(dayId: squatDay1.id, entryIndex: 7, weight: nil, reps: 45),
        ]))

        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].exercise, "Plank")
        XCTAssertEqual(series[0].points.map(\.value), [45])
    }

    func testWeightMetricSkipsRepsOnlyLogs() {
        let series = ProgressData.series(metric: .weight, logs: logs([
            ExerciseLog(dayId: squatDay1.id, entryIndex: 7, weight: nil, reps: 45),
        ]))

        XCTAssertEqual(series, [])
    }

    func testSeriesOrderedByFirstAppearanceInPlan() {
        let series = ProgressData.series(metric: .weight, logs: logs([
            ExerciseLog(dayId: squatDay1.id, entryIndex: 5, weight: 40, reps: 10),
            ExerciseLog(dayId: squatDay1.id, entryIndex: 1, weight: 90, reps: 5),
        ]))

        XCTAssertEqual(series.map(\.exercise), ["Back squat", "DB Romanian deadlift"])
    }

    func testLogsOutsideThePlanAreIgnored() {
        let series = ProgressData.series(metric: .weight, logs: logs([
            ExerciseLog(dayId: 999, entryIndex: 1, weight: 90, reps: 5),
            ExerciseLog(dayId: squatDay1.id, entryIndex: 99, weight: 90, reps: 5),
        ]))

        XCTAssertEqual(series, [])
    }

    func testProgressPointIdIsItsDate() {
        let point = ProgressPoint(date: squatDay1.date, week: 1, value: 115)
        XCTAssertEqual(point.id, squatDay1.date)
    }
}
