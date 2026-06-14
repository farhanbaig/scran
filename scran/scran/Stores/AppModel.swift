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
    let reminders = ReminderService()

    // App-level UI state.
    var paywallTrigger: String?          // non-nil => present paywall with this trigger
    var didBootstrap = false

    // Account state. A session may be a real account or an anonymous (this-device-
    // only) guest. `isAuthenticated` = "has any usable session".
    var authResolved = false             // bootstrap has finished checking for a session
    var isAuthenticated = false          // a session exists (real or anonymous)
    var isAnonymous = false              // the session is an anonymous guest
    var email: String?

    var isPro: Bool { entitlements.isPro }
    var isOnline: Bool { network.isOnline }

    init(entitlements: (any EntitlementsProviding)? = nil,
         analytics: (any AnalyticsTracking)? = nil,
         crash: (any CrashReporting)? = nil) {
        self.entitlements = entitlements ?? LocalEntitlements()
        self.analytics = analytics ?? ConsoleAnalytics()
        self.crash = crash ?? ConsoleCrashReporter()
    }

    /// One-time startup: crash reporting, network, restore a stored account
    /// session (no anonymous fallback), then hydrate from server + sync.
    func bootstrap(context: ModelContext) async {
        guard !didBootstrap else { return }
        didBootstrap = true

        // Keychain items survive app deletion on iOS, so a reinstall would silently
        // restore the old session. UserDefaults IS wiped on delete — use a flag to
        // detect a fresh install and clear the stored token first, so a deleted app
        // really does sign the user out.
        let launchedKey = "clearo.hasLaunchedBefore"
        if !UserDefaults.standard.bool(forKey: launchedKey) {
            await SupabaseClient.shared.signOutAndWipeLocalSession()
            UserDefaults.standard.set(true, forKey: launchedKey)
        }

        crash.bootstrap()
        network.start()

        let restored = await SupabaseClient.shared.restoreSession()
        if let session = restored {
            // A session exists (real account or anonymous guest).
            await activateSession(session, context: context, pull: !session.isAnonymous)
        } else if await SupabaseClient.shared.hasStoredRefreshToken() {
            // Couldn't reach the server (offline/transient) but a session is
            // stored — show the app from local data; refresh on next foreground.
            // NOTE: we never wipe local SwiftData here, so no data is lost offline.
            isAuthenticated = true
        } else {
            isAuthenticated = false
        }
        reminders.start(context: context)
        authResolved = true
    }

    /// Wire up services for a session (real or anonymous) and optionally pull data.
    private func activateSession(_ session: SupabaseSession, context: ModelContext, pull: Bool) async {
        analytics.configure(userId: session.userId)
        await entitlements.configure(appUserId: session.userId)
        crash.breadcrumb("session ready")
        email = session.email
        isAnonymous = session.isAnonymous
        isAuthenticated = true
        quota.isPro = entitlements.isPro
        await quota.refresh()
        if pull { await sync.pullAll(context: context) }
        await sync.syncPending(context: context)
    }

    /// Continue as an anonymous guest (no account; this device only).
    func continueAnonymously(context: ModelContext) async {
        do {
            let s = try await SupabaseClient.shared.continueAnonymously()
            await activateSession(s, context: context, pull: false)
            analytics.track(.signedUp(method: "anonymous"))
        } catch {
            crash.capture(error, context: ["phase": "anonymous"])
        }
    }

    /// Called by the auth screen after a successful sign-in / sign-up session.
    func completeSignIn(_ session: SupabaseSession, context: ModelContext) async {
        await activateSession(session, context: context, pull: true)
        authResolved = true
    }

    /// Sign out: revoke the session and wipe all local data so the next account
    /// starts clean. Returns the app to the auth wall.
    func signOut(context: ModelContext) async {
        await SupabaseClient.shared.signOut()
        try? context.delete(model: FoodEntry.self)
        try? context.delete(model: SavedMeal.self)
        try? context.delete(model: WeightEntry.self)
        try? context.delete(model: UserPlan.self)
        try? context.save()
        email = nil
        isAnonymous = false
        isAuthenticated = false
        reminders.handleSignOut()
        analytics.track(.signedOut)
    }

    /// Call when the app returns to the foreground.
    func onForeground(context: ModelContext) async {
        await entitlements.refresh()
        quota.isPro = entitlements.isPro
        await quota.refresh()
        await sync.syncPending(context: context)
        await reminders.onForeground()
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
