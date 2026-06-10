//
//  ScranColor.swift
//  scran
//
//  "Confident Dark" palette — identical hex to scran-landing-dark.html.
//  Dark-first: the app ships dark as the only theme for v1.
//

import SwiftUI

extension Color {
    /// Hex initialiser. Supports "RRGGBB" and "RRGGBBAA".
    init(hex: String, opacity: Double = 1.0) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r, g, b: Double
        let a: Double
        if s.count == 8 {
            r = Double((rgb & 0xFF00_0000) >> 24) / 255
            g = Double((rgb & 0x00FF_0000) >> 16) / 255
            b = Double((rgb & 0x0000_FF00) >> 8) / 255
            a = Double(rgb & 0x0000_00FF) / 255
        } else {
            r = Double((rgb & 0xFF0000) >> 16) / 255
            g = Double((rgb & 0x00FF00) >> 8) / 255
            b = Double(rgb & 0x0000FF) / 255
            a = 1.0
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a * opacity)
    }
}

/// Brand colour tokens. Names mirror the landing-page CSS variables.
enum ScranColor {
    static let bg          = Color(hex: "0B0D0F")
    static let panel       = Color(hex: "13161A")
    static let panel2      = Color(hex: "181C21")

    static let line        = Color.white.opacity(0.09)
    static let lineStrong  = Color.white.opacity(0.16)

    static let textPrimary = Color(hex: "F4F2EC")
    static let textMuted   = Color(hex: "9BA0A8")

    static let verified    = Color(hex: "34B779")
    static let verifiedDim  = Color(hex: "34B779", opacity: 0.14)
    static let database    = Color(hex: "6B9BFF")
    static let databaseDim  = Color(hex: "6B9BFF", opacity: 0.13)
    static let estimate    = Color(hex: "E8A94C")
    static let estimateDim  = Color(hex: "E8A94C", opacity: 0.13)
    static let error       = Color(hex: "E0564C")

    /// Text colour that sits on top of a filled `verified` CTA.
    static let onVerified  = Color(hex: "06140D")
}
