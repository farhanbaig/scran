//
//  SavedMealsView.swift
//  scran
//
//  Screen 9. Sorted by timesLogged desc. One tap re-logs at the current time;
//  swipe to delete. Reused as a picker inside the Log flow and as a managed
//  list from Settings.
//

import SwiftUI
import SwiftData

struct SavedMealsView: View {
    enum Mode { case picker, manage }
    var mode: Mode = .manage
    var onLogged: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query private var meals: [SavedMeal]

    init(mode: Mode = .manage, onLogged: (() -> Void)? = nil) {
        self.mode = mode
        self.onLogged = onLogged
        _meals = Query(filter: #Predicate<SavedMeal> { $0.deletedAt == nil },
                       sort: [SortDescriptor(\.timesLogged, order: .reverse),
                              SortDescriptor(\.lastLoggedAt, order: .reverse)])
    }

    var body: some View {
        Group {
            if meals.isEmpty {
                empty
            } else {
                List {
                    ForEach(meals) { meal in
                        row(meal)
                            .listRowBackground(ScranColor.panel)
                            .listRowSeparatorTint(ScranColor.line)
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .scranScreen()
        .navigationTitle("Saved meals")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ meal: SavedMeal) -> some View {
        Button {
            relog(meal)
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(meal.name)
                        .font(ScranFont.body(16, weight: .bold, relativeTo: .body))
                        .foregroundStyle(ScranColor.textPrimary)
                    HStack(spacing: 10) {
                        Text(ScranFormat.kcalText(meal.total.kcal))
                            .font(ScranFont.mono(13, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(ScranColor.verified)
                        Text("logged \(meal.timesLogged)×")
                            .font(ScranFont.mono(12, relativeTo: .caption))
                            .foregroundStyle(ScranColor.textMuted)
                    }
                }
                Spacer()
                Image(systemName: mode == .picker ? "plus.circle.fill" : "arrow.clockwise.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(ScranColor.verified)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var empty: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark")
                .font(.system(size: 40)).foregroundStyle(ScranColor.textMuted)
            Text("No saved meals yet")
                .font(ScranFont.display(24, relativeTo: .title)).textCase(.uppercase)
                .foregroundStyle(ScranColor.textPrimary)
            Text("When you log something you eat often, flip \"Save as meal\" and it'll wait here for a one-tap re-log.")
                .font(ScranFont.body(15, relativeTo: .body))
                .multilineTextAlignment(.center).foregroundStyle(ScranColor.textMuted)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func relog(_ meal: SavedMeal) {
        for item in meal.items { context.insert(item.makeEntry()) }
        meal.timesLogged += 1
        meal.lastLoggedAt = .now
        meal.syncState = SyncState.pending.rawValue
        try? context.save()
        app.analytics.track(.mealRelogged)
        Haptics.success()
        let ctx = context
        Task { await app.sync.syncPending(context: ctx) }
        onLogged?()
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            let meal = meals[index]
            meal.deletedAt = .now
            meal.syncState = SyncState.pending.rawValue
        }
        try? context.save()
        Haptics.selection()
        let ctx = context
        Task { await app.sync.syncPending(context: ctx) }
    }
}
