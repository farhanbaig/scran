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
    @State private var healthSexImported = false
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
                title: "Bring in Apple Health",
                subtitle: "Pull your activity, sleep and weight across from Health — read-only, so your plan has the fullest picture from day one.",
                ctaTitle: healthImported ? "Continue" : (healthImporting ? "Connecting…" : "Connect Apple Health"),
                ctaEnabled: !healthImporting,
                secondaryTitle: "Skip",
                onSecondary: advance,
                onContinue: {
                    if healthImported { advance() }
                    else { Task { await importHealth(into: d) } }
                }) {
                VStack(spacing: 20) {
                    if healthImported {
                        HealthImportedSummary(stats: importedStats(d))
                    } else {
                        HealthSyncArt().frame(maxWidth: .infinity)
                    }
                }
            }

        case .sex:
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "Your biological sex",
                               subtitle: "It feeds the metabolism maths — that's the only reason we ask.",
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
                               title: "When's your birthday?",
                               subtitle: "Age is one of the inputs to your daily energy number.",
                               onContinue: advance) {
                DOBPicker(date: $d.dateOfBirth).frame(maxWidth: .infinity)
            }

        case .height:
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "How tall are you?",
                               onContinue: advance) {
                HeightPicker(heightCm: $d.heightCm, unit: $d.heightUnit).frame(maxWidth: .infinity)
            }

        case .weight:
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "And your weight right now?",
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
                               title: "How active is a normal day?",
                               subtitle: "Be honest — over-guessing here is the usual reason targets drift.",
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
                               title: "Workouts in a typical week?",
                               subtitle: "We calibrate around this — and never quietly hand the calories back when you train.",
                               onContinue: advance) {
                VStack(spacing: 12) {
                    workoutCard("0–2", "Now and then", value: 1)
                    workoutCard("3–5", "A few workouts a week", value: 4)
                    workoutCard("6+", "Dedicated athlete", value: 6)
                }
            }

        case .goal:
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "What are you here to do?",
                               subtitle: "This sets your calorie target — and we'll show you exactly how it's worked out.",
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
                               title: "At what pace?",
                               subtitle: "A faster pace means a tighter daily target. 0.5 kg a week is the sustainable sweet spot.",
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
                               title: "What are you hoping to feel?",
                               subtitle: "Pick anything that fits — it shapes how we talk to you along the way.",
                               ctaEnabled: !d.motivations.isEmpty, onContinue: advance) {
                MultiSelectList(options: Motivation.allCases, selection: $d.motivations,
                                label: \.label, icon: { $0.icon })
            }

        case .blockers:
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "What's tripped you up before?",
                               subtitle: "Knowing the snag helps us design around it, not nag you about it.",
                               ctaEnabled: !d.blockers.isEmpty, onContinue: advance) {
                MultiSelectList(options: Blocker.allCases, selection: $d.blockers,
                                label: \.label, icon: { $0.icon })
            }

        case .diet:
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "Eating a particular way?",
                               subtitle: "Optional — it helps us tune the suggestions we make.",
                               ctaEnabled: d.diet != nil, onContinue: advance) {
                SingleSelectList(options: DietType.allCases, selection: $d.diet,
                                 label: \.label, icon: { $0.icon })
            }

        case .focusAreas:
            // Focus areas can imply health information, so this step collects
            // explicit UK GDPR consent: informed copy + an affirmative Continue.
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "Anything you want to watch closely?",
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
            yesNo(title: "Tried other trackers before?",
                  subtitle: nil, value: $d.triedOtherApps)

        case .worksPro:
            yesNo(title: "Working with a coach or dietitian?",
                  subtitle: "If so, we'll keep your data easy to export and share with them.", value: $d.worksWithPro)

        case .referral:
            OnboardingScaffold(progress: progress, onBack: backAction,
                               title: "How did you find Clearo?",
                               ctaEnabled: d.referral != nil, onContinue: advance) {
                SingleSelectList(options: ReferralSource.allCases, selection: $d.referral,
                                 label: \.label, icon: { $0.icon })
            }

        case .trust:
            AffirmationScreen(progress: progress, onBack: backAction,
                              icon: "checkmark.seal.fill",
                              title: "That's everything — thank you",
                              subtitle: "Now we'll build your plan, with every number sourced and the maths on screen.",
                              badge: "Yours on every device",
                              badgeDetail: "Next, create an account so your plan and log sync anywhere — and export any time.",
                              onContinue: advance)

        case .notifications:
            PermissionPrimeScreen(
                progress: progress, onBack: backAction,
                icon: "bell.badge.fill",
                title: "Want a nudge to log?",
                subtitle: "One gentle reminder around mealtimes — never spam, and off whenever you like.",
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

    private func importedStats(_ d: OnboardingDraft) -> [HealthStat] {
        var s: [HealthStat] = []
        if let sex = importedSex(d) {
            s.append(HealthStat(icon: "person.fill", label: "Sex", value: sex))
        }
        let age = PlanCalculator.age(from: d.dateOfBirth)
        if age > 0 { s.append(HealthStat(icon: "calendar", label: "Age", value: "\(age) yrs")) }
        if d.heightCm > 50 { s.append(HealthStat(icon: "ruler.fill", label: "Height", value: "\(Int(d.heightCm)) cm")) }
        if d.weightKg > 20 { s.append(HealthStat(icon: "scalemass.fill", label: "Weight", value: String(format: "%.1f kg", d.weightKg))) }
        return s
    }

    /// Sex label only when Health actually supplied it (tracked at import time).
    private func importedSex(_ d: OnboardingDraft) -> String? {
        guard healthSexImported else { return nil }
        return d.sex == .female ? "Female" : "Male"
    }

    private func importHealth(into d: OnboardingDraft) async {
        healthImporting = true
        defer { healthImporting = false }
        guard await HealthKitService.shared.requestAuthorization() else { return }
        let snap = await HealthKitService.shared.snapshot()
        if let s = snap.biologicalSex, let sex = BiologicalSex(rawValue: s) {
            d.sex = sex; healthSexImported = true
        }
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
            VStack(spacing: 20) {
                ClearoMark(size: 120)
                Text("CLEARO")
                    .font(ScranFont.display(32, relativeTo: .largeTitle))
                    .tracking(10)
                    .foregroundStyle(ScranColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
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

// MARK: - Imported-from-Health animated summary

struct HealthStat: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
}

/// Shows the values pulled from Apple Health, revealing each row one-by-one so
/// the user can see exactly what the app imported.
private struct HealthImportedSummary: View {
    let stats: [HealthStat]
    @State private var headerShown = false
    @State private var revealed = 0

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(ScranColor.positive)
                Text("Pulled from Apple Health")
                    .font(ScranFont.body(15, weight: .bold, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary)
                Spacer()
            }
            .opacity(headerShown ? 1 : 0)
            .offset(y: headerShown ? 0 : -6)

            VStack(spacing: 10) {
                ForEach(Array(stats.enumerated()), id: \.element.id) { i, s in
                    HStack(spacing: 12) {
                        Image(systemName: s.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ScranColor.textPrimary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(ScranColor.panel))
                        Text(s.label)
                            .font(ScranFont.body(15, weight: .medium, relativeTo: .body))
                            .foregroundStyle(ScranColor.textMuted)
                        Spacer()
                        Text(s.value)
                            .font(ScranFont.mono(17, weight: .bold, relativeTo: .body))
                            .foregroundStyle(ScranColor.textPrimary)
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 14).fill(ScranColor.bg))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ScranColor.lineStrong))
                    .opacity(i < revealed ? 1 : 0)
                    .offset(x: i < revealed ? 0 : 28)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .task {
            withAnimation(.snappy(duration: 0.3)) { headerShown = true }
            for i in 1...max(1, stats.count) {
                try? await Task.sleep(nanoseconds: 320_000_000)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { revealed = i }
                Haptics.selection()
            }
        }
    }
}
