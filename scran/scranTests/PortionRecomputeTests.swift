//
//  PortionRecomputeTests.swift
//  scranTests
//
//  The headline acceptance criterion: changing serving size or quantity
//  recomputes every nutrient, always. (The exact Cal AI failure we fix.)
//

import Testing
import Foundation
@testable import scran

@MainActor
struct PortionRecomputeTests {

    // Aldi Greek yogurt per 100g: 93 kcal, 5.6g protein.
    private let yogurt = NutrientBlock(kcal: 93, proteinG: 5.6, carbsG: 4.0, fatG: 5.0,
                                       satFatG: 3.3, fibreG: 0, sugarG: 4.0, saltG: 0.1)

    @Test func scalingToServingSize() {
        let scaled = yogurt.scaled(toGrams: 150)
        #expect(abs(scaled.kcal - 139.5) < 0.001)
        #expect(abs(scaled.proteinG - 8.4) < 0.001)
        #expect(abs((scaled.saltG ?? 0) - 0.15) < 0.001)
    }

    @Test func changingServingSizeChangesEveryNumber() {
        let entry = FoodEntry(name: "Greek yogurt", source: EntrySource.label.rawValue,
                              per100g: yogurt, servingSizeG: 100, quantity: 1)
        let before = entry.total
        entry.servingSizeG = 170
        let after = entry.total
        #expect(after.kcal > before.kcal)
        #expect(after.proteinG > before.proteinG)
        #expect(after.fatG > before.fatG)
        #expect(abs(after.kcal - 158.1) < 0.001)
    }

    @Test func changingQuantityScalesTotals() {
        let entry = FoodEntry(name: "Greek yogurt", source: EntrySource.label.rawValue,
                              per100g: yogurt, servingSizeG: 100, quantity: 1)
        entry.quantity = 2
        #expect(entry.totalGrams == 200)
        #expect(abs(entry.total.kcal - 186) < 0.001)
    }

    @Test func nilNutrientsStayNil() {
        let sparse = NutrientBlock(kcal: 200, proteinG: 10, carbsG: 20, fatG: 5)
        let scaled = sparse.scaled(toGrams: 50)
        #expect(scaled.fibreG == nil)
        #expect(scaled.saltG == nil)
        #expect(abs(scaled.kcal - 100) < 0.001)
    }

    @Test func summingEntriesAddsOptionalsCorrectly() {
        let a = NutrientBlock(kcal: 100, proteinG: 5, carbsG: 10, fatG: 2, satFatG: 1)
        let b = NutrientBlock(kcal: 50, proteinG: 3, carbsG: 4, fatG: 1, satFatG: nil, fibreG: 2)
        let sum = a + b
        #expect(sum.kcal == 150)
        #expect(sum.satFatG == 1)      // 1 + nil → 1
        #expect(sum.fibreG == 2)       // nil + 2 → 2
        #expect(sum.sugarG == nil)     // nil + nil → nil
    }

    @Test func savedMealRoundTripsThroughSnapshot() {
        let entry = FoodEntry(name: "Daal", source: EntrySource.estimate.rawValue,
                              confidence: 0.7, per100g: yogurt, servingSizeG: 250, quantity: 1)
        let snapshot = SavedMealItem(from: entry)
        let relogged = snapshot.makeEntry()
        #expect(relogged.name == "Daal")
        #expect(relogged.servingSizeG == 250)
        #expect(abs(relogged.total.kcal - entry.total.kcal) < 0.001)
    }
}
