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

// MARK: - Section label

/// Calm sentence-case section header. Replaces the old mono-caps eyebrows —
/// ALL-CAPS + tracking is now reserved for badges (SourceBadge, LevelChip,
/// PRO/FREE) and at most one hero eyebrow per screen, so labels stop shouting.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(ScranFont.body(17, weight: .bold, relativeTo: .headline))
            .foregroundStyle(ScranColor.textPrimary)
    }
}

// MARK: - Flow layout (wrapping chips)

/// Lays children left-to-right, wrapping to the next line when they don't fit.
/// Used for chip rows (e.g. the Settings "Your focus" summary).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 { x = 0; y += lineHeight + lineSpacing; lineHeight = 0 }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += lineHeight + lineSpacing; lineHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - AI scan quota pill

/// Shows remaining free AI scans. Subtle tinted pill while scans remain; when
/// exhausted it's a high-contrast solid red pill — a clear, highlighted stop.
/// Shared by Today and the Log sheet.
struct QuotaPill: View {
    let remaining: Int
    var body: some View {
        let exhausted = remaining <= 0
        let tint = exhausted ? ScranColor.error : (remaining <= 1 ? ScranColor.estimate : ScranColor.positive)
        HStack(spacing: 7) {
            Image(systemName: exhausted ? "exclamationmark.circle.fill" : "sparkles")
                .font(.system(size: 13, weight: .bold))
                .accessibilityHidden(true)
            Text(exhausted ? "No AI scans left today"
                           : "\(remaining) AI \(remaining == 1 ? "scan" : "scans") left today")
                .font(ScranFont.body(13, weight: .bold, relativeTo: .footnote))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(tint))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Card

struct ScranCard<Content: View>: View {
    /// Defaults to the screen colour (white in light mode); separation comes from
    /// a soft shadow + hairline border, not a grey fill.
    var background: Color = ScranColor.bg
    var border: Color = ScranColor.lineStrong
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 20
    /// Lays a faint dot-grid "graph paper" texture behind the content.
    var textured: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(background)
                    .overlay {
                        if textured {
                            DotField()
                                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        }
                    }
            )
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
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ScranColor.bg))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ScranColor.lineStrong, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Screen header (replaces system large titles, brand-set)

struct ScranHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(ScranFont.display(30, relativeTo: .largeTitle)).textCase(.uppercase)
                .foregroundStyle(ScranColor.verified)
            if let subtitle {
                Text(subtitle)
                    .font(ScranFont.body(15, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(ScranColor.textPrimary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
    /// Tap the value to type an exact number on a keypad.
    var editable: Bool = false
    /// +/- step scales with magnitude (small/medium/large) instead of a fixed step.
    var adaptive: Bool = false
    var format: (Double) -> String

    @State private var editing = false
    @State private var draft = ""

    /// Step that grows with the value so big and small portions both adjust fast.
    private var effectiveStep: Double {
        guard adaptive else { return step }
        switch value {
        case ..<50:  return 5
        case ..<200: return 10
        default:     return 25
        }
    }

    var body: some View {
        HStack {
            Text(label)
                .font(ScranFont.body(15, weight: .medium, relativeTo: .body))
                .foregroundStyle(ScranColor.textMuted)
            Spacer()
            HStack(spacing: 14) {
                stepButton(systemName: "minus") {
                    value = max(range.lowerBound, value - effectiveStep)
                }
                valueLabel
                stepButton(systemName: "plus") {
                    value = min(range.upperBound, value + effectiveStep)
                }
            }
        }
        // Exact entry via a native alert — an explicit "Set" button applies it.
        // Avoids keyboard-toolbar focus conflicts (no flaky "Done").
        .alert(label, isPresented: $editing) {
            TextField("Value", text: $draft)
                .keyboardType(.decimalPad)
            Button("Set") { commitEdit() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(unit.isEmpty ? "Type an exact value." : "Type an exact value in \(unit).")
        }
    }

    @ViewBuilder private var valueLabel: some View {
        Text(format(value))
            .font(ScranFont.mono(16, weight: .bold, relativeTo: .body))
            .foregroundStyle(ScranColor.textPrimary)
            .frame(minWidth: 64)
            .contentTransition(.numericText())
            .overlay(alignment: .bottom) {
                if editable {
                    Rectangle().fill(ScranColor.lineStrong)
                        .frame(height: 1).offset(y: 4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard editable else { return }
                draft = value == value.rounded() ? String(Int(value)) : String(value)
                editing = true
                Haptics.selection()
            }
            .accessibilityAddTraits(editable ? .isButton : [])
            .accessibilityHint(editable ? "Tap to type an exact value" : "")
    }

    private func commitEdit() {
        if let n = Double(draft.replacingOccurrences(of: ",", with: ".")) {
            value = min(range.upperBound, max(range.lowerBound, n))
        }
        editing = false
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
                .background(Circle().fill(ScranColor.bg))
                .overlay(Circle().strokeBorder(ScranColor.lineStrong, lineWidth: 1))
                .padding(5)  // 44pt hit target (HIG minimum); circle stays 34pt
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel("\(systemName == "minus" ? "Decrease" : "Increase") \(label)")
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

    /// Background for a pinned bottom action bar — matches the screen exactly
    /// (no translucent material band) with a hairline top edge.
    func scranBottomBar() -> some View {
        self.background(
            ScranColor.bg
                .overlay(alignment: .top) { Rectangle().fill(ScranColor.line).frame(height: 1) }
                .ignoresSafeArea()
        )
    }
}
