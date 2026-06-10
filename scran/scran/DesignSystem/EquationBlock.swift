//
//  EquationBlock.swift
//  scran
//
//  Signature treatment: the plan equation. bg-coloured inset card, 1pt line
//  border, 14pt radius, Space Mono rows (label … value), a 2pt rule above the
//  total, and the daily-target value in verified green with a soft glow.
//

import SwiftUI

struct EquationRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    var isTotal: Bool = false
}

struct EquationBlock: View {
    let rows: [EquationRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { _, row in
                if row.isTotal {
                    Rectangle()
                        .fill(ScranColor.textPrimary)
                        .frame(height: 2)
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label)
                        .font(ScranFont.mono(row.isTotal ? 15 : 13, relativeTo: .footnote))
                        .foregroundStyle(ScranColor.textMuted)
                    Spacer(minLength: 12)
                    Text(row.value)
                        .font(ScranFont.mono(row.isTotal ? 19 : 14, weight: .bold,
                                             relativeTo: row.isTotal ? .title3 : .body))
                        .foregroundStyle(row.isTotal ? ScranColor.verified : ScranColor.textPrimary)
                        .shadow(color: row.isTotal ? ScranColor.verified.opacity(0.5) : .clear,
                                radius: row.isTotal ? 12 : 0)
                }
                .padding(.vertical, row.isTotal ? 0 : 7)
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ScranColor.bg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ScranColor.line, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    EquationBlock(rows: [
        EquationRow(label: "Base metabolism (BMR)", value: "1,712 kcal"),
        EquationRow(label: "× activity (3 workouts/wk)", value: "2,482 kcal"),
        EquationRow(label: "− deficit (0.5 kg/week)", value: "−500 kcal"),
        EquationRow(label: "Daily target", value: "1,982 kcal", isTotal: true),
    ])
    .padding(24)
    .background(ScranColor.panel2)
    .preferredColorScheme(.dark)
}
