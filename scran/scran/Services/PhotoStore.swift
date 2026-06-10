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
        return "food-photos/\(name)"
    }

    static func image(atRelativePath path: String?) -> UIImage? {
        guard let path else { return nil }
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}
#endif
