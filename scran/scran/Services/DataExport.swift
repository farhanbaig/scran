//
//  DataExport.swift
//  scran
//
//  CSV export (a free trust feature — your food log belongs to you) and full
//  account deletion. Export writes a temp file for the share sheet.
//

import Foundation
import SwiftData

enum DataExport {

    /// Build a CSV of all (non-deleted) food entries and write it to a temp file.
    @MainActor
    static func exportCSV(context: ModelContext) throws -> URL {
        let descriptor = FetchDescriptor<FoodEntry>(
            sortBy: [SortDescriptor(\.loggedAt, order: .forward)])
        let entries = (try? context.fetch(descriptor))?.filter { $0.deletedAt == nil } ?? []

        let iso = ISO8601DateFormatter()
        var rows = ["logged_at,name,brand,source,confidence,serving_g,quantity,kcal,protein_g,carbs_g,fat_g,satfat_g,fibre_g,sugar_g,salt_g"]
        for e in entries {
            let t = e.total
            let fields: [String] = [
                iso.string(from: e.loggedAt),
                csvEscape(e.name),
                csvEscape(e.brand ?? ""),
                e.source,
                e.confidence.map { String(format: "%.2f", $0) } ?? "",
                String(format: "%.0f", e.servingSizeG),
                String(format: "%.2f", e.quantity),
                String(format: "%.0f", t.kcal),
                String(format: "%.1f", t.proteinG),
                String(format: "%.1f", t.carbsG),
                String(format: "%.1f", t.fatG),
                t.satFatG.map { String(format: "%.1f", $0) } ?? "",
                t.fibreG.map { String(format: "%.1f", $0) } ?? "",
                t.sugarG.map { String(format: "%.1f", $0) } ?? "",
                t.saltG.map { String(format: "%.2f", $0) } ?? "",
            ]
            rows.append(fields.joined(separator: ","))
        }

        let csv = rows.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scran-export-\(Int(Date().timeIntervalSince1970)).csv")
        try csv.data(using: .utf8)?.write(to: url)
        return url
    }

    /// Build a CSV of all (non-deleted) weight entries, oldest first.
    @MainActor
    static func exportWeightsCSV(context: ModelContext) throws -> URL {
        let descriptor = FetchDescriptor<WeightEntry>(
            sortBy: [SortDescriptor(\.date, order: .forward)])
        let entries = (try? context.fetch(descriptor))?.filter { $0.deletedAt == nil } ?? []

        let iso = ISO8601DateFormatter()
        var rows = ["date,weight_kg"]
        for e in entries {
            rows.append("\(iso.string(from: e.date)),\(String(format: "%.2f", e.weightKg))")
        }

        let csv = rows.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clearo-weights-\(Int(Date().timeIntervalSince1970)).csv")
        try csv.data(using: .utf8)?.write(to: url)
        return url
    }

    private static func csvEscape(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

enum AccountService {
    /// Full server-side wipe via the delete-account Edge Function, then clears
    /// the local store and session.
    @MainActor
    static func deleteAccount(context: ModelContext) async throws {
        _ = try await SupabaseClient.shared.invokeFunction("delete-account", body: [:])
        // Wipe local data.
        try context.delete(model: FoodEntry.self)
        try context.delete(model: SavedMeal.self)
        try context.delete(model: WeightEntry.self)
        try context.delete(model: UserPlan.self)
        try context.save()
        await SupabaseClient.shared.signOutAndWipeLocalSession()
    }
}
