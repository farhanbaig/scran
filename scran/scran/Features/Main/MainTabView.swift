//
//  MainTabView.swift
//  scran
//
//  Tab container with a custom bottom bar: Today · Progress · Settings around a
//  prominent raised "Log" action button. The bar installs as a bottom safe-area
//  inset so screen content (and pinned buttons) always sit clear of it.
//

import SwiftUI
import SwiftData

enum ScranTab: Hashable { case today, progress, settings }

/// Lets pushed detail screens (Edit plan, Plan reveal) hide the custom tab bar
/// so their pinned action buttons aren't overlapped. Injected by MainTabView;
/// absent (nil) outside it, e.g. during onboarding.
@MainActor @Observable final class ChromeVisibility {
    var tabBarHidden = false
}

struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @State private var tab: ScranTab = .today
    @State private var showLogSheet = false
    @State private var activeFlow: LogFlowKind? = nil
    @State private var chrome = ChromeVisibility()

    var body: some View {
        // Screens stay mounted (opacity-toggled) so tab switches preserve their
        // scroll position and navigation state, like a system TabView.
        ZStack {
            screen(.today) { TodayView(onLog: { Haptics.tap(); showLogSheet = true }) }
            screen(.progress) { ProgressTabView() }
            screen(.settings) { NavigationStack { SettingsView() } }
        }
        .environment(chrome)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !chrome.tabBarHidden { ScranTabBar(selection: $tab) }
        }
        .scranScreen()
        .sheet(isPresented: $showLogSheet) {
            LogSheet { kind in activeFlow = kind }
                .environment(app)
        }
        .fullScreenCover(item: $activeFlow) { kind in
            LogFlowView(kind: kind) { activeFlow = nil }
                .environment(app)
        }
    }

    @ViewBuilder private func screen<Content: View>(_ which: ScranTab, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .opacity(tab == which ? 1 : 0)
            .allowsHitTesting(tab == which)
            .accessibilityHidden(tab != which)
    }
}

// MARK: - Custom bottom bar (Today · Progress · Settings)

struct ScranTabBar: View {
    @Binding var selection: ScranTab

