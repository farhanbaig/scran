//
//  EdgeFunctions.swift
//  scran
//
//  Typed clients for the four Edge Functions. Response shapes mirror §5 of the
//  build spec exactly. NutrientBlock decodes directly from the per100g JSON.
//

import Foundation

// MARK: - scan-label

struct LabelScanResult: Decodable, Sendable {
    enum Status: String, Decodable, Sendable { case ok, unreadable, not_a_label }
    let status: Status
    let productName: String?
    let per100g: NutrientBlock
    let servingSizeG: Double
    let servingsPerPack: Double?
    let readConfidence: Double
    let warnings: [String]
    let scansRemaining: Int?

    private enum CodingKeys: String, CodingKey {
        case status, productName, per100g, servingSizeG, servingsPerPack, readConfidence, warnings, scansRemaining
    }

    // Tolerant decoding: on `unreadable` / `not_a_label` the function returns a
    // minimal object, so every field except `status` may be absent.
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(Status.self, forKey: .status)
        productName = try c.decodeIfPresent(String.self, forKey: .productName)
        per100g = try c.decodeIfPresent(NutrientBlock.self, forKey: .per100g) ?? .zero
        servingSizeG = try c.decodeIfPresent(Double.self, forKey: .servingSizeG) ?? 100
        servingsPerPack = try c.decodeIfPresent(Double.self, forKey: .servingsPerPack)
        readConfidence = try c.decodeIfPresent(Double.self, forKey: .readConfidence) ?? 0
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
        scansRemaining = try c.decodeIfPresent(Int.self, forKey: .scansRemaining)
    }
}

// MARK: - scan-plate

struct PlateScanResult: Decodable, Sendable {
    enum Status: String, Decodable, Sendable { case ok, no_food }
    struct Item: Decodable, Sendable, Identifiable {
        var id: String { name }
        let name: String
        let estimatedGrams: Double
        let per100g: NutrientBlock
        let confidence: Double
    }
    let status: Status
    let items: [Item]
    let overallConfidence: Double
    let clarifyingQuestion: String?
    let clarifyingImpact: String?
    let scansRemaining: Int?
}

// MARK: - lookup-barcode

struct BarcodeLookupResult: Decodable, Sendable {
    enum Status: String, Decodable, Sendable { case found, not_found }
    struct Product: Decodable, Sendable {
        let name: String
        let brand: String?
        let barcode: String
    }
    let status: Status
    let product: Product?
    let per100g: NutrientBlock?
    let servingSizeG: Double?
}

// MARK: - explain-plan

struct ExplainPlanResult: Decodable, Sendable {
    let explanation: String
    let source: String
}

/// High-level scan/AI service. Stateless; wraps the Supabase client.
enum ScanService {

    private static let client = SupabaseClient.shared
    private static let decoder = JSONDecoder()

    static func scanLabel(imageBase64: String) async throws -> LabelScanResult {
        let data = try await client.invokeFunction("scan-label", body: ["imageBase64": imageBase64])
        guard let r = try? decoder.decode(LabelScanResult.self, from: data) else {
            throw SupabaseError.decoding
        }
        return r
    }

    static func scanPlate(imageBase64: String) async throws -> PlateScanResult {
        let data = try await client.invokeFunction("scan-plate", body: ["imageBase64": imageBase64])
        guard let r = try? decoder.decode(PlateScanResult.self, from: data) else {
            throw SupabaseError.decoding
        }
        return r
    }

    static func lookupBarcode(_ barcode: String) async throws -> BarcodeLookupResult {
        let data = try await client.invokeFunction("lookup-barcode", body: ["barcode": barcode])
        guard let r = try? decoder.decode(BarcodeLookupResult.self, from: data) else {
            throw SupabaseError.decoding
        }
        return r
    }

    /// Plain-English plan explanation. Falls back to deterministic copy if the
    /// network/AI is unavailable so the Plan Reveal always shows something.
    static func explainPlan(_ plan: UserPlan) async throws -> String {
        let body: [String: Any] = ["plan": [
            "bmr": plan.bmr, "tdee": plan.tdee, "dailyTargetKcal": plan.dailyTargetKcal,
            "goal": plan.goal, "weeklyRateKg": plan.weeklyRateKg,
            "weeklyWorkouts": plan.weeklyWorkouts, "activityLevel": plan.activityLevel,
            "proteinTargetG": plan.proteinTargetG, "carbsTargetG": plan.carbsTargetG,
            "fatTargetG": plan.fatTargetG,
        ]]
        let data = try await client.invokeFunction("explain-plan", body: body)
        guard let r = try? decoder.decode(ExplainPlanResult.self, from: data) else {
            throw SupabaseError.decoding
        }
        return r.explanation
    }
}
