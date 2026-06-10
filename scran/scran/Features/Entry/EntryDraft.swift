//
//  EntryDraft.swift
//  scran
//
//  Editable working copy of a food entry, shared by every logging path. Totals
//  are always derived from per100g × grams, so any edit recomputes everything.
//

import Foundation
import SwiftUI
import Observation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class EntryDraft {
    var name: String
    var brand: String?
    var source: EntrySource
    var confidence: Double?
    var barcode: String?
    var per100g: NutrientBlock
    var servingSizeG: Double
    var quantity: Double
    var clarifications: [String]
    var warnings: [String]
    #if canImport(UIKit)
    var photo: UIImage?
    #endif

    var saveAsMeal: Bool = false
    var mealName: String = ""

    init(name: String = "", brand: String? = nil, source: EntrySource = .manual,
         confidence: Double? = nil, barcode: String? = nil,
         per100g: NutrientBlock = .zero, servingSizeG: Double = 100, quantity: Double = 1,
         clarifications: [String] = [], warnings: [String] = []) {
        self.name = name; self.brand = brand; self.source = source
        self.confidence = confidence; self.barcode = barcode; self.per100g = per100g
        self.servingSizeG = servingSizeG; self.quantity = quantity
        self.clarifications = clarifications; self.warnings = warnings
    }

    var totalGrams: Double { servingSizeG * quantity }
    var total: NutrientBlock { per100g.scaled(toGrams: totalGrams) }

    var canLog: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && servingSizeG > 0 }

    // MARK: - Factories

    static func fromLabel(_ r: LabelScanResult) -> EntryDraft {
        EntryDraft(name: r.productName ?? "Label scan", source: .label,
                   per100g: r.per100g, servingSizeG: r.servingSizeG > 0 ? r.servingSizeG : 100,
                   warnings: r.warnings)
    }

    static func fromBarcode(_ r: BarcodeLookupResult) -> EntryDraft {
        EntryDraft(name: r.product?.name ?? "Product", brand: r.product?.brand,
                   source: .barcode, barcode: r.product?.barcode,
                   per100g: r.per100g ?? .zero,
                   servingSizeG: r.servingSizeG ?? 100)
    }

    static func fromPlateItem(_ item: PlateScanResult.Item, clarifications: [String]) -> EntryDraft {
        EntryDraft(name: item.name, source: .estimate, confidence: item.confidence,
                   per100g: item.per100g, servingSizeG: item.estimatedGrams,
                   clarifications: clarifications)
    }

    func makeFoodEntry() -> FoodEntry {
        FoodEntry(name: name.trimmingCharacters(in: .whitespaces),
                  brand: brand?.isEmpty == true ? nil : brand,
                  source: source.rawValue, confidence: confidence, barcode: barcode,
                  per100g: per100g, servingSizeG: servingSizeG, quantity: quantity,
                  clarifications: clarifications)
    }
}
