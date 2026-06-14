//
//  ScranConfig.swift
//  scran
//
//  Central configuration. The app talks ONLY to Supabase (anon key + RLS) and
//  RevenueCat (public SDK key). No AI/provider keys ever live in the binary —
//  Gemini / Claude / Open Food Facts calls happen inside Edge Functions.
//

import Foundation

enum ScranConfig {

    // MARK: - Supabase (project: Scran · eu-west-1)
    /// REST/Auth/Functions base URL.
    static let supabaseURL = URL(string: "https://qrbwqvpcskwrgmzxehpt.supabase.co")!

    /// Publishable (anon) key. Safe to ship: all access is gated by RLS.
    /// Modern publishable key format. Rotate independently in the dashboard.
    static let supabasePublishableKey = "sb_publishable_xCgqXy65hZ47XYWgb_L6Jw_IqOPWPNq"

    static var functionsURL: URL { supabaseURL.appendingPathComponent("functions/v1") }
    static var authURL: URL { supabaseURL.appendingPathComponent("auth/v1") }
    static var restURL: URL { supabaseURL.appendingPathComponent("rest/v1") }
    static var storageURL: URL { supabaseURL.appendingPathComponent("storage/v1") }

    // MARK: - RevenueCat
    /// Public SDK key (set in App Store Connect / RevenueCat dashboard before ship).
    /// Left empty by default so the app runs on the local entitlements stub.
    static let revenueCatPublicKey = ""

    static let entitlementPro = "pro"
    static let productMonthly = "clearo_pro_monthly_399"
    static let productAnnual = "clearo_pro_annual_2499"
    static let offeringDefault = "default"

    // MARK: - PostHog (EU host)
    static let posthogKey = ""
    static let posthogHost = "https://eu.i.posthog.com"

    // MARK: - Sentry
    static let sentryDSN = ""

    // MARK: - Auth
    /// Flip to `true` once Sign in with Apple is configured in BOTH the Apple
    /// Developer portal (Services ID + key, capability on the App ID) and the
    /// Supabase dashboard (Apple provider enabled, bundle id as a client). Until
    /// then the Apple button stays hidden so users never hit a broken flow.
    static let appleSignInEnabled = true

    // MARK: - Product rules
    static let freeDailyScans = 5
    static let freeSavedMealsLimit = 10
    static let freeHistoryDays = 14

    // MARK: - Pricing copy (display only; truth is RevenueCat StoreProduct)
    static let priceMonthlyDisplay = "£3.99"
    static let priceAnnualDisplay = "£24.99"
    static let priceAnnualPerMonth = "£2.08"

    // MARK: - Branding (Clearo — a Wireside Studios product, getclearo.com)
    static let appName = "Clearo"
    static let supportEmail = "hello@getclearo.com"
    static let privacyURL = URL(string: "https://getclearo.com/privacy")!
    static let termsURL = URL(string: "https://getclearo.com/terms")!

    /// True when a real RevenueCat key is configured.
    static var hasRevenueCat: Bool { !revenueCatPublicKey.isEmpty }
    static var hasAnalytics: Bool { !posthogKey.isEmpty }
    static var hasCrashReporting: Bool { !sentryDSN.isEmpty }
}
