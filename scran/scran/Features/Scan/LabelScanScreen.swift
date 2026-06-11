//
//  LabelScanScreen.swift
//  scran
//
//  Screen 6. Photograph a UK nutrition label → scan-label → Entry Editor
//  pre-filled with a VERIFIED LABEL badge. Unreadable shows an explicit error
//  and a retake path (LAW 3).
//

import SwiftUI
#if canImport(UIKit)
import UIKit

struct LabelScanScreen: View {
    @Environment(AppModel.self) private var app
    let coordinator: LogCoordinator

    private enum Stage: Equatable { case capturing, processing, error(String) }
    @State private var stage: Stage = .capturing
    @State private var captured: UIImage? = nil
    @State private var scanTask: Task<Void, Never>? = nil

    var body: some View {
        Group {
            switch stage {
            case .capturing:
                PhotoCaptureScreen(
                    title: "Photograph the label",
                    instruction: "Fill the frame with the nutrition table",
                    accent: ScranColor.verified,
                    showLabelGuide: true,
                    onCapture: { image in process(image) },
                    onCancel: { coordinator.cancel() })

            case .processing:
                ScanProgressView(accent: ScranColor.verified, message: "Reading the label…",
                                 image: captured,
                                 cancel: { scanTask?.cancel(); stage = .capturing })

            case .error(let msg):
                ScanErrorView(
                    accent: ScranColor.error,
                    title: "Couldn't read that",
                    message: msg,
                    retake: { stage = .capturing },
                    cancel: { coordinator.cancel() })
            }
        }
        .animation(.snappy(duration: 0.25), value: stage)
        .scranScreen()
    }

    private func process(_ image: UIImage) {
        captured = image
        stage = .processing
        guard let base64 = ImageCompressor.base64(from: image) else {
            stage = .error("That photo didn't encode properly. Try again.")
            return
        }
        scanTask = Task {
            do {
                let result = try await ScanService.scanLabel(imageBase64: base64)
                guard !Task.isCancelled else { return }
                app.quota.noteScanUsed(remainingFromServer: result.scansRemaining)
                switch result.status {
                case .ok:
                    Haptics.success()
                    app.analytics.track(.labelScan(ok: true, confidence: result.readConfidence))
                    let draft = EntryDraft.fromLabel(result)
                    draft.photo = image
                    coordinator.showEditor(draft)
                case .unreadable:
                    app.analytics.track(.labelScan(ok: false, confidence: 0))
                    Haptics.warning()
                    stage = .error("The nutrition table wasn't legible. Get closer, avoid glare, and keep the per-100g column in frame.")
                case .not_a_label:
                    Haptics.warning()
                    stage = .error("That doesn't look like a nutrition label. Point at the printed nutrition table on the packet.")
                }
            } catch SupabaseError.quotaExceeded(_, _) {
                app.presentPaywall(trigger: "quota")
                coordinator.cancel()
            } catch {
                // User backed out — no error screen for a cancelled scan.
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
                app.crash.capture(error, context: ["fn": "scan-label"])
                Haptics.error()
                stage = .error(app.isOnline
                    ? "Something went wrong reading the label. Try again."
                    : "You're offline — label scanning needs a connection. Your barcode and manual logging still work.")
            }
        }
    }
}
#endif
