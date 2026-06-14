//
//  ProgressCharts.swift
//  scran
//
//  Swift Charts for the Progress tab. Minimal, white-first: explicit adaptive
//  colours and faint axis ink (never `.secondary`, which would be full ink here
//  since there's no grey token). Every chart guards empty / single-point data.
//

import SwiftUI
import Charts

// MARK: - Week bar chart (last 7 days vs target)

/// Drop-in for the old hand-drawn WeekBars: a verdict-tinted bar per day plus a
/// dashed target rule.
struct WeekBarChart: View {
    let days: [DayStat]
    let target: Double

    private var series: [(date: Date, kcal: Double)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
            return (d, days.first { $0.day == d }?.total.kcal ?? 0)
        }
    }

    var body: some View {
        Chart {
            ForEach(series, id: \.date) { d in
                BarMark(
                    x: .value("Day", d.date, unit: .day),
                    y: .value("kcal", d.kcal),
                    width: .ratio(0.55))
                .foregroundStyle(d.kcal > 0 ? DayVerdict(kcal: d.kcal, target: target).tint
                                            : ScranColor.verified.opacity(0.18))
                .cornerRadius(5)
            }
            if target > 0 {
                RuleMark(y: .value("Target", target))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(ScranColor.verified.opacity(0.5))
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: series.map(\.date)) { value in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
                    .font(ScranFont.mono(10, relativeTo: .caption2))
                    .foregroundStyle(ScranColor.textMuted)
            }
        }
        .frame(height: 96)
    }
}

// MARK: - Weight trend (line)

/// Weight over time. Falls back to nothing (caller keeps the list) when there
/// are fewer than two points, since a single point draws no line.
struct WeightTrendChart: View {
    let entries: [WeightEntry]   // already filtered to non-deleted

    private var points: [WeightEntry] { entries.sorted { $0.date < $1.date } }

    private var yDomain: ClosedRange<Double> {
        let ws = points.map(\.weightKg)
        guard let lo = ws.min(), let hi = ws.max() else { return 0...1 }
        let pad = max(0.5, (hi - lo) * 0.15)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        if points.count >= 2 {
            ScranCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("Weight trend")
                    Chart(points) { w in
                        AreaMark(x: .value("Date", w.date), y: .value("kg", w.weightKg))
                            .foregroundStyle(.linearGradient(
                                colors: [ScranColor.verified.opacity(0.22), ScranColor.verified.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Date", w.date), y: .value("kg", w.weightKg))
                            .foregroundStyle(ScranColor.verified)
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(x: .value("Date", w.date), y: .value("kg", w.weightKg))
                            .foregroundStyle(ScranColor.verified)
                            .symbolSize(26)
                    }
                    .chartYScale(domain: yDomain)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: max(1, points.count / 4))) { _ in
                            AxisGridLine().foregroundStyle(ScranColor.line)
                            AxisValueLabel(format: .dateTime.day().month(.narrow))
                                .font(ScranFont.mono(10, relativeTo: .caption2))
                                .foregroundStyle(ScranColor.textMuted)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine().foregroundStyle(ScranColor.line)
                            AxisValueLabel()
                                .font(ScranFont.mono(10, relativeTo: .caption2))
                                .foregroundStyle(ScranColor.textMuted)
                        }
                    }
                    // Clip the plot so the area fill can't bleed past the frame
                    // (flat/near-flat data made the AreaMark spill down the screen).
                    .chartPlotStyle { $0.clipped() }
                    .frame(height: 170)
                    .clipped()
                }
            }
        }
    }
}
