//
//  HealthKitService.swift
//  scran
//
//  Optional Apple Health integration. Read-only: pulls weight (latest + history),
//  height, age, biological sex, and today's activity (active energy + steps) to
//  set up and enrich the plan. We NEVER write to Health, and activity is shown
//  as information only — it is not added back to the calorie budget (the plan
//  already accounts for movement).
//

import Foundation
import Observation
#if canImport(HealthKit)
import HealthKit
#endif

/// A snapshot of everything useful we could read from Health in one go.
struct HealthSnapshot: Sendable {
    var weightKg: Double?
    var heightCm: Double?
    var dateOfBirth: Date?
    var biologicalSex: String?     // matches BiologicalSex.rawValue ("male"/"female") when known
    var activeEnergyKcal: Double?  // today
    var steps: Double?             // today
    var exerciseMinutes: Double?   // today
    var sleepHours: Double?        // last night
    var restingHeartRate: Double?  // latest, bpm
    var weightHistory: [(date: Date, kg: Double)] = []

    /// True when there's at least one activity metric worth showing.
    var hasActivity: Bool {
        [activeEnergyKcal, steps, exerciseMinutes, sleepHours, restingHeartRate]
            .contains { ($0 ?? 0) >= 1 }
    }
}

@MainActor
@Observable
final class HealthKitService {
    static let shared = HealthKitService()

    private(set) var isConnected = false
    /// Last snapshot read, so Today can render without re-querying every appear.
    private(set) var latest: HealthSnapshot?

    static var isSupported: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    #if canImport(HealthKit)
    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var t: Set<HKObjectType> = []
        if let m = HKObjectType.quantityType(forIdentifier: .bodyMass) { t.insert(m) }
        if let h = HKObjectType.quantityType(forIdentifier: .height) { t.insert(h) }
        if let e = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { t.insert(e) }
        if let s = HKObjectType.quantityType(forIdentifier: .stepCount) { t.insert(s) }
        if let x = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) { t.insert(x) }
        if let hr = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { t.insert(hr) }
        if let sl = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { t.insert(sl) }
        t.insert(HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!)
        t.insert(HKObjectType.characteristicType(forIdentifier: .biologicalSex)!)
        return t
    }

    /// Ask permission for the read types. Returns false if Health is unavailable
    /// or the request errors (the user declining still "succeeds" — Health hides
    /// which types were granted, so we discover that when reads return nil).
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard Self.isSupported else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isConnected = true
            return true
        } catch {
            return false
        }
    }

    /// One round trip that gathers everything useful. Caches into `latest`.
    @discardableResult
    func snapshot() async -> HealthSnapshot {
        guard Self.isSupported else { return HealthSnapshot() }
        var snap = HealthSnapshot()
        snap.weightKg = await latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo))
        snap.heightCm = await latestQuantity(.height, unit: .meterUnit(with: .centi))
        snap.activeEnergyKcal = await sumToday(.activeEnergyBurned, unit: .kilocalorie())
        snap.steps = await sumToday(.stepCount, unit: .count())
        snap.exerciseMinutes = await sumToday(.appleExerciseTime, unit: .minute())
        snap.restingHeartRate = await latestQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        snap.sleepHours = await sleepHoursLastNight()
        snap.weightHistory = await weightHistory(daysBack: 180)
        snap.dateOfBirth = characteristicDOB()
        snap.biologicalSex = characteristicSex()
        // Don't blank an existing card on a transient empty read.
        if snap.hasActivity || latest == nil { latest = snap }
        return snap
    }

    /// Refresh the cached snapshot if the user has connected Health.
    func refreshIfConnected() async {
        guard Self.isSupported,
              UserDefaults.standard.bool(forKey: "scran.healthConnected") else { return }
        await snapshot()
    }

    // MARK: - Characteristics

    private func characteristicDOB() -> Date? {
        guard let comps = try? store.dateOfBirthComponents() else { return nil }
        return Calendar.current.date(from: comps)
    }

    private func characteristicSex() -> String? {
        guard let s = try? store.biologicalSex().biologicalSex else { return nil }
        switch s {
        case .male:   return "male"
        case .female: return "female"
        default:      return nil   // other/notSet — leave the user's onboarding choice
        }
    }

    // MARK: - Quantity reads

    private func latestQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let v = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: v)
            }
            store.execute(q)
        }
    }

    private func sumToday(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    /// Hours actually asleep in the last night (from yesterday 18:00 → now).
    private func sleepHoursLastNight() async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let cal = Calendar.current
        let start = cal.date(byAdding: .hour, value: -18, to: cal.startOfDay(for: Date())) ?? Date()
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, _ in
                cont.resume(returning: (s as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let seconds = samples
            .filter { asleep.contains($0.value) }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return seconds > 0 ? seconds / 3600 : nil
    }

    /// One representative (latest) weight per day over the window, oldest→newest.
    private func weightHistory(daysBack: Int) async -> [(date: Date, kg: Double)] {
        guard let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let samples: [HKQuantitySample] = await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, s, _ in
                cont.resume(returning: (s as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
        let cal = Calendar.current
        var perDay: [Date: Double] = [:]
        for s in samples {
            let day = cal.startOfDay(for: s.endDate)
            perDay[day] = s.quantity.doubleValue(for: .gramUnit(with: .kilo))  // later sample wins (sorted ascending)
        }
        return perDay.sorted { $0.key < $1.key }.map { (date: $0.key, kg: $0.value) }
    }

    #else
    func requestAuthorization() async -> Bool { false }
    @discardableResult func snapshot() async -> HealthSnapshot { HealthSnapshot() }
    func refreshIfConnected() async {}
    #endif
}
