//
//  PlateScanScreen.swift
//  scran
//
//  Screen 7. Photograph a plate → scan-plate → items with per-item confidence,
//  an honest overall band, and at most one clarifying chip (answering updates
//  numbers live) → Entry Editor with an ESTIMATE n% badge.
//

import SwiftUI
#if canImport(UIKit)
import UIKit

struct PlateScanScreen: View {
    @Environment(AppModel.self) private var app
    let coordinator: LogCoordinator

    private enum Stage: Equatable { case capturing, processing, result, error(String) }
    @State private var stage: Stage = .capturing
    @State private var captured: UIImage? = nil
    @State private var imageBase64: String? = nil
    @State private var result: PlateScanResult? = nil
    @State private var scanTask: Task<Void, Never>? = nil

    // User corrections ("that's mutton, not pork") — sent back with the photo
    // for a server-side re-estimate; kept for the entry's clarification trail.
    @State private var appliedCorrections: [String] = []
    @State private var showCorrectionSheet = false
    @State private var correctionText = ""

    // Selected answers to the AI's structured questions (prompt → chosen options).
    @State private var answers: [String: [String]] = [:]
    // The item being corrected via the "what is this?" sheet.
    @State private var editingItem: PlateScanResult.Item? = nil
    @State private var itemCorrectionText = ""

    var body: some View {
        Group {
            switch stage {
            case .capturing:
                PhotoCaptureScreen(
                    title: "Photograph the plate",
                    instruction: "Frame the whole plate from above",
                    accent: ScranColor.estimate,
                    onCapture: { process($0) },
                    onCancel: { coordinator.cancel() })
            case .processing:
                ScanProgressView(accent: ScranColor.estimate,
                                 message: appliedCorrections.isEmpty
                                     ? "Estimating the plate…"
                                     : "Recalculating with your correction…",
                                 image: captured,
                                 cancel: { scanTask?.cancel(); stage = .capturing })
            case .result:
                if let result { resultView(result) }
            case .error(let msg):
                ScanErrorView(accent: ScranColor.error, title: "Couldn't read the plate",
                              message: msg, retake: { stage = .capturing },
                              cancel: { coordinator.cancel() })
            }
        }
        .animation(.snappy(duration: 0.25), value: stage)
        .scranScreen()
        .sheet(isPresented: $showCorrectionSheet) { correctionSheet }
        .sheet(item: $editingItem) { item in itemCorrectionSheet(item) }
    }

    // MARK: - Result

    private func resultView(_ r: PlateScanResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    SourceBadge(source: .estimate, confidence: r.overallConfidence)
                    Spacer()
                }
                Text("Honest estimate")
                    .font(ScranFont.display(28, relativeTo: .title)).textCase(.uppercase)
                    .foregroundStyle(ScranColor.textPrimary)

                // Range band, never a single false-precision number.
                bandCard(r)

                if !r.questions.isEmpty { questionsSection(r) }

                Text("ITEMS")
                    .font(ScranFont.mono(12, weight: .bold, relativeTo: .caption))
                    .tracking(1.4).foregroundStyle(ScranColor.textMuted)
                Text("Tap an item to fix what it is.")
                    .font(ScranFont.body(12, relativeTo: .caption2))
                    .foregroundStyle(ScranColor.textMuted)
                ForEach(r.items) { item in
                    itemRow(item)
                }