    /// Bar content height (excludes the home-indicator safe area). Screens add
    /// this as bottom padding so their last item clears the bar.
    static let contentHeight: CGFloat = 60

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            item(.today, "Today", "flame.fill")
            item(.progress, "Progress", "chart.line.uptrend.xyaxis")
            item(.settings, "Settings", "gearshape.fill")
        }
        .padding(.top, 12)
        .padding(.horizontal, 6)
        .background(
            ScranColor.bg
                .overlay(alignment: .top) { Rectangle().fill(ScranColor.line).frame(height: 1) }
                .shadow(color: .black.opacity(0.05), radius: 8, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func item(_ t: ScranTab, _ title: String, _ icon: String) -> some View {
        Button {
            if selection != t { Haptics.selection() }
            selection = t
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                Text(title).font(ScranFont.body(10, weight: .semibold, relativeTo: .caption2))
            }
            .foregroundStyle(selection == t ? ScranColor.verified : ScranColor.textMuted)
            .frame(maxWidth: .infinity).frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selection == t ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Progress tab (honest: weight trend + recalibration, no streaks/badges)

struct ProgressTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: [SortDescriptor(\WeightEntry.date, order: .reverse)]) private var weights: [WeightEntry]
    @Query(sort: [SortDescriptor(\UserPlan.createdAt, order: .reverse)]) private var plans: [UserPlan]

    @State private var showLogWeight = false
    @State private var draftWeight: Double = 80

    private var plan: UserPlan? { plans.first }
    private var live: [WeightEntry] { weights.filter { $0.deletedAt == nil } }
    private var latest: Double { live.first?.weightKg ?? plan?.weightKg ?? 0 }

    /// "−0.4 kg over the last week" — latest weigh-in vs the most recent one at
    /// least 6 days older. Honest: needs two real data points, no extrapolation.
    private var weeklyTrend: String? {
        guard let newest = live.first,
              let anchor = live.first(where: {
                  newest.date.timeIntervalSince($0.date) >= 6 * 86_400
              }) else { return nil }
        let delta = newest.weightKg - anchor.weightKg
        guard abs(delta) >= 0.05 else { return "Holding steady this week" }
        return String(format: "%@%.1f kg over the last week", delta < 0 ? "−" : "+", abs(delta))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ScranHeader(title: "Progress",
                            subtitle: weeklyTrend ?? "Weigh in weekly to see your trend")
                currentCard
                if let plan, latest > 0 { bmiCard(heightCm: plan.heightCm, weightKg: latest) }
                noteCard
                if !live.isEmpty { historySection }
            }
            .padding(20).padding(.bottom, 24)
        }
        .scranScreen()
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Log weight", systemImage: "scalemass") {
                draftWeight = latest > 0 ? latest : 80
                showLogWeight = true
            }
            .padding(20).scranBottomBar()
        }
        .sheet(isPresented: $showLogWeight) { logWeightSheet }
    }

    private var currentCard: some View {
        ScranCard(background: ScranColor.panel2, textured: true) {
            VStack(alignment: .leading, spacing: 6) {
                Text("CURRENT WEIGHT")
                    .font(ScranFont.mono(11, weight: .bold, relativeTo: .caption2))
                    .tracking(1.4).foregroundStyle(ScranColor.textMuted)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(latest > 0 ? String(format: "%.1f", latest) : "—")
                        .font(ScranFont.mono(40, weight: .bold, relativeTo: .largeTitle))
                        .foregroundStyle(ScranColor.verified)
                        .shadow(color: ScranColor.verified.opacity(0.5), radius: 12)
                    Text("kg").font(ScranFont.mono(16, relativeTo: .body))
                        .foregroundStyle(ScranColor.textMuted)
                }
                if let plan {
                    Text("Plan started at \(String(format: "%.1f", plan.weightKg)) kg · goal \(plan.goalEnum.label.lowercased())")
                        .font(ScranFont.body(13, relativeTo: .footnote))
                        .foregroundStyle(ScranColor.textMuted)
                }
            }
        }
    }

    // MARK: - BMI

    private func bmiCard(heightCm: Double, weightKg: Double) -> some View {
        let m = heightCm / 100
        let bmi = m > 0 ? weightKg / (m * m) : 0
        let (label, tint) = Self.bmiCategory(bmi)
        // Healthy-weight range for this height, so the number has context.
        let lo = 18.5 * m * m, hi = 24.9 * m * m
        return ScranCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("BODY MASS INDEX")
                        .font(ScranFont.mono(11, weight: .bold, relativeTo: .caption2))
                        .tracking(1.4).foregroundStyle(ScranColor.textMuted)
                    Spacer()
                    Text(label.uppercased())
                        .font(ScranFont.mono(10, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(tint.opacity(0.14)))
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", bmi))
                        .font(ScranFont.mono(36, weight: .bold, relativeTo: .largeTitle))
                        .foregroundStyle(tint)
                    Text("kg/m²").font(ScranFont.mono(14, relativeTo: .footnote))
                        .foregroundStyle(ScranColor.textMuted)
                }
                bmiScale(bmi: bmi)
                Text("A healthy BMI for your height is \(String(format: "%.0f", lo))–\(String(format: "%.0f", hi)) kg. BMI is a rough guide — it ignores muscle and build.")
                    .font(ScranFont.body(13, relativeTo: .footnote))
                    .foregroundStyle(ScranColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Body mass index \(String(format: "%.1f", bmi)), \(label)")
    }

    /// Proportional 15–40 scale (under/healthy/over/obese) with a needle.
    private func bmiScale(bmi: Double) -> some View {
        let lo = 15.0, hi = 40.0
        let pos = min(1, max(0, (bmi - lo) / (hi - lo)))
        let zones: [(Double, Color)] = [
            (18.5, ScranColor.database), (25, ScranColor.verified),
            (30, ScranColor.estimate), (40, ScranColor.error),
        ]
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(Array(zones.enumerated()), id: \.offset) { i, z in
                        let prev = i == 0 ? lo : zones[i - 1].0
                        z.1.frame(width: geo.size.width * ((z.0 - prev) / (hi - lo)))
                    }
                }
                .frame(height: 8).clipShape(Capsule())
                Rectangle().fill(ScranColor.textPrimary)
                    .frame(width: 3, height: 16)
                    .offset(x: geo.size.width * pos - 1.5)
                    .shadow(color: .black.opacity(0.25), radius: 2)
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }

    private static func bmiCategory(_ bmi: Double) -> (String, Color) {
        switch bmi {
        case ..<18.5:  return ("Underweight", ScranColor.database)
        case ..<25:    return ("Healthy", ScranColor.verified)
        case ..<30:    return ("Overweight", ScranColor.estimate)
        default:       return ("Obese", ScranColor.error)
        }
    }

    private var noteCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill").foregroundStyle(ScranColor.database)
                .accessibilityHidden(true)
            Text("Weigh in weekly. Once we have a few weeks of data we'll recalibrate your target from what actually happens — not a black-box formula.")
                .font(ScranFont.body(14, relativeTo: .footnote))
                .foregroundStyle(ScranColor.textMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(ScranColor.databaseDim))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ScranColor.database.opacity(0.3)))
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HISTORY")
                .font(ScranFont.mono(11, weight: .bold, relativeTo: .caption2))
                .tracking(1.4).foregroundStyle(ScranColor.textMuted)
            ForEach(live) { w in
                HStack {
                    Text(String(format: "%.1f kg", w.weightKg))
                        .font(ScranFont.mono(15, weight: .bold, relativeTo: .body))
                        .foregroundStyle(ScranColor.textPrimary)
                    Spacer()
                    Text(w.date.formatted(date: .abbreviated, time: .omitted))
                        .font(ScranFont.body(13, relativeTo: .footnote))
                        .foregroundStyle(ScranColor.textMuted)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(ScranColor.panel))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ScranColor.line))
            }
        }
    }

    private var logWeightSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                RulerSlider(value: $draftWeight, range: 35...200, step: 0.1, unit: "kg")
                    .padding(.top, 30)
                Spacer()
                PrimaryButton(title: "Save weight", systemImage: "checkmark") { saveWeight() }
                    .padding(20)
            }
            .scranScreen()
            .navigationTitle("Log weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ScranColor.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showLogWeight = false }.foregroundStyle(ScranColor.textMuted)
                }
            }
        }
        .presentationDetents([.medium])
        .scranAppearance()
    }

    private func saveWeight() {
        let entry = WeightEntry(date: .now, weightKg: draftWeight)
        context.insert(entry)
        if let plan { plan.weightKg = draftWeight; plan.syncState = SyncState.pending.rawValue }
        try? context.save()
        Haptics.success()
        showLogWeight = false
        let ctx = context
        Task { await app.sync.syncPending(context: ctx) }
    }
}
