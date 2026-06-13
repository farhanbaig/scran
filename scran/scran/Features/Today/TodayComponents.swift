//
//  TodayComponents.swift
//  scran
//
//  The Today hero pieces: calorie ring, macro bars, and the "evidence bar" that
//  shows what proportion of today's calories are verified / database / estimate.
//

import SwiftUI

struct CalorieRing: View {
    let consumed: Double
    let target: Double

    private var progress: Double { target > 0 ? min(consumed / target, 1) : 0 }
    private var remaining: Double { target - consumed }
    private var over: Bool { remaining < 0 }
    private var ringColor: Color { over ? ScranColor.error : ScranColor.verified }

    var body: some View {
        ZStack {
            // Track is a faint tint of the ring colour — no neutral grey.
            Circle().stroke(ringColor.opacity(0.15), lineWidth: 14)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColor.opacity(0.5), radius: 12)
                .animation(.snappy(duration: 0.4), value: progress)
            VStack(spacing: 2) {
                Text(ScranFormat.int(abs(remaining)))
                    .font(ScranFont.mono(44, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(ringColor)
                    .shadow(color: ringColor.opacity(0.5), radius: 12)
                    .contentTransition(.numericText())
                Text(over ? "kcal over" : "kcal left")
                    .font(ScranFont.mono(13, relativeTo: .footnote))
                    .foregroundStyle(ScranColor.textMuted)
                Text("\(ScranFormat.int(consumed)) / \(ScranFormat.int(target))")
                    .font(ScranFont.mono(12, relativeTo: .caption))
                    .foregroundStyle(ScranColor.textMuted)
                    .padding(.top, 4)
            }
        }
        .frame(width: 196, height: 196)
        .accessibilityElement()
        .accessibilityLabel("\(ScranFormat.int(abs(remaining))) kilocalories \(over ? "over" : "left"), \(ScranFormat.int(consumed)) of \(ScranFormat.int(target)) eaten, \(Int((progress * 100).rounded())) percent of daily target")
    }
}

struct MacroBar: View {
    let label: String
    let consumed: Double
    let target: Double
    var tint: Color = ScranColor.textPrimary
    /// Optional nutrient glyph shown before the label (see MacroGlyph).
    var icon: String? = nil

    private var progress: Double { target > 0 ? min(consumed / target, 1) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Label on its own line — never competes with the value for width.
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
                Text(label).font(ScranFont.body(12, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(ScranColor.textMuted)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.16)).frame(height: 6)
                    Capsule().fill(tint).frame(width: geo.size.width * progress, height: 6)
                }
            }
            .frame(height: 6)
            // Value on its own line below the bar — full column width, no crop.
            Text("\(ScranFormat.int(consumed)) / \(ScranFormat.int(target))g")
                .font(ScranFont.mono(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(ScranColor.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(ScranFormat.int(consumed)) of \(ScranFormat.int(target)) grams")
    }
}

/// The evidence bar — proportion of today's kcal by source colour.
struct EvidenceBar: View {
    let verifiedKcal: Double
    let databaseKcal: Double
    let estimateKcal: Double
    let otherKcal: Double

    private var total: Double { verifiedKcal + databaseKcal + estimateKcal + otherKcal }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Today's evidence")
            GeometryReader { geo in
                HStack(spacing: 2) {
                    segment(verifiedKcal, ScranColor.verified, geo.size.width)
                    segment(databaseKcal, ScranColor.database, geo.size.width)
                    segment(estimateKcal, ScranColor.estimate, geo.size.width)
                    segment(otherKcal, ScranColor.textMuted, geo.size.width)
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            .background(Capsule().fill(ScranColor.verified.opacity(0.12)))
            FlowLayout(spacing: 14, lineSpacing: 6) {
                legend("Verified", ScranColor.verified, verifiedKcal)
                legend("Database", ScranColor.database, databaseKcal)
                legend("Estimate", ScranColor.estimate, estimateKcal)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(evidenceSummary)
    }

    private var evidenceSummary: String {
        guard total > 0 else { return "Today's evidence: nothing logged yet" }
        let pct = { (v: Double) in Int((v / total * 100).rounded()) }
        return "Today's evidence: \(pct(verifiedKcal)) percent verified, \(pct(databaseKcal)) percent database, \(pct(estimateKcal)) percent estimate"
    }

    private func segment(_ value: Double, _ color: Color, _ width: CGFloat) -> some View {
        Rectangle().fill(color)
            .frame(width: total > 0 ? width * (value / total) : 0)
    }

    private func legend(_ name: String, _ color: Color, _ value: Double) -> some View {
        let pct = total > 0 ? Int((value / total * 100).rounded()) : 0
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(name) \(pct)%")
                .font(ScranFont.mono(12, relativeTo: .caption))
                .foregroundStyle(ScranColor.textMuted)
        }
    }
}
