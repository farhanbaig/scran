//
//  PlanEditView.swift
//  scran
//
//  Edit the plan inputs. Saving recalculates every number and invalidates the
//  cached explanation so the Plan Reveal regenerates it.
//

import SwiftUI
import SwiftData

struct PlanEditView: View {
    let plan: UserPlan
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    // Local editable copies so the live plan only changes on Save.
    @State private var sex: BiologicalSex
    @State private var dob: Date
    @State private var heightCm: Double
    @State private var weightKg: Double
    @State private var activity: ActivityLevel
    @State private var workouts: Int
    @State private var goal: Goal
    @State private var rate: Double

    init(plan: UserPlan) {
        self.plan = plan
        _sex = State(initialValue: plan.sex)
        _dob = State(initialValue: plan.dateOfBirth)
        _heightCm = State(initialValue: plan.heightCm)
        _weightKg = State(initialValue: plan.weightKg)
        _activity = State(initialValue: plan.activity)
        _workouts = State(initialValue: plan.weeklyWorkouts)
        _goal = State(initialValue: plan.goalEnum)
        _rate = State(initialValue: plan.weeklyRateKg == 0 ? 0.5 : plan.weeklyRateKg)
    }

    private var previewTarget: Double {
        PlanCalculator.calculate(
            PlanInput(heightCm: heightCm, weightKg: weightKg,
                      age: PlanCalculator.age(from: dob), sex: sex, activity: activity,
                      weeklyWorkouts: workouts, goal: goal,
                      weeklyRateKg: goal.usesRate ? rate : 0)).dailyTargetKcal
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                preview
                group("Sex") {
                    ScranSegmented(options: BiologicalSex.allCases.map { ($0, $0.label) }, selection: $sex)
                }
                group("Date of birth") {
                    DatePicker("", selection: $dob, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.compact).labelsHidden().tint(ScranColor.verified).colorScheme(.dark)
                }
                sliderGroup("Height", value: $heightCm, range: 140...210, step: 1) { "\(Int($0)) cm" }
                sliderGroup("Weight", value: $weightKg, range: 40...180, step: 0.5) { String(format: "%.1f kg", $0) }
                group("Activity") {
                    ScranSegmented(options: ActivityLevel.allCases.map { ($0, shortLabel($0)) }, selection: $activity)
                }
                group("Workouts per week") {
                    Stepper(value: $workouts, in: 0...14) {
                        Text("\(workouts)").font(ScranFont.mono(16, weight: .bold, relativeTo: .body))
                            .foregroundStyle(ScranColor.textPrimary)
                    }.tint(ScranColor.verified)
                }
                group("Goal") {
                    ScranSegmented(options: Goal.allCases.map { ($0, $0.label) }, selection: $goal)
                }
                if goal.usesRate {
                    group("Weekly rate") {
                        ScranSegmented(options: [(0.25, "0.25"), (0.5, "0.5"), (0.75, "0.75")], selection: $rate)
                    }
                }
            }
            .padding(20).padding(.bottom, 100)
        }
        .scranScreen()
        .navigationTitle("Edit plan")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Recalculate", systemImage: "function") { save() }
                .padding(20).background(.ultraThinMaterial)
        }
    }

    private var preview: some View {
        ScranCard(background: ScranColor.panel2) {
            HStack {
                Text("New daily target").font(ScranFont.body(14, relativeTo: .body))
                    .foregroundStyle(ScranColor.textMuted)
                Spacer()
                Text("\(ScranFormat.int(previewTarget)) kcal")
                    .font(ScranFont.mono(20, weight: .bold, relativeTo: .title3))
                    .foregroundStyle(ScranColor.verified)
                    .contentTransition(.numericText())
            }
            .animation(.snappy(duration: 0.2), value: previewTarget)
        }
    }

    private func group<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(ScranFont.body(13, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(ScranColor.textMuted)
            content()
        }
    }

    private func sliderGroup(_ label: String, value: Binding<Double>,
                             range: ClosedRange<Double>, step: Double,
                             format: @escaping (Double) -> String) -> some View {
        group(label) {
            HStack {
                Slider(value: value, in: range, step: step).tint(ScranColor.verified)
                Text(format(value.wrappedValue))
                    .font(ScranFont.mono(14, weight: .bold, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary).frame(width: 78, alignment: .trailing)
            }
        }
    }

    private func shortLabel(_ a: ActivityLevel) -> String {
        switch a {
        case .sedentary: return "Low"
        case .light:     return "Light"
        case .moderate:  return "Mod"
        case .active:    return "High"
        }
    }

    private func save() {
        plan.heightCm = heightCm
        plan.weightKg = weightKg
        plan.dateOfBirth = dob
        plan.biologicalSex = sex.rawValue
        plan.activityLevel = activity.rawValue
        plan.weeklyWorkouts = workouts
        plan.goal = goal.rawValue
        plan.weeklyRateKg = goal.usesRate ? rate : 0
        plan.recompute()   // recomputes targets, invalidates explanation, marks pending
        try? context.save()
        Haptics.success()
        let ctx = context
        Task { await app.sync.syncPending(context: ctx) }
        dismiss()
    }
}
