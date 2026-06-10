//
//  LogSheet.swift
//  scran
//
//  Screen 4. Four ways in: scan barcode / photograph label / photograph plate /
//  saved meals. Manual lives behind "Can't scan? Enter manually". Scan-mode
//  cards carry ghost 01/02/03 numerals and source-colour top strips (§3).
//

import SwiftUI

struct LogSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    /// Called after the sheet dismisses itself, to launch the chosen flow.
    var onSelect: (LogFlowKind) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                modeCard(number: "01", kind: .barcode, source: .barcode,
                         title: "Scan barcode",
                         subtitle: "Packaged food. Checks the UK database.",
                         requiresNetwork: true, isAI: false)

                modeCard(number: "02", kind: .label, source: .label,
                         title: "Photograph label",
                         subtitle: "Reads the per-100g nutrition table properly.",
                         requiresNetwork: true, isAI: true)

                modeCard(number: "03", kind: .plate, source: .estimate,
                         title: "Photograph plate",
                         subtitle: "An honest range with a confidence score.",
                         requiresNetwork: true, isAI: true)

                savedCard

                Button {
                    launch(.manual)
                } label: {
                    Text("Can't scan? Enter manually")
                        .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(ScranColor.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }

                if !app.isOnline {
                    ScranBanner(kind: .info,
                                text: "You're offline. Barcode, label and plate scanning need a connection — manual and saved meals still work.")
                }
            }
            .padding(20)
        }
        .scranScreen()
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Log food")
                .font(ScranFont.display(30, relativeTo: .largeTitle)).textCase(.uppercase)
                .foregroundStyle(ScranColor.textPrimary)
            if let counter = app.quota.counterText {
                Text("// \(counter)")
                    .font(ScranFont.mono(13, relativeTo: .footnote))
                    .foregroundStyle(app.quota.isExhausted ? ScranColor.estimate : ScranColor.textMuted)
            }
        }
        .padding(.bottom, 4)
    }

    private func modeCard(number: String, kind: LogFlowKind, source: EntrySource,
                          title: String, subtitle: String,
                          requiresNetwork: Bool, isAI: Bool) -> some View {
        let disabled = requiresNetwork && !app.isOnline
        return Button {
            if isAI && !app.canStartAIScan() { dismiss(); return }
            launch(kind)
        } label: {
            ZStack(alignment: .topTrailing) {
                // ghost numeral
                Text(number)
                    .font(ScranFont.display(46, relativeTo: .largeTitle))
                    .foregroundStyle(Color.white.opacity(0.06))
                    .padding(.trailing, 8).padding(.top, 4)

                VStack(alignment: .leading, spacing: 12) {
                    SourceBadge(source: source)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(ScranFont.display(20, relativeTo: .title3)).textCase(.uppercase)
                            .foregroundStyle(ScranColor.textPrimary)
                        Text(subtitle)
                            .font(ScranFont.body(14, relativeTo: .footnote))
                            .foregroundStyle(ScranColor.textMuted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ScranColor.panel)
                    .overlay(alignment: .top) {
                        Rectangle().fill(source.color).frame(height: 3)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
            )
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(ScranColor.line, lineWidth: 1))
            .opacity(disabled ? 0.45 : 1)
        }
        .buttonStyle(PressableStyle())
        .disabled(disabled)
    }

    private var savedCard: some View {
        Button { launch(.saved) } label: {
            HStack(spacing: 14) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(ScranColor.textMuted)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Saved meals")
                        .font(ScranFont.body(16, weight: .bold, relativeTo: .body))
                        .foregroundStyle(ScranColor.textPrimary)
                    Text("One tap to re-log a regular meal")
                        .font(ScranFont.body(13, relativeTo: .footnote))
                        .foregroundStyle(ScranColor.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(ScranColor.textMuted)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(ScranColor.panel))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(ScranColor.line, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

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
