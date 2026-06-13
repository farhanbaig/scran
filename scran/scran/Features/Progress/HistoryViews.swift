//
//  HistoryViews.swift
//  scran
//
//  Day-by-day logging history. Honest by design: descriptive verdicts (under /
//  on target / over vs the plan), no streaks, no badges, no guilt mechanics.
//  Free tier sees the last `ScranConfig.freeHistoryDays`; older days unlock
//  with Pro.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Day aggregation

/// One logged day, totalled.
struct DayStat: Identifiable {
    let day: Date                 // startOfDay
    let total: NutrientBlock
    let entries: [FoodEntry]      // that day's live entries, oldest first
    var id: Date { day }

    /// Group live entries into per-day totals, newest day first.
    static func build(from entries: [FoodEntry]) -> [DayStat] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: entries.filter { $0.deletedAt == nil }) {
            cal.startOfDay(for: $0.loggedAt)
        }
        return groups.map { day, items in
            DayStat(day: day,
                    total: items.reduce(.zero) { $0 + $1.total },
                    entries: items.sorted { $0.loggedAt < $1.loggedAt })
        }
        .sorted { $0.day > $1.day }
    }
}

/// Descriptive day verdict vs the plan target. ±10% counts as on target —
/// honest framing, not a judgement.
enum DayVerdict {
    case under, onTarget, over

    init(kcal: Double, target: Double) {
        guard target > 0 else { self = .onTarget; return }
        switch kcal / target {
        case ..<0.9:      self = .under
        case ...1.1:      self = .onTarget
        default:          self = .over
        }
    }

    var label: String {
        switch self {
        case .under:    return "UNDER"
        case .onTarget: return "ON TARGET"
        case .over:     return "OVER"
        }
    }

    var tint: Color {
        switch self {
        case .under:    return ScranColor.database
        case .onTarget: return ScranColor.verified
        case .over:     return ScranColor.estimate
        }
    }
}

// MARK: - Progress-tab overview card

/// The "how am I doing overall" card: totals, on-target share, a 7-day bar
/// strip, and the way into the full day list.
struct LoggedDaysCard: View {
    let days: [DayStat]
    let plan: UserPlan?

    private var target: Double { plan?.dailyTargetKcal ?? 0 }

    /// Share of the last 30 logged days that landed on target.
    private var onTargetText: String {
        let recent = days.prefix(30)
        guard !recent.isEmpty, target > 0 else { return "—" }
        let hits = recent.filter { DayVerdict(kcal: $0.total.kcal, target: target) == .onTarget }.count
        return "\(hits)/\(recent.count)"
    }

