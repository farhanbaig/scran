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

    @Query private var plans: [UserPlan]
    @Query private var entries: [FoodEntry]

    @State private var editingEntry: FoodEntry? = nil
    @State private var health = HealthKitService.shared
    @AppStorage("scran.healthConnected") private var healthConnected = false

    init(onLog: @escaping () -> Void = {}) {
        self.onLog = onLog
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

    /// "Wednesday 11 June · 1,460 kcal left · 2 AI scans left today"
    private var headerSubtitle: String {
        var parts = [Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))]
        if let plan {
            let left = plan.dailyTargetKcal - consumed.kcal
            parts.append(left >= 0
                ? "\(ScranFormat.int(left)) kcal left"
                : "\(ScranFormat.int(-left)) kcal over")
        }
        if let counter = app.quota.counterText { parts.append(counter) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    HStack(alignment: .top, spacing: 12) {
                        ScranHeader(title: "Today", subtitle: headerSubtitle)
                        logButton
                    }
                    if let plan {
                        ringCard(plan)
                        EvidenceBarCard(entries: entries)
                        if healthConnected, let snap = health.latest, snap.hasActivity {
                            HealthTodayCard(snapshot: snap)
                        }
                        if entries.isEmpty { emptyState } else { entryList }
                    } else {
                        ProgressView().tint(ScranColor.verified).padding(.top, 80)
                    }
                }
                .padding(20)
                .padding(.bottom, ScranTabBar.contentHeight + 16)
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
                    .shadow(color: ScranColor.verified.opacity(0.4), radius: 10, y: 3)
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(ScranColor.onVerified)
            }
            .overlay(alignment: .topTrailing) { quotaBadge }
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel("Log food")
        .accessibilityHint(app.quota.counterText ?? "")
    }

    @ViewBuilder private var quotaBadge: some View {
        if let r = app.quota.remaining, r <= 2 {
            Text("\(r)")
                .font(ScranFont.mono(11, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(r == 0 ? ScranColor.bg : ScranColor.onVerified)
                .frame(width: 19, height: 19)
                .background(Circle().fill(r == 0 ? ScranColor.error : ScranColor.estimate))
                .overlay(Circle().strokeBorder(ScranColor.bg, lineWidth: 2))
                .offset(x: 3, y: -3)
                .accessibilityHidden(true)
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
    var body: some View {
        HStack(spacing: 12) {
            #if canImport(UIKit)
            if let photo = PhotoStore.image(atRelativePath: entry.photoLocalPath) {
                Image(uiImage: photo)
                    .resizable().scaledToFill()
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ScranColor.line))
                    .accessibilityHidden(true)
            }
            #endif
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
