//
//  Models.swift
//  scran
//
//  SwiftData models — the local source of truth for UX. Offline-first: all
//  writes land locally first, then a sync queue pushes to Supabase.
//

import Foundation
import SwiftData

// MARK: - UserPlan

@Model
final class UserPlan {
    @Attribute(.unique) var id: UUID
    var heightCm: Double
    var weightKg: Double            // current weight — drives the live plan maths
    /// The weight the journey began at — a fixed baseline for "started at / since
    /// start", independent of later weigh-ins. Defaults to 0 for plans created
    /// before this field existed; `journeyStartWeightKg` falls back to weightKg.
    var startWeightKg: Double = 0
    var dateOfBirth: Date
    var biologicalSex: String      // BiologicalSex.rawValue
    var activityLevel: String      // ActivityLevel.rawValue
    var weeklyWorkouts: Int
    var goal: String               // Goal.rawValue
    var weeklyRateKg: Double
    var bmr: Double
    var tdee: Double
    var dailyTargetKcal: Double
    var proteinTargetG: Double
    var carbsTargetG: Double
    var fatTargetG: Double
    var satFatLimitG: Double
    var fibreTargetG: Double
    var focusAreas: [String]       // FocusArea.rawValue — user-chosen daily-view lenses
    var explanation: String?
    var explanationVersion: Int
    var createdAt: Date
    var updatedAt: Date
    var syncState: String

    init(id: UUID = UUID(), heightCm: Double, weightKg: Double, startWeightKg: Double? = nil,
         dateOfBirth: Date,
         biologicalSex: String, activityLevel: String, weeklyWorkouts: Int, goal: String,
         weeklyRateKg: Double, bmr: Double, tdee: Double, dailyTargetKcal: Double,
         proteinTargetG: Double, carbsTargetG: Double, fatTargetG: Double,
         satFatLimitG: Double, fibreTargetG: Double, focusAreas: [String] = [],
         explanation: String? = nil,
         explanationVersion: Int = 0, createdAt: Date = .now, updatedAt: Date = .now,
         syncState: String = SyncState.pending.rawValue) {
        self.id = id; self.heightCm = heightCm; self.weightKg = weightKg
        self.startWeightKg = startWeightKg ?? weightKg
        self.dateOfBirth = dateOfBirth; self.biologicalSex = biologicalSex
        self.activityLevel = activityLevel; self.weeklyWorkouts = weeklyWorkouts
        self.goal = goal; self.weeklyRateKg = weeklyRateKg; self.bmr = bmr; self.tdee = tdee
        self.dailyTargetKcal = dailyTargetKcal; self.proteinTargetG = proteinTargetG
        self.carbsTargetG = carbsTargetG; self.fatTargetG = fatTargetG
        self.satFatLimitG = satFatLimitG; self.fibreTargetG = fibreTargetG
        self.focusAreas = focusAreas
        self.explanation = explanation; self.explanationVersion = explanationVersion
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.syncState = syncState
    }

    var sex: BiologicalSex { BiologicalSex(rawValue: biologicalSex) ?? .male }
    var activity: ActivityLevel { ActivityLevel(rawValue: activityLevel) ?? .moderate }
    var goalEnum: Goal { Goal(rawValue: goal) ?? .maintain }
    var age: Int { PlanCalculator.age(from: dateOfBirth) }

    /// Decoded focus-area lenses the user chose during onboarding.
    var focus: Set<FocusArea> { Set(focusAreas.compactMap(FocusArea.init(rawValue:))) }

    var input: PlanInput {
        PlanInput(heightCm: heightCm, weightKg: weightKg, age: age, sex: sex,
                  activity: activity, weeklyWorkouts: weeklyWorkouts, goal: goalEnum,
                  weeklyRateKg: weeklyRateKg)
    }

    /// Fixed journey baseline. Falls back to current weight for legacy plans.
    var journeyStartWeightKg: Double { startWeightKg > 0 ? startWeightKg : weightKg }

    /// The daily calorie target this plan would set at a given body weight — used
    /// to show how the target shifts as weight changes (start → now).
    func dailyTarget(atWeightKg w: Double) -> Double {
        var i = input
        i.weightKg = w
        return PlanCalculator.calculate(i).dailyTargetKcal
    }

    /// Recompute all derived numbers from current inputs and stamp a new version.
    func recompute() {
        let out = PlanCalculator.calculate(input)
        bmr = out.bmr; tdee = out.tdee; dailyTargetKcal = out.dailyTargetKcal
        proteinTargetG = out.proteinTargetG; carbsTargetG = out.carbsTargetG
        fatTargetG = out.fatTargetG; satFatLimitG = out.satFatLimitG
        fibreTargetG = out.fibreTargetG
        explanationVersion += 1
        explanation = nil   // invalidate cached copy; re-fetch from explain-plan
        updatedAt = .now
        syncState = SyncState.pending.rawValue
    }
}

// MARK: - FoodEntry

