//
//  ContentView.swift
//  scran
//
//  RootView — routes between onboarding and the main app based on whether a
//  plan exists, owns app bootstrap + foreground refresh, and hosts the
//  contextual paywall.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Query private var plans: [UserPlan]

    /// DEBUG screenshot/dev mode: `-uiPreview` launch argument skips auth and
    /// onboarding, seeding a local plan + sample entries instead.
    private var isUIPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uiPreview")
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if isUIPreview {
                MainTabView()
            } else if !app.authResolved {
                AuthSplash()
            } else if app.isAuthenticated && !plans.isEmpty {
                MainTabView()
            } else {
                // Not signed in (or signed in without a plan yet) → onboarding.
                // Onboarding asks the questions first, then asks to create an
                // account near the end (to build + save the plan).
                OnboardingFlow()
            }
        }
        .animation(.snappy(duration: 0.3), value: app.authResolved)
        .animation(.snappy(duration: 0.3), value: plans.isEmpty)
        .task {
            #if DEBUG
            if isUIPreview { seedPreviewData(); return }
            #endif
            await app.bootstrap(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await app.onForeground(context: context) }
            }
        }
        .sheet(isPresented: Binding(
            get: { app.paywallTrigger != nil },
            set: { if !$0 { app.paywallTrigger = nil } })) {
            if let trigger = app.paywallTrigger {
                PaywallView(trigger: trigger)
                    .environment(app)
                    .presentationDetents([.large])
                    .scranAppearance()
            }
        }
    }
}

#if DEBUG
extension RootView {
    /// Idempotent sample data for `-uiPreview` runs: a Heart + Blood-sugar plan
    /// and a porridge breakfast, so Today shows the focus grid and flags.
    fileprivate func seedPreviewData() {
        guard ((try? context.fetch(FetchDescriptor<UserPlan>())) ?? []).isEmpty else { return }
        let plan = UserPlan(
            heightCm: 178, weightKg: 82,
            dateOfBirth: Calendar.current.date(byAdding: .year, value: -34, to: .now) ?? .now,
            biologicalSex: BiologicalSex.male.rawValue,
            activityLevel: ActivityLevel.moderate.rawValue,
            weeklyWorkouts: 4, goal: Goal.lose.rawValue, weeklyRateKg: 0.5,
            bmr: 1780, tdee: 2540, dailyTargetKcal: 2040,
            proteinTargetG: 150, carbsTargetG: 200, fatTargetG: 65,
            satFatLimitG: 20, fibreTargetG: 30,
            focusAreas: [FocusArea.heart.rawValue, FocusArea.bloodSugar.rawValue])
        context.insert(plan)
        // One meal = one entry (a scan logs as a single combined dish).
        let meals: [(String, NutrientBlock, Double, String)] = [
            ("Porridge with berries",
             NutrientBlock(kcal: 76, proteinG: 2.9, carbsG: 14, fatG: 1.6,
                           satFatG: 0.7, fibreG: 1.7, sugarG: 6.3, saltG: 0.1), 367,
             EntrySource.estimate.rawValue),
            ("Cheeseburger",
             NutrientBlock(kcal: 263, proteinG: 13, carbsG: 21, fatG: 14,
                           satFatG: 6.2, fibreG: 1.2, sugarG: 3.5, saltG: 1.3), 250,
             EntrySource.estimate.rawValue),
        ]
        for (name, per100g, grams, source) in meals {
            context.insert(FoodEntry(name: name, source: source,
                                     confidence: 0.9, per100g: per100g, servingSizeG: grams))
        }
        // A week of varied past days so Progress/history shows real verdicts.
        let cal = Calendar.current
        let pastDayKcal: [Double] = [1980, 2350, 1450, 2050, 2620, 1890]
        for (i, kcal) in pastDayKcal.enumerated() {
            guard let day = cal.date(byAdding: .day, value: -(i + 1), to: .now) else { continue }
            for (meal, share) in [(9, 0.3), (13, 0.4), (19, 0.3)] {
                let at = cal.date(bySettingHour: meal, minute: 15, second: 0, of: day) ?? day
                context.insert(FoodEntry(
                    loggedAt: at, name: "Sample meal",
                    source: EntrySource.barcode.rawValue,
                    per100g: NutrientBlock(kcal: kcal * share / 4, proteinG: 6, carbsG: 12,
                                           fatG: 4, satFatG: 1.5, fibreG: 1.8,
                                           sugarG: 5, saltG: 0.4),
                    servingSizeG: 400))
            }
        }
        // A few weigh-ins so the weight trend chart has a line to draw.
        let weights: [(Int, Double)] = [(28, 84.2), (21, 83.6), (14, 83.1), (7, 82.6), (0, 82.0)]
        for (daysAgo, kg) in weights {
            guard let d = cal.date(byAdding: .day, value: -daysAgo, to: .now) else { continue }
            context.insert(WeightEntry(date: d, weightKg: kg))
        }
        try? context.save()
    }
}
#endif

// Back-compat alias: the Xcode template references ContentView in some places.
typealias ContentView = RootView

#Preview {
    RootView()
        .environment(AppModel())
        .modelContainer(for: [UserPlan.self, FoodEntry.self, SavedMeal.self, WeightEntry.self],
                        inMemory: true)
        .preferredColorScheme(.dark)
}
