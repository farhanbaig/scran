//
//  BarcodeScanScreen.swift
//  scran
//
//  Screen 5. Full-screen DataScanner → lookup-barcode. Found: Entry Editor with
//  a DATABASE badge. Not found: inline fallback card → label camera, the whole
//  point of a UK-first tracker (LAW 3, no dead ends).
//

import SwiftUI
#if canImport(UIKit)
import UIKit

struct BarcodeScanScreen: View {
    @Environment(AppModel.self) private var app
    let coordinator: LogCoordinator

    private enum Stage: Equatable { case scanning, looking, notFound(String), error(String) }
    @State private var stage: Stage = .scanning
    @State private var torchOn = false
    @State private var lastBarcode: String? = nil

    var body: some View {
        ZStack {
            ScranColor.bg.ignoresSafeArea()

            if BarcodeScannerRepresentable.isSupported {
                BarcodeScannerRepresentable(isTorchOn: torchOn) { payload in
                    guard stage == .scanning else { return }
                    handle(payload)
                }
                .ignoresSafeArea()
            } else {
                unsupported
            }

            VStack {
                topBar
                Spacer()
                switch stage {
                case .scanning:
                    hint("Point at a barcode")
                case .looking:
                    hint("Looking it up…")
                case .notFound(let code):
                    fallbackCard(code)
                case .error(let message):
                    errorCard(message)
                }
            }
            .padding(20)
        }
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack {
            Button { Haptics.tap(); coordinator.cancel() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(ScranColor.textPrimary)
                    .frame(width: 44, height: 44).background(Circle().fill(.black.opacity(0.45)))
            }
            .accessibilityLabel("Close scanner")
            Spacer()
            Button { torchOn.toggle(); Haptics.selection() } label: {
                Image(systemName: torchOn ? "bolt.fill" : "bolt.slash")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(torchOn ? ScranColor.database : ScranColor.textPrimary)
                    .frame(width: 44, height: 44).background(Circle().fill(.black.opacity(0.45)))
            }
            .accessibilityLabel(torchOn ? "Turn off flashlight" : "Turn on flashlight")
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(ScranFont.mono(13, relativeTo: .footnote))
            .foregroundStyle(ScranColor.textPrimary)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Capsule().fill(.black.opacity(0.5)))
            .padding(.bottom, 40)
    }

    private func fallbackCard(_ code: String) -> some View {
        ScranCard(background: ScranColor.panel2, border: ScranColor.lineStrong) {
            VStack(alignment: .leading, spacing: 14) {
                SourceBadge(source: .barcode, customText: "NOT IN DATABASE")
                Text("Not in the database")
                    .font(ScranFont.body(18, weight: .bold, relativeTo: .headline))
                    .foregroundStyle(ScranColor.textPrimary)
                Text("Photograph the nutrition label and we'll read it properly.")
                    .font(ScranFont.body(15, relativeTo: .body))
                    .foregroundStyle(ScranColor.textMuted)
                PrimaryButton(title: "Photograph label", systemImage: "camera") {
                    coordinator.showLabelCamera()
                }
                Button("Scan a different barcode") {
                    lastBarcode = nil; stage = .scanning
                }
                .font(ScranFont.body(14, weight: .semibold, relativeTo: .body))
                .foregroundStyle(ScranColor.textMuted)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 20)
    }

    private func errorCard(_ message: String) -> some View {
        ScranCard(background: ScranColor.panel2, border: ScranColor.error.opacity(0.35)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(ScranColor.error)
                        .accessibilityHidden(true)
                    Text("Couldn't check the database")
                        .font(ScranFont.body(18, weight: .bold, relativeTo: .headline))
                        .foregroundStyle(ScranColor.textPrimary)
                }
                Text(message)
                    .font(ScranFont.body(15, relativeTo: .body))
                    .foregroundStyle(ScranColor.textMuted)
                PrimaryButton(title: "Try again", systemImage: "arrow.clockwise") {
                    lastBarcode = nil; stage = .scanning
                }
                Button("Photograph the label instead") { coordinator.showLabelCamera() }
                    .font(ScranFont.body(14, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(ScranColor.textMuted)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 20)
    }

    private var unsupported: some View {
        VStack(spacing: 16) {
            Image(systemName: "barcode.viewfinder").font(.system(size: 40))
                .foregroundStyle(ScranColor.textMuted)
                .accessibilityHidden(true)
            Text("Barcode scanning needs a device camera.")
                .font(ScranFont.body(15, relativeTo: .body))
                .foregroundStyle(ScranColor.textMuted).multilineTextAlignment(.center)
            SecondaryButton(title: "Enter manually") { coordinator.showManualEntry() }
            Button("Cancel") { coordinator.cancel() }
                .foregroundStyle(ScranColor.textMuted)
        }.padding(32)
    }

    private func handle(_ payload: String) {
        guard payload != lastBarcode else { return }
        lastBarcode = payload
        stage = .looking
        Haptics.tap()
        Task {
            do {
                let r = try await ScanService.lookupBarcode(payload)
                if r.status == .found, r.per100g != nil {
                    app.analytics.track(.barcodeScanned(hit: true))
                    coordinator.showEditor(EntryDraft.fromBarcode(r))
                } else {
                    app.analytics.track(.barcodeScanned(hit: false))
                    app.analytics.track(.barcodeMiss(prefix: String(payload.prefix(7))))
                    Haptics.warning()
                    stage = .notFound(payload)
                }
            } catch {
                app.crash.capture(error, context: ["fn": "lookup-barcode"])
                Haptics.error()
                // A genuine failure (no session, network, server) — not a DB miss.
                stage = .error(app.isOnline
                    ? "We couldn't reach the food database. Check you're signed in and online, then try again."
                    : "You're offline. Barcode lookup needs a connection — your manual and saved-meal logging still work.")
            }
        }
    }
}
#endif
