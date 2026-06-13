//
//  LogFlow.swift
//  scran
//
//  Coordinator + container for the logging flows launched from the Log sheet.
//  Each flow is a NavigationStack that ends at the Entry Editor.
//

import SwiftUI
import Observation
#if canImport(UIKit)
import UIKit
#endif

enum LogFlowKind: Identifiable {
    case barcode, label, plate, saved, manual
    var id: Int { hashValue }
}

/// Boxes a reference-type draft so it can travel through a Hashable nav path.
struct DraftBox: Identifiable, Hashable {
    let id = UUID()
    let draft: EntryDraft
    static func == (lhs: DraftBox, rhs: DraftBox) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum ScanDestination: Hashable {
    case editor(DraftBox)
    case labelCamera
}

@MainActor
@Observable
final class LogCoordinator {
    var path: [ScanDestination] = []
    private let close: () -> Void
    init(close: @escaping () -> Void) { self.close = close }

    func cancel() { close() }
    func finished() { close() }
    func showEditor(_ draft: EntryDraft) { path.append(.editor(DraftBox(draft: draft))) }
    func showLabelCamera() { path.append(.labelCamera) }
    func showManualEntry() { path.append(.editor(DraftBox(draft: EntryDraft()))) }
}

struct LogFlowView: View {
    let kind: LogFlowKind
    @State private var coordinator: LogCoordinator
    @State private var manualDraft = EntryDraft()

    init(kind: LogFlowKind, onClose: @escaping () -> Void) {
        self.kind = kind
        _coordinator = State(initialValue: LogCoordinator(close: onClose))
    }

    var body: some View {
        @Bindable var coord = coordinator
        return NavigationStack(path: $coord.path) {
            root(coordinator)
                .navigationDestination(for: ScanDestination.self) { dest in
                    switch dest {
                    case .editor(let box):
                        EntryEditorView(draft: box.draft, onLogged: { coordinator.finished() })
                    case .labelCamera:
                        #if canImport(UIKit)
                        LabelScanScreen(coordinator: coordinator)
                        #else
                        EmptyView()
                        #endif
                    }
                }
        }
        .tint(ScranColor.verified)
    }

    @ViewBuilder
    private func root(_ coord: LogCoordinator) -> some View {
        switch kind {
        #if canImport(UIKit)
        case .barcode: BarcodeScanScreen(coordinator: coord)
        case .label:   LabelScanScreen(coordinator: coord)
        case .plate:   PlateScanScreen(coordinator: coord)
        #else
        case .barcode, .label, .plate:
            Text("Camera unavailable").foregroundStyle(ScranColor.textMuted).scranScreen()
        #endif
        case .saved:
            SavedMealsView(mode: .picker, onLogged: { coord.finished() })
                .toolbar { closeButton(coord) }
        case .manual:
            EntryEditorView(draft: manualDraft, onLogged: { coord.finished() })
                .navigationTitle("Manual entry")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { closeButton(coord) }
        }
    }

    /// These roots have no full-screen cancel of their own (unlike the camera
    /// screens), so give them an explicit Close so the sheet can be dismissed.
    @ToolbarContentBuilder
    private func closeButton(_ coord: LogCoordinator) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { Haptics.tap(); coord.cancel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ScranColor.textPrimary)
            }
            .accessibilityLabel("Close")
        }
    }
}
