//
//  SyncQueue.swift
//  scran
//
//  Offline-first sync. Local SwiftData is the source of truth for UX; this
//  pushes `pending` rows to Supabase in the background. Last-write-wins on
//  conflicts (single-device assumption for v1). Deletes are soft (deleted_at).
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class SyncQueue {
    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Push everything marked pending. Safe to call repeatedly; no-ops offline.
    func syncPending(context: ModelContext) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        guard let userId = try? await SupabaseClient.shared.ensureSession().userId else {
            return // offline / not authenticated — try again later
        }

        await pushPlans(context: context, userId: userId)
        await pushFoodEntries(context: context, userId: userId)
        await pushSavedMeals(context: context, userId: userId)
        await pushWeights(context: context, userId: userId)

        lastSyncedAt = .now
    }

    // MARK: - Plans

    private func pushPlans(context: ModelContext, userId: String) async {
        let pending = SyncState.pending.rawValue
        let descriptor = FetchDescriptor<UserPlan>(
            predicate: #Predicate { $0.syncState == pending })
        guard let plans = try? context.fetch(descriptor), !plans.isEmpty else { return }

        let rows = plans.map { p -> [String: Any] in
            [
                "id": p.id.uuidString,
                "user_id": userId,
                "height_cm": p.heightCm,
                "weight_kg": p.weightKg,
                "date_of_birth": dayFormatter.string(from: p.dateOfBirth),
                "biological_sex": p.biologicalSex,
                "activity_level": p.activityLevel,
                "weekly_workouts": p.weeklyWorkouts,
                "goal": p.goal,
                "weekly_rate_kg": p.weeklyRateKg,
                "bmr": p.bmr, "tdee": p.tdee, "daily_target_kcal": p.dailyTargetKcal,
                "protein_target_g": p.proteinTargetG, "carbs_target_g": p.carbsTargetG,
                "fat_target_g": p.fatTargetG, "sat_fat_limit_g": p.satFatLimitG,
                "fibre_target_g": p.fibreTargetG,
                "explanation": p.explanation ?? NSNull(),
                "explanation_version": p.explanationVersion,
                "updated_at": iso.string(from: p.updatedAt),
            ]
        }
        if (try? await SupabaseClient.shared.upsert(table: "plans", rows: rows)) != nil {
            for p in plans { p.syncState = SyncState.synced.rawValue }
            try? context.save()
        }
    }

    // MARK: - Food entries

    private func pushFoodEntries(context: ModelContext, userId: String) async {
        let pending = SyncState.pending.rawValue
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.syncState == pending })
        guard let entries = try? context.fetch(descriptor), !entries.isEmpty else { return }

        let rows = entries.map { e -> [String: Any] in
            [
                "id": e.id.uuidString,
                "user_id": userId,
                "logged_at": iso.string(from: e.loggedAt),
                "name": e.name,
                "brand": e.brand ?? NSNull(),
                "source": e.source,
                "confidence": e.confidence ?? NSNull(),
                "barcode": e.barcode ?? NSNull(),
                "per100g": Self.nutrientDict(e.per100g),
                "serving_size_g": e.servingSizeG,
                "quantity": e.quantity,
                "photo_remote_path": e.photoRemotePath ?? NSNull(),
                "clarifications": e.clarifications,
                "deleted_at": e.deletedAt.map { iso.string(from: $0) } ?? NSNull(),
                "updated_at": iso.string(from: e.updatedAt),
            ]
        }
        if (try? await SupabaseClient.shared.upsert(table: "food_entries", rows: rows)) != nil {
            for e in entries { e.syncState = SyncState.synced.rawValue }
            try? context.save()
        }
    }

    // MARK: - Saved meals

    private func pushSavedMeals(context: ModelContext, userId: String) async {
        let pending = SyncState.pending.rawValue
        let descriptor = FetchDescriptor<SavedMeal>(
            predicate: #Predicate { $0.syncState == pending })
        guard let meals = try? context.fetch(descriptor), !meals.isEmpty else { return }

        let rows = meals.map { m -> [String: Any] in
            let items = m.items.map { item -> [String: Any] in
                [
                    "name": item.name, "brand": item.brand ?? NSNull(), "source": item.source,
                    "confidence": item.confidence ?? NSNull(),
                    "per100g": Self.nutrientDict(item.per100g),
                    "servingSizeG": item.servingSizeG, "quantity": item.quantity,
                ]
            }
            return [
                "id": m.id.uuidString,
                "user_id": userId,
                "name": m.name,
                "entries": items,
                "times_logged": m.timesLogged,
                "last_logged_at": m.lastLoggedAt.map { iso.string(from: $0) } ?? NSNull(),
                "deleted_at": m.deletedAt.map { iso.string(from: $0) } ?? NSNull(),
                "updated_at": iso.string(from: m.updatedAt),
            ]
        }
        if (try? await SupabaseClient.shared.upsert(table: "saved_meals", rows: rows)) != nil {
            for m in meals { m.syncState = SyncState.synced.rawValue }
            try? context.save()
        }
    }

    // MARK: - Weights

    private func pushWeights(context: ModelContext, userId: String) async {
        let pending = SyncState.pending.rawValue
        let descriptor = FetchDescriptor<WeightEntry>(
            predicate: #Predicate { $0.syncState == pending })
        guard let weights = try? context.fetch(descriptor), !weights.isEmpty else { return }

        let rows = weights.map { w -> [String: Any] in
            [
                "id": w.id.uuidString,
                "user_id": userId,
                "date": dayFormatter.string(from: w.date),
                "weight_kg": w.weightKg,
                "deleted_at": w.deletedAt.map { iso.string(from: $0) } ?? NSNull(),
            ]
        }
        if (try? await SupabaseClient.shared.upsert(table: "weight_entries", rows: rows)) != nil {
            for w in weights { w.syncState = SyncState.synced.rawValue }
            try? context.save()
        }
    }

    // MARK: - Helpers

    static func nutrientDict(_ n: NutrientBlock) -> [String: Any] {
        [
            "kcal": n.kcal, "proteinG": n.proteinG, "carbsG": n.carbsG, "fatG": n.fatG,
            "satFatG": n.satFatG ?? NSNull(), "fibreG": n.fibreG ?? NSNull(),
            "sugarG": n.sugarG ?? NSNull(), "saltG": n.saltG ?? NSNull(),
        ]
    }
}
