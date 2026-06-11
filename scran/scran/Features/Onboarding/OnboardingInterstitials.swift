//
//  OnboardingInterstitials.swift
//  scran
//
//  The non-question screens that give the funnel momentum — rebuilt honest:
//   • Affirmation — pacing + reassurance.
//   • HonestPlanLoading — the inversion of Cal AI's fake "estimating metabolic
//     age" loader. We show the REAL equation assembling from the user's numbers.
//   • SocialProof — credibility from why we exist, not fabricated user counts.
//   • PermissionPrime — honest framing, no coached taps, opt-ins off by default.
//

import SwiftUI
#if canImport(UIKit)
import UserNotifications
#endif

// MARK: - Affirmation

struct AffirmationScreen: View {
    var progress: Double
    var onBack: (() -> Void)? = nil
    let icon: String
    let title: String
    var subtitle: String? = nil
    var badge: String? = nil
    var badgeDetail: String? = nil
    var ctaTitle: String = "Continue"
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressBar(progress: progress, onBack: onBack)
            Spacer()
            ZStack {
                RadialGlow(diameter: 320)
                Image(systemName: icon)
                    .font(.system(size: 64, weight: .regular))
                    .foregroundStyle(ScranColor.verified)
                    .shadow(color: ScranColor.verified.opacity(0.5), radius: 16)
            }
            Text(title)
                .font(ScranFont.display(30, relativeTo: .largeTitle))
                .textCase(.uppercase).multilineTextAlignment(.center)
                .foregroundStyle(ScranColor.textPrimary)
                .padding(.horizontal, 24).padding(.top, 8)
            if let subtitle {
                Text(subtitle)
                    .font(ScranFont.body(16, relativeTo: .body))
                    .foregroundStyle(ScranColor.textMuted)
                    .multilineTextAlignment(.center).padding(.horizontal, 32).padding(.top, 10)
            }
            if let badge {
                VStack(spacing: 6) {
                    Text(badge)
                        .font(ScranFont.body(15, weight: .bold, relativeTo: .body))
                        .foregroundStyle(ScranColor.textPrimary)
                    if let badgeDetail {
                        Text(badgeDetail)
                            .font(ScranFont.body(13, relativeTo: .footnote))
                            .foregroundStyle(ScranColor.textMuted)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 16).fill(ScranColor.panel))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ScranColor.line))
                .padding(.horizontal, 24).padding(.top, 24)
            }
            Spacer()
            PrimaryButton(title: ctaTitle, action: onContinue)
                .padding(.horizontal, 20).padding(.bottom, 8)
        }
        .scranScreen()
    }
}

// MARK: - Honest plan loading (real equation, not theatre)

struct HonestPlanLoadingScreen: View {
    let output: PlanOutput
    let workouts: Int
    var onPrefetch: () async -> Void = {}
    let onDone: () -> Void

    @State private var revealed = 0
    @State private var done = false

    private var rows: [(String, String)] {
        [
            ("Base metabolism (BMR)", ScranFormat.kcalText(output.bmr)),
            ("× activity (\(workouts) workouts/wk)", ScranFormat.kcalText(output.tdee)),
            (output.dailyDeltaKcal < 0 ? "− deficit" : (output.dailyDeltaKcal > 0 ? "+ surplus" : "maintenance"),
             "\(output.dailyDeltaKcal == 0 ? "±0" : (output.dailyDeltaKcal < 0 ? "−" : "+"))\(ScranFormat.int(abs(output.dailyDeltaKcal))) kcal"),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Text("// doing the maths — no black box")
                    .font(ScranFont.mono(13, relativeTo: .footnote))
                    .foregroundStyle(ScranColor.verified)
                Text("Building your plan")
                    .font(ScranFont.display(30, relativeTo: .largeTitle))
                    .textCase(.uppercase).foregroundStyle(ScranColor.textPrimary)

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                        if idx < revealed {
                            HStack {
                                Text(row.0).font(ScranFont.mono(13, relativeTo: .footnote))
                                    .foregroundStyle(ScranColor.textMuted)
                                Spacer(minLength: 12)
                                Text(row.1).font(ScranFont.mono(14, weight: .bold, relativeTo: .body))
                                    .foregroundStyle(ScranColor.textPrimary)
                            }
                            .padding(.vertical, 8)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                    if done {
                        Rectangle().fill(ScranColor.textPrimary).frame(height: 2).padding(.vertical, 10)
                        HStack {
                            Text("Daily target").font(ScranFont.mono(15, relativeTo: .body))
                                .foregroundStyle(ScranColor.textMuted)
                            Spacer()
                            Text("\(ScranFormat.int(output.dailyTargetKcal)) kcal")
                                .font(ScranFont.mono(20, weight: .bold, relativeTo: .title3))
                                .foregroundStyle(ScranColor.verified)
                                .shadow(color: ScranColor.verified.opacity(0.5), radius: 12)
                        }
                        .transition(.opacity)
                    } else {
                        HStack(spacing: 10) {
                            ProgressView().tint(ScranColor.verified)
                            Text("Calculating from your numbers…")
                                .font(ScranFont.mono(12, relativeTo: .caption))
                                .foregroundStyle(ScranColor.textMuted)
                        }
                        .padding(.top, 10)
                    }
                }
                .padding(22)
                .background(RoundedRectangle(cornerRadius: 14).fill(ScranColor.bg))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ScranColor.line))
            }
            .padding(.horizontal, 20)
            Spacer()
        }
        .background(ScranColor.bg.ignoresSafeArea()
            .overlay(alignment: .top) { RadialGlow().offset(y: -100) })
        .task {
            await onPrefetch()
            for i in 1...rows.count {
                try? await Task.sleep(nanoseconds: 600_000_000)
                withAnimation(.snappy) { revealed = i }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            withAnimation(.snappy) { done = true }
            Haptics.success()
            try? await Task.sleep(nanoseconds: 900_000_000)
            onDone()
        }
    }
}