    private var weekAverageText: String {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: .now)) ?? .now
        let week = days.filter { $0.day >= cutoff }
        guard !week.isEmpty else { return "—" }
        return ScranFormat.int(week.reduce(0) { $0 + $1.total.kcal } / Double(week.count))
    }

    var body: some View {
        NavigationLink {
            HistoryListView(days: days, plan: plan)
        } label: {
            ScranCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        SectionLabel("Days logged")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ScranColor.textMuted)
                    }
                    HStack(spacing: 0) {
                        stat("\(days.count)", "days logged")
                        stat(onTargetText, "on target (30d)")
                        stat(weekAverageText, "avg kcal (7d)")
                    }
                    WeekBars(days: days, target: target)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Shows every logged day")
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(ScranFont.mono(20, weight: .bold, relativeTo: .title3))
                .foregroundStyle(ScranColor.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(caption)
                .font(ScranFont.body(11, relativeTo: .caption2))
                .foregroundStyle(ScranColor.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Last 7 calendar days as bars against the kcal target (dashed line at 100%).
private struct WeekBars: View {
    let days: [DayStat]
    let target: Double

    private var week: [(Date, Double)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
            return (d, days.first { $0.day == d }?.total.kcal ?? 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                // Target line at 2/3 height; bars scale so target == 2/3.
                Rectangle()
                    .fill(ScranColor.lineStrong)
                    .frame(height: 1)
                    .offset(y: -40)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(week, id: \.0) { day, kcal in
                        let ratio = target > 0 ? kcal / target : 0
                        let height = max(kcal > 0 ? 4 : 2, min(60, 40 * ratio))
                        let verdict = DayVerdict(kcal: kcal, target: target)
                        VStack(spacing: 4) {
                            Capsule()
                                .fill(kcal > 0 ? verdict.tint : ScranColor.lineStrong)
                                .frame(height: height)
                            Text(day.formatted(.dateTime.weekday(.narrow)))
                                .font(ScranFont.mono(9, relativeTo: .caption2))
                                .foregroundStyle(ScranColor.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 78, alignment: .bottom)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last seven days of calories against your target")
    }
}

// MARK: - Full history list

struct HistoryListView: View {
    let days: [DayStat]
    let plan: UserPlan?
    @Environment(AppModel.self) private var app

    private var target: Double { plan?.dailyTargetKcal ?? 0 }

    /// Free tier: only days within the last `freeHistoryDays` are open.
    private var lockCutoff: Date {
        Calendar.current.date(byAdding: .day, value: -ScranConfig.freeHistoryDays,
                              to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
    }
    private var openDays: [DayStat] { app.isPro ? days : days.filter { $0.day >= lockCutoff } }
    private var lockedCount: Int { days.count - openDays.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                if days.isEmpty {
                    VStack(spacing: 16) {
                        PlateMark(size: 132)
                        Text("Nothing logged yet — your days will appear here.")
                            .font(ScranFont.body(15, relativeTo: .body))
                            .foregroundStyle(ScranColor.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 48)
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(openDays) { day in
                        NavigationLink { DayDetailView(day: day, plan: plan) } label: {
                            DayRow(day: day, target: target)
                        }
                        .buttonStyle(PressableStyle())
                    }
                    if lockedCount > 0 { lockedCard }
                }
            }
            .padding(20)
        }
        .scranScreen()
        .navigationTitle("All days")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lockedCard: some View {
        Button { app.presentPaywall(trigger: "history") } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(ScranColor.estimate)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(lockedCount) earlier day\(lockedCount == 1 ? "" : "s")")
                        .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(ScranColor.textPrimary)
                    Text("Free keeps \(ScranConfig.freeHistoryDays) days of history — Pro keeps it all.")
                        .font(ScranFont.body(12, relativeTo: .caption))
                        .foregroundStyle(ScranColor.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ScranColor.textMuted)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(ScranColor.estimateDim))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ScranColor.estimate.opacity(0.3)))
        }
        .buttonStyle(PressableStyle())
    }
}

private struct DayRow: View {
    let day: DayStat
    let target: Double

    #if canImport(UIKit)
    /// Up to three distinct meal photos from the day (entries from one scan
    /// share a photo, so de-dupe by path).
    private var photos: [UIImage] {
        var seen = Set<String>()
        var out: [UIImage] = []
        for e in day.entries {
            guard out.count < 3, let p = e.photoLocalPath, !seen.contains(p),
                  let img = PhotoStore.image(atRelativePath: p) else { continue }
            seen.insert(p); out.append(img)
        }
        return out
    }
    #endif

    var body: some View {
        let verdict = DayVerdict(kcal: day.total.kcal, target: target)
        HStack(spacing: 12) {
            #if canImport(UIKit)
            if !photos.isEmpty {
                HStack(spacing: -12) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { _, img in
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 38, height: 38)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(ScranColor.bg, lineWidth: 2))
                    }
                }
                .accessibilityHidden(true)
            }
            #endif
            VStack(alignment: .leading, spacing: 4) {
                Text(day.day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                    .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary)
                HStack(spacing: 8) {
                    Text("\(day.entries.count) item\(day.entries.count == 1 ? "" : "s")")
                        .font(ScranFont.mono(11, relativeTo: .caption2))
                        .foregroundStyle(ScranColor.textMuted)
                    if target > 0 {
                        LevelChip(text: verdict.label, color: verdict.tint)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(ScranFormat.kcalText(day.total.kcal))
                    .font(ScranFont.mono(15, weight: .bold, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary)
                if target > 0 {
                    kcalBar(ratio: day.total.kcal / target, tint: verdict.tint)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(ScranColor.panel))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ScranColor.line))
        .contentShape(Rectangle())
    }

    private func kcalBar(ratio: Double, tint: Color) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(ScranColor.lineStrong).frame(width: 72, height: 5)
            Capsule().fill(tint)
                .frame(width: 72 * min(1, max(0.02, ratio)), height: 5)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Single-day detail

struct DayDetailView: View {
    let day: DayStat
    let plan: UserPlan?
    @Environment(AppModel.self) private var app
    @State private var editingEntry: FoodEntry? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                totalsCard
                if let plan {
                    ScranCard {
                        FocusBudgetGrid(plan: plan, consumed: day.total)
                    }
                }
                entriesList
            }
            .padding(20)
        }
        .scranScreen()
        .navigationTitle(day.day.formatted(.dateTime.day().month(.wide)))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingEntry) { entry in
            NavigationStack { EntryDetailSheet(entry: entry) }
                .environment(app)
        }
    }

    private var totalsCard: some View {
        ScranCard(background: ScranColor.panel2, textured: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel("The day")
                    Spacer()
                    if let plan {
                        let verdict = DayVerdict(kcal: day.total.kcal, target: plan.dailyTargetKcal)
                        LevelChip(text: verdict.label, color: verdict.tint)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ScranFormat.int(day.total.kcal))
                        .font(ScranFont.mono(36, weight: .bold, relativeTo: .largeTitle))
                        .foregroundStyle(ScranColor.verified)
                        .shadow(color: ScranColor.verified.opacity(0.5), radius: 12)
                    Text("kcal").font(ScranFont.mono(15, relativeTo: .body))
                        .foregroundStyle(ScranColor.textMuted)
                    Spacer()
                    if let plan {
                        Text("target \(ScranFormat.int(plan.dailyTargetKcal))")
                            .font(ScranFont.mono(13, relativeTo: .footnote))
                            .foregroundStyle(ScranColor.textMuted)
                    }
                }
                MacroTriple(protein: day.total.proteinG, carbs: day.total.carbsG,
                            fat: day.total.fatG)
            }
        }
    }

    private var entriesList: some View {
        let groups = Dictionary(grouping: day.entries) { $0.mealtime }
        return VStack(spacing: 22) {
            ForEach(Mealtime.allCases.sorted { $0.order < $1.order }, id: \.self) { meal in
                if let items = groups[meal], !items.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionLabel(meal.label)
                            Spacer()
                            Text(ScranFormat.kcalText(items.reduce(0) { $0 + $1.total.kcal }))
                                .font(ScranFont.mono(13, weight: .bold, relativeTo: .caption))
                                .foregroundStyle(ScranColor.textMuted)
                        }
                        ForEach(items) { entry in
                            EntryRow(entry: entry, flag: plan?.highFlag(for: entry.total))
                                .onTapGesture { editingEntry = entry }
                        }
                    }
                }
            }
        }
    }
}
