//
//  FocusLens.swift
//  scran
//
//  The focus-area lens system. A user picks what to keep an eye on during
//  onboarding (see `FocusArea`); this file turns those choices into the extra
//  numbers and guidance the app surfaces — daily budgets on Today and per-meal
//  insight in the entry sheet.
//
//  Wellness lane, on purpose: every line here is DESCRIPTIVE (what's in the food,
//  general nutrition education) — never a diagnosis, never a target set on the
//  user's behalf, never "this treats your condition". Facts and education only.
//

import SwiftUI

// MARK: - Focus nutrient

/// A single nutrient a focus area cares about, measured against an everyday
/// public-health guideline, with one line of honest, non-prescriptive education.
enum FocusNutrient: String, CaseIterable, Identifiable {
    case satFat, salt, sugar, fibre
    var id: String { rawValue }

    /// Compact label for the Today budget bars.
    var short: String {
        switch self {
        case .satFat: return "SAT FAT"
        case .salt:   return "SALT"
        case .sugar:  return "SUGAR"
        case .fibre:  return "FIBRE"
        }
    }

    /// Full label for the per-meal insight rows.
    var label: String {
        switch self {
        case .satFat: return "Saturated fat"
        case .salt:   return "Salt"
        case .sugar:  return "Sugar"
        case .fibre:  return "Fibre"
        }
    }

    /// True when lower is better (a limit). Fibre is the one we aim *up* toward.
    var isLimit: Bool { self != .fibre }

    var tint: Color {
        switch self {
        case .satFat: return ScranColor.error
        case .salt:   return ScranColor.estimate
        case .sugar:  return ScranColor.database
        case .fibre:  return ScranColor.verified
        }
    }

    /// One-line, wellness-safe education — general nutrition info only.
    var education: String {
        switch self {
        case .satFat:
            return "Of everything you eat, saturated fat has the biggest link to LDL (\u{201C}bad\u{201D}) cholesterol. Swapping it for unsaturated fats — olive oil, nuts, oily fish — is the usual swap."
        case .salt:
            return "Eating less salt is linked to healthier blood pressure. UK guidance is to stay under 6g of salt a day for adults."
        case .sugar:
            return "Free sugars raise blood glucose the fastest. Pairing them with fibre, protein or fat softens the rise."
        case .fibre:
            return "Fibre supports heart and gut health and helps steady blood sugar — most adults fall short of around 30g a day. Oats, beans, lentils and wholegrains are rich sources."
        }
    }

    /// Amount of this nutrient in a block (a single meal, or a whole day's total).
    func amount(in b: NutrientBlock) -> Double {
        switch self {
        case .satFat: return b.satFatG ?? 0
        case .salt:   return b.saltG ?? 0
        case .sugar:  return b.sugarG ?? 0
        case .fibre:  return b.fibreG ?? 0
        }
    }

    /// Daily reference: prefer the user's computed plan target where one exists,
    /// otherwise an everyday UK public-health guideline.
    func dailyTarget(_ plan: UserPlan) -> Double {
        switch self {
        case .satFat: return plan.satFatLimitG
        case .fibre:  return plan.fibreTargetG
        case .salt:   return 6      // NHS adult maximum
        case .sugar:  return 30     // NHS free-sugars guidance
        }
    }
}

// MARK: - Meal-level classification

/// How notable this nutrient is in a single meal, relative to a day's guideline.
enum NutrientLevel {
    case low, moderate, high, good   // `good` = a meaningful win for an aim-up nutrient

    var label: String {
        switch self {
        case .low:      return "LOW"
        case .moderate: return "SOME"
        case .high:     return "HIGH"
        case .good:     return "GOOD"
        }
    }
}

extension FocusNutrient {
    /// Classify how much of the daily guideline a single meal contributes.
    func level(forMeal amount: Double, plan: UserPlan) -> NutrientLevel {
        let daily = dailyTarget(plan)
        guard daily > 0 else { return .low }
        let frac = amount / daily
        if isLimit {
            if frac >= 0.5  { return .high }
            if frac >= 0.25 { return .moderate }
            return .low
        } else {
            // Aim-up nutrient (fibre): a single meal giving a quarter of the day is a win.
            return frac >= 0.25 ? .good : .low
        }
    }

    /// Colour for a meal-level badge. Limits go amber/red as they climb; the
    /// aim-up nutrient goes green when the meal lands a good amount.
    func color(for level: NutrientLevel) -> Color {
        switch level {
        case .high:     return ScranColor.error
        case .moderate: return ScranColor.estimate
        case .good:     return ScranColor.verified
        case .low:      return isLimit ? ScranColor.verified : ScranColor.textMuted
        }
    }
}

