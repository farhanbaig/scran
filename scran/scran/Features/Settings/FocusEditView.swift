//
//  FocusEditView.swift
//  scran
//
//  Edit (or clear) your focus areas after onboarding — the GDPR promise that you
//  "can change or clear them any time". Reuses the onboarding MultiSelectList.
//  Clearing all selections is allowed: it withdraws the health-data consent and
//  Today simply stops showing the focus grid.
//

import SwiftUI
import SwiftData

struct FocusEditView: View {
    @Bindable var plan: UserPlan
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var selection: Set<FocusArea>

    init(plan: UserPlan) {
        self.plan = plan
        _selection = State(initialValue: Set(plan.focus))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Pick what to keep an eye on. Clearo surfaces the right numbers on your daily view — general nutrition info, not medical advice. Clear everything to stop highlighting any.")
                    .font(ScranFont.body(15, relativeTo: .body))
                    .foregroundStyle(ScranColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                MultiSelectList(options: FocusArea.allCases, selection: $selection,
                                label: \.label, icon: { $0.icon })
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .scranScreen()
        .navigationTitle("Your focus")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Save", systemImage: "checkmark") { save() }
                .padding(20).scranBottomBar()
        }
    }

    private func save() {
        plan.focusAreas = FocusArea.allCases.filter { selection.contains($0) }.map(\.rawValue)
        plan.updatedAt = .now
        plan.syncState = SyncState.pending.rawValue
        try? context.save()
        Haptics.success()
        let ctx = context
        Task { await app.sync.syncPending(context: ctx) }
        dismiss()
    }
}
