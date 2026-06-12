//
//  OnboardingData.swift
//  scran
//
//  Onboarding state + the extra "engagement" enums modelled on the Cal AI funnel
//  but kept honest: every answer either feeds the plan / AI prompt or is stored
//  to the profile — nothing is collected as theatre.
//

import Foundation
import SwiftUI
import Observation

// MARK: - Engagement enums

enum HeightUnit: String, CaseIterable, Sendable { case ftIn, cm
    var label: String { self == .ftIn ? "ft, in" : "cm" }
}
enum WeightUnit: String, CaseIterable, Sendable { case lb, kg
    var label: String { self == .lb ? "lbs" : "kg" }
}

enum Motivation: String, CaseIterable, Identifiable, Sendable {
    case healthier, energy, consistency, body
    var id: String { rawValue }
    var label: String {
        switch self {
        case .healthier:   return "Eat and live healthier"
        case .energy:      return "Boost my energy and mood"
        case .consistency: return "Stay motivated and consistent"
        case .body:        return "Feel better about my body"
        }
    }
    var icon: String {
        switch self {
        case .healthier:   return "leaf.fill"
        case .energy:      return "sun.max.fill"
        case .consistency: return "figure.strengthtraining.traditional"
        case .body:        return "figure.mind.and.body"
        }
    }
}

enum Blocker: String, CaseIterable, Identifiable, Sendable {
    case consistency, eating, support, schedule, inspiration
    var id: String { rawValue }
    var label: String {
        switch self {
        case .consistency: return "Lack of consistency"
        case .eating:      return "Unhealthy eating habits"
        case .support:     return "Lack of support"
        case .schedule:    return "Busy schedule"
        case .inspiration: return "Lack of meal inspiration"
        }
    }
    var icon: String {
        switch self {
        case .consistency: return "chart.bar.fill"
        case .eating:      return "takeoutbag.and.cup.and.straw.fill"
        case .support:     return "hands.clap.fill"
        case .schedule:    return "calendar"
        case .inspiration: return "fork.knife"
        }
    }
}

enum DietType: String, CaseIterable, Identifiable, Sendable {
    case balanced, wholeFood, mediterranean, flexitarian, pescatarian, vegetarian, vegan
    var id: String { rawValue }
    var label: String {
        switch self {
        case .balanced:      return "Balanced"
        case .wholeFood:     return "Whole-food focus"
        case .mediterranean: return "Mediterranean"
        case .flexitarian:   return "Flexitarian"
        case .pescatarian:   return "Pescatarian"
        case .vegetarian:    return "Vegetarian"
        case .vegan:         return "Vegan"
        }
    }
    var icon: String {
        switch self {
        case .balanced:      return "fork.knife"
        case .wholeFood:     return "carrot.fill"
        case .mediterranean: return "leaf.fill"
        case .flexitarian:   return "arrow.triangle.2.circlepath"
        case .pescatarian:   return "fish.fill"
        case .vegetarian:    return "leaf.circle.fill"
        case .vegan:         return "tree.fill"
        }
    }
}

/// What the user wants to keep an eye on. Drives which numbers get surfaced on
/// the daily view — a user-chosen *lens*, not a medical condition mapping. Stays
/// firmly in the wellness lane: we surface facts, we never diagnose or prescribe.
enum FocusArea: String, CaseIterable, Identifiable, Sendable {
    case weight, heart, bloodSugar, protein, gut
    var id: String { rawValue }
    var label: String {
        switch self {
        case .weight:     return "Weight & calories"
        case .heart:      return "Heart — sat fat, salt, fibre"
        case .bloodSugar: return "Blood sugar — carbs & sugar"
        case .protein:    return "Protein & strength"
        case .gut:        return "Gut health & fibre"
        }
    }
    var icon: String {
        switch self {
        case .weight:     return "scalemass.fill"
        case .heart:      return "heart.fill"
        case .bloodSugar: return "drop.fill"
        case .protein:    return "figure.strengthtraining.traditional"
        case .gut:        return "leaf.fill"
        }
    }
}

enum ReferralSource: String, CaseIterable, Identifiable, Sendable {
    case tiktok, instagram, youtube, appStore, friend, x, web, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tiktok:    return "TikTok"
        case .instagram: return "Instagram"
        case .youtube:   return "YouTube"
        case .appStore:  return "App Store"
        case .friend:    return "Friend or family"
        case .x:         return "X"
        case .web:       return "Web search"
        case .other:     return "Other"
        }
    }
    var icon: String {
        switch self {
        case .tiktok:    return "music.note"
        case .instagram: return "camera.fill"
        case .youtube:   return "play.rectangle.fill"
        case .appStore:  return "apple.logo"
        case .friend:    return "person.2.fill"
        case .x:         return "bird.fill"
        case .web:       return "magnifyingglass"
        case .other:     return "ellipsis"
        }
    }
}

// MARK: - Draft

@MainActor
@Observable
final class OnboardingDraft {
    // Core plan inputs (feed PlanCalculator)
    var sex: BiologicalSex = .male
    var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    var heightCm: Double = 175
    var weightKg: Double = 80
    var activity: ActivityLevel = .moderate
    var weeklyWorkouts: Int = 4
    var goal: Goal = .lose
    var weeklyRateKg: Double = 0.5
    var targetWeightKg: Double = 75

    // Units (display only; storage stays metric)
    var heightUnit: HeightUnit = .cm
    var weightUnit: WeightUnit = .kg

    // Engagement answers (stored to profile; some enrich the explain-plan prompt)
    var motivations: Set<Motivation> = []
    var blockers: Set<Blocker> = []
    var diet: DietType? = nil
    var triedOtherApps: Bool? = nil
    var worksWithPro: Bool? = nil
    var referral: ReferralSource? = nil

    // What to keep an eye on. Defaults to weight so the baseline view is unchanged.
    var focusAreas: Set<FocusArea> = [.weight]

    var input: PlanInput {
        PlanInput(heightCm: heightCm, weightKg: weightKg,
                  age: PlanCalculator.age(from: dateOfBirth), sex: sex, activity: activity,
                  weeklyWorkouts: weeklyWorkouts, goal: goal,
                  weeklyRateKg: goal.usesRate ? weeklyRateKg : 0)
    }

    func makePlan() -> UserPlan {
        let out = PlanCalculator.calculate(input)
        return UserPlan(heightCm: heightCm, weightKg: weightKg, dateOfBirth: dateOfBirth,
                        biologicalSex: sex.rawValue, activityLevel: activity.rawValue,
                        weeklyWorkouts: weeklyWorkouts, goal: goal.rawValue,
                        weeklyRateKg: goal.usesRate ? weeklyRateKg : 0,
                        bmr: out.bmr, tdee: out.tdee, dailyTargetKcal: out.dailyTargetKcal,
                        proteinTargetG: out.proteinTargetG, carbsTargetG: out.carbsTargetG,
                        fatTargetG: out.fatTargetG, satFatLimitG: out.satFatLimitG,
                        fibreTargetG: out.fibreTargetG,
                        focusAreas: focusAreas.map(\.rawValue))
    }

    /// Compact context passed to explain-plan so the AI copy can acknowledge the
    /// user's stated goal, blockers and diet — honestly, not as a gimmick.
    var promptContext: [String: Any] {
        [
            "motivations": motivations.map(\.rawValue),
            "blockers": blockers.map(\.rawValue),
            "diet": diet?.rawValue as Any,
            "focusAreas": focusAreas.map(\.rawValue),
        ]
    }
}
