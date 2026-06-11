//
//  OnboardingKit.swift
//  scran
//
//  Reusable Confident-Dark building blocks for a data-driven onboarding funnel.
//  Matches the craft of best-in-class funnels (progress, momentum, pinned CTA)
//  without the dark patterns. Scroll indicators are hidden everywhere per brief.
//

import SwiftUI

// MARK: - Progress bar + back

struct OnboardingProgressBar: View {
    /// 0...1
    let progress: Double
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            if let onBack {
                Button(action: { Haptics.selection(); onBack() }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(ScranColor.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(ScranColor.panel))
                        .overlay(Circle().strokeBorder(ScranColor.line, lineWidth: 1))
                }
                .buttonStyle(PressableStyle(scale: 0.9))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(ScranColor.lineStrong).frame(height: 6)
                    Capsule().fill(ScranColor.verified)
                        .frame(width: max(6, geo.size.width * progress), height: 6)
                        .shadow(color: ScranColor.verified.opacity(0.5), radius: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .animation(.snappy(duration: 0.3), value: progress)
    }
}

// MARK: - Header

struct OnboardingHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(ScranFont.display(32, relativeTo: .largeTitle))
                .textCase(.uppercase)
                .foregroundStyle(ScranColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(ScranFont.body(16, relativeTo: .body))
                    .foregroundStyle(ScranColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Scaffold

/// Standard onboarding screen: progress + back, scrollable header/content, and a
/// pinned bottom CTA that disables until the step is valid.
struct OnboardingScaffold<Content: View>: View {
    let progress: Double
    var onBack: (() -> Void)? = nil
    let title: String
    var subtitle: String? = nil
    var ctaTitle: String = "Continue"
    var ctaEnabled: Bool = true
    var secondaryTitle: String? = nil
    var onSecondary: (() -> Void)? = nil
    let onContinue: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressBar(progress: progress, onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    OnboardingHeader(title: title, subtitle: subtitle)
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .scranScreen()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                PrimaryButton(title: ctaTitle, enabled: ctaEnabled, action: onContinue)
                if let secondaryTitle, let onSecondary {
                    Button(secondaryTitle, action: onSecondary)
                        .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(ScranColor.textMuted)
                        .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(
                ScranColor.bg
                    .overlay(alignment: .top) { Rectangle().fill(ScranColor.line).frame(height: 1) }
                    .ignoresSafeArea()
            )
        }
    }
}

// MARK: - Choice card (single + multi)

struct ChoiceCard: View {
    let title: String
    var subtitle: String? = nil
    var systemIcon: String? = nil
    let isSelected: Bool
    var isMulti: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: { Haptics.selection(); action() }) {
            HStack(spacing: 14) {
                if let systemIcon {
                    Image(systemName: systemIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isSelected ? ScranColor.verified : ScranColor.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(isSelected ? ScranColor.verifiedDim : ScranColor.panel2))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(ScranFont.body(16, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(ScranColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(ScranFont.body(13, relativeTo: .footnote))
                            .foregroundStyle(ScranColor.textMuted)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                indicator
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? ScranColor.verifiedDim : ScranColor.panel))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? ScranColor.verified.opacity(0.6) : ScranColor.line,
                              lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder private var indicator: some View {
        if isMulti {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(isSelected ? ScranColor.verified : ScranColor.lineStrong)
        } else {
            ZStack {
                Circle().strokeBorder(isSelected ? ScranColor.verified : ScranColor.lineStrong, lineWidth: 2)
                    .frame(width: 24, height: 24)
                if isSelected {
                    Circle().fill(ScranColor.verified).frame(width: 13, height: 13)
                }
            }
        }
    }
}

/// Convenience list builder for a single-select group bound to an Optional.
struct SingleSelectList<T: Identifiable & Hashable>: View {
    let options: [T]
    @Binding var selection: T?
    let label: (T) -> String
    var subtitle: (T) -> String? = { _ in nil }
    var icon: (T) -> String? = { _ in nil }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(options) { opt in
                ChoiceCard(title: label(opt), subtitle: subtitle(opt), systemIcon: icon(opt),
                           isSelected: selection == opt) { selection = opt }
            }
        }
    }
}

/// Convenience list builder for a multi-select group bound to a Set.
struct MultiSelectList<T: Identifiable & Hashable>: View {
    let options: [T]
    @Binding var selection: Set<T>
    let label: (T) -> String
    var icon: (T) -> String? = { _ in nil }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(options) { opt in
                ChoiceCard(title: label(opt), systemIcon: icon(opt),
                           isSelected: selection.contains(opt), isMulti: true) {
                    if selection.contains(opt) { selection.remove(opt) } else { selection.insert(opt) }
                }
            }
        }
    }
}