// MARK: - Honest social proof

struct SocialProofScreen: View {
    var progress: Double
    var onBack: (() -> Void)? = nil
    let onContinue: () -> Void

    private let receipts: [(String, String)] = [
        ("Broken plan maths", "Other apps double-count exercise and hide how your target was set."),
        ("US-centric data", "UK own-brand barcodes go unrecognised; labels don't recompute."),
        ("Oversold guessing", "A confident single number for food a photo physically can't read."),
    ]

    var body: some View {
        OnboardingScaffold(
            progress: progress, onBack: onBack,
            title: "We read the one-star reviews so you don't live them",
            subtitle: "Scran is built against the four failures of the big AI calorie apps. Each one is a design rule here.",
            ctaTitle: "Continue", onContinue: onContinue
        ) {
            VStack(spacing: 12) {
                ForEach(Array(receipts.enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: 8) {
                        SourceBadge(source: .estimate, customText: r.0)
                        Text(r.1).font(ScranFont.body(15, relativeTo: .body))
                            .foregroundStyle(ScranColor.textMuted)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(ScranColor.panel))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ScranColor.line))
                }
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(ScranColor.verified)
                    Text("UK-built · your data stays in the UK/EU, never sold")
                        .font(ScranFont.mono(12, relativeTo: .caption))
                        .foregroundStyle(ScranColor.textMuted)
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Permission prime (honest)

struct PermissionPrimeScreen: View {
    var progress: Double
    var onBack: (() -> Void)? = nil
    let icon: String
    let title: String
    let subtitle: String
    let primaryTitle: String
    let onPrimary: () async -> Void
    let onSkip: () -> Void

    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressBar(progress: progress, onBack: onBack)
            Spacer()
            ZStack {
                RadialGlow(diameter: 300)
                Image(systemName: icon).font(.system(size: 58))
                    .foregroundStyle(ScranColor.verified)
                    .shadow(color: ScranColor.verified.opacity(0.5), radius: 16)
            }
            Text(title)
                .font(ScranFont.display(28, relativeTo: .largeTitle)).textCase(.uppercase)
                .multilineTextAlignment(.center).foregroundStyle(ScranColor.textPrimary)
                .padding(.horizontal, 24).padding(.top, 8)
            Text(subtitle)
                .font(ScranFont.body(16, relativeTo: .body)).foregroundStyle(ScranColor.textMuted)
                .multilineTextAlignment(.center).padding(.horizontal, 32).padding(.top, 10)
            Spacer()
            VStack(spacing: 6) {
                PrimaryButton(title: working ? "…" : primaryTitle, enabled: !working) {
                    working = true
                    Task { await onPrimary(); working = false }
                }
                Button("Not now", action: onSkip)
                    .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(ScranColor.textMuted).padding(.vertical, 6)
            }
            .padding(.horizontal, 20).padding(.bottom, 8)
        }
        .scranScreen()
    }
}

enum OnboardingPermissions {
    static func requestNotifications() async {
        #if canImport(UIKit)
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        #endif
    }
}
