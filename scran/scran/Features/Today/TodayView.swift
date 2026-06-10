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

    @Query private var plans: [UserPlan]
    @Query private var entries: [FoodEntry]

    @State private var showLogSheet = false
    @State private var activeFlow: LogFlowKind? = nil
    @State private var editingEntry: FoodEntry? = nil
    @State private var showSettings = false

    init() {
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let plan {
                        ringCard(plan)
                        EvidenceBarCard(entries: entries)
                        if entries.isEmpty { emptyState } else { entryList }
                    } else {
                        ProgressView().tint(ScranColor.verified).padding(.top, 80)
                    }
                }
                .padding(20)
                .padding(.bottom, 96)
            }
            .scranScreen()
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape").foregroundStyle(ScranColor.textPrimary)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) { fab }
            .navigationDestination(isPresented: $showSettings) { SettingsView() }
        }
        .tint(ScranColor.verified)
        .sheet(isPresented: $showLogSheet) {
            LogSheet { kind in activeFlow = kind }
                .environment(app)
        }
        .fullScreenCover(item: $activeFlow) { kind in
            LogFlowView(kind: kind) { activeFlow = nil }
                .environment(app)
        }
        .sheet(item: $editingEntry) { entry in
            NavigationStack { EntryDetailSheet(entry: entry) }
                .environment(app)
        }
    }

    // MARK: - Ring

    private func ringCard(_ plan: UserPlan) -> some View {
        ScranCard(background: ScranColor.panel2) {
            VStack(spacing: 22) {
                CalorieRing(consumed: consumed.kcal, target: plan.dailyTargetKcal)
                HStack(spacing: 22) {
                    MacroBar(label: "PROTEIN", consumed: consumed.proteinG,
                             target: plan.proteinTargetG, tint: ScranColor.verified)
                    MacroBar(label: "CARBS", consumed: consumed.carbsG,
                             target: plan.carbsTargetG, tint: ScranColor.database)
                    MacroBar(label: "FAT", consumed: consumed.fatG,
                             target: plan.fatTargetG, tint: ScranColor.estimate)
                }
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
                        HStack {
                            Text(meal.label.uppercased())
                                .font(ScranFont.mono(12, weight: .bold, relativeTo: .caption))
                                .tracking(1.2).foregroundStyle(ScranColor.textMuted)
                            Spacer()
                            Text(ScranFormat.kcalText(items.reduce(0) { $0 + $1.total.kcal }))
                                .font(ScranFont.mono(12, weight: .bold, relativeTo: .caption))
                                .foregroundStyle(ScranColor.textMuted)
                        }
                        ForEach(items) { entry in
                            EntryRow(entry: entry)
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
        VStack(spacing: 18) {
            Text("Nothing logged yet")
                .font(ScranFont.display(24, relativeTo: .title)).textCase(.uppercase)
                .foregroundStyle(ScranColor.textPrimary)
            Text("Three ways in — every number gets a badge:")
                .font(ScranFont.body(15, relativeTo: .body)).foregroundStyle(ScranColor.textMuted)
            VStack(spacing: 10) {
                teach(.barcode, "Scan a barcode", "UK database lookup")
                teach(.label, "Photograph a label", "We read the per-100g table")
                teach(.estimate, "Photograph a plate", "An honest range, not a fake number")
            }
        }
        .padding(.top, 12)
    }

    private func teach(_ source: EntrySource, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            SourceBadge(source: source)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(ScranFont.body(14, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary)
                Text(sub).font(ScranFont.body(12, relativeTo: .caption))
                    .foregroundStyle(ScranColor.textMuted)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(ScranColor.panel))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ScranColor.line))
    }

    // MARK: - FAB

    private var fab: some View {
        Button { Haptics.tap(); showLogSheet = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(ScranColor.onVerified)
                .frame(width: 62, height: 62)
                .background(Circle().fill(ScranColor.verified))
                .shadow(color: ScranColor.verified.opacity(0.5), radius: 16, y: 6)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .padding(.trailing, 22)
        .padding(.bottom, 22)
        .accessibilityLabel("Log food")
    }

    private func delete(_ entry: FoodEntry) {
        entry.deletedAt = .now
        entry.syncState = SyncState.pending.rawValue
        try? context.save()
        Haptics.selection()
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
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.name)
                    .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary).lineLimit(1)
                HStack(spacing: 8) {
                    SourceBadge(source: entry.sourceEnum, confidence: entry.confidence)
                    Text(ScranFormat.grams(entry.totalGrams))
                        .font(ScranFont.mono(11, relativeTo: .caption2))
                        .foregroundStyle(ScranColor.textMuted)
                }
            }
            Spacer()
            Text(ScranFormat.kcalText(entry.total.kcal))
                .font(ScranFont.mono(15, weight: .bold, relativeTo: .body))
                .foregroundStyle(ScranColor.textPrimary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(ScranColor.panel))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ScranColor.line))
        .contentShape(Rectangle())
    }
}
