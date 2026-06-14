//
//  ScranArt.swift
//  scran
//
//  Bespoke vector art, drawn (not bundled) so it scales crisply, adapts to
//  light/dark, and animates. The motifs are the app's own signatures — the
//  calorie ring and the three evidence sources (verified / database / estimate)
//  — so the art reads as unmistakably Scran rather than generic stock.
//

import SwiftUI

// MARK: - Clearo logo mark

/// The brand mark: the calorie ring opened into a "C" — a ring with nothing to
/// hide — with the plate-dot at its centre. Drawn so it stays crisp at any size
/// and adapts to light/dark. The app icon is this same mark rendered to PNG.
struct ClearoMark: View {
    var size: CGFloat = 150
    /// The C opening, centred on the right, in degrees.
    private let gap: Double = 76

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: (360 - gap) / 360)
                .stroke(ScranColor.verified,
                        style: StrokeStyle(lineWidth: size * 0.135, lineCap: .round))
                .rotationEffect(.degrees(gap / 2))   // centre the opening at 0° (right)
                .frame(width: size * 0.78, height: size * 0.78)
                .shadow(color: ScranColor.verified.opacity(0.18), radius: size * 0.05)
            Circle()
                .fill(ScranColor.verified)
                .frame(width: size * 0.21, height: size * 0.21)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Signature "sourced plate" illustration

/// The brand idea as art: a plate (centre disc) whose food is broken into its
/// three evidence sources, ringed by a slow data-dot halo. Gently animated and
/// Reduce-Motion-safe. Used as the hero of empty states.
struct PlateMark: View {
    var size: CGFloat = 200
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            RadialGradient(gradient: Gradient(colors: [ScranColor.verified.opacity(0.12), .clear]),
                           center: .center, startRadius: 0, endRadius: size * 0.52)
                .frame(width: size, height: size)

            // Slow data-dot halo.
            DottedRing(count: 40, dotRadius: size * 0.011)
                .fill(ScranColor.lineStrong)
                .frame(width: size * 0.98, height: size * 0.98)
                .rotationEffect(.degrees(spin ? 360 : 0))

            // Three evidence-source arcs (echoes the calorie ring + evidence bar).
            EvidenceArcs(lineWidth: size * 0.05)
                .frame(width: size * 0.72, height: size * 0.72)

            // The plate.
            Circle().fill(ScranColor.panel)
                .frame(width: size * 0.5, height: size * 0.5)
                .overlay(Circle().strokeBorder(ScranColor.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)

            // The three sources, plated.
            HStack(spacing: size * 0.05) {
                sourceDot(ScranColor.verified)
                sourceDot(ScranColor.database)
                sourceDot(ScranColor.estimate)
            }
            .scaleEffect(pulse ? 1 : 0.82)
            .opacity(pulse ? 1 : 0.7)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 44).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityHidden(true)
    }

    private func sourceDot(_ c: Color) -> some View {
        Circle().fill(c)
            .frame(width: size * 0.05, height: size * 0.05)
            .shadow(color: c.opacity(0.5), radius: size * 0.02)
    }
}

private struct EvidenceArcs: View {
    var lineWidth: CGFloat
    var body: some View {
        ZStack {
            arc(0.04, 0.30, ScranColor.verified)
            arc(0.37, 0.63, ScranColor.database)
            arc(0.70, 0.96, ScranColor.estimate)
        }
    }
    private func arc(_ from: CGFloat, _ to: CGFloat, _ c: Color) -> some View {
        Circle().trim(from: from, to: to)
            .stroke(c, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
}

/// A ring of evenly spaced dots — a Shape so it fills with one colour.
struct DottedRing: Shape {
    var count: Int
    var dotRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let radius = min(rect.width, rect.height) / 2 - dotRadius
        let c = CGPoint(x: rect.midX, y: rect.midY)
        for i in 0..<max(1, count) {
            let a = Double(i) / Double(count) * 2 * .pi
            let x = c.x + CGFloat(cos(a)) * radius
            let y = c.y + CGFloat(sin(a)) * radius
            p.addEllipse(in: CGRect(x: x - dotRadius, y: y - dotRadius,
                                    width: dotRadius * 2, height: dotRadius * 2))
        }
        return p
    }
}

// MARK: - Data-dot texture

/// A subtle dotted "graph paper" texture for hero card backgrounds. Drawn in a
/// Canvas for performance; uses the faint adaptive hairline colour so it reads
/// as paper texture, not noise. Drop behind card content, clipped to its shape.
struct DotField: View {
    var spacing: CGFloat = 16
    var dotRadius: CGFloat = 1.0
    var color: Color = ScranColor.line

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x - dotRadius, y: y - dotRadius,
                                               width: dotRadius * 2, height: dotRadius * 2))
                    x += spacing
                }
                y += spacing
            }
            ctx.fill(path, with: .color(color))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Lays a faint dot-grid texture behind a card's content, clipped to its
    /// rounded rectangle.
    func scranTexture(cornerRadius: CGFloat = 20) -> some View {
        background(
            DotField()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        )
    }
}

