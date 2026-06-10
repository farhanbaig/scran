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
    @State private var exportURL: URL? = nil
    @State private var showExport = false
    @State private var confirmDelete = false
    @State private var deleting = false

    private var plan: UserPlan? { plans.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let plan { planSection(plan) }
                subscriptionSection
                dataSection
                supportSection
                legalSection
                deleteSection
                footer
            }
            .padding(20)
        }
        .scranScreen()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { diagnosticId = (await SupabaseClient.shared.userId) ?? "—" }
        #if canImport(UIKit)
        .sheet(isPresented: $showExport) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        #endif
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
            exportURL = try DataExport.exportCSV(context: context)
            app.analytics.track(.exportCSV)
            showExport = true
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

#if canImport(UIKit)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif
