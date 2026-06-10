//
//  Motion.swift
//  scran
//
//  Motion + haptics, both respecting accessibility settings.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum ScranMotion {
    /// Standard press animation (0.15s ease). Disabled under Reduce Motion.
    static let press: Animation = .easeOut(duration: 0.15)
    static let entry: Animation = .easeOut(duration: 0.28)
}

/// A button style that applies a 0.98 press-scale, honouring Reduce Motion.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat = 0.98
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1.0)
            .animation(reduceMotion ? nil : ScranMotion.press, value: configuration.isPressed)
    }
}

enum Haptics {
    #if canImport(UIKit)
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    #else
    static func success() {}
    static func warning() {}
    static func error() {}
    static func selection() {}
    static func tap() {}
    #endif
}
