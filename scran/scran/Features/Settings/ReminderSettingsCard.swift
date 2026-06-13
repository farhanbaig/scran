//
//  ReminderSettingsCard.swift
//  scran
//
//  Settings → Reminders. Master toggle plus a per-meal time picker. Honest by
//  design: at most one quiet nudge per unlogged meal, and it disappears the
//  moment you log. Reflects the real iOS permission state.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ReminderSettingsCard: View {
    @Environment(AppModel.self) private var app
    @State private var requesting = false

    private var reminders: ReminderService { app.reminders }

    var body: some View {
        SettingsCard(title: "Reminders") {
            masterToggle

            if reminders.enabled {
                if isDenied {
                    deniedRow
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(ReminderService.ReminderMeal.allCases.enumerated()), id: \.element) { i, meal in
                            if i > 0 { Divider().overlay(ScranColor.line) }
                            mealRow(meal)
                        }
                    }
                    .padding(.top, 4)
                }
            }

            Text("One quiet nudge per unlogged meal — never more. It vanishes the moment you log.")
                .font(ScranFont.body(12, relativeTo: .caption))
                .foregroundStyle(ScranColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            #if DEBUG
            Button("Send test reminder (6s)") {
                Task { await reminders.scheduleTestNotification() }
            }
            .font(ScranFont.body(13, weight: .semibold, relativeTo: .footnote))
            .foregroundStyle(ScranColor.verified)
            .padding(.top, 4)
            #endif
        }
        .task { await reminders.refreshAuthorization() }
    }

    // MARK: - Master toggle

    private var masterToggle: some View {
        Toggle(isOn: Binding(
            get: { reminders.enabled },
            set: { on in
                if on { enable() } else { disable() }
            })) {
            Text("Daily meal reminders")
                .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                .foregroundStyle(ScranColor.textPrimary)
        }
        .tint(ScranColor.verified)
        .disabled(requesting)
    }

    private func enable() {
        Task {
            // notDetermined → ask inline; revert the toggle if refused.
            if reminders.authorization == .notDetermined {
                requesting = true
                let granted = await reminders.requestPermission()
                requesting = false
                guard granted else { return }
            }
            reminders.setEnabled(true)
            app.analytics.track(.remindersEnabled(source: "settings"))
        }
    }

    private func disable() {
        reminders.setEnabled(false)
        app.analytics.track(.remindersDisabled)
    }

    // MARK: - Per-meal row

    private func mealRow(_ meal: ReminderService.ReminderMeal) -> some View {
        let onBinding = Binding(
            get: { reminders.mealEnabled[meal] ?? true },
            set: {
                reminders.setMeal(meal, enabled: $0)
                app.analytics.track(.reminderMealToggled(meal: meal.rawValue, on: $0))
            })
        let timeBinding = Binding<Date>(
            get: { Self.date(fromMinutes: reminders.mealMinutes[meal] ?? meal.defaultMinutes) },
            set: {
                reminders.setTime(meal, minutes: Self.minutes(from: $0))
                app.analytics.track(.reminderTimeChanged(meal: meal.rawValue))
            })

        return HStack(spacing: 12) {
            Toggle(isOn: onBinding) {
                Text(meal.label)
                    .font(ScranFont.body(15, relativeTo: .body))
                    .foregroundStyle(ScranColor.textPrimary)
            }
            .tint(ScranColor.verified)
            .labelsHidden()
            Text(meal.label)
                .font(ScranFont.body(15, relativeTo: .body))
                .foregroundStyle(ScranColor.textPrimary)
            Spacer()
            DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .disabled(!(reminders.mealEnabled[meal] ?? true))
                .opacity((reminders.mealEnabled[meal] ?? true) ? 1 : 0.4)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Denied state

    private var isDenied: Bool { reminders.authorization == .denied }

    private var deniedRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(ScranColor.estimate)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Notifications are turned off for Clearo in iOS Settings.")
                    .font(ScranFont.body(13, relativeTo: .footnote))
                    .foregroundStyle(ScranColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                #if canImport(UIKit)
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(ScranFont.body(13, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(ScranColor.verified)
                #endif
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(ScranColor.estimateDim))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ScranColor.estimate.opacity(0.3)))
        .padding(.top, 4)
    }

    // MARK: - Minutes ↔ Date helpers (DatePicker wants a Date)

    private static func date(fromMinutes m: Int) -> Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: cal.startOfDay(for: .now)) ?? .now
    }

    private static func minutes(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
