//
//  OnboardingFlow.swift
//  scran
//
//  Data-driven onboarding funnel. The order lives in `steps` — reorder or
//  A/B-test by editing that array, not the views. Full honest-momentum flow
//  ending at the Plan Reveal payoff. No account wall (anonymous auth), no fake
//  loaders, no pre-checked opt-ins.
//

import SwiftUI
import SwiftData

enum OnboardingStep: Hashable {
    case welcome
    case health
    case sex, dob, height, weight
    case activity, workouts
    case goal, rate
    case socialProof
    case motivations, blockers, diet, focusAreas
    case triedApps, worksPro, referral
    case trust, notifications
    case account
    case loading, reveal
}

struct OnboardingFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app

    @State private var draft = OnboardingDraft()
    @State private var step: OnboardingStep = .welcome
    @State private var revealPlan: UserPlan?
    @State private var healthImporting = false
    @State private var healthImported = false
    @State private var showSignIn = false

    /// Ordered funnel. Rate step is conditional on a non-maintain goal.
    private var steps: [OnboardingStep] {
        var s: [OnboardingStep] = [.welcome]
        if HealthKitService.isSupported { s.append(.health) }
        s += [.sex, .dob, .height, .weight, .activity, .workouts, .goal]
        if draft.goal.usesRate { s.append(.rate) }
        s += [.socialProof, .motivations, .blockers, .diet, .focusAreas, .triedApps,
              .worksPro, .referral, .trust, .notifications]
        // Ask for an account at the end — after the questions, before we build
        // and save the plan. Skipped if already signed in.
        if !app.isAuthenticated { s.append(.account) }
        s += [.loading, .reveal]
        return s
    }

    private var index: Int { steps.firstIndex(of: step) ?? 0 }

    /// Progress excludes welcome and the reveal payoff.
    private var progress: Double {
        let total = max(1, steps.count - 2)
        return min(1, Double(max(0, index)) / Double(total))
    }

    var body: some View {
        content
            .animation(.snappy(duration: 0.25), value: step)
            .onAppear { app.analytics.track(.onboardingStarted) }
            .fullScreenCover(isPresented: $showSignIn) {
                AuthView(startInSignIn: true,
                         onComplete: { showSignIn = false },
                         onBack: { showSignIn = false })
                    .scranAppearance()
            }
    }

    // MARK: - Routing

    private func advance() {
        Haptics.tap()
        if step == .loading { return } // loading advances itself
        let next = steps[min(index + 1, steps.count - 1)]
        withAnimation { step = next }
    }

    private func back() {
        let prev = steps[max(index - 1, 0)]
        withAnimation { step = prev }
    }

    private var backAction: (() -> Void)? {
        if index <= 0 {
            return nil
        } else {
            return back
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        contentView
    }
    
    @ViewBuilder private var contentView: some View {
        @Bindable var d = draft
        switch step {
        case .welcome:
            WelcomeScreen(onStart: { advance() }, onSignIn: { showSignIn = true })

        case .health:
            OnboardingScaffold(
                progress: progress, onBack: backAction,
                title: "Connect to Apple Health",
                subtitle: "Sync your activity, sleep and weight between Clearo and the Health app — read-only, for the most complete picture.",
                ctaTitle: healthImported ? "Continue" : (healthImporting ? "Connecting…" : "Connect Apple Health"),
                ctaEnabled: !healthImporting,
                secondaryTitle: "Skip",
                onSecondary: advance,
                onContinue: {
                    if healthImported { advance() }
                    else { Task { await importHealth(into: d) } }
                }) {
                VStack(spacing: 20) {
                    HealthSyncArt().frame(maxWidth: .infinity)
                    if healthImported {
                        Label("Imported \(importedSummary(d))", systemImage: "checkmark.circle.fill")
                            .font(ScranFont.body(14, weight: .semibold, relativeTo: .footnote))
                            .foregroundStyle(ScranColor.verified)
                    }
                }
            }

        case .sex:
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "Choose your sex",
                               subtitle: "Used only for the Mifflin-St Jeor metabolism formula.",
                               ctaEnabled: true, onContinue: advance) {
                VStack(spacing: 12) {
                    ChoiceCard(title: "Male", systemIcon: "person.fill",
                               isSelected: d.sex == .male) { d.sex = .male }
                    ChoiceCard(title: "Female", systemIcon: "person.fill",
                               isSelected: d.sex == .female) { d.sex = .female }
                }
            }

        case .dob:
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "When were you born?",
                               subtitle: "Age factors into your daily energy calculation.",
                               onContinue: advance) {
                DOBPicker(date: $d.dateOfBirth).frame(maxWidth: .infinity)
            }

        case .height:
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "What is your height?",
                               onContinue: advance) {
                HeightPicker(heightCm: $d.heightCm, unit: $d.heightUnit).frame(maxWidth: .infinity)
            }

        case .weight:
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "What is your weight?",
                               onContinue: advance) {
                VStack(spacing: 18) {
                    ScranSegmented(options: WeightUnit.allCases.map { ($0, $0.label) },
                                   selection: $d.weightUnit).frame(maxWidth: 240)
                    if d.weightUnit == .kg {
                        RulerSlider(value: $d.weightKg, range: 35...200, step: 0.1, unit: "kg")
                    } else {
                        let lbBinding = Binding<Double>(
                            get: { d.weightKg * 2.2046226 },
                            set: { d.weightKg = $0 / 2.2046226 }
                        )
                        RulerSlider(value: lbBinding, range: 77...440, step: 0.2, unit: "lbs")
                    }
                }
            }

        case .activity:
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "How active are you?",
                               onContinue: advance) {
                VStack(spacing: 12) {
                    ForEach(ActivityLevel.allCases) { lvl in
                        ChoiceCard(title: lvl.label, subtitle: lvl.blurb,
                                   systemIcon: "figure.walk",
                                   isSelected: d.activity == lvl) { d.activity = lvl }
                    }
                }
            }

        case .workouts:
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "How many workouts per week?",
                               subtitle: "This calibrates your plan — and we never add the calories back.",
                               onContinue: advance) {
                VStack(spacing: 12) {
                    workoutCard("0–2", "Now and then", value: 1)
                    workoutCard("3–5", "A few workouts a week", value: 4)
                    workoutCard("6+", "Dedicated athlete", value: 6)
                }
            }

        case .goal:
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "What is your goal?",
                               subtitle: "This shapes your calorie target — shown with full working.",
                               onContinue: advance) {
                VStack(spacing: 12) {
                    ChoiceCard(title: "Lose weight", systemIcon: "arrow.down",
                               isSelected: d.goal == .lose) { d.goal = .lose }
                    ChoiceCard(title: "Maintain", systemIcon: "minus",
                               isSelected: d.goal == .maintain) { d.goal = .maintain }
                    ChoiceCard(title: "Gain weight", systemIcon: "arrow.up",
                               isSelected: d.goal == .gain) { d.goal = .gain }
                }
            }

        case .rate:
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "How fast?",
                               subtitle: "A faster rate means a tighter daily target. 0.5 kg/week is a sustainable default.",
                               onContinue: advance) {
                VStack(spacing: 18) {
                    ScranSegmented(options: [(0.25, "0.25 kg"), (0.5, "0.5 kg"), (0.75, "0.75 kg")],
                                   selection: $d.weeklyRateKg)
                    Text("per week")
                        .font(ScranFont.body(13, relativeTo: .footnote))
                        .foregroundStyle(ScranColor.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

        case .socialProof:
            SocialProofScreen(progress: progress, onBack: backAction, onContinue: advance)

        case .motivations:
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "What would you like to accomplish?",
                               subtitle: "Pick any that fit — we'll reflect these in your plan.",
                               ctaEnabled: !d.motivations.isEmpty, onContinue: advance) {
                MultiSelectList(options: Motivation.allCases, selection: $d.motivations,
                                label: \.label, icon: { $0.icon })
            }

        case .blockers:
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "What's stopping you from reaching your goals?",
                               ctaEnabled: !d.blockers.isEmpty, onContinue: advance) {
                MultiSelectList(options: Blocker.allCases, selection: $d.blockers,
                                label: \.label, icon: { $0.icon })
            }

        case .diet:
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "Do you follow a specific diet?",
                               ctaEnabled: d.diet != nil, onContinue: advance) {
                SingleSelectList(options: DietType.allCases, selection: $d.diet,
                                 label: \.label, icon: { $0.icon })
            }

        case .focusAreas:
            // Focus areas can imply health information, so this step collects
            // explicit UK GDPR consent: informed copy + an affirmative Continue.
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "What do you want to keep an eye on?",
                               subtitle: "We'll surface the right numbers on your daily view — like saturated fat and fibre if you're watching your heart. General nutrition info, not medical advice. Because these choices can relate to your health, they're stored securely as health data, used only to personalise your numbers, and never for advertising. Tapping Continue gives your consent — you can change or clear them any time.",
                               ctaEnabled: !d.focusAreas.isEmpty,
                               onContinue: {
                                   UserDefaults.standard.set(Date.now.timeIntervalSince1970,
                                                             forKey: "clearo.healthDataConsentAt")
                                   advance()
                               }) {
                MultiSelectList(options: FocusArea.allCases, selection: $d.focusAreas,
                                label: \.label, icon: { $0.icon })
            }

        case .triedApps:
            yesNo(title: "Have you tried other calorie tracking apps?",
                  subtitle: nil, value: $d.triedOtherApps)

        case .worksPro:
            yesNo(title: "Do you work with a personal trainer or dietitian?",
                  subtitle: "We'll make your data easy to export and share.", value: $d.worksWithPro)

        case .referral:
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "Where did you hear about us?",
                               ctaEnabled: d.referral != nil, onContinue: advance) {
                SingleSelectList(options: ReferralSource.allCases, selection: $d.referral,
                                 label: \.label, icon: { $0.icon })
            }

        case .trust:
            AffirmationScreen(progress: progress, onBack: backAction,
                              icon: "checkmark.seal.fill",
                              title: "Thank you for trusting us",
                              subtitle: "Now let's build your plan — with every number sourced and the maths on screen.",
                              badge: "Yours, everywhere",
                              badgeDetail: "Next you'll create an account so your plan and log sync to any device — exportable any time.",
                              onContinue: advance)

        case .notifications:
            PermissionPrimeScreen(
                progress: progress, onBack: backAction,
                icon: "bell.badge.fill",
                title: "Stay on track",
                subtitle: "A gentle daily nudge to log — never spam, and you can turn it off any time.",
                primaryTitle: "Enable reminders",
                onPrimary: {
                    // Only flip the pref on; actual scheduling waits until the plan
                    // exists (the plan insert at the end of onboarding triggers it),
                    // so abandoned sign-ups never get nudged.
                    if await OnboardingPermissions.requestNotifications() {
                        app.reminders.setEnabled(true)
                        app.analytics.track(.remindersEnabled(source: "onboarding"))
                    }
                    advance()
                },
                onSkip: advance)

        case .account:
            // The questions are done — create an account to build & save the plan
            // so it follows you to any device. Returning users can sign in here too.
            AuthView(allowAnonymous: true,
                     onComplete: { withAnimation { step = .loading } },
                     onBack: { back() })

        case .loading:
            HonestPlanLoadingScreen(
                output: PlanCalculator.calculate(draft.input),
                workouts: draft.weeklyWorkouts,
                onPrefetch: { await prefetchPlan() },
                onDone: { withAnimation { step = .reveal } })

        case .reveal:
            if let revealPlan {
                PlanRevealView(plan: revealPlan, primaryTitle: "Start logging") {
                    finish(revealPlan)
                }
                .navigationBarBackButtonHidden(true)
            } else {
                ProgressView().tint(ScranColor.verified).scranScreen()
                    .task { await prefetchPlan() }
            }
        }
    }

    // MARK: - Helpers

    private func workoutCard(_ title: String, _ subtitle: String, value: Int) -> some View {
        ChoiceCard(title: title, subtitle: subtitle, systemIcon: "flame.fill",
                   isSelected: draft.weeklyWorkouts == value) { draft.weeklyWorkouts = value }
    }

    // MARK: - Apple Health step

    private func importedSummary(_ d: OnboardingDraft) -> String {
        var parts: [String] = []
        if d.heightCm > 50 { parts.append("\(Int(d.heightCm)) cm") }
        if d.weightKg > 20 { parts.append(String(format: "%.1f kg", d.weightKg)) }
        let age = PlanCalculator.age(from: d.dateOfBirth)
        if age > 0 { parts.append("age \(age)") }
        return parts.isEmpty ? "Tap Continue to carry on" : parts.joined(separator: " · ")
    }

    private func importHealth(into d: OnboardingDraft) async {
        healthImporting = true
        defer { healthImporting = false }
        guard await HealthKitService.shared.requestAuthorization() else { return }
        let snap = await HealthKitService.shared.snapshot()
        if let s = snap.biologicalSex, let sex = BiologicalSex(rawValue: s) { d.sex = sex }
        if let dob = snap.dateOfBirth { d.dateOfBirth = dob }
        if let h = snap.heightCm, h > 50 { d.heightCm = h }
        if let w = snap.weightKg, w > 20 { d.weightKg = w }
        UserDefaults.standard.set(true, forKey: "scran.healthConnected")
        healthImported = true
        Haptics.success()
    }

    private func yesNo(title: String, subtitle: String?, value: Binding<Bool?>) -> some View {
        OnboardingScaffold(progress: progress, onBack: backAction, title: title, subtitle: subtitle,
                           ctaEnabled: value.wrappedValue != nil, onContinue: advance) {
            VStack(spacing: 12) {
                ChoiceCard(title: "Yes", systemIcon: "hand.thumbsup.fill",
                           isSelected: value.wrappedValue == true) { value.wrappedValue = true }
                ChoiceCard(title: "No", systemIcon: "hand.thumbsdown.fill",
                           isSelected: value.wrappedValue == false) { value.wrappedValue = false }
            }
        }
    }

    /// Build the plan once and prefetch its explanation so the reveal is instant.
    private func prefetchPlan() async {
        let plan = revealPlan ?? draft.makePlan()
        if plan.explanation == nil {
            if let text = try? await ScanService.explainPlan(plan) { plan.explanation = text }
        }
        revealPlan = plan
    }

    private func finish(_ plan: UserPlan) {
        context.insert(plan)
        try? context.save()
        app.analytics.track(.planCreated(goal: plan.goal, rate: plan.weeklyRateKg))
        app.analytics.track(.onboardingCompleted)
        Haptics.success()
        let ctx = context
        Task { await app.sync.syncPending(context: ctx) }
    }
}

