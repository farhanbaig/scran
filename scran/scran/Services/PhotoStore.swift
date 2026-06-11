//
//  PhotoStore.swift
//  scran
//
//  Local persistence for food photos in the app's Documents/food-photos dir.
//

import Foundation
#if canImport(UIKit)
import UIKit

enum PhotoStore {
    /// In-memory cache so list rows don't hit disk on every render.
    private static let cache = NSCache<NSString, UIImage>()

    private static var dir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("food-photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Save a JPEG for an entry and return its relative path.
    @discardableResult
    static func save(_ image: UIImage, entryId: UUID) -> String? {
        guard let data = ImageCompressor.jpegData(from: image) else { return nil }
        let name = "\(entryId.uuidString).jpg"
        let url = dir.appendingPathComponent(name)
        try? data.write(to: url)
        cache.setObject(image, forKey: "food-photos/\(name)" as NSString)
        return "food-photos/\(name)"
    }

    static func image(atRelativePath path: String?) -> UIImage? {
        guard let path else { return nil }
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}
#endif
