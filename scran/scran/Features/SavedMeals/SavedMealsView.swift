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
                            .listRowBackground(ScranColor.bg)
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
                mealThumb(meal)
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

    /// Photo of the meal where one exists, otherwise a quiet bookmark tile.
    @ViewBuilder private func mealThumb(_ meal: SavedMeal) -> some View {
        #if canImport(UIKit)
        if let path = meal.items.first(where: { $0.photoLocalPath != nil })?.photoLocalPath,
           let photo = PhotoStore.image(atRelativePath: path) {
            Image(uiImage: photo)
                .resizable().scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ScranColor.line))
                .accessibilityHidden(true)
        } else {
            fallbackThumb
        }
        #else
        fallbackThumb
        #endif
    }

    private var fallbackThumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(ScranColor.bg)
                .frame(width: 56, height: 56)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ScranColor.lineStrong))
            Image(systemName: "bookmark.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ScranColor.verified)
        }
        .accessibilityHidden(true)
    }

    private var empty: some View {
        VStack(spacing: 16) {
            SavedMealArt(size: 160)
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
        Haptics.warning()
        let ctx = context
        Task { await app.sync.syncPending(context: ctx) }
    }
}
