//
//  PlanRevealView.swift
//  scran
//
//  Screen 2 — the signature screen. Radial green glow, an Archivo Black headline,
//  the equation in Space Mono, the Claude-written explanation, the exercise
//  sentence highlighted, macro/satfat/fibre targets, and an honest timeline.
//

import SwiftUI
import SwiftData

struct PlanRevealView: View {
    @Bindable var plan: UserPlan
    var primaryTitle: String = "Start logging"
    var onPrimary: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var explanation: String? = nil
    @State private var loadingExplanation = true

    static let exerciseSentence =
        "Your weekly exercise is already included in this target — logging a workout will not add calories back."

    private var delta: Double { plan.dailyTargetKcal - plan.tdee }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                EquationBlock(rows: equationRows)
                explanationSection
                exerciseCallout
                targetsCard
                timelineCard
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background(
            ScranColor.bg.ignoresSafeArea()
                .overlay(alignment: .top) { RadialGlow().offset(y: -120) }
        )
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: primaryTitle, systemImage: "arrow.right") { onPrimary() }
                .padding(20).scranBottomBar()
        }
        .navigationTitle("Your plan")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadExplanation() }
        // Pinned CTA needs the full bottom edge; harmless outside a TabView
        // (e.g. during onboarding).
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "Your plan", color: ScranColor.verified, ruleColor: ScranColor.verified)
            Text("Your plan, with the working")
                .font(ScranFont.display(40, relativeTo: .largeTitle))
                .textCase(.uppercase)
                .lineSpacing(-2)
                .foregroundStyle(ScranColor.textPrimary)
            if plan.bmr == 0 { ProgressView().tint(ScranColor.verified) }
        }
    }

    // MARK: - Equation

    private var equationRows: [EquationRow] {
        var rows: [EquationRow] = [
            EquationRow(label: "Base metabolism (BMR)", value: ScranFormat.kcalText(plan.bmr)),
            EquationRow(label: "× activity (\(plan.weeklyWorkouts) workouts/wk)",
                        value: ScranFormat.kcalText(plan.tdee)),
        ]
        switch plan.goalEnum {
        case .lose:
            rows.append(EquationRow(label: "− deficit (\(rateText) /week)",
                                    value: "−\(ScranFormat.int(abs(delta))) kcal"))
        case .gain:
            rows.append(EquationRow(label: "+ surplus (\(rateText) /week)",
                                    value: "+\(ScranFormat.int(abs(delta))) kcal"))
        case .maintain:
            rows.append(EquationRow(label: "maintenance", value: "±0 kcal"))
        }
        rows.append(EquationRow(label: "Daily target",
                                value: "\(ScranFormat.int(plan.dailyTargetKcal)) kcal/day",
                                isTotal: true))
        return rows
    }

    private var rateText: String {
        plan.weeklyRateKg == plan.weeklyRateKg.rounded()
            ? "\(Int(plan.weeklyRateKg)) kg"
            : String(format: "%.2g kg", plan.weeklyRateKg)
    }

    // MARK: - Explanation

    private var explanationSection: some View {
        ScranCard {
            if loadingExplanation && explanation == nil {
                HStack(spacing: 10) {
                    ProgressView().tint(ScranColor.verified)
                    Text("Writing your explanation…")
                        .font(ScranFont.body(14, relativeTo: .body))
                        .foregroundStyle(ScranColor.textMuted)
                }
            } else {
                Text(explanation ?? localFallback)
                    .font(ScranFont.body(16, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary)
                    .lineSpacing(4)
            }
        }
    }

    private var exerciseCallout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(ScranColor.verified)
            Text(Self.exerciseSentence)
                .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                .foregroundStyle(ScranColor.textPrimary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(ScranColor.verifiedDim))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ScranColor.verified.opacity(0.35)))
    }

    // MARK: - Targets

    private var targetsCard: some View {
        ScranCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Daily targets")
                targetRow("Protein", ScranFormat.grams(plan.proteinTargetG))
                targetRow("Carbohydrate", ScranFormat.grams(plan.carbsTargetG))
                targetRow("Fat", ScranFormat.grams(plan.fatTargetG))
                targetRow("Saturated fat (limit)", "≤ \(ScranFormat.grams(plan.satFatLimitG))")
                targetRow("Fibre", ScranFormat.grams(plan.fibreTargetG))
            }
        }
    }

    private func targetRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(ScranFont.body(14, relativeTo: .body))
                .foregroundStyle(ScranColor.textMuted)
            Spacer()
            Text(value).font(ScranFont.mono(14, weight: .bold, relativeTo: .body))
                .foregroundStyle(ScranColor.textPrimary)
        }
    }

    // MARK: - Timeline

    private var timelineCard: some View {
        let projection = abs(delta) > 0 ? plan.weeklyRateKg * 12 : 0
        return ScranCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Projected")
                if projection > 0 {
                    Text("At \(rateText)/week, about \(String(format: "%.1f", projection)) kg over 12 weeks.")
                        .font(ScranFont.body(15, relativeTo: .body))
                        .foregroundStyle(ScranColor.textPrimary)
                } else {
                    Text("Holding steady at maintenance.")
                        .font(ScranFont.body(15, relativeTo: .body))
                        .foregroundStyle(ScranColor.textPrimary)
                }
                Text("// estimates drift; we'll recalibrate from your data in a future update")
                    .font(ScranFont.mono(12, relativeTo: .caption))
                    .foregroundStyle(ScranColor.textMuted)
            }
        }
    }

    // MARK: - Data

    private func loadExplanation() async {
        if let cached = plan.explanation, !cached.isEmpty {
            explanation = cached; loadingExplanation = false; return
        }
        loadingExplanation = true
        do {
            let text = try await ScanService.explainPlan(plan)
            explanation = text
            plan.explanation = text
            // Persist only if the plan is in the store (settings edit path).
            if plan.modelContext != nil { try? context.save() }
        } catch {
            explanation = localFallback
        }
        app.analytics.track(.planExplanationViewed)
        loadingExplanation = false
    }

    private var localFallback: String {
        let g = plan.goalEnum.verb
        return [
            "Your body burns about \(ScranFormat.int(plan.bmr)) kcal a day at rest — your base metabolism from your height, weight, age and sex. Factoring in how active you are brings your daily burn to roughly \(ScranFormat.int(plan.tdee)) kcal.",
            "To \(g == "maintain" ? "maintain your weight" : "\(g) weight") at the rate you chose, your daily target is \(ScranFormat.int(plan.dailyTargetKcal)) kcal. \(Self.exerciseSentence)",
            "These are honest estimates, not lab measurements — real bodies vary. Log consistently and the numbers will tell you whether to nudge the target up or down.",
        ].joined(separator: "\n\n")
    }
}
