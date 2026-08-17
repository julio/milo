import XCTest
@testable import WorkoutTracker

final class TrainingPlanTests: XCTestCase {
    let days = TrainingPlan.days
    let maxes = TrainingMaxes.standard

    // MARK: - Plan structure

    func testPlanHas39Sessions() {
        XCTAssertEqual(days.count, 39)
    }

    func testIdsMatchPositions() {
        for (i, day) in days.enumerated() {
            XCTAssertEqual(day.id, i)
        }
    }

    func testDatesAreStrictlyIncreasing() {
        for i in 1..<days.count {
            XCTAssertLessThan(days[i - 1].date, days[i].date)
        }
    }

    func testFirstAndLastSession() {
        XCTAssertEqual(days.first?.month, 8)
        XCTAssertEqual(days.first?.day, 17)
        XCTAssertEqual(days.first?.label, "SQUAT DAY")
        XCTAssertEqual(days.last?.month, 11)
        XCTAssertEqual(days.last?.day, 13)
        XCTAssertEqual(days.last?.label, "DEADLIFT DAY")
    }

    func testSessionsAreMonWedFri() {
        let calendar = Calendar.current
        for day in days {
            let weekday = calendar.component(.weekday, from: day.date)
            XCTAssertTrue([2, 4, 6].contains(weekday),
                          "\(day.dateTitle) is not Mon/Wed/Fri")
            let expectedName = ["", "Sunday", "Monday", "Tuesday", "Wednesday",
                                "Thursday", "Friday", "Saturday"][weekday]
            XCTAssertEqual(day.weekday, expectedName)
        }
    }

    func testWeeklyPatternIsSquatBenchDeadlift() {
        for chunk in stride(from: 0, to: days.count, by: 3) {
            XCTAssertEqual(days[chunk].label, "SQUAT DAY")
            XCTAssertEqual(days[chunk + 1].label, "BENCH DAY")
            XCTAssertEqual(days[chunk + 2].label, "DEADLIFT DAY")
        }
    }

    func testDeloadWeeksAre4And8And12() {
        let deloadWeeks = Set(days.filter(\.isDeload).map(\.week))
        XCTAssertEqual(deloadWeeks, [4, 8, 12])
        XCTAssertEqual(days.filter(\.isDeload).count, 9)
    }

    func testDeloadDaysSkipVolumeWork() {
        for day in days where day.isDeload {
            let skipped = day.entries.filter(\.isSkipped)
            XCTAssertEqual(skipped.count, 1)
            XCTAssertEqual(skipped.first?.exercise, "Volume work")
        }
        for day in days where !day.isDeload {
            XCTAssertTrue(day.entries.allSatisfy { !$0.isSkipped })
        }
    }

    func testCycleProgression() {
        XCTAssertEqual(days.map(\.cycle), Array(repeating: 1, count: 12)
                       + Array(repeating: 2, count: 12)
                       + Array(repeating: 3, count: 12)
                       + Array(repeating: 4, count: 3))
        for day in days {
            XCTAssertEqual(day.weekOfCycle, (day.week - 1) % 4 + 1)
        }
    }

    func testEveryDayStartsAndEndsWithTreadmill() {
        for day in days {
            XCTAssertEqual(day.entries.first?.exercise, "Treadmill, easy")
            XCTAssertEqual(day.entries.last?.exercise, "Treadmill, steady")
        }
    }

    func testMainLiftPercentsMatchWeekOfCycle() {
        let expected: [Int: [Double]] = [
            1: [65, 75, 85], 2: [70, 80, 90], 3: [75, 85, 95], 4: [40, 50, 60],
        ]
        for day in days {
            // The three numbered main-lift sets ("Set 1/2/3"); the volume
            // work also uses a percent (always 50) but is a separate block.
            let pcts = day.entries.compactMap { entry -> Double? in
                if case .percent(_, _, let pct) = entry.weight,
                   entry.setsReps.hasPrefix("Set ") {
                    return pct
                }
                return nil
            }
            XCTAssertEqual(pcts, expected[day.weekOfCycle],
                           "wrong main-lift percents on \(day.dateTitle)")
        }
    }

    func testPercentEntriesUseTheDaysLiftAndCycle() {
        let liftForLabel: [String: Lift] = [
            "SQUAT DAY": .squat, "BENCH DAY": .bench, "DEADLIFT DAY": .dead,
        ]
        for day in days {
            for entry in day.entries {
                if case .percent(let lift, let cycle, _) = entry.weight {
                    XCTAssertEqual(lift, liftForLabel[day.label])
                    XCTAssertEqual(cycle, day.cycle)
                }
            }
        }
    }

