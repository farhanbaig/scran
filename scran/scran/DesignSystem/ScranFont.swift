//
//  ScranFont.swift
//  scran
//
//  Type system with Dynamic Type scaling. Three families:
//    Display  — Archivo Black (titles, headlines, prices). UPPERCASE, sparingly.
//    Body     — Inter Tight (all body copy, buttons, labels).
//    Mono     — Space Mono (every numeric value, badges, // microcopy).
//
//  Fonts are registered at runtime from the app bundle (see AppFonts). If the
//  font files are absent, Font.custom falls back to the system font of the same
//  size, so the app still builds and runs.
//

import SwiftUI
import CoreText

enum ScranFont {

    // PostScript names of the bundled fonts.
    private static let displayName = "ArchivoBlack-Regular"
    private static let monoRegular = "SpaceMono-Regular"
    private static let monoBold    = "SpaceMono-Bold"

    /// Global type-scale multiplier. Bumps every font up proportionally — text
    /// across the app reads larger without touching individual call sites.
    /// Display (already large titles) scales a little less to avoid truncation.
    private static let bodyScale: CGFloat = 1.13
    private static let displayScale: CGFloat = 1.06

    enum BodyWeight {
        case regular, medium, semibold, bold
        var name: String {
            switch self {
            case .regular:  return "InterTight-Regular"
            case .medium:   return "InterTight-Medium"
            case .semibold: return "InterTight-SemiBold"
            case .bold:     return "InterTight-Bold"
            }
        }
        var system: Font.Weight {
            switch self {
            case .regular:  return .regular
            case .medium:   return .medium
            case .semibold: return .semibold
            case .bold:     return .bold
            }
        }
    }

    /// Archivo Black — display headlines. Pair with `.textCase(.uppercase)`.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom(displayName, size: (size * displayScale).rounded(), relativeTo: style)
    }

    /// Inter Tight — body, buttons, labels.
    static func body(_ size: CGFloat, weight: BodyWeight = .regular,
                     relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.name, size: (size * bodyScale).rounded(), relativeTo: style)
    }

    /// Space Mono — numbers, evidence, badge text, microcopy.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular,
                     relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight == .bold ? monoBold : monoRegular, size: (size * bodyScale).rounded(), relativeTo: style)
    }
}

/// Registers bundled OFL fonts at launch so they're usable without an
/// Info.plist `UIAppFonts` array. Safe no-op when files are missing.
enum AppFonts {
    private static let files = [
        "ArchivoBlack-Regular",
        "InterTight-Regular", "InterTight-Medium", "InterTight-SemiBold", "InterTight-Bold",
        "SpaceMono-Regular", "SpaceMono-Bold",
    ]

    static func register() {
        for name in files {
            for ext in ["ttf", "otf"] {
                guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { continue }
                var error: Unmanaged<CFError>?
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
                break
            }
        }
        #if DEBUG
        if Bundle.main.url(forResource: "ArchivoBlack-Regular", withExtension: "ttf") == nil {
            print("⚠️ Scran fonts not bundled — falling back to system fonts. " +
                  "Add .ttf files to scran/Resources/Fonts (see Resources/Fonts/README.md).")
        }
        #endif
    }
}
