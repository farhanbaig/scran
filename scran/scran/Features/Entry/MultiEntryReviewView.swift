//
//  MultiEntryReviewView.swift
//  scran
//
//  Confirm and log a multi-item plate scan as SEPARATE entries — one per
//  detected item, each individually named and portioned, all sharing the one
//  photo. Editing any portion recomputes that item and the running total live.
//

import SwiftUI
import SwiftData

struct MultiEntryReviewView: View {
    let box: MultiDraftBox
    var onLogged: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var drafts: [EntryDraft]
    @State private var saveAsMeal = false
    @State private var mealName = ""
    @State private var logging = false
    @FocusState private var fieldFocused: Bool

    init(box: MultiDraftBox, onLogged: @escaping () -> Void) {
        self.box = box
        self.onLogged = onLogged
        _drafts = State(initialValue: box.drafts)
    }

    private var totalKcal: Double { drafts.reduce(0) { $0 + $1.total.kcal } }
    private var totalGrams: Double { drafts.reduce(0) { $0 + $1.totalGrams } }
    private var canLog: Bool { !drafts.isEmpty && drafts.allSatisfy(\.canLog) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    SourceBadge(source: .estimate, confidence: box.confidence)
                    Spacer()
                }

                totalsCard

                Text("\(drafts.count) ITEMS — LOGGED SEPARATELY")
                    .font(ScranFont.mono(12, weight: .bold, relativeTo: .caption))
                    .tracking(1.4).foregroundStyle(ScranColor.textMuted)
                Text("Each item gets its own entry, so you can edit or delete them individually later.")
                    .font(ScranFont.body(12, relativeTo: .caption2))
                    .foregroundStyle(ScranColor.textMuted)

                ForEach(drafts) { draft in
                    ItemCard(draft: draft,
                             canRemove: drafts.count > 1,
                             onRemove: { remove(draft) })
                }

                saveAsMealCard
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .scranScreen()
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: logging ? "Logging…" : "Log \(drafts.count) item\(drafts.count == 1 ? "" : "s")",
                          systemImage: "checkmark", enabled: canLog && !logging) {
                log()
            }
            .padding(20)
            .scranBottomBar()
        }
        .navigationTitle("Confirm items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { fieldFocused = false }
                    .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Cards

    private var totalsCard: some View {
        ScranCard(background: ScranColor.panel2) {
            VStack(alignment: .leading, spacing: 10) {
                Text("WHOLE PLATE")
                    .font(ScranFont.mono(12, weight: .bold, relativeTo: .caption))
                    .tracking(1.4).foregroundStyle(ScranColor.textMuted)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ScranFormat.int(totalKcal))
                        .font(ScranFont.mono(40, weight: .bold, relativeTo: .largeTitle))
                        .foregroundStyle(ScranColor.verified)
                        .shadow(color: ScranColor.verified.opacity(0.5), radius: 12)
                        .contentTransition(.numericText())
                    Text("kcal").font(ScranFont.mono(16, relativeTo: .body))
                        .foregroundStyle(ScranColor.textMuted)
                    Spacer()
                    Text(ScranFormat.grams(totalGrams))
                        .font(ScranFont.mono(15, relativeTo: .body))
                        .foregroundStyle(ScranColor.textMuted)
                }
            }
            .animation(.snappy(duration: 0.2), value: totalKcal)
        }
    }

    private var saveAsMealCard: some View {
        ScranCard {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $saveAsMeal) {
                    Text("Save as meal")
                        .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(ScranColor.textPrimary)
                }
                .tint(ScranColor.verified)
                if saveAsMeal {
                    TextField("Meal name (e.g. Berry porridge)", text: $mealName)
                        .font(ScranFont.body(15, relativeTo: .body))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ScranColor.bg))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ScranColor.line))
                }
            }
        }
    }

    // MARK: - Actions

    private func remove(_ draft: EntryDraft) {
        Haptics.warning()
        withAnimation(.snappy(duration: 0.2)) {
            drafts.removeAll { $0 === draft }
        }
    }

    private func canSaveAnotherMeal() -> Bool {
        if app.isPro { return true }
        let descriptor = FetchDescriptor<SavedMeal>(
            predicate: #Predicate { $0.deletedAt == nil })
        let count = (try? context.fetchCount(descriptor)) ?? 0
        return count < ScranConfig.freeSavedMealsLimit
    }

    private func log() {
        guard canLog else { return }
        logging = true
        let entries = drafts.map { $0.makeFoodEntry() }

        // One photo on disk, shared by every entry from this scan.
        #if canImport(UIKit)
        if let photo = box.photo, let first = entries.first,
           let path = PhotoStore.save(photo, entryId: first.id) {
            for e in entries { e.photoLocalPath = path }
        }
        #endif

        for e in entries { context.insert(e) }

        if saveAsMeal {
            if canSaveAnotherMeal() {
                let name = mealName.isEmpty
                    ? entries.map(\.name).first ?? "Plate scan" : mealName
                let meal = SavedMeal(name: name, items: entries.map { SavedMealItem(from: $0) },
                                     timesLogged: 1, lastLoggedAt: .now)
                context.insert(meal)
                app.analytics.track(.mealSaved)
            } else {
                app.presentPaywall(trigger: "saved_meals_limit")
            }
        }

        try? context.save()
        for e in entries { app.analytics.track(.entryLogged(source: e.source)) }
        Haptics.success()

        // Background: upload the shared photo once, point every entry at it, sync.
        let context = context
        Task { @MainActor in
            #if canImport(UIKit)
            if let photo = box.photo, let first = entries.first,
               let data = ImageCompressor.jpegData(from: photo),
               let remote = try? await SupabaseClient.shared.uploadFoodPhoto(entryId: first.id, jpeg: data) {
                for e in entries { e.photoRemotePath = remote }
                try? context.save()
            }
            #endif
            await app.sync.syncPending(context: context)
        }

        onLogged()
    }
}

// MARK: - Item card

/// One scanned item: editable name, portion stepper, live kcal — compact but
/// complete enough that most plates never need the full editor.
private struct ItemCard: View {
    @Bindable var draft: EntryDraft
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        ScranCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    TextField("Name", text: $draft.name)
                        .font(ScranFont.body(16, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(ScranColor.textPrimary)
                    Spacer()
                    Text(ScranFormat.kcalText(draft.total.kcal))
                        .font(ScranFont.mono(15, weight: .bold, relativeTo: .body))
                        .foregroundStyle(ScranColor.estimate)
                        .contentTransition(.numericText())
                    if canRemove {
                        Button { onRemove() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(ScranColor.textMuted.opacity(0.5))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("Remove \(draft.name)")
                    }
                }
                ScranStepper(label: "Portion", value: $draft.servingSizeG, step: 10,
                             range: 1...5000, format: { ScranFormat.grams($0) })
            }
            .animation(.snappy(duration: 0.2), value: draft.total.kcal)
        }
    }
}
