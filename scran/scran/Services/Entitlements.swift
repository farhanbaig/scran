//
//  Entitlements.swift
//  scran
//
//  Subscription state behind a protocol so the app builds and runs without the
//  RevenueCat SDK. The default implementation is a local, offline-first store
//  that NEVER locks out a user (the Cal AI lockout bug is our recruiting poster).
//
//  To go live: add the RevenueCat SPM package, set ScranConfig.revenueCatPublicKey,
//  and implement `RevenueCatEntitlements` (template at the bottom of this file)
//  conforming to EntitlementsProviding, then swap it in AppModel.
//

import Foundation
import Observation

struct ProductPrice: Sendable, Hashable {
    let id: String
    let displayPrice: String     // localized, from StoreProduct.localizedPriceString
    let period: String           // "month" | "year"
}

protocol EntitlementsProviding: AnyObject {
    /// True when the `pro` entitlement is active. Reads from cache when offline.
    var isPro: Bool { get }
    /// Localized prices for the paywall, fetched from the store.
    var prices: [ProductPrice] { get }

    func configure(appUserId: String) async
    func refresh() async
    func purchase(productId: String) async throws
    func restore() async throws
}

/// Local entitlements: free tier by default, with an offline cache and a grace
/// window. Used until the RevenueCat SDK is wired. Reads never throw.
@MainActor
@Observable
final class LocalEntitlements: EntitlementsProviding {
    private(set) var isPro: Bool = false
    private(set) var prices: [ProductPrice] = [
        ProductPrice(id: ScranConfig.productMonthly,
                     displayPrice: ScranConfig.priceMonthlyDisplay, period: "month"),
        ProductPrice(id: ScranConfig.productAnnual,
                     displayPrice: ScranConfig.priceAnnualDisplay, period: "year"),
    ]

    private let cacheKey = "scran.entitlement.pro"
    private let graceKey = "scran.entitlement.proUntil"

    func configure(appUserId: String) async {
        // Restore cached entitlement, honouring a grace period so a sync hiccup
        // never demotes a paying user.
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: cacheKey) {
            isPro = true
        } else if let until = defaults.object(forKey: graceKey) as? Date, until > .now {
            isPro = true
        }
    }

    func refresh() async { /* no-op in local mode */ }

    func purchase(productId: String) async throws {
        // Local mode cannot transact. Wire RevenueCat to enable purchases.
        throw EntitlementError.notConfigured
    }

    func restore() async throws {
        throw EntitlementError.notConfigured
    }

    /// Test/preview helper to simulate Pro locally.
    func setProForTesting(_ value: Bool, graceDays: Int = 30) {
        isPro = value
        let defaults = UserDefaults.standard
        defaults.set(value, forKey: cacheKey)
        if value {
            defaults.set(Calendar.current.date(byAdding: .day, value: graceDays, to: .now),
                         forKey: graceKey)
        }
    }
}

enum EntitlementError: Error, LocalizedError {
    case notConfigured
    case purchaseFailed(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "In-app purchases aren't configured in this build yet."
        case .purchaseFailed(let m):
            return m
        }
    }
}

// MARK: - RevenueCat adapter (template — uncomment after adding the SPM package)
/*
import RevenueCat

@MainActor
@Observable
final class RevenueCatEntitlements: EntitlementsProviding {
    private(set) var isPro = false
    private(set) var prices: [ProductPrice] = []

    func configure(appUserId: String) async {
        Purchases.logLevel = .warn
        Purchases.configure(with:
            .builder(withAPIKey: ScranConfig.revenueCatPublicKey)
            .with(appUserID: appUserId)            // == Supabase user id
            .build())
        // Grace periods + offline entitlement cache are ON by default in the SDK.
        await refresh()
        await loadPrices()
    }

    func refresh() async {
        if let info = try? await Purchases.shared.customerInfo() {
            isPro = info.entitlements[ScranConfig.entitlementPro]?.isActive == true
        }
    }

    private func loadPrices() async {
        guard let offering = try? await Purchases.shared.offerings().current else { return }
        prices = offering.availablePackages.map {
            ProductPrice(id: $0.storeProduct.productIdentifier,
                         displayPrice: $0.storeProduct.localizedPriceString,
                         period: $0.packageType == .annual ? "year" : "month")
        }
    }

    func purchase(productId: String) async throws {
        guard let offering = try await Purchases.shared.offerings().current,
              let package = offering.availablePackages.first(where: {
                  $0.storeProduct.productIdentifier == productId }) else {
            throw EntitlementError.purchaseFailed("Product unavailable")
        }
        let result = try await Purchases.shared.purchase(package: package)
        isPro = result.customerInfo.entitlements[ScranConfig.entitlementPro]?.isActive == true
    }

    func restore() async throws {
        let info = try await Purchases.shared.restorePurchases()
        isPro = info.entitlements[ScranConfig.entitlementPro]?.isActive == true
    }
}
*/
