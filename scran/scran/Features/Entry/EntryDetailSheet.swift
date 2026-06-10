//
//  EntryDetailSheet.swift
//  scran
//
//  Tap a logged entry to inspect and adjust it. Editing serving size or quantity
//  recomputes every nutrient instantly (the core acceptance criterion).
//

import SwiftUI
import SwiftData

struct EntryDetailSheet: View {
    @Bindable var entry: FoodEntry
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    SourceBadge(source: entry.sourceEnum, confidence: entry.confidence)
                    Spacer()
                }
                Text(entry.name)
                    .font(ScranFont.body(22, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(ScranColor.textPrimary)
                if let brand = entry.brand {
                    Text(brand).font(ScranFont.body(14, relativeTo: .body))
                        .foregroundStyle(ScranColor.textMuted)
                }

                ScranCard(background: ScranColor.panel2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ScranFormat.int(entry.total.kcal))
                            .font(ScranFont.mono(36, weight: .bold, relativeTo: .largeTitle))
                            .foregroundStyle(ScranColor.verified)
                            .shadow(color: ScranColor.verified.opacity(0.5), radius: 12)
                            .contentTransition(.numericText())
                        Text("kcal").font(ScranFont.mono(15, relativeTo: .body))
                            .foregroundStyle(ScranColor.textMuted)
                        Spacer()
                        MacroTriple(protein: entry.total.proteinG, carbs: entry.total.carbsG,
                                    fat: entry.total.fatG)
                    }
                    .animation(.snappy(duration: 0.2), value: entry.total.kcal)
                }

                ScranCard {
                    VStack(spacing: 16) {
                        ScranStepper(label: "Serving size", value: $entry.servingSizeG, step: 10,
                                     range: 1...5000, format: { ScranFormat.grams($0) })
                        Divider().overlay(ScranColor.line)
                        ScranStepper(label: "Quantity", value: $entry.quantity, step: 0.5,
                                     range: 0.5...50,
                                     format: { $0 == $0.rounded() ? "\(Int($0))×" : String(format: "%.1f×", $0) })
                    }
                }

                if !entry.clarifications.isEmpty {
                    ScranCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CLARIFIED")
                                .font(ScranFont.mono(11, weight: .bold, relativeTo: .caption2))
                                .tracking(1.2).foregroundStyle(ScranColor.textMuted)
                            ForEach(entry.clarifications, id: \.self) { c in
                                Text("// \(c)").font(ScranFont.mono(12, relativeTo: .caption))
                                    .foregroundStyle(ScranColor.textMuted)
                            }
                        }
                    }
                }

                Button(role: .destructive) { deleteEntry() } label: {
                    Text("Delete entry")
                        .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(ScranColor.error)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(ScranColor.error.opacity(0.12)))
                }
            }
            .padding(20)
        }
        .scranScreen()
        .navigationTitle("Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { save(); dismiss() }
                    .foregroundStyle(ScranColor.verified)
            }
        }
        .onChange(of: entry.servingSizeG) { _, _ in markDirty() }
        .onChange(of: entry.quantity) { _, _ in markDirty() }
    }

    private func markDirty() {
        entry.updatedAt = .now
        entry.syncState = SyncState.pending.rawValue
        app.analytics.track(.entryPortionEdited)
    }

    private func save() {
        try? context.save()
        let ctx = context
        Task { await app.sync.syncPending(context: ctx) }
    }

    private func deleteEntry() {
        entry.deletedAt = .now
        entry.syncState = SyncState.pending.rawValue
        try? context.save()
        Haptics.selection()
        let ctx = context
        Task { await app.sync.syncPending(context: ctx) }
        dismiss()
    }
}