                correctionCard
            }
            .padding(20).padding(.bottom, 100)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Review & log", systemImage: "arrow.right") {
                let draft = combinedDraft(r)
                coordinator.showEditor(draft)
            }
            .padding(20).scranBottomBar()
        }
    }

    private func bandCard(_ r: PlateScanResult) -> some View {
        let total = r.items.reduce(0) { $0 + $1.per100g.kcal * $1.estimatedGrams / 100 }
        let conf = r.overallConfidence
        let spread = total * (1 - conf) * 0.6
        let low = max(0, total - spread), high = total + spread
        return ScranCard(background: ScranColor.panel2) {
            VStack(alignment: .leading, spacing: 8) {
                Text("roughly")
                    .font(ScranFont.body(13, relativeTo: .footnote)).foregroundStyle(ScranColor.textMuted)
                Text("\(ScranFormat.int(low))–\(ScranFormat.int(high)) kcal")
                    .font(ScranFont.mono(30, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(ScranColor.estimate)
                Text("\(Int((conf * 100).rounded()))% confident overall")
                    .font(ScranFont.mono(13, relativeTo: .footnote)).foregroundStyle(ScranColor.textMuted)
            }
        }
    }

    // MARK: - Structured questions (AI-suggested, tappable options)

    private var hasAnswers: Bool { answers.values.contains { !$0.isEmpty } }

    private func questionsSection(_ r: PlateScanResult) -> some View {
        ScranCard(background: ScranColor.estimateDim, border: ScranColor.estimate.opacity(0.35)) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sharpen the estimate")
                    .font(ScranFont.body(16, weight: .bold, relativeTo: .headline))
                    .foregroundStyle(ScranColor.textPrimary)
                Text("Answer what you can — it makes the numbers more accurate and won't use another scan.")
                    .font(ScranFont.body(13, relativeTo: .footnote))
                    .foregroundStyle(ScranColor.textMuted)

                ForEach(r.questions) { q in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(q.prompt)
                            .font(ScranFont.body(14, weight: .semibold, relativeTo: .body))
                            .foregroundStyle(ScranColor.textPrimary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(q.options, id: \.self) { opt in
                                    optionChip(opt, selected: isSelected(q, opt)) { toggle(q, opt) }
                                }
                            }
                        }
                    }
                }

                PrimaryButton(title: "Update estimate", systemImage: "arrow.triangle.2.circlepath",
                              enabled: hasAnswers) {
                    applyAnswers(r)
                }
            }
        }
    }

    private func optionChip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.selection(); action() }) {
            Text(label)
                .font(ScranFont.body(14, weight: .semibold, relativeTo: .body))
                .padding(.vertical, 9).padding(.horizontal, 16)
                .foregroundStyle(selected ? ScranColor.bg : ScranColor.textPrimary)
                .background(Capsule().fill(selected ? ScranColor.estimate : ScranColor.panel))
                .overlay(Capsule().strokeBorder(ScranColor.estimate.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    private func isSelected(_ q: PlateScanResult.Question, _ opt: String) -> Bool {
        answers[q.prompt]?.contains(opt) ?? false
    }

    private func toggle(_ q: PlateScanResult.Question, _ opt: String) {
        var sel = answers[q.prompt] ?? []
        if q.multi {
            if let i = sel.firstIndex(of: opt) { sel.remove(at: i) } else { sel.append(opt) }
        } else {
            sel = sel == [opt] ? [] : [opt]
        }
        answers[q.prompt] = sel
    }

    private func applyAnswers(_ r: PlateScanResult) {
        let parts: [String] = r.questions.compactMap { q in
            guard let sel = answers[q.prompt], !sel.isEmpty else { return nil }
            return "\(q.prompt) → \(sel.joined(separator: ", "))"
        }
        guard !parts.isEmpty else { return }
        appliedCorrections.append(contentsOf: parts)
        rescan()
    }

    // MARK: - Per-item correction ("what is this?")

    private func itemCorrectionSheet(_ item: PlateScanResult.Item) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("We read this as \"\(item.name)\". What is it really?")
                    .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.alternatives.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(item.alternatives, id: \.self) { alt in
                            Button { correctItem(item, to: alt) } label: {
                                HStack {
                                    Text(alt).font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                                        .foregroundStyle(ScranColor.textPrimary)
                                    Spacer()
                                    Image(systemName: "arrow.right").foregroundStyle(ScranColor.estimate)
                                }
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 14).fill(ScranColor.panel))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ScranColor.line))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                TextField("Or type what it is…", text: $itemCorrectionText)
                    .font(ScranFont.body(15, relativeTo: .body))
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(ScranColor.panel))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ScranColor.line))
                PrimaryButton(title: "Recalculate", systemImage: "arrow.triangle.2.circlepath",
                              enabled: !itemCorrectionText.trimmingCharacters(in: .whitespaces).isEmpty) {
                    correctItem(item, to: itemCorrectionText.trimmingCharacters(in: .whitespaces))
                }
                Spacer()
            }
            .padding(20)
            .scranScreen()
            .navigationTitle("Fix this item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { editingItem = nil }.foregroundStyle(ScranColor.textMuted)
                }
            }
        }
        .presentationDetents([.medium])
        .scranAppearance()
    }

    private func correctItem(_ item: PlateScanResult.Item, to identity: String) {
        guard !identity.isEmpty else { return }
        appliedCorrections.append("The item read as \"\(item.name)\" is actually \(identity)")
        itemCorrectionText = ""
        editingItem = nil
        rescan()
    }

    /// "Not quite right?" — wrong name, wrong portion, or something missing all
    /// route through one free-text correction that triggers a re-estimate.
    private var correctionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Not quite right?")
                .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                .foregroundStyle(ScranColor.textPrimary)
            Text("Tell us what's wrong or missing and we'll recalculate — it won't use another scan.")
                .font(ScranFont.body(13, relativeTo: .footnote))
                .foregroundStyle(ScranColor.textMuted)
            SecondaryButton(title: "Correct & recalculate", systemImage: "arrow.triangle.2.circlepath") {
                correctionText = ""
                showCorrectionSheet = true
            }
            if !appliedCorrections.isEmpty {
                ForEach(appliedCorrections, id: \.self) { c in
                    Text("// applied: \(c)")
                        .font(ScranFont.mono(12, relativeTo: .caption))
                        .foregroundStyle(ScranColor.estimate)
                }
            }
        }
        .padding(.top, 6)
    }

    private var correctionSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("What did we get wrong or miss?")
                    .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary)
                TextField("e.g. That's mutton, not pork — and there's a chapati too",
                          text: $correctionText, axis: .vertical)
                    .lineLimit(2...4)
                    .font(ScranFont.body(15, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(ScranColor.panel))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ScranColor.line))
                Spacer()
                PrimaryButton(title: "Recalculate", systemImage: "arrow.triangle.2.circlepath",
                              enabled: !correctionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    let text = correctionText.trimmingCharacters(in: .whitespacesAndNewlines)
                    appliedCorrections.append(text)
                    showCorrectionSheet = false
                    rescan()
                }
            }
            .padding(20)
            .scranScreen()
            .navigationTitle("Correct the estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showCorrectionSheet = false }
                        .foregroundStyle(ScranColor.textMuted)
                }
            }
        }
        .presentationDetents([.height(300)])
        .scranAppearance()
    }

    private func amountText(_ item: PlateScanResult.Item) -> String {
        item.kind == .liquid
            ? "≈ \(ScranFormat.int(item.estimatedGrams)) ml"
            : "≈ \(ScranFormat.grams(item.estimatedGrams))"
    }

    private func itemRow(_ item: PlateScanResult.Item) -> some View {
        Button { Haptics.tap(); itemCorrectionText = ""; editingItem = item } label: {
            ScranCard {
                HStack(spacing: 10) {
                    Image(systemName: item.kind == .liquid ? "cup.and.saucer.fill" : "fork.knife")
                        .font(.system(size: 14))
                        .foregroundStyle(ScranColor.textMuted)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(ScranFont.body(16, weight: .semibold, relativeTo: .body))
                            .foregroundStyle(ScranColor.textPrimary)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text("\(amountText(item)) · \(Int((item.confidence * 100).rounded()))%")
                                .font(ScranFont.mono(12, relativeTo: .caption))
                                .foregroundStyle(ScranColor.textMuted)
                            if !item.alternatives.isEmpty {
                                Text("· not right?")
                                    .font(ScranFont.mono(12, relativeTo: .caption))
                                    .foregroundStyle(ScranColor.estimate)
                            }
                        }
                    }
                    Spacer()
                    Text(ScranFormat.kcalText(item.per100g.kcal * item.estimatedGrams / 100))
                        .font(ScranFont.mono(15, weight: .bold, relativeTo: .body))
                        .foregroundStyle(ScranColor.estimate)
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ScranColor.textMuted.opacity(0.6))
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Tap to correct what this item is")
    }

    // MARK: - Logic

    private func combinedDraft(_ r: PlateScanResult) -> EntryDraft {
        // Merge plate items into a single entry (per-100g blended over total grams).
        let totalGrams = r.items.reduce(0) { $0 + $1.estimatedGrams }
        var totalBlock = NutrientBlock.zero
        for item in r.items { totalBlock = totalBlock + item.per100g.scaled(toGrams: item.estimatedGrams) }
        let per100g = totalGrams > 0 ? totalBlock.scaled(toGrams: 100 * 100 / totalGrams) : totalBlock
        let clar = appliedCorrections.map { "Correction: \($0)" }
        let name = r.items.count == 1 ? r.items[0].name
            : r.items.prefix(2).map(\.name).joined(separator: " + ") + (r.items.count > 2 ? " +" : "")
        let draft = EntryDraft(name: name, source: .estimate, confidence: r.overallConfidence,
                               per100g: per100g, servingSizeG: totalGrams, quantity: 1,
                               clarifications: clar)
        draft.photo = captured
        return draft
    }

    /// Honest, actionable copy per failure mode — never a bare "something went wrong".
    private static func scanErrorMessage(_ error: Error, isOnline: Bool) -> String {
        guard isOnline else { return "You're offline — plate scanning needs a connection." }
        if case SupabaseError.http(let status, _) = error {
            switch status {
            case 429: return "Scanning is busy right now. Give it a few seconds and try again."
            case 500...599: return "The scan service hit a snag. Your photo is fine — try again."
            default: break
            }
        }
        if (error as? URLError)?.code == .timedOut {
            return "That scan took too long. Check your signal and try again."
        }
        return "Something went wrong. Try again."
    }

    private func process(_ image: UIImage) {
        captured = image
        appliedCorrections = []
        stage = .processing
        guard let base64 = ImageCompressor.base64(from: image) else {
            stage = .error("That photo didn't encode properly. Try again."); return
        }
        imageBase64 = base64
        runScan(correction: nil)
    }

    /// Re-estimate the SAME photo with the user's corrections as ground truth.
    /// Refinements don't consume a daily scan (server-enforced).
    private func rescan() {
        guard imageBase64 != nil else { return }
        stage = .processing
        runScan(correction: appliedCorrections.joined(separator: "; "))
    }

    private func runScan(correction: String?) {
        guard let base64 = imageBase64 else { return }
        let isRefinement = correction != nil
        scanTask = Task {
            do {
                let r = try await ScanService.scanPlate(imageBase64: base64, correction: correction)
                guard !Task.isCancelled else { return }
                app.quota.noteScanUsed(remainingFromServer: r.scansRemaining)
                if r.status == .no_food || r.items.isEmpty {
                    Haptics.warning()
                    if isRefinement, result != nil {
                        // Empty re-estimate: keep the previous valid result.
                        appliedCorrections.removeLast()
                        stage = .result
                    } else {
                        stage = .error("No food spotted. Frame the whole plate from above and try again.")
                    }
                } else {
                    Haptics.success()
                    app.analytics.track(.plateScan(confidence: r.overallConfidence,
                                                   clarified: !r.questions.isEmpty))
                    answers = [:]   // fresh questions arrived; clear stale selections
                    result = r
                    stage = .result
                }
            } catch SupabaseError.quotaExceeded(_, _) {
                app.presentPaywall(trigger: "quota"); coordinator.cancel()
            } catch {
                // User backed out — no error screen for a cancelled scan.
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
                app.crash.capture(error, context: ["fn": "scan-plate"])
                Haptics.error()
                if isRefinement, result != nil {
                    // Keep the previous (still valid) estimate rather than
                    // stranding the user on an error screen.
                    appliedCorrections.removeLast()
                    stage = .result
                } else {
                    stage = .error(Self.scanErrorMessage(error, isOnline: app.isOnline))
                }
            }
        }
    }
}
#endif