    // MARK: - Weight formula (mirrors the HTML's JS: round(tm*pct/100/5)*5)

    func testWeightFormulaCycle1() {
        XCTAssertEqual(maxes.weight(lift: .squat, cycle: 1, pct: 65), 120)
        XCTAssertEqual(maxes.weight(lift: .squat, cycle: 1, pct: 75), 140)
        XCTAssertEqual(maxes.weight(lift: .squat, cycle: 1, pct: 85), 155)
        XCTAssertEqual(maxes.weight(lift: .squat, cycle: 1, pct: 50), 95)
        XCTAssertEqual(maxes.weight(lift: .bench, cycle: 1, pct: 65), 100)
        XCTAssertEqual(maxes.weight(lift: .dead, cycle: 1, pct: 85), 190)
    }

    func testWeightFormulaAddsPerCycle() {
        // Cycle 2 TMs: squat 195, bench 160, dead 235.
        XCTAssertEqual(maxes.weight(lift: .squat, cycle: 2, pct: 100), 195)
        XCTAssertEqual(maxes.weight(lift: .bench, cycle: 2, pct: 100), 160)
        XCTAssertEqual(maxes.weight(lift: .dead, cycle: 2, pct: 100), 235)
        // Cycle 4 TMs: squat 215, bench 170, dead 255.
        XCTAssertEqual(maxes.weight(lift: .squat, cycle: 4, pct: 100), 215)
        XCTAssertEqual(maxes.weight(lift: .bench, cycle: 4, pct: 100), 170)
        XCTAssertEqual(maxes.weight(lift: .dead, cycle: 4, pct: 100), 255)
    }

    func testWeightRoundsToNearestFive() {
        // 185 * 0.65 = 120.25 -> 120; 225 * 0.75 = 168.75 -> 170.
        XCTAssertEqual(maxes.weight(lift: .squat, cycle: 1, pct: 65) % 5, 0)
        for day in days {
            for entry in day.entries {
                if case .percent(let lift, let cycle, let pct) = entry.weight {
                    XCTAssertEqual(maxes.weight(lift: lift, cycle: cycle, pct: pct) % 5, 0)
                }
            }
        }
    }

    func testBaseForLift() {
        XCTAssertEqual(maxes.base(for: .squat), 185)
        XCTAssertEqual(maxes.base(for: .bench), 155)
        XCTAssertEqual(maxes.base(for: .dead), 225)
    }

    func testWeightDisplay() {
        XCTAssertEqual(maxes.display(for: .none), "—")
        XCTAssertEqual(maxes.display(for: .percent(lift: .squat, cycle: 1, pct: 65)),
                       "120 lb")
    }

    // MARK: - Default index (which day to show on open)

    private func date(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testDefaultIndexBeforePlanStartsIsFirstDay() {
        XCTAssertEqual(TrainingPlan.defaultIndex(for: date(8, 1)), 0)
    }

    func testDefaultIndexOnASessionDayIsThatDay() {
        XCTAssertEqual(TrainingPlan.defaultIndex(for: date(8, 17)), 0)
        XCTAssertEqual(TrainingPlan.defaultIndex(for: date(8, 19)), 1)
        XCTAssertEqual(TrainingPlan.defaultIndex(for: date(11, 13)), 38)
    }

    func testDefaultIndexBetweenSessionsIsNextSession() {
        XCTAssertEqual(TrainingPlan.defaultIndex(for: date(8, 18)), 1)
        XCTAssertEqual(TrainingPlan.defaultIndex(for: date(8, 22)), 3)
    }

    func testDefaultIndexAfterPlanEndsIsLastDay() {
        XCTAssertEqual(TrainingPlan.defaultIndex(for: date(12, 25)), 38)
        XCTAssertEqual(TrainingPlan.defaultIndex(for: date(1, 1, year: 2027)), 38)
    }

    func testDayForDate() {
        XCTAssertEqual(TrainingPlan.day(for: date(8, 17))?.id, 0)
        XCTAssertEqual(TrainingPlan.day(for: date(11, 13))?.id, 38)
        XCTAssertNil(TrainingPlan.day(for: date(8, 16)))
        XCTAssertNil(TrainingPlan.day(for: date(8, 18)))
        XCTAssertNil(TrainingPlan.day(for: date(8, 17, year: 2027)))
    }

    // MARK: - Presentation helpers

    func testDateTitleContainsWeekdayAndDay() {
        let first = days[0]
        XCTAssertTrue(first.dateTitle.hasPrefix("Monday, "))
        XCTAssertTrue(first.dateTitle.contains("17"))
    }
}