// MARK: - Welcome

private struct WelcomeScreen: View {
    let onStart: () -> Void
    var onSignIn: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                RadialGlow(diameter: 420)
                VStack(spacing: 22) {
                    ClearoMark(size: 150)
                    Text("CLEARO")
                        .font(ScranFont.display(34, relativeTo: .largeTitle))
                        .tracking(10)
                        .foregroundStyle(ScranColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                Text("Calorie tracking that shows its working")
                    .font(ScranFont.display(32, relativeTo: .largeTitle))
                    .textCase(.uppercase)
                    .foregroundStyle(ScranColor.textPrimary)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Every number has a source. Every plan shows its maths. UK-first, honest by design.")
                    .font(ScranFont.body(16, relativeTo: .body))
                    .foregroundStyle(ScranColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            PrimaryButton(title: "Get started", systemImage: "arrow.right", action: onStart)
                .padding(.horizontal, 20)
            Button { Haptics.selection(); onSignIn() } label: {
                Text("Already have an account? Sign in")
                    .font(ScranFont.body(14, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(ScranColor.verified)
            }
            .padding(.top, 14)
            Text("// no card required · free forever tier")
                .font(ScranFont.mono(12, relativeTo: .caption))
                .foregroundStyle(ScranColor.textMuted)
                .padding(.top, 10).padding(.bottom, 8)
        }
        .scranScreen()
    }
}
