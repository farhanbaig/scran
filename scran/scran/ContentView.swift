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

    var body: some View {
        Group {
            if !app.authResolved {
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
        .task { await app.bootstrap(context: context) }
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

// Back-compat alias: the Xcode template references ContentView in some places.
typealias ContentView = RootView

#Preview {
    RootView()
        .environment(AppModel())
        .modelContainer(for: [UserPlan.self, FoodEntry.self, SavedMeal.self, WeightEntry.self],
                        inMemory: true)
        .preferredColorScheme(.dark)
}
