//
//  ReminderService.swift
//  scran
//
//  Honest meal-logging reminders. One quiet nudge per *unlogged* meal — never a
//  repeating ping. Once you log a meal it cancels that meal's reminder; an
//  abandoned app goes quiet after a week. No spam, no badges, no streak-guilt.
//
//  Strategy: a rolling 7-day window of one-shot UNCalendarNotificationTrigger
//  requests (repeating triggers can't skip days you've already logged). Every
//  refresh removes our pending requests and re-adds the next 7 days, skipping
//  disabled meals, today's already-logged mealtimes, and times already past.
//  Refresh is triggered by ModelContext saves (so logging a meal silences it
//  with zero call-site wiring), by foreground, and by pref changes.
//

import Foundation
import SwiftData
import Observation
#if canImport(UIKit)
import UIKit
import UserNotifications
#endif

@MainActor
@Observable
final class ReminderService {

    // MARK: - Meals we remind about (snack's window is 22:00–04:00 — never nudge then)

    enum ReminderMeal: String, CaseIterable, Identifiable {
        case breakfast, lunch, dinner
        var id: String { rawValue }
        var label: String {
            switch self {
            case .breakfast: return "Breakfast"
            case .lunch:     return "Lunch"
            case .dinner:    return "Dinner"
            }
        }
        var mealtime: Mealtime {
            switch self {
            case .breakfast: return .breakfast
            case .lunch:     return .lunch
            case .dinner:    return .dinner
            }
        }
        /// Default reminder time, minutes from midnight. Sits inside each window.
        var defaultMinutes: Int {
            switch self {
            case .breakfast: return 8 * 60 + 30   // 08:30
            case .lunch:     return 12 * 60 + 45   // 12:45
            case .dinner:    return 18 * 60 + 45   // 18:45
            }
        }
        /// Rotating copy so reminders never feel robotic. Warm, honest, never
        /// guilt-trippy — picked by calendar day in `refresh()` so consecutive
        /// days differ and a given date is stable across reschedules.
        var variants: [(title: String, body: String)] {
            switch self {
            case .breakfast:
                return [
                    ("Breakfast time 🍳", "Snap it while it's in front of you — 20 seconds and today's on track."),
                    ("Morning — what's on the plate?", "A quick log now beats guessing this afternoon."),
                    ("Start the day on the record", "Tea and toast? Log it before the day runs away."),
                    ("First meal, first log", "Catch breakfast now while the details are fresh."),
                ]
            case .lunch:
                return [
                    ("Lunch break? 🥗", "Log it now — it's easy to forget by mid-afternoon."),
                    ("What's for lunch?", "A quick photo keeps your day adding up."),
                    ("Midday check-in", "Twenty seconds to log lunch while you remember it."),
                    ("Halfway through the day", "Get lunch on the record before the afternoon kicks off."),
                ]
            case .dinner:
                return [
                    ("Dinner sorted? 🍽️", "Round off the day — log your evening meal."),
                    ("What's for dinner?", "A quick log now and today's complete."),
                    ("Last meal to log", "Twenty seconds and your day's fully on the record."),
                    ("Evening wind-down", "Log dinner now so tomorrow starts with a clean slate."),
                ]
            }
        }
    }

    // MARK: - Observable prefs (loaded from UserDefaults; setters persist)

    private enum Key {
        static let enabled = "scran.reminders.enabled"
        static func meal(_ m: ReminderMeal) -> String { "scran.reminders.\(m.rawValue)" }
        static func time(_ m: ReminderMeal) -> String { "scran.reminders.time.\(m.rawValue)" }
    }

    /// Master switch. Per-meal enabled. Per-meal time (minutes from midnight).
    private(set) var enabled: Bool
    private(set) var mealEnabled: [ReminderMeal: Bool]
    private(set) var mealMinutes: [ReminderMeal: Int]

    /// Latest known system authorization. `.notDetermined` until first checked.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    // MARK: - Internals

    private let ud = UserDefaults.standard
    private let idPrefix = "reminder."
    private let thread = "scran.reminders"
    /// Rolling window length. A week of silence for an abandoned app is on-brand;
    /// 3 meals × 7 days = 21 pending, well under the 64-request limit.
    private let windowDays = 7

    private weak var context: ModelContext?
    private var refreshTask: Task<Void, Never>?
    private var saveObserver: NSObjectProtocol?
    private var started = false

