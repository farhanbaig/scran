//
//  PaywallView.swift
//  scran
//
//  Presented contextually, never as an onboarding wall. Price is shown before
//  any commitment. No variable pricing, ever. Free-forever tier stated explicitly.
//

import SwiftUI

struct PaywallView: View {
    let trigger: String
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var working = false
    @State private var message: String? = nil

    private var monthly: ProductPrice? {
        app.entitlements.prices.first { $0.period == "month" }
    }
    private var annual: ProductPrice? {
        app.entitlements.prices.first { $0.period == "year" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if trigger == "quota" {
                    ScranBanner(kind: .info,
                                text: "You've used today's \(ScranConfig.freeDailyScans) free AI scans. Barcode and manual logging still work — or go unlimited.")
                }
                freeCard
                proCard
                promise
                if let message {
                    ScranBanner(kind: .error, text: message)
                }
                Button("Restore purchases") { Task { await restore() } }
                    .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary)
                    .frame(maxWidth: .infinity).padding(.top, 4)

                // Required on subscription screens (App Review 3.1.2): renewal
                // terms plus tappable Terms of Use and Privacy Policy links.
                VStack(spacing: 6) {
                    Text("Subscriptions renew automatically until cancelled. Manage or cancel any time in your App Store account settings.")
                        .font(ScranFont.body(11, relativeTo: .caption2))
                        .foregroundStyle(ScranColor.textMuted)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 16) {
                        Link("Terms of Use", destination: ScranConfig.termsURL)
                        Link("Privacy Policy", destination: ScranConfig.privacyURL)
                    }
                    .font(ScranFont.body(12, weight: .semibold, relativeTo: .caption))
                    .tint(ScranColor.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            .padding(20).padding(.bottom, 30)
        }
        .background(ScranColor.bg.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(ScranColor.textMuted)
                    .frame(width: 38, height: 38)
            }
            .padding(8)
        }
        .onAppear { app.analytics.track(.paywallViewed(trigger: trigger)) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Clearo Pro", color: ScranColor.verified, ruleColor: ScranColor.verified)
            Text("Unlimited scans. Same honest numbers.")
                .font(ScranFont.display(30, relativeTo: .largeTitle)).textCase(.uppercase)
                .foregroundStyle(ScranColor.textPrimary)
        }
        .padding(.top, 12)
    }

    private var freeCard: some View {
        ScranCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("FREE").font(ScranFont.mono(12, weight: .bold, relativeTo: .caption))
                    .tracking(1.6).foregroundStyle(ScranColor.textMuted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("£0").font(ScranFont.display(44, relativeTo: .largeTitle))
                        .foregroundStyle(ScranColor.textPrimary)
                    Text("forever").font(ScranFont.body(14, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(ScranColor.textMuted)
                }
                Text("// no card required").font(ScranFont.mono(12, relativeTo: .caption))
                    .foregroundStyle(ScranColor.textMuted)
                featureList([
                    "Unlimited barcode & manual logging",
                    "\(ScranConfig.freeDailyScans) AI scans every day",
                    "10 saved meals, one-tap re-log",
                    "Your data, exportable as CSV",
                ])
            }
        }
    }

    private var proCard: some View {
        ScranCard(border: ScranColor.verified.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 14) {
                Text("PRO").font(ScranFont.mono(12, weight: .bold, relativeTo: .caption))
                    .tracking(1.6).foregroundStyle(ScranColor.verified)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(monthly?.displayPrice ?? ScranConfig.priceMonthlyDisplay)
                        .font(ScranFont.display(44, relativeTo: .largeTitle))
                        .foregroundStyle(ScranColor.textPrimary)
                    Text("/month").font(ScranFont.body(14, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(ScranColor.textMuted)
                }
                Text("// or \(annual?.displayPrice ?? ScranConfig.priceAnnualDisplay)/year ≈ \(ScranConfig.priceAnnualPerMonth)/mo")
                    .font(ScranFont.mono(12, relativeTo: .caption))
                    .foregroundStyle(ScranColor.textMuted)
                featureList([
                    "Unlimited AI label & plate scans",
                    "Unlimited saved meals",
                    "Full history & trends",
                    "Priority scanning lane",
                ])
                VStack(spacing: 10) {
                    PrimaryButton(title: working ? "…" : "Go Pro — \(annual?.displayPrice ?? ScranConfig.priceAnnualDisplay)/yr",
                                  enabled: !working) {
                        Task { await purchase(annual?.id ?? ScranConfig.productAnnual) }
                    }
                    SecondaryButton(title: "Monthly — \(monthly?.displayPrice ?? ScranConfig.priceMonthlyDisplay)/mo") {
                        Task { await purchase(monthly?.id ?? ScranConfig.productMonthly) }
                    }
                }
                .padding(.top, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [ScranColor.verified.opacity(0.07), .clear],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }

    private var promise: some View {
        Text("Free forever tier — no card needed. Price shown before you start · cancel in two taps · exports are free.")
            .font(ScranFont.mono(12, relativeTo: .caption))
            .foregroundStyle(ScranColor.verified)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(ScranColor.verifiedDim))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ScranColor.verified.opacity(0.35)))
    }

    private func featureList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Text("✓").font(ScranFont.mono(14, weight: .bold, relativeTo: .body))
                        .foregroundStyle(ScranColor.verified)
                    Text(item).font(ScranFont.body(15, relativeTo: .body))
                        .foregroundStyle(ScranColor.textPrimary)
                }
            }
        }
        .padding(.top, 4)
    }

    private func purchase(_ productId: String) async {
        working = true; message = nil
        do {
            try await app.entitlements.purchase(productId: productId)
            app.quota.isPro = app.entitlements.isPro
            app.analytics.track(.purchase(product: productId))
            Haptics.success()
            if app.entitlements.isPro { dismiss() }
        } catch {
            message = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't complete the purchase. No charge was made."
        }
        working = false
    }

    private func restore() async {
        working = true; message = nil
        do {
            try await app.entitlements.restore()
            app.quota.isPro = app.entitlements.isPro
            if app.entitlements.isPro { Haptics.success(); dismiss() }
            else { message = "No active subscription found to restore." }
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "Couldn't restore right now."
        }
        working = false
    }
}
