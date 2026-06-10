//
//  EntryEditorView.swift
//  scran
//
//  Screen 8. Confirm and log an entry. Every numeric edit recomputes everything
//  instantly. Carries exactly one source badge. "Save as meal" optional.
//

import SwiftUI
import SwiftData

struct EntryEditorView: View {
    @Bindable var draft: EntryDraft
    var onLogged: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var showPer100g = false
    @State private var logging = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if !draft.warnings.isEmpty {
                    ForEach(draft.warnings, id: \.self) { w in
                        ScranBanner(kind: .info, text: w)
                    }
                }

                totalsCard
                portionCard
                per100gCard

                if draft.source == .label || draft.source == .estimate || draft.source == .manual {
                    saveAsMealCard
                }
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .scranScreen()
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: logging ? "Logging…" : "Log it",
                          systemImage: "checkmark", enabled: draft.canLog && !logging) {
                log()
            }
            .padding(20)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Confirm")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SourceBadge(source: draft.source, confidence: draft.confidence)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                TextField("Name", text: $draft.name)
                    .font(ScranFont.body(22, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(ScranColor.textPrimary)
                TextField("Brand (optional)", text: Binding(
                    get: { draft.brand ?? "" },
                    set: { draft.brand = $0.isEmpty ? nil : $0 }))
                    .font(ScranFont.body(15, relativeTo: .body))
                    .foregroundStyle(ScranColor.textMuted)
            }
        }
    }

    private var totalsCard: some View {
        ScranCard(background: ScranColor.panel2) {
            VStack(alignment: .leading, spacing: 14) {
                Text("THIS ENTRY")
                    .font(ScranFont.mono(12, weight: .bold, relativeTo: .caption))
                    .tracking(1.4).foregroundStyle(ScranColor.textMuted)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ScranFormat.int(draft.total.kcal))
                        .font(ScranFont.mono(40, weight: .bold, relativeTo: .largeTitle))
                        .foregroundStyle(ScranColor.verified)
                        .shadow(color: ScranColor.verified.opacity(0.5), radius: 12)
                        .contentTransition(.numericText())
                    Text("kcal").font(ScranFont.mono(16, relativeTo: .body))
                        .foregroundStyle(ScranColor.textMuted)
                    Spacer()
                    Text(ScranFormat.grams(draft.totalGrams))
                        .font(ScranFont.mono(15, relativeTo: .body))
                        .foregroundStyle(ScranColor.textMuted)
                }
                MacroTriple(protein: draft.total.proteinG, carbs: draft.total.carbsG,
                            fat: draft.total.fatG)
            }
            .animation(.snappy(duration: 0.2), value: draft.total.kcal)
        }
    }

    private var portionCard: some View {
        ScranCard {
            VStack(spacing: 16) {
                ScranStepper(label: "Serving size", value: $draft.servingSizeG, step: 10,
                             range: 1...5000, format: { ScranFormat.grams($0) })
                    .onChange(of: draft.servingSizeG) { _, _ in app.analytics.track(.entryPortionEdited) }
                Divider().overlay(ScranColor.line)
                ScranStepper(label: "Quantity", value: $draft.quantity, step: 0.5,
                             range: 0.5...50, format: { $0 == $0.rounded() ? "\(Int($0))×" : String(format: "%.1f×", $0) })
            }
        }
    }

    private var per100gCard: some View {
        ScranCard {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { showPer100g.toggle() }
                } label: {
                    HStack {
                        Text("Per 100g")
                            .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                            .foregroundStyle(ScranColor.textPrimary)
                        Spacer()
                        Image(systemName: showPer100g ? "chevron.up" : "chevron.down")
                            .foregroundStyle(ScranColor.textMuted)
                    }
                }
                .buttonStyle(.plain)

                if showPer100g {
                    VStack(spacing: 10) {
                        per100gRow("Energy", value: $draft.per100g.kcal, unit: "kcal")
                        per100gRow("Protein", value: $draft.per100g.proteinG, unit: "g")
                        per100gRow("Carbs", value: $draft.per100g.carbsG, unit: "g")
                        per100gRow("Fat", value: $draft.per100g.fatG, unit: "g")
                        per100gOptionalRow("Saturated fat", value: $draft.per100g.satFatG)
                        per100gOptionalRow("Fibre", value: $draft.per100g.fibreG)
                        per100gOptionalRow("Sugar", value: $draft.per100g.sugarG)
                        per100gOptionalRow("Salt", value: $draft.per100g.saltG)
                    }
                    .padding(.top, 14)
                }
            }
        }
    }

    private var saveAsMealCard: some View {
        ScranCard {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $draft.saveAsMeal) {
                    Text("Save as meal")
                        .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(ScranColor.textPrimary)
                }
                .tint(ScranColor.verified)
                if draft.saveAsMeal {
                    TextField("Meal name (e.g. Tuesday daal)", text: $draft.mealName)
                        .font(ScranFont.body(15, relativeTo: .body))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ScranColor.bg))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ScranColor.line))
                }
            }
        }
    }

    // MARK: - Rows

    private func per100gRow(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label).font(ScranFont.body(14, relativeTo: .footnote))
                .foregroundStyle(ScranColor.textMuted)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(ScranFont.mono(14, weight: .bold, relativeTo: .body))
                .foregroundStyle(ScranColor.textPrimary)
                .frame(width: 70)
            Text(unit).font(ScranFont.mono(12, relativeTo: .caption))
                .foregroundStyle(ScranColor.textMuted).frame(width: 34, alignment: .leading)
        }
    }

    private func per100gOptionalRow(_ label: String, value: Binding<Double?>) -> some View {
        // .number formats Double, not Double? — bridge through a non-optional proxy.
        let proxy = Binding<Double>(
            get: { value.wrappedValue ?? 0 },
            set: { value.wrappedValue = $0 })
        return HStack {
            Text(label).font(ScranFont.body(14, relativeTo: .footnote))
                .foregroundStyle(ScranColor.textMuted)
            Spacer()
            TextField("—", value: proxy, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(ScranFont.mono(14, weight: .bold, relativeTo: .body))
                .foregroundStyle(ScranColor.textPrimary)
                .frame(width: 70)
            Text("g").font(ScranFont.mono(12, relativeTo: .caption))
                .foregroundStyle(ScranColor.textMuted).frame(width: 34, alignment: .leading)
        }
    }

    // MARK: - Actions

    private func canSaveAnotherMeal() -> Bool {
        if app.isPro { return true }
        let descriptor = FetchDescriptor<SavedMeal>(
            predicate: #Predicate { $0.deletedAt == nil })
        let count = (try? context.fetchCount(descriptor)) ?? 0
        return count < ScranConfig.freeSavedMealsLimit
    }

    private func log() {
        guard draft.canLog else { return }
        logging = true
        let entry = draft.makeFoodEntry()

        #if canImport(UIKit)
        if let photo = draft.photo, let path = PhotoStore.save(photo, entryId: entry.id) {
            entry.photoLocalPath = path
        }
        #endif

        context.insert(entry)

        if draft.saveAsMeal {
            if canSaveAnotherMeal() {
                let mealName = draft.mealName.isEmpty ? entry.name : draft.mealName
                let meal = SavedMeal(name: mealName, items: [SavedMealItem(from: entry)],
                                     timesLogged: 1, lastLoggedAt: .now)
                context.insert(meal)
                app.analytics.track(.mealSaved)
            } else {
                // Free tier caps saved meals; the entry still logs.
                app.presentPaywall(trigger: "saved_meals_limit")
            }
        }

        try? context.save()
        app.analytics.track(.entryLogged(source: entry.source))
        Haptics.success()

        // Background: upload photo + sync.
        let context = context
        Task { @MainActor in
            #if canImport(UIKit)
            if let photo = draft.photo,
               let data = ImageCompressor.jpegData(from: photo),
               let remote = try? await SupabaseClient.shared.uploadFoodPhoto(entryId: entry.id, jpeg: data) {
                entry.photoRemotePath = remote
                try? context.save()
            }
            #endif
            await app.sync.syncPending(context: context)
        }

        onLogged()
    }
}

/// Compact macro readout used on cards.
struct MacroTriple: View {
    let protein: Double
    let carbs: Double
    let fat: Double

    var body: some View {
        HStack(spacing: 18) {
            macro("P", protein)
            macro("C", carbs)
            macro("F", fat)
        }
    }

    private func macro(_ letter: String, _ grams: Double) -> some View {
        HStack(spacing: 6) {
            Text(letter).font(ScranFont.mono(12, relativeTo: .caption))
                .foregroundStyle(ScranColor.textMuted)
            Text(ScranFormat.grams(grams))
                .font(ScranFont.mono(14, weight: .bold, relativeTo: .body))
                .foregroundStyle(ScranColor.textPrimary)
        }
    }
}
