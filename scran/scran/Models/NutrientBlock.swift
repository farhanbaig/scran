//
//  NutrientBlock.swift
//  scran
//
//  Per-100g nutrition, the unit of truth. Totals are ALWAYS recomputed from
//  per100g × grams — changing a portion changes every number (the exact Cal AI
//  failure mode we exist to fix).
//

import Foundation

struct NutrientBlock: Codable, Hashable, Sendable {
    var kcal: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var satFatG: Double?
    var fibreG: Double?
    var sugarG: Double?
    var saltG: Double?

    init(kcal: Double = 0, proteinG: Double = 0, carbsG: Double = 0, fatG: Double = 0,
         satFatG: Double? = nil, fibreG: Double? = nil, sugarG: Double? = nil, saltG: Double? = nil) {
        self.kcal = kcal; self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG
        self.satFatG = satFatG; self.fibreG = fibreG; self.sugarG = sugarG; self.saltG = saltG
    }

    static let zero = NutrientBlock()

    /// Scale per-100g values to an absolute amount in grams.
    func scaled(toGrams grams: Double) -> NutrientBlock {
        let f = grams / 100.0
        return NutrientBlock(
            kcal: kcal * f, proteinG: proteinG * f, carbsG: carbsG * f, fatG: fatG * f,
            satFatG: satFatG.map { $0 * f }, fibreG: fibreG.map { $0 * f },
            sugarG: sugarG.map { $0 * f }, saltG: saltG.map { $0 * f }
        )
    }

    static func + (lhs: NutrientBlock, rhs: NutrientBlock) -> NutrientBlock {
        func add(_ a: Double?, _ b: Double?) -> Double? {
            if a == nil && b == nil { return nil }
            return (a ?? 0) + (b ?? 0)
        }
        return NutrientBlock(
            kcal: lhs.kcal + rhs.kcal, proteinG: lhs.proteinG + rhs.proteinG,
            carbsG: lhs.carbsG + rhs.carbsG, fatG: lhs.fatG + rhs.fatG,
            satFatG: add(lhs.satFatG, rhs.satFatG), fibreG: add(lhs.fibreG, rhs.fibreG),
            sugarG: add(lhs.sugarG, rhs.sugarG), saltG: add(lhs.saltG, rhs.saltG)
        )
    }
}
