//
//  OnboardingFlow.swift
//  scran
//
//  Screen 1. Four steps, one question per screen: about you → activity →
//  goal + rate → Plan Reveal. Nothing is persisted until "Start logging".
//

import SwiftUI
import SwiftData
import Observation

@MainActor
@Observable
final class OnboardingDraft {
    var sex: BiologicalSex = .male
    var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    var heightCm: Double = 175
    var weightKg: Double = 80
    var activity: ActivityLevel = .moderate
    var weeklyWorkouts: Int = 3
    var goal: Goal = .lose
    var weeklyRateKg: Double = 0.5
    var targetWeightKg: Double = 75

    var input: PlanInput {
        PlanInput(heightCm: heightCm, weightKg: weightKg,
                  age: PlanCalculator.age(from: dateOfBirth), sex: sex, activity: activity,
                  weeklyWorkouts: weeklyWorkouts, goal: goal,
                  weeklyRateKg: goal.usesRate ? weeklyRateKg : 0)
    }

    func makePlan() -> UserPlan {
        let out = PlanCalculator.calculate(input)
        return UserPlan(heightCm: heightCm, weightKg: weightKg, dateOfBirth: dateOfBirth,
                        biologicalSex: sex.rawValue, activityLevel: activity.rawValue,
                        weeklyWorkouts: weeklyWorkouts, goal: goal.rawValue,
                        weeklyRateKg: goal.usesRate ? weeklyRateKg : 0,
                        bmr: out.bmr, tdee: out.tdee, dailyTargetKcal: out.dailyTargetKcal,
                        proteinTargetG: out.proteinTargetG, carbsTargetG: out.carbsTargetG,
                        fatTargetG: out.fatTargetG, satFatLimitG: out.satFatLimitG,
                        fibreTargetG: out.fibreTargetG)
    }
}

struct OnboardingFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app

    @State private var draft = OnboardingDraft()
    @State private var step = 0
    @State private var revealPlan: UserPlan? = nil
    @State private var showReveal = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressDots(count: 3, index: step).padding(.top, 8)

                TabView(selection: $step) {
                    AboutYouStep(draft: draft).tag(0)
                    ActivityStep(draft: draft).tag(1)
                    GoalStep(draft: draft).tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.snappy, value: step)

                footer
            }
            .scranScreen()
            .navigationDestination(isPresented: $showReveal) {
                if let revealPlan {
                    PlanRevealView(plan: revealPlan, primaryTitle: "Start logging") {
                        finishOnboarding(revealPlan)
                    }
                    .navigationBarBackButtonHidden(true)
                }
            }
            .onAppear { app.analytics.track(.onboardingStarted) }
        }
        .tint(ScranColor.verified)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            PrimaryButton(title: step < 2 ? "Continue" : "See my plan") {
                if step < 2 {
                    withAnimation { step += 1 }
                } else {
                    revealPlan = draft.makePlan()
                    showReveal = true
                }
            }
            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
                    .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(ScranColor.textMuted)
            }
        }
        .padding(20)
    }

    private func finishOnboarding(_ plan: UserPlan) {
        context.insert(plan)
        try? context.save()
        app.analytics.track(.planCreated(goal: plan.goal, rate: plan.weeklyRateKg))
        app.analytics.track(.onboardingCompleted)
        Haptics.success()
        let ctx = context
        Task { await app.sync.syncPending(context: ctx) }
    }
}

// MARK: - Steps

private struct AboutYouStep: View {
    @Bindable var draft: OnboardingDraft
    var body: some View {
        StepScaffold(eyebrow: "About you", title: "The basics") {
            VStack(spacing: 20) {
                LabeledControl("Sex") {
                    ScranSegmented(options: BiologicalSex.allCases.map { ($0, $0.label) },
                                   selection: $draft.sex)
                }
                LabeledControl("Date of birth") {
                    DatePicker("", selection: $draft.dateOfBirth, in: ...Date(),
                               displayedComponents: .date)
                        .datePickerStyle(.compact).labelsHidden().tint(ScranColor.verified)
                        .colorScheme(.dark)
                }
                SliderControl(label: "Height", value: $draft.heightCm, range: 140...210,
                              step: 1, format: { "\(Int($0)) cm" })
                SliderControl(label: "Weight", value: $draft.weightKg, range: 40...180,
                              step: 0.5, format: { String(format: "%.1f kg", $0) })
            }
        }
    }
}

