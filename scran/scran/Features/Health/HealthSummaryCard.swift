//
//  HealthSummaryCard.swift
//  scran
//
//  Shared presentation of Apple Health metrics — a small stat grid used on Today
//  (when connected) and inside Settings. Read-only and informational; activity is
//  never added back to the calorie budget.
//

import SwiftUI

/// One metric tile: icon, value, caption.
struct HealthStatTile: View {
    let icon: String
    let value: String
    let label: String
    var tint: Color = ScranColor.verified

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(value)
                .font(ScranFont.mono(18, weight: .bold, relativeTo: .title3))
                .foregroundStyle(ScranColor.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label)
                .font(ScranFont.body(11, relativeTo: .caption2))
                .foregroundStyle(ScranColor.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ScranColor.bg))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ScranColor.lineStrong))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// A responsive grid of whatever metrics are present in the snapshot.
struct HealthStatGrid: View {
    let snapshot: HealthSnapshot

    private var tiles: [HealthStatTile] {
        var t: [HealthStatTile] = []
        if let s = snapshot.steps, s >= 1 {
            t.append(HealthStatTile(icon: "figure.walk", value: Self.grouped(s), label: "Steps", tint: ScranColor.database))
        }
        if let e = snapshot.activeEnergyKcal, e >= 1 {
            t.append(HealthStatTile(icon: "flame.fill", value: "\(Int(e))", label: "Active kcal", tint: ScranColor.estimate))
        }
        if let x = snapshot.exerciseMinutes, x >= 1 {
            t.append(HealthStatTile(icon: "timer", value: "\(Int(x)) m", label: "Exercise", tint: ScranColor.verified))
        }
        if let sl = snapshot.sleepHours, sl >= 0.5 {
            t.append(HealthStatTile(icon: "bed.double.fill", value: String(format: "%.1f h", sl), label: "Sleep", tint: ScranColor.database))
        }
        if let hr = snapshot.restingHeartRate, hr >= 1 {
            t.append(HealthStatTile(icon: "heart.fill", value: "\(Int(hr))", label: "Resting bpm", tint: ScranColor.error))
        }
        return t
    }

    var body: some View {
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        LazyVGrid(columns: cols, spacing: 10) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in tile }
        }
    }

    static func grouped(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
    }
}

/// The Today card: "Apple Health · today" header + stat grid.
struct HealthTodayCard: View {
    let snapshot: HealthSnapshot

    var body: some View {
        ScranCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ScranColor.error)
                        .accessibilityHidden(true)
                    SectionLabel("Apple Health · today")
                }
                HealthStatGrid(snapshot: snapshot)
            }
        }
    }
}