// MARK: - Apple Health sync illustration

/// Two app tiles (Scran + Apple Health) feeding a central checkmark, ringed by
/// floating activity labels — the "sync between the two apps" idea, drawn to
/// match a premium onboarding illustration. Adaptive + gently animated.
struct HealthSyncArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(ScranColor.panel2).frame(width: 250, height: 250)
                .overlay(Circle().strokeBorder(ScranColor.line, lineWidth: 1))

            label("Walking", x: -92, y: -96)
            label("Running", x: -108, y: -44)
            label("Yoga", x: 104, y: 30)
            label("Sleep", x: 84, y: 80)

            // Connectors from each tile to the centre checkmark.
            ConnectorCurve(from: CGPoint(x: 64, y: -52), to: CGPoint(x: 8, y: -6))
                .stroke(ScranColor.textPrimary, style: .init(lineWidth: 2, lineCap: .round))
                .frame(width: 200, height: 200)
            ConnectorCurve(from: CGPoint(x: -64, y: 52), to: CGPoint(x: -8, y: 6))
                .stroke(ScranColor.textPrimary, style: .init(lineWidth: 2, lineCap: .round))
                .frame(width: 200, height: 200)

            // Scran tile (top-right).
            tile(dark: true) {
                ZStack {
                    Circle().stroke(ScranColor.lineStrong, lineWidth: 5).frame(width: 40, height: 40)
                    Circle().trim(from: 0, to: 0.72)
                        .stroke(ScranColor.verified, style: .init(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 40, height: 40)
                    Circle().fill(ScranColor.verified).frame(width: 11, height: 11)
                }
            }
            .offset(x: 78, y: -70)

            // Apple Health tile (bottom-left).
            tile(dark: false) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: "FF5E7A"), Color(hex: "FF2D55")],
                                                    startPoint: .top, endPoint: .bottom))
            }
            .offset(x: -78, y: 70)

            // Central checkmark.
            ZStack {
                Circle().fill(ScranColor.textPrimary).frame(width: 46, height: 46)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(ScranColor.bg)
            }
            .scaleEffect(pulse ? 1 : 0.9)
        }
        .frame(width: 300, height: 280)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityHidden(true)
    }

    private func tile<Content: View>(dark: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(dark ? ScranColor.textPrimary : ScranColor.panel)
            .frame(width: 92, height: 92)
            .overlay(content())
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(ScranColor.line))
            .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
    }

    private func label(_ text: String, x: CGFloat, y: CGFloat) -> some View {
        Text(text)
            .font(ScranFont.body(15, weight: .bold, relativeTo: .subheadline))
            .foregroundStyle(ScranColor.textPrimary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(ScranColor.panel))
            .overlay(Capsule().strokeBorder(ScranColor.line))
            .offset(x: x, y: y)
    }
}

/// A quadratic curve between two points (in a centred coordinate space).
private struct ConnectorCurve: Shape {
    var from: CGPoint
    var to: CGPoint
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let p0 = CGPoint(x: c.x + from.x, y: c.y + from.y)
        let p1 = CGPoint(x: c.x + to.x, y: c.y + to.y)
        let control = CGPoint(x: c.x + to.x, y: c.y + from.y)
        var path = Path()
        path.move(to: p0)
        path.addQuadCurve(to: p1, control: control)
        return path
    }
}
