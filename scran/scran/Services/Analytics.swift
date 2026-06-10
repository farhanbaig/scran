//
//  Analytics.swift
//  scran
//
//  The PostHog event contract (§9) behind a protocol. Default impl logs to the
//  console in DEBUG and is a no-op in release until PostHog is wired.
//

import Foundation

/// Every analytics event in the app. Keeps the contract in one type-safe place.
enum AnalyticsEvent {
    case onboardingStarted
    case onboardingCompleted
    case planCreated(goal: String, rate: Double)
    case planExplanationViewed
    case logOpened(entryPoint: String)
    case barcodeScanned(hit: Bool)
    case barcodeMiss(prefix: String)
    case labelScan(ok: Bool, confidence: Double)
    case plateScan(confidence: Double, clarified: Bool)
    case entryLogged(source: String)
    case entryPortionEdited
    case mealSaved
    case mealRelogged
    case paywallViewed(trigger: String)
    case purchase(product: String)
    case quotaHit
    case exportCSV
    case supportOpened

    var name: String {
        switch self {
        case .onboardingStarted:    return "onboarding_started"
        case .onboardingCompleted:  return "onboarding_completed"
        case .planCreated:          return "plan_created"
        case .planExplanationViewed: return "plan_explanation_viewed"
        case .logOpened:            return "log_opened"
        case .barcodeScanned:       return "barcode_scanned"
        case .barcodeMiss:          return "barcode_miss"
        case .labelScan:            return "label_scan"
        case .plateScan:            return "plate_scan"
        case .entryLogged:          return "entry_logged"
        case .entryPortionEdited:   return "entry_portion_edited"
        case .mealSaved:            return "meal_saved"
        case .mealRelogged:         return "meal_relogged"
        case .paywallViewed:        return "paywall_viewed"
        case .purchase:             return "purchase"
        case .quotaHit:             return "quota_hit"
        case .exportCSV:            return "export_csv"
        case .supportOpened:        return "support_opened"
        }
    }

    var properties: [String: Any] {
        switch self {
        case .planCreated(let goal, let rate):       return ["goal": goal, "rate": rate]
        case .logOpened(let entryPoint):             return ["entry_point": entryPoint]
        case .barcodeScanned(let hit):               return ["result": hit ? "hit" : "miss"]
        case .barcodeMiss(let prefix):               return ["prefix": prefix]
        case .labelScan(let ok, let confidence):     return ["result": ok ? "ok" : "unreadable", "confidence": confidence]
        case .plateScan(let confidence, let clarified): return ["confidence": confidence, "clarified": clarified]
        case .entryLogged(let source):               return ["source": source]
        case .paywallViewed(let trigger):            return ["trigger": trigger]
        case .purchase(let product):                 return ["product": product]
        default:                                     return [:]
        }
    }
}

protocol AnalyticsTracking: Sendable {
    func configure(userId: String)
    func track(_ event: AnalyticsEvent)
}

/// Console analytics: prints in DEBUG, silent in release.
struct ConsoleAnalytics: AnalyticsTracking {
    func configure(userId: String) {}
    func track(_ event: AnalyticsEvent) {
        #if DEBUG
        let props = event.properties.isEmpty ? "" : " \(event.properties)"
        print("📊 \(event.name)\(props)")
        #endif
    }
}

// MARK: - PostHog adapter (template — uncomment after adding the SPM package)
/*
import PostHog

struct PostHogAnalytics: AnalyticsTracking {
    static func bootstrap() {
        let config = PostHogConfig(apiKey: ScranConfig.posthogKey, host: ScranConfig.posthogHost)
        PostHogSDK.shared.setup(config)
    }
    func configure(userId: String) { PostHogSDK.shared.identify(userId) }
    func track(_ event: AnalyticsEvent) {
        PostHogSDK.shared.capture(event.name, properties: event.properties)
    }
}
*/
