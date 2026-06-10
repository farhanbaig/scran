//
//  Enums.swift
//  scran
//
//  Plan inputs as typed enums with their raw string values matching the
//  SwiftData / Postgres columns.
//

import Foundation

enum BiologicalSex: String, CaseIterable, Identifiable, Sendable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? "Male" : "Female" }
    /// Used for Mifflin-St Jeor only.
    var mifflinConstant: Double { self == .male ? 5 : -161 }
    /// Responsible minimum daily intake floor (NHS-aligned).
    var calorieFloor: Double { self == .male ? 1500 : 1200 }
}

enum ActivityLevel: String, CaseIterable, Identifiable, Sendable {
    case sedentary, light, moderate, active
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sedentary: return "Sedentary"
        case .light:     return "Lightly active"
        case .moderate:  return "Moderately active"
        case .active:    return "Very active"
        }
    }
    var blurb: String {
        switch self {
        case .sedentary: return "Desk job, little exercise"
        case .light:     return "Light exercise 1–3 days/week"
        case .moderate:  return "Exercise 3–5 days/week"
        case .active:    return "Hard exercise 6–7 days/week"
        }
    }
    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light:     return 1.375
        case .moderate:  return 1.55
        case .active:    return 1.725
        }
    }
}

enum Goal: String, CaseIterable, Identifiable, Sendable {
    case lose, maintain, gain
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lose:     return "Lose weight"
        case .maintain: return "Maintain"
        case .gain:     return "Gain weight"
        }
    }
    var verb: String {
        switch self {
        case .lose:     return "lose"
        case .maintain: return "maintain"
        case .gain:     return "gain"
        }
    }
    var usesRate: Bool { self != .maintain }
}
