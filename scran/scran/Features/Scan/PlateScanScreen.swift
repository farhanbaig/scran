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
    @State private var result: PlateScanResult? = nil
    @State private var clarified: Bool? = nil   // nil = unanswered

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
                ScanProgressView(accent: ScranColor.estimate, message: "Estimating the plate…",
                                 image: captured)
            case .result:
                if let result { resultView(result) }
            case .error(let msg):
                ScanErrorView(accent: ScranColor.error, title: "Couldn't read the plate",
                              message: msg, retake: { stage = .capturing },
                              cancel: { coordinator.cancel() })
            }
        }
        .scranScreen()
    }

    // MARK: - Result

    private func resultView(_ r: PlateScanResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    SourceBadge(source: .estimate, confidence: adjustedConfidence(r))
                    Spacer()
                }
                Text("Honest estimate")
                    .font(ScranFont.display(28, relativeTo: .title)).textCase(.uppercase)
                    .foregroundStyle(ScranColor.textPrimary)

                // Range band, never a single false-precision number.
                bandCard(r)

                if let q = r.clarifyingQuestion {
                    clarifyChip(q, impact: r.clarifyingImpact)
                }

                Text("ITEMS")
                    .font(ScranFont.mono(12, weight: .bold, relativeTo: .caption))
                    .tracking(1.4).foregroundStyle(ScranColor.textMuted)
                ForEach(r.items) { item in
                    itemRow(item)
                }
            }
            .padding(20).padding(.bottom, 100)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Review & log", systemImage: "arrow.right") {
                let draft = combinedDraft(r)
                coordinator.showEditor(draft)
            }
            .padding(20).background(.ultraThinMaterial)
        }
    }

    private func bandCard(_ r: PlateScanResult) -> some View {
        let total = r.items.reduce(0) { $0 + $1.per100g.kcal * $1.estimatedGrams / 100 }
        let conf = adjustedConfidence(r)
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

    private func clarifyChip(_ question: String, impact: String?) -> some View {
        ScranCard(background: ScranColor.estimateDim, border: ScranColor.estimate.opacity(0.35)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(question)
                    .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary)
                if let impact {
                    Text("// \(impact)")
                        .font(ScranFont.mono(12, relativeTo: .caption))
                        .foregroundStyle(ScranColor.estimate)
                }
                HStack(spacing: 10) {
                    chipButton("Yes", selected: clarified == true) { clarified = true; Haptics.selection() }
                    chipButton("No", selected: clarified == false) { clarified = false; Haptics.selection() }
                }
            }
        }
    }

    private func chipButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(ScranFont.body(14, weight: .bold, relativeTo: .body))
                .padding(.vertical, 9).padding(.horizontal, 22)
                .foregroundStyle(selected ? ScranColor.bg : ScranColor.textPrimary)
                .background(Capsule().fill(selected ? ScranColor.estimate : ScranColor.panel))
                .overlay(Capsule().strokeBorder(ScranColor.estimate.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    private func itemRow(_ item: PlateScanResult.Item) -> some View {
        ScranCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(ScranFont.body(16, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(ScranColor.textPrimary)
                    Text("≈ \(ScranFormat.grams(item.estimatedGrams)) · \(Int((item.confidence * 100).rounded()))%")
                        .font(ScranFont.mono(12, relativeTo: .caption))
                        .foregroundStyle(ScranColor.textMuted)
                }
                Spacer()
                Text(ScranFormat.kcalText(item.per100g.kcal * item.estimatedGrams / 100))
                    .font(ScranFont.mono(15, weight: .bold, relativeTo: .body))
                    .foregroundStyle(ScranColor.estimate)
            }
        }
    }

    // MARK: - Logic

    /// Answering "yes" to an oil/sugar question nudges confidence up (we now know).
    private func adjustedConfidence(_ r: PlateScanResult) -> Double {
        guard r.clarifyingQuestion != nil, let answered = clarified else { return r.overallConfidence }
        _ = answered
        return min(0.95, r.overallConfidence + 0.1)
    }

    private func combinedDraft(_ r: PlateScanResult) -> EntryDraft {
        // Merge plate items into a single entry (per-100g blended over total grams).
        let totalGrams = r.items.reduce(0) { $0 + $1.estimatedGrams }
        var totalBlock = NutrientBlock.zero
        for item in r.items { totalBlock = totalBlock + item.per100g.scaled(toGrams: item.estimatedGrams) }
        let per100g = totalGrams > 0 ? totalBlock.scaled(toGrams: 100 * 100 / totalGrams) : totalBlock
        var clar: [String] = []
        if let q = r.clarifyingQuestion, let a = clarified {
            clar.append("\(q) \(a ? "yes" : "no")")
        }
        let name = r.items.count == 1 ? r.items[0].name
            : r.items.prefix(2).map(\.name).joined(separator: " + ") + (r.items.count > 2 ? " +" : "")
        let draft = EntryDraft(name: name, source: .estimate, confidence: adjustedConfidence(r),
                               per100g: per100g, servingSizeG: totalGrams, quantity: 1,
                               clarifications: clar)
        draft.photo = captured
        return draft
    }

    private func process(_ image: UIImage) {
        captured = image
        stage = .processing
        guard let base64 = ImageCompressor.base64(from: image) else {
            stage = .error("That photo didn't encode properly. Try again."); return
        }
        Task {
            do {
                let r = try await ScanService.scanPlate(imageBase64: base64)
                app.quota.noteScanUsed(remainingFromServer: r.scansRemaining)
                if r.status == .no_food || r.items.isEmpty {
                    Haptics.warning()
                    stage = .error("No food spotted. Frame the whole plate from above and try again.")
                } else {
                    app.analytics.track(.plateScan(confidence: r.overallConfidence,
                                                   clarified: r.clarifyingQuestion != nil))
                    result = r
                    stage = .result
                }
            } catch SupabaseError.quotaExceeded(_, _) {
                app.presentPaywall(trigger: "quota"); coordinator.cancel()
            } catch {
                app.crash.capture(error, context: ["fn": "scan-plate"])
                Haptics.error()
                stage = .error(app.isOnline
                    ? "Something went wrong. Try again."
                    : "You're offline — plate scanning needs a connection.")
            }
        }
    }
}
#endif
