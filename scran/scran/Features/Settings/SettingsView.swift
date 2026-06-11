//
//  SettingsView.swift
//  scran
//
//  Screen 10. Plan (view/edit → recalculates + new explanation), subscription
//  status with prominent restore, free CSV export, support with a diagnostic ID,
//  privacy, and full account deletion.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: [SortDescriptor(\UserPlan.createdAt, order: .reverse)]) private var plans: [UserPlan]

    @State private var diagnosticId = "—"
    @State private var exportFile: ExportFile? = nil
    @State private var confirmDelete = false
    @State private var confirmSignOut = false
    @State private var showUpgrade = false
    @State private var deleting = false
    @AppStorage(ScranAppearance.storageKey) private var appearanceRaw = ScranAppearance.system.rawValue
    @AppStorage("scran.healthConnected") private var healthConnected = false
    @State private var connectingHealth = false
    @State private var healthSummary: String? = nil
    @State private var health = HealthKitService.shared

    private var plan: UserPlan? { plans.first }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                ScranHeader(title: "Settings",
                            subtitle: "Your plan, your data, your account")
                    .padding(.bottom, 4)
                accountSection
                if let plan { planSection(plan) }
                if HealthKitService.isSupported { healthSection }
                appearanceSection
                subscriptionSection
                dataSection
                supportSection
                legalSection
                deleteSection
                footer
            }
            .padding(20)
            .padding(.bottom, ScranTabBar.contentHeight + 16)
        }
        .scranScreen()
        .toolbar(.hidden, for: .navigationBar)
        .task { diagnosticId = (await SupabaseClient.shared.userId) ?? "—" }
        #if canImport(UIKit)
        // .sheet(item:) so the share sheet only presents once the file URL is
        // ready — .sheet(isPresented:) raced and showed blank on first tap.
        .sheet(item: $exportFile) { file in
            ShareSheet(items: [file.url])
        }
        #endif
        .alert("Sign out?", isPresented: $confirmSignOut) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) { Task { await app.signOut(context: context) } }
        } message: {
            Text("Your data is saved to your account and will be here when you sign back in on any device.")
        }
        .alert("Delete account?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete everything", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("This permanently erases your plan, every entry, your photos and your account from our servers. This can't be undone.")
        }
    }

    // MARK: - Plan

    private func planSection(_ plan: UserPlan) -> some View {
        SettingsCard(title: "Your plan") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily target").font(ScranFont.body(13, relativeTo: .footnote))
                        .foregroundStyle(ScranColor.textMuted)
                    Text("\(ScranFormat.int(plan.dailyTargetKcal)) kcal")
                        .font(ScranFont.mono(22, weight: .bold, relativeTo: .title2))
                        .foregroundStyle(ScranColor.verified)
                }
                Spacer()
                SourceBadge(source: .label, customText: plan.goalEnum.label.uppercased())
            }
            HStack(spacing: 10) {
                NavigationLink {
                    PlanRevealView(plan: plan, primaryTitle: "Done") {}
                } label: { rowButtonLabel("View the working", "function") }
                NavigationLink {
                    PlanEditView(plan: plan)
                } label: { rowButtonLabel("Edit plan", "slider.horizontal.3") }
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        SettingsCard(title: "Account") {
            HStack(spacing: 12) {
                Image(systemName: app.isAnonymous ? "person.crop.circle.badge.exclamationmark" : "person.crop.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(app.isAnonymous ? ScranColor.estimate : ScranColor.verified)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.isAnonymous ? "Guest" : (app.email ?? "Signed in"))
                        .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(ScranColor.textPrimary).lineLimit(1)
                    Text(app.isAnonymous ? "On this device only — not synced" : "Synced to your account")
                        .font(ScranFont.body(12, relativeTo: .caption))
                        .foregroundStyle(ScranColor.textMuted)
                }
                Spacer()
            }
            if app.isAnonymous {
                PrimaryButton(title: "Create an account to sync", systemImage: "arrow.triangle.2.circlepath") {
                    showUpgrade = true
                }
            } else {
                Button { confirmSignOut = true } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign out").font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                        Spacer()
                    }
                    .foregroundStyle(ScranColor.textPrimary)
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(ScranColor.panel2))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ScranColor.lineStrong))
                }
            }
        }
        .sheet(isPresented: $showUpgrade) {
            NavigationStack {
                AuthView(isUpgrade: true, onComplete: { showUpgrade = false })
            }
            .scranAppearance()
        }
    }

    // MARK: - Apple Health

    private var healthSection: some View {
        SettingsCard(title: "Apple Health") {
            if healthConnected, let snap = health.latest, snap.hasActivity {
                HealthStatGrid(snapshot: snap)
            }
            settingsButton(
                connectingHealth ? "Reading from Apple Health…"
                                 : (healthConnected ? "Refresh from Apple Health" : "Connect Apple Health"),
                healthConnected ? "arrow.clockwise" : "heart.fill") {
                    guard !connectingHealth else { return }
                    Task { await connectHealth() }
                }
            .disabled(connectingHealth)
            if let healthSummary {
                Text(healthSummary)
                    .font(ScranFont.body(13, relativeTo: .footnote))
                    .foregroundStyle(ScranColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("// read-only — we import your weigh-ins and show steps, energy, exercise & sleep for context; movement is never added back to your budget")
                .font(ScranFont.mono(11, relativeTo: .caption2)).foregroundStyle(ScranColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { if healthConnected { await health.refreshIfConnected() } }
    }

    private func connectHealth() async {
        connectingHealth = true
        defer { connectingHealth = false }
        guard await HealthKitService.shared.requestAuthorization() else {
            healthSummary = "Couldn't connect to Apple Health."
            return
        }
        healthConnected = true
        let snap = await HealthKitService.shared.snapshot()

        // Import weigh-ins we don't already have (one per day).
        let cal = Calendar.current
        let existing = (try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []
        var days = Set(existing.filter { $0.deletedAt == nil }.map { cal.startOfDay(for: $0.date) })
        var imported = 0
        for w in snap.weightHistory {
            let day = cal.startOfDay(for: w.date)
            if days.contains(day) { continue }
            days.insert(day)
            context.insert(WeightEntry(date: day, weightKg: w.kg))
            imported += 1
        }
        if imported > 0 {
            try? context.save()
            let ctx = context
            Task { await app.sync.syncPending(context: ctx) }
        }

        var line = imported > 0 ? "Imported \(imported) weigh-in\(imported == 1 ? "" : "s") from Health."
                                : "Connected — no new weigh-ins to import."
        var activity: [String] = []
        if let e = snap.activeEnergyKcal, e >= 1 { activity.append("\(Int(e)) kcal active") }
        if let s = snap.steps, s >= 1 { activity.append("\(Int(s)) steps") }
        if let x = snap.exerciseMinutes, x >= 1 { activity.append("\(Int(x)) min exercise") }
        if !activity.isEmpty { line += " Today: " + activity.joined(separator: " · ") + "." }
        healthSummary = line
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        SettingsCard(title: "Appearance") {
            ScranSegmented(
                options: ScranAppearance.allCases.map { ($0.rawValue, $0.label) },
                selection: $appearanceRaw)
            Text("// system follows your device's light/dark setting")
                .font(ScranFont.mono(11, relativeTo: .caption2)).foregroundStyle(ScranColor.textMuted)
        }
    }

    // MARK: - Subscription

    private var subscriptionSection: some View {
        SettingsCard(title: "Subscription") {
            HStack {
                Text(app.isPro ? "Scran Pro" : "Free plan")
                    .font(ScranFont.body(16, weight: .bold, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary)
                Spacer()
                SourceBadge(source: app.isPro ? .label : .manual,
                            customText: app.isPro ? "PRO" : "FREE")
            }
            if !app.isPro {
                PrimaryButton(title: "Go Pro") { app.presentPaywall(trigger: "settings") }
            }
            Button("Restore purchases") {
                Task {
                    try? await app.entitlements.restore()
                    app.quota.isPro = app.entitlements.isPro
                }
            }
            .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
            .foregroundStyle(ScranColor.textPrimary)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        SettingsCard(title: "Your data") {
            settingsButton("Export as CSV", "square.and.arrow.up") { exportCSV() }
            Text("// your food log belongs to you — export is always free")
                .font(ScranFont.mono(11, relativeTo: .caption2)).foregroundStyle(ScranColor.textMuted)
        }
    }

    private var supportSection: some View {
        SettingsCard(title: "Support") {
            settingsButton("Email support", "envelope") { openSupport() }
            Text("Diagnostic ID: \(diagnosticId.prefix(8))")
                .font(ScranFont.mono(11, relativeTo: .caption2)).foregroundStyle(ScranColor.textMuted)
        }
    }

    private var legalSection: some View {
        SettingsCard(title: "Legal") {
            settingsLink("Privacy policy", url: ScranConfig.privacyURL)
            settingsLink("Terms of use", url: ScranConfig.termsURL)
        }
    }

    private var deleteSection: some View {
        SettingsCard(title: "Danger zone") {
            Button(role: .destructive) { confirmDelete = true } label: {
                HStack {
                    Text(deleting ? "Deleting…" : "Delete account")
                        .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                    Spacer()
                    if deleting { ProgressView().tint(ScranColor.error) }
                    else { Image(systemName: "trash") }
                }
                .foregroundStyle(ScranColor.error)
            }
            .disabled(deleting)
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Scran · built in Kent by Wireside Studios Ltd")
                .font(ScranFont.mono(11, relativeTo: .caption2))
            Text("v\(Bundle.main.appVersion)")
                .font(ScranFont.mono(11, relativeTo: .caption2))
        }
        .foregroundStyle(ScranColor.textMuted)
        .padding(.top, 12)
    }

    // MARK: - Row helpers

    private func rowButtonLabel(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title).font(ScranFont.body(14, weight: .semibold, relativeTo: .footnote))
        }
        .foregroundStyle(ScranColor.textPrimary)
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(ScranColor.panel2))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ScranColor.lineStrong))
    }

    private func settingsButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).foregroundStyle(ScranColor.textMuted)
                Text(title).font(ScranFont.body(15, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(ScranColor.textMuted)
            }
            .padding(.vertical, 6)
        }
    }

    private func settingsLink(_ title: String, url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Text(title).font(ScranFont.body(15, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary)
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(ScranColor.textMuted)
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Actions

    private func exportCSV() {
        do {
            let url = try DataExport.exportCSV(context: context)
            app.analytics.track(.exportCSV)
            exportFile = ExportFile(url: url)
        } catch {
            app.crash.capture(error, context: ["action": "export_csv"])
        }
    }

    private func openSupport() {
        app.analytics.track(.supportOpened)
        let subject = "Scran support".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let body = "\n\n—\nDiagnostic ID: \(diagnosticId)\nApp: Scran v\(Bundle.main.appVersion)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        #if canImport(UIKit)
        if let url = URL(string: "mailto:\(ScranConfig.supportEmail)?subject=\(subject)&body=\(body)") {
            UIApplication.shared.open(url)
        }
        #endif
    }

    private func deleteAccount() async {
        deleting = true
        do {
            try await AccountService.deleteAccount(context: context)
            Haptics.success()
            // Return to the auth wall — the account and its data are gone.
            app.email = nil
            app.isAuthenticated = false
        } catch {
            app.crash.capture(error, context: ["action": "delete_account"])
        }
        deleting = false
    }
}

// MARK: - Settings card

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(ScranFont.mono(11, weight: .bold, relativeTo: .caption2))
                .tracking(1.4).foregroundStyle(ScranColor.textMuted)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20).fill(ScranColor.panel))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(ScranColor.line))
    }
}

extension Bundle {
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
}

/// Identifiable wrapper so the share sheet presents via `.sheet(item:)`.
struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

#if canImport(UIKit)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif
