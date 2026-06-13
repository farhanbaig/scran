//
//  Illustrations.swift
//  scran
//
//  Custom brand spot-illustrations, drawn in SwiftUI so they adapt to light/dark
//  and cost nothing in app size. Line-art style, one accent colour (brand green)
//  with a soft glow — consistent with ClearoMark / the charts. Used to lift the
//  app's empty states out of bare text.
//

import SwiftUI

// MARK: - Cutlery shapes

/// A simple fork: handle + three tines.
private struct ForkShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        let cx = r.midX
        let stemW = w * 0.16
        let tineTop = r.minY
        let tineBottom = r.minY + h * 0.34
        // three tines
        for i in 0..<3 {
            let x = r.minX + w * (0.18 + 0.32 * CGFloat(i))
            p.addRoundedRect(in: CGRect(x: x - stemW / 2, y: tineTop, width: stemW, height: tineBottom - tineTop),
                             cornerSize: CGSize(width: stemW / 2, height: stemW / 2))
        }
        // neck joining the tines
        p.addRoundedRect(in: CGRect(x: cx - w * 0.28, y: tineBottom - stemW * 0.4, width: w * 0.56, height: stemW),
                         cornerSize: CGSize(width: stemW / 2, height: stemW / 2))
        // handle
        p.addRoundedRect(in: CGRect(x: cx - stemW / 2, y: tineBottom, width: stemW, height: r.maxY - tineBottom),
                         cornerSize: CGSize(width: stemW / 2, height: stemW / 2))
        return p
    }
}

/// A simple knife: tapered blade + handle.
private struct KnifeShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        let cx = r.midX
        let stemW = w * 0.16
        let bladeBottom = r.minY + h * 0.42
        // blade (rounded leaf-ish)
        p.move(to: CGPoint(x: cx, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: cx + w * 0.22, y: bladeBottom),
                       control: CGPoint(x: cx + w * 0.26, y: r.minY + h * 0.18))
        p.addLine(to: CGPoint(x: cx - stemW * 0.4, y: bladeBottom))
        p.addQuadCurve(to: CGPoint(x: cx, y: r.minY),
                       control: CGPoint(x: cx - stemW * 0.4, y: r.minY + h * 0.20))
        p.closeSubpath()
        // handle
        p.addRoundedRect(in: CGRect(x: cx - stemW / 2, y: bladeBottom, width: stemW, height: r.maxY - bladeBottom),
                         cornerSize: CGSize(width: stemW / 2, height: stemW / 2))
        return p
    }
}

// MARK: - Empty meal illustration

/// Top-down plate flanked by a fork & knife, with a small "+" cue — the
/// "nothing logged yet, add your first meal" spot illustration.
struct EmptyMealArt: View {
    var size: CGFloat = 168
    private var tint: Color { ScranColor.verified }

    var body: some View {
        ZStack {
            RadialGlow(diameter: size * 1.5)

            ForkShape()
                .fill(tint.opacity(0.9))
                .frame(width: size * 0.16, height: size * 0.62)
                .offset(x: -size * 0.4)
            KnifeShape()
                .fill(tint.opacity(0.9))
                .frame(width: size * 0.16, height: size * 0.62)
                .offset(x: size * 0.4)

            // Plate
            Circle().fill(ScranColor.verifiedDim)
                .frame(width: size * 0.66, height: size * 0.66)
            Circle().strokeBorder(tint, lineWidth: size * 0.04)
                .frame(width: size * 0.66, height: size * 0.66)
            Circle().strokeBorder(tint.opacity(0.4), lineWidth: size * 0.022)
                .frame(width: size * 0.46, height: size * 0.46)

            // "Add" cue
            Image(systemName: "plus")
                .font(.system(size: size * 0.13, weight: .bold))
                .foregroundStyle(ScranColor.onVerified)
                .frame(width: size * 0.24, height: size * 0.24)
                .background(Circle().fill(tint).shadow(color: tint.opacity(0.5), radius: size * 0.05))
                .offset(x: size * 0.22, y: -size * 0.22)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Bookmark + plate motif for the Saved-meals empty state.
struct SavedMealArt: View {
    var size: CGFloat = 168
    private var tint: Color { ScranColor.verified }

    var body: some View {
        ZStack {
            RadialGlow(diameter: size * 1.4)
            Circle().fill(ScranColor.verifiedDim)
                .frame(width: size * 0.7, height: size * 0.7)
            Circle().strokeBorder(tint, lineWidth: size * 0.04)
                .frame(width: size * 0.7, height: size * 0.7)
            Image(systemName: "bookmark.fill")
                .font(.system(size: size * 0.3, weight: .semibold))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.4), radius: size * 0.04)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Rising trend motif for the History empty state.
struct TrendArt: View {
    var size: CGFloat = 168
    private var tint: Color { ScranColor.verified }

    var body: some View {
        ZStack {
            RadialGlow(diameter: size * 1.4)
            Circle().fill(ScranColor.verifiedDim)
                .frame(width: size * 0.7, height: size * 0.7)
            Circle().strokeBorder(tint, lineWidth: size * 0.04)
                .frame(width: size * 0.7, height: size * 0.7)
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: size * 0.28, weight: .semibold))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.4), radius: size * 0.04)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
