//
//  LogSheet.swift
//  scran
//
//  Screen 4. Four ways in: scan barcode / photograph label / photograph plate /
//  saved meals, plus manual entry. Scan modes are grouped and each row carries a
//  source-coloured icon tile; AI modes (label/plate) show their scan cost so the
//  free-tier budget is never a surprise.
//

import SwiftUI

struct LogSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    /// Called after the sheet dismisses itself, to launch the chosen flow.
    var onSelect: (LogFlowKind) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                section("Scan") {
                    modeRow(kind: .barcode, source: .barcode, icon: "barcode.viewfinder",
                            title: "Scan barcode",
                            subtitle: "Packaged food — checks the UK database.",
                            tag: .free, requiresNetwork: true, isAI: false)
                    modeRow(kind: .label, source: .label, icon: "doc.text.viewfinder",
                            title: "Photograph label",
                            subtitle: "Reads the per-100g nutrition table properly.",
                            tag: .ai, requiresNetwork: true, isAI: true)
                    modeRow(kind: .plate, source: .estimate, icon: "fork.knife",
                            title: "Photograph plate",
                            subtitle: "An honest range with a confidence score.",
                            tag: .ai, requiresNetwork: true, isAI: true)
                }

                section("Quick") {
                    modeRow(kind: .saved, source: .label, icon: "bookmark.fill",
                            title: "Saved meals",
                            subtitle: "One tap to re-log a regular meal.",
                            tag: .none, requiresNetwork: false, isAI: false, tinted: false)
                    modeRow(kind: .manual, source: .manual, icon: "square.and.pencil",
                            title: "Enter manually",
                            subtitle: "Type the numbers yourself — always works.",
                            tag: .none, requiresNetwork: false, isAI: false, tinted: false)
                }

                if !app.isOnline {
                    ScranBanner(kind: .info,
                                text: "You're offline. Barcode, label and plate scanning need a connection — manual and saved meals still work.")
                }
            }
            .padding(20)
            .padding(.bottom, 8)
        }
        .scranScreen()
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Log food")
                .font(ScranFont.display(30, relativeTo: .largeTitle)).textCase(.uppercase)
                .foregroundStyle(ScranColor.textPrimary)
            if let r = app.quota.remaining {
                quotaPill(remaining: r)
            } else if app.isPro {
                Text("Unlimited AI scans")
                    .font(ScranFont.body(14, relativeTo: .footnote))
                    .foregroundStyle(ScranColor.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quotaPill(remaining r: Int) -> some View {
        let exhausted = r <= 0
        let tint = exhausted ? ScranColor.error : (r <= 1 ? ScranColor.estimate : ScranColor.verified)
        return HStack(spacing: 7) {
            Image(systemName: exhausted ? "exclamationmark.circle.fill" : "sparkles")
                .font(.system(size: 12, weight: .bold))
                .accessibilityHidden(true)
            Text(exhausted ? "No AI scans left today"
                           : "\(r) AI \(r == 1 ? "scan" : "scans") left today")
                .font(ScranFont.body(13, weight: .semibold, relativeTo: .footnote))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Capsule().fill(tint.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Section

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title)
            VStack(spacing: 10) { content() }
        }
    }

    // MARK: - Mode row

    private enum Tag { case free, ai, none }

    private func modeRow(kind: LogFlowKind, source: EntrySource, icon: String,
                         title: String, subtitle: String, tag: Tag,
                         requiresNetwork: Bool, isAI: Bool, tinted: Bool = true) -> some View {
        let disabled = requiresNetwork && !app.isOnline
        return Button {
            if isAI && !app.canStartAIScan() { dismiss(); return }
            launch(kind)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(tinted ? source.color.opacity(0.14) : ScranColor.panel2)
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(tinted ? source.color : ScranColor.textPrimary)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(ScranFont.body(16, weight: .bold, relativeTo: .body))
                        .foregroundStyle(ScranColor.textPrimary)
                    Text(subtitle)
                        .font(ScranFont.body(13, relativeTo: .footnote))
                        .foregroundStyle(ScranColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                trailingTag(tag)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tinted ? source.color : ScranColor.verified)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(ScranColor.bg)
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ScranColor.lineStrong, lineWidth: 1))
            .opacity(disabled ? 0.5 : 1)
        }
        .buttonStyle(PressableStyle())
        .disabled(disabled)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle + (tag == .ai ? ". Uses one AI scan." : ""))
    }

    @ViewBuilder private func trailingTag(_ tag: Tag) -> some View {
        switch tag {
        case .ai:
            tagPill("1 SCAN", color: ScranColor.estimate)
        case .free:
            tagPill("FREE", color: ScranColor.verified)
        case .none:
            EmptyView()
        }
    }

    private func tagPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(ScranFont.mono(9, weight: .bold, relativeTo: .caption2))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.13)))
            .accessibilityHidden(true)
    }

    // MARK: - Launch

    private func launch(_ kind: LogFlowKind) {
        let entry: String
        switch kind {
        case .barcode: entry = "barcode"
        case .label:   entry = "label"
        case .plate:   entry = "plate"
        case .saved:   entry = "saved"
        case .manual:  entry = "manual"
        }
        app.analytics.track(.logOpened(entryPoint: entry))
        dismiss()
        onSelect(kind)
    }
}