private struct ActivityStep: View {
    @Bindable var draft: OnboardingDraft
    var body: some View {
        StepScaffold(eyebrow: "Movement", title: "How active are you?") {
            VStack(spacing: 12) {
                ForEach(ActivityLevel.allCases) { level in
                    SelectableRow(title: level.label, subtitle: level.blurb,
                                  selected: draft.activity == level) {
                        draft.activity = level; Haptics.selection()
                    }
                }
                LabeledControl("Workouts per week") {
                    Stepper(value: $draft.weeklyWorkouts, in: 0...14) {
                        Text("\(draft.weeklyWorkouts)")
                            .font(ScranFont.mono(16, weight: .bold, relativeTo: .body))
                            .foregroundStyle(ScranColor.textPrimary)
                    }
                    .tint(ScranColor.verified)
                }
                .padding(.top, 6)
            }
        }
    }
}

private struct GoalStep: View {
    @Bindable var draft: OnboardingDraft
    var body: some View {
        StepScaffold(eyebrow: "Your goal", title: "What are you after?") {
            VStack(spacing: 16) {
                ScranSegmented(options: Goal.allCases.map { ($0, $0.label) },
                               selection: $draft.goal)
                if draft.goal.usesRate {
                    LabeledControl("Weekly rate") {
                        ScranSegmented(options: [(0.25, "0.25 kg"), (0.5, "0.5 kg"), (0.75, "0.75 kg")],
                                       selection: $draft.weeklyRateKg)
                    }
                    SliderControl(label: draft.goal == .lose ? "Target weight" : "Target weight",
                                  value: $draft.targetWeightKg, range: 40...180, step: 0.5,
                                  format: { String(format: "%.1f kg", $0) })
                }
                Text("// the faster the rate, the tighter the daily target")
                    .font(ScranFont.mono(12, relativeTo: .caption))
                    .foregroundStyle(ScranColor.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Reusable step pieces

private struct StepScaffold<Content: View>: View {
    let eyebrow: String
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Eyebrow(text: eyebrow, color: ScranColor.verified, ruleColor: ScranColor.verified)
                Text(title)
                    .font(ScranFont.display(34, relativeTo: .largeTitle)).textCase(.uppercase)
                    .foregroundStyle(ScranColor.textPrimary)
                content
            }
            .padding(20)
        }
    }
}

private struct LabeledControl<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(ScranFont.body(13, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(ScranColor.textMuted)
            content
        }
    }
}

private struct SliderControl: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(ScranFont.body(13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(ScranColor.textMuted)
                Spacer()
                Text(format(value)).font(ScranFont.mono(14, weight: .bold, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary)
            }
            Slider(value: $value, in: range, step: step).tint(ScranColor.verified)
        }
    }
}

private struct SelectableRow: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(ScranFont.body(16, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(ScranColor.textPrimary)
                    Text(subtitle).font(ScranFont.body(13, relativeTo: .footnote))
                        .foregroundStyle(ScranColor.textMuted)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? ScranColor.verified : ScranColor.lineStrong)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16)
                .fill(selected ? ScranColor.verifiedDim : ScranColor.panel))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(selected ? ScranColor.verified.opacity(0.5) : ScranColor.line, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

struct ProgressDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i <= index ? ScranColor.verified : ScranColor.lineStrong)
                    .frame(width: i == index ? 22 : 8, height: 6)
                    .animation(.snappy, value: index)
            }
        }
    }
}
