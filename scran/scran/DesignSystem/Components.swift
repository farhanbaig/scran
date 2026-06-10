//
//  Components.swift
//  scran
//
//  Shared primitives: cards, the single primary CTA, segmented control, steppers,
//  banners, the radial green glow, and number formatting. 8pt spacing grid,
//  20pt card radius, 14pt CTA radius.
//

import SwiftUI

// MARK: - Number formatting (Space Mono, never reflow)

enum ScranFormat {
    private static let kcal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "en_GB")
        return f
    }()

    static func int(_ value: Double) -> String {
        kcal.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value.rounded()))"
    }

    /// Grams with up to one decimal, trimmed.
    static func grams(_ value: Double) -> String {
        if value == value.rounded() { return "\(Int(value))g" }
        return String(format: "%.1fg", value)
    }

    static func kcalText(_ value: Double) -> String { "\(int(value)) kcal" }
}

// MARK: - Card

struct ScranCard<Content: View>: View {
    var background: Color = ScranColor.panel
    var border: Color = ScranColor.line
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(background))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
    }
}

// MARK: - Primary CTA (one per screen)

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            HStack(spacing: 10) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
                    .font(ScranFont.body(16, weight: .bold, relativeTo: .headline))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(ScranColor.onVerified)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ScranColor.verified)
            )
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }
}

/// Secondary / ghost button on a hairline border.
struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            HStack(spacing: 10) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(ScranFont.body(16, weight: .semibold, relativeTo: .headline))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(ScranColor.textPrimary)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ScranColor.panel))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ScranColor.lineStrong, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Segmented control

struct ScranSegmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let isSelected = opt.0 == selection
                Button {
                    Haptics.selection()
                    selection = opt.0
                } label: {
                    Text(opt.1)
                        .font(ScranFont.body(13, weight: .bold, relativeTo: .footnote))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(isSelected ? ScranColor.bg : ScranColor.textMuted)
                        .background(isSelected ? ScranColor.textPrimary : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(ScranColor.lineStrong, lineWidth: 1))
    }
}

// MARK: - Numeric stepper (grams / quantity)

struct ScranStepper: View {
    let label: String
    @Binding var value: Double
    var step: Double = 1
    var range: ClosedRange<Double> = 0...100000
    var unit: String = ""
    var format: (Double) -> String

    var body: some View {
        HStack {
            Text(label)
                .font(ScranFont.body(15, weight: .medium, relativeTo: .body))
                .foregroundStyle(ScranColor.textMuted)
            Spacer()
            HStack(spacing: 14) {
                stepButton(systemName: "minus") {
                    value = max(range.lowerBound, value - step)
                }
                Text(format(value))
                    .font(ScranFont.mono(16, weight: .bold, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary)
                    .frame(minWidth: 64)
                    .contentTransition(.numericText())
                stepButton(systemName: "plus") {
                    value = min(range.upperBound, value + step)
                }
            }
        }
    }

    private func stepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.snappy(duration: 0.15)) { action() }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 34, height: 34)
                .foregroundStyle(ScranColor.textPrimary)
                .background(Circle().fill(ScranColor.panel2))
                .overlay(Circle().strokeBorder(ScranColor.lineStrong, lineWidth: 1))
        }
        .buttonStyle(PressableStyle(scale: 0.9))
    }
}

// MARK: - Banners (success / error), LAW 3

struct ScranBanner: View {
    enum Kind { case success, error, info }
    let kind: Kind
    let text: String

    private var color: Color {
        switch kind {
        case .success: return ScranColor.verified
        case .error:   return ScranColor.error
        case .info:    return ScranColor.database
        }
    }
    private var icon: String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .error:   return "exclamationmark.triangle.fill"
        case .info:    return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text)
                .font(ScranFont.body(14, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(ScranColor.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.13)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Radial green glow (Plan Reveal + Paywall only)

struct RadialGlow: View {
    var color: Color = ScranColor.verified
    var opacity: Double = 0.13
    var diameter: CGFloat = 520

    var body: some View {
        RadialGradient(
            gradient: Gradient(colors: [color.opacity(opacity), .clear]),
            center: .center, startRadius: 0, endRadius: diameter / 2
        )
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }
}

// MARK: - Eyebrow / kicker (mono, tracked, with leading rule)

struct Eyebrow: View {
    let text: String
    var color: Color = ScranColor.textMuted
    var ruleColor: Color = ScranColor.lineStrong

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(ruleColor).frame(width: 34, height: 2)
            Text(text)
                .font(ScranFont.mono(12, weight: .bold, relativeTo: .caption))
                .tracking(2.0)
                .textCase(.uppercase)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Screen background

struct ScranBackground: View {
    var body: some View {
        ScranColor.bg.ignoresSafeArea()
    }
}

extension View {
    /// Wraps a view in the standard dark background.
    func scranScreen() -> some View {
        self.background(ScranColor.bg.ignoresSafeArea())
    }
}
