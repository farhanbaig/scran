//
//  ImageCompressor.swift
//  scran
//
//  Client-side image compression before upload: ≤1280px longest edge, JPEG 0.7.
//  Keeps the vision-call payload small and the p95 latency budget under 4s.
//

import Foundation
#if canImport(UIKit)
import UIKit

enum ImageCompressor {
    static let maxEdge: CGFloat = 1280
    static let quality: CGFloat = 0.7

    static func jpegData(from image: UIImage) -> Data? {
        resized(image).jpegData(compressionQuality: quality)
    }

    static func base64(from image: UIImage) -> String? {
        jpegData(from: image)?.base64EncodedString()
    }

    static func resized(_ image: UIImage) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
#endif
