//
//  TodayView.swift
//  scran
//
//  Screen 3 (home). Calorie ring + macro bars + evidence bar + entries grouped
//  by mealtime, each with a source badge. FAB opens the Log sheet. Empty state
//  teaches the three scan modes.
//

import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app

    /// Opens the Log sheet (owned by the tab container).
    var onLog: () -> Void = {}
    /// Jumps straight into a specific capture mode (empty-state shortcuts).
    var onMode: (LogFlowKind) -> Void = { _ in }

    @Query private var plans: [UserPlan]
    @Query private var entries: [FoodEntry]

    @State private var editingEntry: FoodEntry? = nil
    @State private var health = HealthKitService.shared
    @AppStorage("scran.healthConnected") private var healthConnected = false

    init(onLog: @escaping () -> Void = {}, onMode: @escaping (LogFlowKind) -> Void = { _ in }) {
        self.onLog = onLog
        self.onMode = onMode
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _entries = Query(
            filter: #Predicate<FoodEntry> {
                $0.deletedAt == nil && $0.loggedAt >= start && $0.loggedAt < end
            },
            sort: [SortDescriptor(\.loggedAt, order: .forward)])
        _plans = Query(sort: [SortDescriptor(\.createdAt, order: .reverse)])
    }

    private var plan: UserPlan? { plans.first }
    private var consumed: NutrientBlock { entries.reduce(NutrientBlock.zero) { $0 + $1.total } }

    /// Just the date — "kcal left" lives in the ring, scans live in the quota
    /// pill, so the subtitle no longer duplicates either.
    private var headerSubtitle: String {
        Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            ScranHeader(title: "Today", subtitle: headerSubtitle)
                            logButton
                        }
                        if let r = app.quota.remaining {
                            QuotaPill(remaining: r)
                        }
                    }
                    if let plan {
                        ringCard(plan)
                        // The evidence bar is all-zeros with nothing logged — hide it
                        // so the empty-state hero + CTA sit higher and pull focus.
                        if !entries.isEmpty {
                            EvidenceBarCard(entries: entries)
                        }
                        if healthConnected, let snap = health.latest, snap.hasActivity {
                            HealthTodayCard(snapshot: snap)
                        }
                        if entries.isEmpty { emptyState } else { entryList }
                    } else {
                        ProgressView().tint(ScranColor.verified).padding(.top, 80)
                    }
                }
                .padding(20)
                .padding(.bottom, 16)
            }
            .scranScreen()
            .toolbar(.hidden, for: .navigationBar)
            .task { await health.refreshIfConnected() }
        }
        .tint(ScranColor.verified)
        .sheet(item: $editingEntry) { entry in
            NavigationStack { EntryDetailSheet(entry: entry) }
                .environment(app)
        }
    }

    // MARK: - Header log button

    /// Prominent primary CTA for logging, anchored at the top of Today. Shows a
    /// low-quota badge so the free-tier budget is visible before tapping.
    private var logButton: some View {
        Button { onLog() } label: {
            ZStack {
                Circle().fill(ScranColor.verified)
                    .frame(width: 50, height: 50)
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(ScranColor.onVerified)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel("Log food")
        .accessibilityHint(app.quota.counterText ?? "")
    }

    // MARK: - Ring

    private func ringCard(_ plan: UserPlan) -> some View {
        ScranCard {
            VStack(spacing: 22) {
                CalorieRing(consumed: consumed.kcal, target: plan.dailyTargetKcal)
                HStack(spacing: 22) {
                    MacroBar(label: "Protein", consumed: consumed.proteinG,
                             target: plan.proteinTargetG, tint: ScranColor.verified,
                             icon: MacroGlyph.protein)
                    MacroBar(label: "Carbs", consumed: consumed.carbsG,
                             target: plan.carbsTargetG, tint: ScranColor.database,
                             icon: MacroGlyph.carbs)
                    MacroBar(label: "Fat", consumed: consumed.fatG,
                             target: plan.fatTargetG, tint: ScranColor.estimate,
                             icon: MacroGlyph.fat)
                }
                FocusBudgetGrid(plan: plan, consumed: consumed)
            }
        }
    }

    // MARK: - Entry list grouped by mealtime

    private var entryList: some View {
        let groups = Dictionary(grouping: entries) { $0.mealtime }
        return VStack(spacing: 22) {
            ForEach(Mealtime.allCases.sorted { $0.order < $1.order }, id: \.self) { meal in
                if let items = groups[meal], !items.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            SectionLabel(meal.label)
                            Spacer()
                            Text(ScranFormat.kcalText(items.reduce(0) { $0 + $1.total.kcal }))
                                .font(ScranFont.mono(15, weight: .bold, relativeTo: .footnote))
                                .foregroundStyle(ScranColor.positive)
                                .padding(.horizontal, 9).padding(.vertical, 3)
                                .background(Capsule().fill(ScranColor.positive.opacity(0.14)))
                        }
                        ForEach(items) { entry in
                            EntryRow(entry: entry, flag: plan?.highFlag(for: entry.total))
                                .onTapGesture { editingEntry = entry }
                                .contextMenu {
                                    Button(role: .destructive) { delete(entry) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty state (teaches the three modes)

    private var emptyState: some View {
        VStack(spacing: 16) {
            EmptyMealArt(size: 160)
                .padding(.top, 4)
            VStack(spacing: 6) {
                Text("Nothing logged yet")
                    .font(ScranFont.display(26, relativeTo: .title)).textCase(.uppercase)
                    .foregroundStyle(ScranColor.textPrimary)
                Text("Snap it, scan it, done.")
                    .font(ScranFont.body(15, weight: .medium, relativeTo: .body))
                    .foregroundStyle(ScranColor.textMuted)
            }

            PrimaryButton(title: "Log your first meal", systemImage: "plus") { onLog() }

            // Three fast ways in — each jumps straight into that capture mode.
            VStack(spacing: 10) {
                teach(.estimate, .plate, "Photograph a plate", "An honest range, not a fake number")
                teach(.label, .label, "Photograph a label", "We read the per-100g table")
                teach(.barcode, .barcode, "Scan a barcode", "UK database lookup")
            }
            .padding(.top, 2)
        }
        .padding(.top, 4)
    }

    private func teach(_ source: EntrySource, _ mode: LogFlowKind, _ title: String, _ sub: String) -> some View {
        Button { Haptics.tap(); onMode(mode) } label: {
            HStack(spacing: 12) {
                SourceBadge(source: source)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(ScranFont.body(14, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(ScranColor.textPrimary)
                    Text(sub).font(ScranFont.body(12, relativeTo: .caption))
                        .foregroundStyle(ScranColor.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ScranColor.textMuted)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(ScranColor.bg))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ScranColor.lineStrong))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func delete(_ entry: FoodEntry) {
        entry.deletedAt = .now
        entry.syncState = SyncState.pending.rawValue
        try? context.save()
        Haptics.warning()
        let ctx = context
        Task { await app.sync.syncPending(context: ctx) }
    }
}

// MARK: - Evidence bar wrapper

private struct EvidenceBarCard: View {
    let entries: [FoodEntry]
    var body: some View {
        let v = kcal(.label), d = kcal(.barcode), e = kcal(.estimate)
        let other = entries.reduce(0.0) { $0 + $1.total.kcal } - v - d - e
        return ScranCard {
            EvidenceBar(verifiedKcal: v, databaseKcal: d, estimateKcal: e, otherKcal: max(0, other))
        }
    }
    private func kcal(_ source: EntrySource) -> Double {
        entries.filter { $0.sourceEnum == source }.reduce(0) { $0 + $1.total.kcal }
    }
}

// MARK: - Entry row

struct EntryRow: View {
    let entry: FoodEntry
    /// A focused limit-nutrient this meal is high in, surfaced as a small flag.
    var flag: FocusNutrient? = nil
    var body: some View {
        HStack(spacing: 12) {
            #if canImport(UIKit)
            // The user's own food photo is the most evocative thing on the row —
            // give it real presence rather than a postage stamp.
            if let photo = PhotoStore.image(atRelativePath: entry.photoLocalPath) {
                Image(uiImage: photo)
                    .resizable().scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ScranColor.line))
                    .accessibilityHidden(true)
            }
            #endif
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.name)
                    .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                // Wrap chips to a second line if the row is tight — never compress
                // them into vertical characters.
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    SourceBadge(source: entry.sourceEnum, confidence: entry.confidence)
                    Text(ScranFormat.grams(entry.totalGrams))
                        .font(ScranFont.mono(11, relativeTo: .caption2))
                        .foregroundStyle(ScranColor.textMuted)
                        .fixedSize()
                    if let flag {
                        LevelChip(text: "HIGH \(flag.short)", color: flag.tint)
                    }
                }
            }
            Spacer(minLength: 16)
            Text(ScranFormat.kcalText(entry.total.kcal))
                .font(ScranFont.mono(15, weight: .bold, relativeTo: .body))
                .foregroundStyle(ScranColor.textPrimary)
                .fixedSize()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(ScranColor.bg))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ScranColor.lineStrong))
        .contentShape(Rectangle())
    }
}