    /// Local-timezone day key (NOT the UTC formatter SyncQueue uses).
    private let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_GB_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        let defaults = ud
        // Default OFF — onboarding (or Settings) flips it on with explicit consent.
        enabled = defaults.object(forKey: Key.enabled) as? Bool ?? false
        var me: [ReminderMeal: Bool] = [:]
        var mm: [ReminderMeal: Int] = [:]
        for m in ReminderMeal.allCases {
            me[m] = defaults.object(forKey: Key.meal(m)) as? Bool ?? true
            mm[m] = defaults.object(forKey: Key.time(m)) as? Int ?? m.defaultMinutes
        }
        mealEnabled = me
        mealMinutes = mm
    }

    // MARK: - Lifecycle (called by AppModel)

    /// Wire up the context and the save-observer, then do a first schedule.
    func start(context: ModelContext) {
        self.context = context
        #if DEBUG
        // Screenshot/dev runs seed data — don't schedule from it.
        if ProcessInfo.processInfo.arguments.contains("-uiPreview") { return }
        #endif
        guard !started else { return }
        started = true
        #if canImport(UIKit)
        // One choke point for every data mutation: a SwiftData save. Covers all
        // log/edit/delete paths, plan creation, sync pulls and sign-out wipes —
        // no call-site edits, and self-healing (a deleted entry restores its
        // reminder for free).
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // Any save reschedules. The refresh is debounced + idempotent, so
                // an unrelated save (e.g. a SavedMeal) just costs one cheap pass.
                self?.scheduleRefresh()
            }
        }
        #endif
        Task { await refreshAuthorization(); scheduleRefresh() }
    }

    func onForeground() async {
        await refreshAuthorization()
        scheduleRefresh()
    }

    /// Sign-out wipes data; cancel everything and reset the master switch so the
    /// next account starts clean.
    func handleSignOut() {
        setEnabled(false)
        cancelAllPending()
    }

    // MARK: - Authorization

    func refreshAuthorization() async {
        #if canImport(UIKit)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = settings.authorizationStatus
        #endif
    }

    /// Ask the OS for permission (used by the Settings toggle when status is
    /// `.notDetermined`). Returns whether it's now usable.
    @discardableResult
    func requestPermission() async -> Bool {
        #if canImport(UIKit)
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshAuthorization()
        return granted
        #else
        return false
        #endif
    }

    private var isAuthorized: Bool {
        switch authorization {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    // MARK: - Pref setters (persist + reschedule)

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        ud.set(on, forKey: Key.enabled)
        scheduleRefresh()
    }

    func setMeal(_ m: ReminderMeal, enabled on: Bool) {
        mealEnabled[m] = on
        ud.set(on, forKey: Key.meal(m))
        scheduleRefresh()
    }

    func setTime(_ m: ReminderMeal, minutes: Int) {
        let clamped = max(0, min(24 * 60 - 1, minutes))
        mealMinutes[m] = clamped
        ud.set(clamped, forKey: Key.time(m))
        scheduleRefresh()
    }

    // MARK: - Scheduling

    /// Coalesce bursts of triggers (foreground + a save can arrive together) into
    /// a single refresh. Everything here is @MainActor, so this fully serializes.
    func scheduleRefresh(debounce: Duration = .milliseconds(700)) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func refresh() async {
        #if canImport(UIKit)
        cancelAllPending()
        guard enabled, isAuthorized, hasPlan() else { return }

        let center = UNUserNotificationCenter.current()
        let cal = Calendar.current
        let now = Date()
        let loggedToday = loggedMealtimesToday()
        let today = cal.startOfDay(for: now)

        for dayOffset in 0..<windowDays {
            guard let dayStart = cal.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            let isToday = dayOffset == 0
            for m in ReminderMeal.allCases {
                guard mealEnabled[m] == true, let minutes = mealMinutes[m] else { continue }
                // Today: skip meals already logged, or whose time has passed.
                if isToday && loggedToday.contains(m.mealtime) { continue }
                guard let fire = cal.date(bySettingHour: minutes / 60,
                                          minute: minutes % 60, second: 0, of: dayStart) else { continue }
                if fire <= now.addingTimeInterval(60) { continue }   // 60s grace

                var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                comps.second = 0
                // Rotate copy by the calendar date: stable per day, varies daily,
                // and meals offset from each other so the same day's three nudges
                // don't all land on variant 0.
                let variants = m.variants
                let dayNumber = cal.ordinality(of: .day, in: .era, for: fire) ?? dayOffset
                let variant = variants[(dayNumber + mealOffset(m)) % variants.count]
                let content = UNMutableNotificationContent()
                content.title = variant.title
                content.body = variant.body
                content.sound = .default
                content.threadIdentifier = thread

                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let id = "\(idPrefix)\(m.rawValue).\(dayKey.string(from: fire))"
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                try? await center.add(request)
            }
        }
        #endif
    }

    private func cancelAllPending() {
        #if canImport(UIKit)
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { [idPrefix] requests in
            let ours = requests.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
        #endif
    }

    // MARK: - Data queries

    /// Which mealtimes already have a (non-deleted) entry logged today.
    private func loggedMealtimesToday() -> Set<Mealtime> {
        guard let context else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = FetchDescriptor<FoodEntry>(predicate: #Predicate {
            $0.deletedAt == nil && $0.loggedAt >= start && $0.loggedAt < end
        })
        let entries = (try? context.fetch(descriptor)) ?? []
        return Set(entries.map { Mealtime.from(date: $0.loggedAt) })
    }

    /// Offsets each meal's rotation so the day's three nudges don't share a tone.
    private func mealOffset(_ m: ReminderMeal) -> Int {
        switch m {
        case .breakfast: return 0
        case .lunch:     return 1
        case .dinner:    return 2
        }
    }

    private func hasPlan() -> Bool {
        guard let context else { return false }
        var d = FetchDescriptor<UserPlan>()
        d.fetchLimit = 1
        return ((try? context.fetchCount(d)) ?? 0) > 0
    }
}
