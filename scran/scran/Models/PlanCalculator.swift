//
//  PlanCalculator.swift
//  scran
//
//  Mifflin-St Jeor BMR → activity → goal deficit/surplus → daily target, plus
//  macro / saturated-fat / fibre targets. Pure and fully unit-tested. This is
//  the maths the Plan Reveal screen puts on screen (LAW 2).
//

import Foundation

/// Inputs to the calculator. Decoupled from SwiftData so it stays testable.
struct PlanInput: Sendable, Equatable {
    var heightCm: Double
    var weightKg: Double
    var age: Int
    var sex: BiologicalSex
    var activity: ActivityLevel
    var weeklyWorkouts: Int
    var goal: Goal
    /// kg/week. 0.25 / 0.5 / 0.75. Ignored when goal == .maintain.
    var weeklyRateKg: Double
}

/// Computed outputs, all rounded for display where appropriate.
struct PlanOutput: Sendable, Equatable {
    var bmr: Double
    var tdee: Double
    var dailyDeltaKcal: Double      // negative for deficit, positive for surplus
    var dailyTargetKcal: Double
    var proteinTargetG: Double
    var carbsTargetG: Double
    var fatTargetG: Double
    var satFatLimitG: Double
    var fibreTargetG: Double
    var hitFloor: Bool              // true when target was clamped to the safe floor
}

enum PlanCalculator {

    /// Energy density of body mass used for deficit/surplus maths (kcal per kg).
    static let kcalPerKg: Double = 7700
    static let fibreTargetG: Double = 30        // UK guideline
    static let satFatEnergyFraction: Double = 0.11   // SACN ~11% of energy

    static func age(from dateOfBirth: Date, on date: Date = Date()) -> Int {
        Calendar.current.dateComponents([.year], from: dateOfBirth, to: date).year ?? 0
    }

    static func calculate(_ input: PlanInput) -> PlanOutput {
        // Mifflin-St Jeor
        let bmr = 10 * input.weightKg + 6.25 * input.heightCm
            - 5 * Double(input.age) + input.sex.mifflinConstant
        let tdee = bmr * input.activity.multiplier

        // Goal adjustment
        let dailyDelta: Double
        switch input.goal {
        case .maintain: dailyDelta = 0
        case .lose:     dailyDelta = -(input.weeklyRateKg * kcalPerKg / 7.0)
        case .gain:     dailyDelta =  (input.weeklyRateKg * kcalPerKg / 7.0)
        }

        let rawTarget = tdee + dailyDelta
        let floor = input.sex.calorieFloor
        let hitFloor = input.goal == .lose && rawTarget < floor
        let target = max(rawTarget, floor)

        // Macros
        // Protein scales with bodyweight and goal (higher when cutting).
        let proteinPerKg: Double = {
            switch input.goal {
            case .lose:     return 2.0
            case .maintain: return 1.6
            case .gain:     return 1.8
            }
        }()
        let protein = input.weightKg * proteinPerKg
        // Fat at 30% of energy.
        let fat = (target * 0.30) / 9.0
        // Carbs fill the remainder; never negative.
        let proteinKcal = protein * 4
        let fatKcal = fat * 9
        let carbs = max(0, (target - proteinKcal - fatKcal) / 4.0)

        let satFat = (target * satFatEnergyFraction) / 9.0

        return PlanOutput(
            bmr: bmr.rounded(),
            tdee: tdee.rounded(),
            dailyDeltaKcal: dailyDelta.rounded(),
            dailyTargetKcal: target.rounded(),
            proteinTargetG: protein.rounded(),
            carbsTargetG: carbs.rounded(),
            fatTargetG: fat.rounded(),
            satFatLimitG: (satFat).rounded(),
            fibreTargetG: fibreTargetG,
            hitFloor: hitFloor
        )
    }

    /// Honest projected timeline to a target weight change, in weeks.
    /// Returns nil for maintain or zero rate.
    static func weeksToGoal(deltaKg: Double, weeklyRateKg: Double) -> Int? {
        guard weeklyRateKg > 0, deltaKg > 0 else { return nil }
        return Int((deltaKg / weeklyRateKg).rounded(.up))
    }
}
