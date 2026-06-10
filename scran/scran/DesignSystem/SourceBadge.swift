//
//  SourceBadge.swift
//  scran
//
//  The brand signature. Every food number in the app wears one of these.
//  Built once, rendered on every entry row, entry detail, and the evidence bar.
//
//  Spec: Space Mono 11pt bold, UPPERCASE, .08em tracking, 6×13pt padding,
//  1pt border at source colour @ 35%, fill at the Dim token, leading 7pt dot
//  in the source colour with a soft glow.
//

import SwiftUI

/// Provenance of a food entry's numbers. Maps 1:1 to FoodEntry.source.
enum EntrySource: String, CaseIterable, Sendable {
    case label      // VERIFIED LABEL — AI read a nutrition label photo
    case barcode    // DATABASE — Open Food Facts
    case estimate   // ESTIMATE n% — plate photo
    case manual     // neutral
    case saved      // neutral

    var color: Color {
        switch self {
        case .label:    return ScranColor.verified
        case .barcode:  return ScranColor.database
        case .estimate: return ScranColor.estimate
        case .manual, .saved: return ScranColor.textMuted
        }
    }

    var fill: Color {
        switch self {
        case .label:    return ScranColor.verifiedDim
        case .barcode:  return ScranColor.databaseDim
        case .estimate: return ScranColor.estimateDim
        case .manual, .saved: return ScranColor.panel
        }
    }

    /// Label text. Estimate appends a confidence percentage when supplied.
    func text(confidence: Double?) -> String {
        switch self {
        case .label:    return "VERIFIED LABEL"
        case .barcode:  return "DATABASE"
        case .estimate:
            if let c = confidence { return "ESTIMATE \(Int((c * 100).rounded()))%" }
            return "ESTIMATE"
        case .manual:   return "MANUAL"
        case .saved:    return "SAVED MEAL"
        }
    }
}

struct SourceBadge: View {
    let source: EntrySource
    var confidence: Double? = nil
    /// Free-text override for meta-labels rendered in the neutral style.
    var customText: String? = nil

    private var label: String { customText ?? source.text(confidence: confidence) }
    private var isNeutral: Bool { source == .manual || source == .saved || customText != nil }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(source.color)
                .frame(width: 7, height: 7)
                .shadow(color: source.color.opacity(0.8), radius: 5)
            Text(label)
                .font(ScranFont.mono(11, weight: .bold, relativeTo: .caption2))
                .tracking(0.88) // ≈ .08em at 11pt
                .textCase(.uppercase)
                .foregroundStyle(isNeutral ? ScranColor.textMuted : source.color)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 13)
        .background(
            Capsule(style: .continuous).fill(source.fill)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(source.color.opacity(isNeutral ? 0.16 : 0.35), lineWidth: 1)
        )
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch source {
        case .label:    return "Source: verified from a nutrition label"
        case .barcode:  return "Source: from the food database"
        case .estimate:
            let pct = confidence.map { " \(Int(($0 * 100).rounded())) percent confident" } ?? ""
            return "Source: photo estimate\(pct)"
        case .manual:   return "Source: entered manually"
        case .saved:    return "Source: saved meal"
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 14) {
        SourceBadge(source: .label)
        SourceBadge(source: .barcode)
        SourceBadge(source: .estimate, confidence: 0.78)
        SourceBadge(source: .manual)
        SourceBadge(source: .label, customText: "PER-100G · READ ✓")
    }
    .padding(40)
    .background(ScranColor.bg)
    .preferredColorScheme(.dark)
}
