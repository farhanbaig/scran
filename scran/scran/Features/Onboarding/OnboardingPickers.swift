//
//  OnboardingPickers.swift
//  scran
//
//  Signature input controls: a horizontal ruler slider (weight) and wheel-based
//  height pickers (ft·in / cm), styled for Confident Dark.
//

import SwiftUI

// MARK: - Ruler slider (weight)

/// Momentum-scrolling ruler. Uses a native horizontal ScrollView with
/// view-aligned snapping + scroll position, so it feels smooth with real inertia
/// and fires a selection haptic as each whole unit passes the needle.
struct RulerSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 0.1
    var majorEvery: Int = 10            // a taller tick every N steps (1 unit)
    var tickSpacing: CGFloat = 10
    var unit: String
    var decimals: Int = 1

    @State private var selection: Int?
    @State private var lastHapticUnit: Int = .min

    private var count: Int { Int(((range.upperBound - range.lowerBound) / step).rounded()) + 1 }
    private func valueAt(_ i: Int) -> Double { range.lowerBound + Double(i) * step }
    private var currentIndex: Int { Int(((value - range.lowerBound) / step).rounded()) }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 2) {
                Text(unit == "kg" || unit == "lbs" ? "Current weight" : "Value")
                    .font(ScranFont.body(14, relativeTo: .footnote))
                    .foregroundStyle(ScranColor.textMuted)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.\(decimals)f", value))
                        .font(ScranFont.mono(42, weight: .bold, relativeTo: .largeTitle))
                        .foregroundStyle(ScranColor.textPrimary)
                        .contentTransition(.numericText(value: value))
                        .animation(.snappy(duration: 0.15), value: value)
                    Text(unit)
                        .font(ScranFont.mono(18, relativeTo: .title3))
                        .foregroundStyle(ScranColor.textMuted)
                }
            }

            GeometryReader { geo in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: tickSpacing) {
                        ForEach(0..<count, id: \.self) { i in
                            let isMajor = i % majorEvery == 0
                            Rectangle()
                                .fill(isMajor ? ScranColor.textMuted : ScranColor.lineStrong)
                                .frame(width: 2, height: isMajor ? 38 : 18)
                                .frame(height: 64, alignment: .center)
                                .id(i)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selection, anchor: .center)
                .contentMargins(.horizontal, geo.size.width / 2, for: .scrollContent)
                .overlay(alignment: .center) {
                    Rectangle().fill(ScranColor.verified)
                        .frame(width: 3, height: 52)
                }
            }
            .frame(height: 64)
            .onAppear { if selection == nil { selection = currentIndex } }
            .onChange(of: selection) { _, new in
                guard let new, new >= 0, new < count else { return }
                let v = valueAt(new)
                if abs(v - value) > step / 2 { value = v }
                let unitTick = Int(v.rounded())
                if unitTick != lastHapticUnit { lastHapticUnit = unitTick; Haptics.selection() }
            }
        }
    }
}

// MARK: - Height picker (ft·in / cm)

struct HeightPicker: View {
    @Binding var heightCm: Double
    @Binding var unit: HeightUnit

    var body: some View {
        VStack(spacing: 18) {
            ScranSegmented(options: HeightUnit.allCases.map { ($0, $0.label) }, selection: $unit)
                .frame(maxWidth: 240)

            if unit == .cm {
                Picker("cm", selection: cmBinding) {
                    ForEach(120...220, id: \.self) {
                        Text("\($0) cm").foregroundStyle(ScranColor.textPrimary).tag($0)
                    }
                }
                .pickerStyle(.wheel)
                .tint(ScranColor.textPrimary)
            } else {
                HStack(spacing: 0) {
                    Picker("ft", selection: feetBinding) {
                        ForEach(3...8, id: \.self) {
                            Text("\($0) ft").foregroundStyle(ScranColor.textPrimary).tag($0)
                        }
                    }.pickerStyle(.wheel)
                    Picker("in", selection: inchBinding) {
                        ForEach(0...11, id: \.self) {
                            Text("\($0) in").foregroundStyle(ScranColor.textPrimary).tag($0)
                        }
                    }.pickerStyle(.wheel)
                }
                .tint(ScranColor.textPrimary)
            }
        }
    }

    private var cmBinding: Binding<Int> {
        Binding(get: { Int(heightCm.rounded()) }, set: { heightCm = Double($0) })
    }
    private var totalInches: Double { heightCm / 2.54 }
    private var feetBinding: Binding<Int> {
        Binding(get: { Int(totalInches / 12) },
                set: { heightCm = (Double($0) * 12 + Double(inchBinding.wrappedValue)) * 2.54 })
    }
    private var inchBinding: Binding<Int> {
        Binding(get: { Int((totalInches - Double(Int(totalInches / 12)) * 12).rounded()) },
                set: { heightCm = (Double(feetBinding.wrappedValue) * 12 + Double($0)) * 2.54 })
    }
}

// MARK: - Date of birth wheel

struct DOBPicker: View {
    @Binding var date: Date
    var body: some View {
        DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
            .datePickerStyle(.wheel)
            .labelsHidden()
            .tint(ScranColor.verified)
    }
}
