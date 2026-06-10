//
//  PlanCalculatorTests.swift
//  scranTests
//
//  Verifies the Mifflin-St Jeor maths the Plan Reveal screen puts on screen.
//

import Testing
import Foundation
@testable import scran

@MainActor
struct PlanCalculatorTests {

    // Reference subject: 82kg, 175cm, 34yo male, moderate activity.
    private func subject(goal: Goal = .lose, rate: Double = 0.5,
                         activity: ActivityLevel = .moderate,
                         sex: BiologicalSex = .male) -> PlanInput {
        PlanInput(heightCm: 175, weightKg: 82, age: 34, sex: sex,
                  activity: activity, weeklyWorkouts: 3, goal: goal, weeklyRateKg: rate)
    }

    @Test func bmrMatchesMifflinStJeorForMale() {
        let out = PlanCalculator.calculate(subject())
        // 10*82 + 6.25*175 - 5*34 + 5 = 820 + 1093.75 - 170 + 5 = 1748.75 → 1749
        #expect(out.bmr == 1749)
    }

    @Test func bmrMatchesMifflinStJeorForFemale() {
        let out = PlanCalculator.calculate(subject(sex: .female))
        // 1748.75 - 5 - 161 = 1582.75 → 1583
        #expect(out.bmr == 1583)
    }

    @Test func tdeeAppliesActivityMultiplier() {
        let out = PlanCalculator.calculate(subject(activity: .moderate))
        // 1748.75 * 1.55 = 2710.5625 → 2711
        #expect(out.tdee == 2711)
    }

    @Test func loseGoalAppliesDeficitFrom7700kcalPerKg() {
        let out = PlanCalculator.calculate(subject(goal: .lose, rate: 0.5))
        // deficit/day = 0.5 * 7700 / 7 = 550
        #expect(out.dailyDeltaKcal == -550)
        // target = 2711 - 550 = 2161
        #expect(out.dailyTargetKcal == 2161)
        #expect(out.hitFloor == false)
    }

    @Test func gainGoalAppliesSurplus() {
        let out = PlanCalculator.calculate(subject(goal: .gain, rate: 0.25))
        // surplus/day = 0.25 * 7700 / 7 = 275
        #expect(out.dailyDeltaKcal == 275)
    }

    @Test func maintainHasNoDelta() {
        let out = PlanCalculator.calculate(subject(goal: .maintain, rate: 0))
        #expect(out.dailyDeltaKcal == 0)
        #expect(out.dailyTargetKcal == out.tdee)
    }

    @Test func aggressiveDeficitClampsToSafeFloor() {
        // Small, light woman with max rate would dip below the floor.
        let input = PlanInput(heightCm: 150, weightKg: 45, age: 60, sex: .female,
                              activity: .sedentary, weeklyWorkouts: 0, goal: .lose,
                              weeklyRateKg: 0.75)
        let out = PlanCalculator.calculate(input)
        #expect(out.hitFloor == true)
        #expect(out.dailyTargetKcal == BiologicalSex.female.calorieFloor)
    }

    @Test func macrosAreInternallyConsistent() {
        let out = PlanCalculator.calculate(subject(goal: .lose, rate: 0.5))
        // Protein at 2.0 g/kg for a cut = 164g.
        #expect(out.proteinTargetG == 164)
        // Fat at 30% of target energy.
        let expectedFat = ((out.dailyTargetKcal * 0.30) / 9.0).rounded()
        #expect(out.fatTargetG == expectedFat)
        // Carbs never negative.
        #expect(out.carbsTargetG >= 0)
        // Fibre is the fixed UK guideline.
        #expect(out.fibreTargetG == 30)
        // Saturated fat ~11% of energy.
        let expectedSat = ((out.dailyTargetKcal * 0.11) / 9.0).rounded()
        #expect(out.satFatLimitG == expectedSat)
    }

    @Test func timelineToGoalIsHonest() {
        // Want to lose 6kg at 0.5kg/week → 12 weeks.
        #expect(PlanCalculator.weeksToGoal(deltaKg: 6, weeklyRateKg: 0.5) == 12)
        // Maintain / zero rate → no timeline.
        #expect(PlanCalculator.weeksToGoal(deltaKg: 0, weeklyRateKg: 0) == nil)
    }

    @Test func ageDerivesFromDateOfBirth() {
        var comps = DateComponents()
        comps.year = 1990; comps.month = 6; comps.day = 10
        let dob = Calendar.current.date(from: comps)!
        var on = DateComponents()
        on.year = 2026; on.month = 6; on.day = 10
        let onDate = Calendar.current.date(from: on)!
        #expect(PlanCalculator.age(from: dob, on: onDate) == 36)
    }
}