// MARK: - Plan → nutrients

extension FocusArea {
    /// Nutrients this lens surfaces *beyond* the calorie ring and protein/carbs/fat
    /// bars that every user already sees. Weight & Protein add nothing extra
    /// because the ring and the protein bar already cover them.
    var nutrients: [FocusNutrient] {
        switch self {
        case .heart:      return [.satFat, .salt, .fibre]
        case .bloodSugar: return [.sugar, .fibre]
        case .gut:        return [.fibre]
        case .weight, .protein: return []
        }
    }
}

extension UserPlan {
    /// Ordered, de-duplicated nutrients to surface, from the chosen focus areas.
    /// Order follows `FocusArea.allCases`, so it's stable across launches.
    var focusNutrients: [FocusNutrient] {
        var seen = Set<FocusNutrient>()
        var out: [FocusNutrient] = []
        for area in FocusArea.allCases where focus.contains(area) {
            for n in area.nutrients where !seen.contains(n) {
                seen.insert(n); out.append(n)
            }
        }
        return out
    }

    /// The single most attention-worthy limit nutrient in a meal, if any meal-level
    /// is `.high` — used for the compact flag on the Today list row.
    func highFlag(for meal: NutrientBlock) -> FocusNutrient? {
        focusNutrients.first { $0.isLimit && $0.level(forMeal: $0.amount(in: meal), plan: self) == .high }
    }
}

// MARK: - Today: focus budget grid

/// The "YOUR FOCUS" section under the macro bars on Today. Renders one budget bar
/// per surfaced nutrient (deduped across all chosen lenses) in an even 3-up grid.
struct FocusBudgetGrid: View {
    let plan: UserPlan
    let consumed: NutrientBlock

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 22, alignment: .leading), count: 3)

    var body: some View {
        let nutrients = plan.focusNutrients
        if !nutrients.isEmpty {
            VStack(spacing: 16) {
                Rectangle().fill(ScranColor.line).frame(height: 1)
                HStack {
                    Label("YOUR FOCUS", systemImage: "scope")
                        .font(ScranFont.mono(11, weight: .bold, relativeTo: .caption2))
                        .tracking(1.2).foregroundStyle(ScranColor.textMuted)
                    Spacer()
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(nutrients) { n in
                        MacroBar(label: n.short, consumed: n.amount(in: consumed),
                                 target: n.dailyTarget(plan), tint: n.tint)
                    }
                }
            }
        }
    }
}

// MARK: - Entry sheet: per-meal focus insight

/// "FOR YOUR FOCUS" card in the entry detail sheet. For each surfaced nutrient it
/// shows this meal's amount, a plain-language level, and one line of education —
/// the point-of-decision assistance, kept strictly descriptive.
struct FocusInsightCard: View {
    let meal: NutrientBlock
    let plan: UserPlan

    var body: some View {
        let nutrients = plan.focusNutrients
        if !nutrients.isEmpty {
            ScranCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("FOR YOUR FOCUS")
                        .font(ScranFont.mono(11, weight: .bold, relativeTo: .caption2))
                        .tracking(1.2).foregroundStyle(ScranColor.textMuted)

                    ForEach(nutrients) { n in
                        let amount = n.amount(in: meal)
                        let level = n.level(forMeal: amount, plan: plan)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Circle().fill(n.tint).frame(width: 8, height: 8)
                                Text(n.label)
                                    .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                                    .foregroundStyle(ScranColor.textPrimary)
                                Spacer()
                                Text(ScranFormat.grams(amount))
                                    .font(ScranFont.mono(14, weight: .bold, relativeTo: .body))
                                    .foregroundStyle(ScranColor.textPrimary)
                                LevelChip(text: level.label, color: n.color(for: level))
                            }
                            Text(n.education)
                                .font(ScranFont.body(12, relativeTo: .caption))
                                .foregroundStyle(ScranColor.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if n.id != nutrients.last?.id {
                            Rectangle().fill(ScranColor.line).frame(height: 1)
                        }
                    }

                    Text("General nutrition info, not medical advice. Your doctor's guidance comes first.")
                        .font(ScranFont.mono(11, relativeTo: .caption2))
                        .foregroundStyle(ScranColor.textMuted)
                        .padding(.top, 2)
                }
            }
        }
    }
}

/// Small pill used for meal-level labels (HIGH / SOME / GOOD …).
struct LevelChip: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(ScranFont.mono(10, weight: .bold, relativeTo: .caption2))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}