@Model
final class FoodEntry {
    @Attribute(.unique) var id: UUID
    var loggedAt: Date
    var name: String
    var brand: String?
    var source: String             // EntrySource.rawValue
    var confidence: Double?
    var barcode: String?
    var per100g: NutrientBlock
    var servingSizeG: Double
    var quantity: Double
    var photoLocalPath: String?
    var photoRemotePath: String?
    var clarifications: [String]
    var syncState: String
    var deletedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), loggedAt: Date = .now, name: String, brand: String? = nil,
         source: String, confidence: Double? = nil, barcode: String? = nil,
         per100g: NutrientBlock, servingSizeG: Double, quantity: Double = 1,
         photoLocalPath: String? = nil, photoRemotePath: String? = nil,
         clarifications: [String] = [], syncState: String = SyncState.pending.rawValue,
         deletedAt: Date? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id; self.loggedAt = loggedAt; self.name = name; self.brand = brand
        self.source = source; self.confidence = confidence; self.barcode = barcode
        self.per100g = per100g; self.servingSizeG = servingSizeG; self.quantity = quantity
        self.photoLocalPath = photoLocalPath; self.photoRemotePath = photoRemotePath
        self.clarifications = clarifications; self.syncState = syncState
        self.deletedAt = deletedAt; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    var sourceEnum: EntrySource { EntrySource(rawValue: source) ?? .manual }

    /// The grams this entry represents. Totals ALWAYS derive from this.
    var totalGrams: Double { servingSizeG * quantity }

    /// Recomputed nutrition for the logged amount. Never stored — always derived.
    var total: NutrientBlock { per100g.scaled(toGrams: totalGrams) }

    var mealtime: Mealtime { Mealtime.from(date: loggedAt) }
}

// MARK: - SavedMeal

/// Independent snapshot of an entry's nutrition (not a live relationship).
struct SavedMealItem: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var brand: String?
    var source: String
    var confidence: Double?
    var per100g: NutrientBlock
    var servingSizeG: Double
    var quantity: Double
    /// Local photo of the original entry, if any — additive optional, so rows
    /// saved before this field existed decode as nil.
    var photoLocalPath: String? = nil

    var sourceEnum: EntrySource { EntrySource(rawValue: source) ?? .saved }
    var total: NutrientBlock { per100g.scaled(toGrams: servingSizeG * quantity) }

    init(from entry: FoodEntry) {
        self.name = entry.name; self.brand = entry.brand; self.source = entry.source
        self.confidence = entry.confidence; self.per100g = entry.per100g
        self.servingSizeG = entry.servingSizeG; self.quantity = entry.quantity
        self.photoLocalPath = entry.photoLocalPath
    }

    /// Build a fresh FoodEntry to log this snapshot at a given time. The photo
    /// carries over, so a re-logged meal keeps its picture.
    func makeEntry(loggedAt: Date = .now) -> FoodEntry {
        FoodEntry(loggedAt: loggedAt, name: name, brand: brand, source: source,
                  confidence: confidence, per100g: per100g, servingSizeG: servingSizeG,
                  quantity: quantity, photoLocalPath: photoLocalPath, clarifications: [])
    }
}

@Model
final class SavedMeal {
    @Attribute(.unique) var id: UUID
    var name: String
    var items: [SavedMealItem]
    var timesLogged: Int
    var lastLoggedAt: Date?
    var syncState: String
    var deletedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, items: [SavedMealItem] = [], timesLogged: Int = 0,
         lastLoggedAt: Date? = nil, syncState: String = SyncState.pending.rawValue,
         deletedAt: Date? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id; self.name = name; self.items = items; self.timesLogged = timesLogged
        self.lastLoggedAt = lastLoggedAt; self.syncState = syncState
        self.deletedAt = deletedAt; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    var total: NutrientBlock { items.reduce(NutrientBlock.zero) { $0 + $1.total } }
}

// MARK: - WeightEntry

@Model
final class WeightEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var weightKg: Double
    var syncState: String
    var deletedAt: Date?

    init(id: UUID = UUID(), date: Date = .now, weightKg: Double,
         syncState: String = SyncState.pending.rawValue, deletedAt: Date? = nil) {
        self.id = id; self.date = date; self.weightKg = weightKg
        self.syncState = syncState; self.deletedAt = deletedAt
    }
}

// MARK: - Supporting types

enum SyncState: String, Sendable {
    case pending, synced, failed
}

enum Mealtime: String, CaseIterable, Sendable {
    case breakfast, lunch, dinner, snack

    var label: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch:     return "Lunch"
        case .dinner:    return "Dinner"
        case .snack:     return "Snacks"
        }
    }

    var order: Int {
        switch self {
        case .breakfast: return 0
        case .lunch:     return 1
        case .dinner:    return 2
        case .snack:     return 3
        }
    }

    static func from(date: Date) -> Mealtime {
        let h = Calendar.current.component(.hour, from: date)
        switch h {
        case 4..<11:  return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default:      return .snack
        }
    }
}
