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
#if canImport(UIKit)
import UIKit
#endif

@main
struct scranApp: App {
    @State private var appModel: AppModel
    private let container: ModelContainer

    init() {
        AppFonts.register()

        #if canImport(UIKit)
        // No scroll indicators anywhere (brand spec). Applies to every SwiftUI
        // ScrollView/List, including sheets.
        UIScrollView.appearance().showsVerticalScrollIndicator = false
        UIScrollView.appearance().showsHorizontalScrollIndicator = false
        #endif

        // Build the SwiftData stack.
        container = Self.makeContainer()

        // Choose service implementations. Defaults are safe local/console impls;
        // to go live, bootstrap PostHog/Sentry and pass the SDK-backed adapters.
        // PostHogAnalytics.bootstrap()   // when configured
        let model = AppModel(
            entitlements: LocalEntitlements(),
            analytics: ConsoleAnalytics(),
            crash: ConsoleCrashReporter())
        _appModel = State(initialValue: model)
    }

    /// Build the SwiftData container without ever crash-looping the app:
    /// a corrupt or unmigratable store is destroyed and rebuilt (entries also
    /// live server-side), and as a last resort we run in-memory for the session.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([UserPlan.self, FoodEntry.self, SavedMeal.self, WeightEntry.self])
        do {
            return try ModelContainer(for: schema)
        } catch {
            let url = URL.applicationSupportDirectory.appending(path: "default.store")
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(filePath: url.path + suffix))
            }
            do {
                return try ModelContainer(for: schema)
            } catch {
                let memory = ModelConfiguration(isStoredInMemoryOnly: true)
                // Schema-only failure modes are exhausted above; in-memory cannot
                // fail for storage reasons.
                return try! ModelContainer(for: schema, configurations: memory)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .modelContainer(container)
                .scranAppearance()
                .tint(ScranColor.verified)
        }
    }
}
