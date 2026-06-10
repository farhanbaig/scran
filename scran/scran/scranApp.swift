//
//  scranApp.swift
//  scran
//
//  App entry. Dark-only theme, runtime font registration, SwiftData stack, and
//  the shared AppModel. Third-party SDKs (RevenueCat/PostHog/Sentry) are wired
//  behind protocols — swap the adapters in here once their SPM packages are
//  added (see README).
//

import SwiftUI
import SwiftData

@main
struct scranApp: App {
    @State private var appModel: AppModel
    private let container: ModelContainer

    init() {
        AppFonts.register()

        // Build the SwiftData stack.
        do {
            container = try ModelContainer(
                for: UserPlan.self, FoodEntry.self, SavedMeal.self, WeightEntry.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Choose service implementations. Defaults are safe local/console impls;
        // to go live, bootstrap PostHog/Sentry and pass the SDK-backed adapters.
        // PostHogAnalytics.bootstrap()   // when configured
        let model = AppModel(
            entitlements: LocalEntitlements(),
            analytics: ConsoleAnalytics(),
            crash: ConsoleCrashReporter())
        _appModel = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .modelContainer(container)
                .preferredColorScheme(.dark)
                .tint(ScranColor.verified)
        }
    }
}
