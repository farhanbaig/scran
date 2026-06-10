//
//  AppModel.swift
//  scran
//
//  Root @Observable store. Owns the cross-cutting services and app-level state
//  (auth/session, entitlements, analytics, crash reporting, scan quota, sync,
//  network, and contextual paywall presentation).
//

import Foundation
import SwiftUI
import SwiftData
import Observation

@MainActor
@Observable
final class AppModel {
    // Services (protocol-typed so SDKs drop in without touching call sites).
    let entitlements: any EntitlementsProviding
    let analytics: any AnalyticsTracking
    let crash: any CrashReporting
    let quota = ScanQuota()
    let sync = SyncQueue()
    let network = NetworkMonitor()

    // App-level UI state.
    var paywallTrigger: String?          // non-nil => present paywall with this trigger
    var didBootstrap = false

    var isPro: Bool { entitlements.isPro }
    var isOnline: Bool { network.isOnline }

    init(entitlements: (any EntitlementsProviding)? = nil,
         analytics: (any AnalyticsTracking)? = nil,
         crash: (any CrashReporting)? = nil) {
        self.entitlements = entitlements ?? LocalEntitlements()
        self.analytics = analytics ?? ConsoleAnalytics()
        self.crash = crash ?? ConsoleCrashReporter()
    }

    /// One-time startup: crash reporting, network, anonymous session, services,
    /// quota, and a first sync.
    func bootstrap(context: ModelContext) async {
        guard !didBootstrap else { return }
        didBootstrap = true

        crash.bootstrap()
        network.start()

        do {
            let session = try await SupabaseClient.shared.ensureSession()
            analytics.configure(userId: session.userId)
            await entitlements.configure(appUserId: session.userId)
            crash.breadcrumb("session ready")
        } catch {
            crash.capture(error, context: ["phase": "bootstrap"])
        }

        quota.isPro = entitlements.isPro
        await quota.refresh()
        await sync.syncPending(context: context)
    }

    /// Call when the app returns to the foreground.
    func onForeground(context: ModelContext) async {
        await entitlements.refresh()
        quota.isPro = entitlements.isPro
        await quota.refresh()
        await sync.syncPending(context: context)
    }

    // MARK: - Paywall

    func presentPaywall(trigger: String) {
        analytics.track(.paywallViewed(trigger: trigger))
        paywallTrigger = trigger
    }

    /// Gate an AI scan. Returns true if allowed; otherwise presents the paywall.
    func canStartAIScan() -> Bool {
        if entitlements.isPro { return true }
        if quota.isExhausted {
            analytics.track(.quotaHit)
            presentPaywall(trigger: "quota")
            return false
        }
        return true
    }
}
