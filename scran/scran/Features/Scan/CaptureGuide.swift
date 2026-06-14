//
//  CaptureGuide.swift
//  scran
//
//  The framing guide drawn over the camera + the crop that makes it real: what
//  the user frames inside the box is exactly what gets analysed. Without this the
//  AI received the whole scene (the label-scan failure mode), not the table.
//

import SwiftUI
#if canImport(UIKit)
import UIKit

/// The framing aid shown over the live camera, and the region the capture is
/// cropped to. Dimensions are chosen for the subject: a portrait rectangle for a
/// nutrition table, a large square for a plate shot straight down.
enum CaptureGuide {
    case none
    case label
    case plate

    var cropsToGuide: Bool { self != .none }

    /// The guide rectangle within a camera view of `size`, centred.
    func rect(in size: CGSize) -> CGRect {
        switch self {
        case .none:
            return CGRect(origin: .zero, size: size)
        case .label:
            // Tall rectangle — a nutrition table is a vertical column of rows.
            let w = size.width * 0.84
            let h = min(size.height * 0.56, w * 1.5)
            return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
        case .plate:
            // Large square — encourages filling the frame from directly above.
            let side = min(size.width * 0.9, size.height * 0.62)
            return CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2,
                          width: side, height: side)
        }
    }

    var cornerRadius: CGFloat { self == .plate ? 22 : 14 }
}

extension UIImage {
    /// Redraw to a `.up`-oriented image so pixel math below is correct (camera
    /// photos come back `.right`).
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Crop to a rectangle expressed in the coordinate space of an aspect-fill
    /// camera preview of `viewSize`. Maps view points → image pixels, accounting
    /// for the fill scaling and centring, then crops. Returns self on any miss.
    func croppedToPreviewRect(_ rect: CGRect, viewSize: CGSize) -> UIImage {
        let img = normalizedUp()
        guard viewSize.width > 0, viewSize.height > 0, let cg = img.cgImage else { return img }

        let iw = img.size.width, ih = img.size.height
        let fill = max(viewSize.width / iw, viewSize.height / ih)   // aspect-fill
        let dispW = iw * fill, dispH = ih * fill
        let ox = (viewSize.width - dispW) / 2     // ≤ 0 when cropped on that axis
        let oy = (viewSize.height - dispH) / 2

        // View rect → image points.
        var cropPts = CGRect(x: (rect.minX - ox) / fill,
                             y: (rect.minY - oy) / fill,
                             width: rect.width / fill,
                             height: rect.height / fill)
        cropPts = cropPts.intersection(CGRect(origin: .zero, size: img.size))
        guard !cropPts.isNull, cropPts.width > 16, cropPts.height > 16 else { return img }

        // Image points → pixels.
        let s = img.scale
        let cropPx = CGRect(x: cropPts.minX * s, y: cropPts.minY * s,
                            width: cropPts.width * s, height: cropPts.height * s)
        guard let out = cg.cropping(to: cropPx) else { return img }
        return UIImage(cgImage: out, scale: s, orientation: .up)
    }
}
#endif
