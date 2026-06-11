//
//  ScranColor.swift
//  scran
//
//  Brand palette. Dark is the original "Confident Dark" set (identical hex to
//  scran-landing-dark.html); light is its mirror — same hues, contrast-adjusted
//  for white surfaces. Every token is dynamic and follows the resolved
//  appearance (System / Light / Dark, see ScranAppearance).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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

    /// A colour that resolves per appearance at render time.
    static func scranAdaptive(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #else
        return dark
        #endif
    }
}

/// Brand colour tokens. Names mirror the landing-page CSS variables.
enum ScranColor {
    private static func adaptive(_ light: Color, _ dark: Color) -> Color {
        .scranAdaptive(light: light, dark: dark)
    }

    // Light mode is white-first: pure-white screen background with subtly tinted
    // grey cards so panels still separate. Dark mode is the original palette.
    static let bg          = adaptive(Color(hex: "FFFFFF"), Color(hex: "0B0D0F"))
    static let panel       = adaptive(Color(hex: "F5F6F8"), Color(hex: "13161A"))
    static let panel2      = adaptive(Color(hex: "ECEEF2"), Color(hex: "181C21"))

    static let line        = adaptive(Color.black.opacity(0.07), Color.white.opacity(0.09))
    static let lineStrong  = adaptive(Color.black.opacity(0.14), Color.white.opacity(0.16))

    static let textPrimary = adaptive(Color(hex: "16191D"), Color(hex: "F4F2EC"))
    // No greyed-out secondary text anywhere: secondary copy uses the primary ink
    // colour and relies on size/weight for hierarchy instead of a muted grey.
    static let textMuted   = textPrimary

    static let verified    = adaptive(Color(hex: "1E8F5C"), Color(hex: "34B779"))
    static let verifiedDim = adaptive(Color(hex: "1E8F5C", opacity: 0.12), Color(hex: "34B779", opacity: 0.14))
    static let database    = adaptive(Color(hex: "3D66D6"), Color(hex: "6B9BFF"))
    static let databaseDim = adaptive(Color(hex: "3D66D6", opacity: 0.10), Color(hex: "6B9BFF", opacity: 0.13))
    static let estimate    = adaptive(Color(hex: "B07514"), Color(hex: "E8A94C"))
    static let estimateDim = adaptive(Color(hex: "B07514", opacity: 0.11), Color(hex: "E8A94C", opacity: 0.13))
    static let error       = adaptive(Color(hex: "C2362C"), Color(hex: "E0564C"))

    /// Text colour that sits on top of a filled `verified` CTA.
    static let onVerified  = adaptive(Color(hex: "FFFFFF"), Color(hex: "06140D"))

    /// Very faint fill for decorative numerals/watermarks (visible in both modes).
    static let ghost       = adaptive(Color.black.opacity(0.05), Color.white.opacity(0.06))
}

// MARK: - Appearance preference

/// User-selectable appearance. Raw values are persisted in AppStorage.
enum ScranAppearance: String, CaseIterable {
    case system, light, dark

    static let storageKey = "scran.appearance"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

/// Applies the user's appearance preference. Use on every window/sheet root so
/// presented content resolves the same scheme as the main window.
struct ScranAppearanceModifier: ViewModifier {
    @AppStorage(ScranAppearance.storageKey) private var raw = ScranAppearance.system.rawValue

    func body(content: Content) -> some View {
        content.preferredColorScheme((ScranAppearance(rawValue: raw) ?? .system).colorScheme)
    }
}

extension View {
    func scranAppearance() -> some View { modifier(ScranAppearanceModifier()) }
}
