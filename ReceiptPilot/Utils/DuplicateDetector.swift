// DuplicateDetector.swift
// Detects likely duplicate receipts by comparing:
//   - Same merchant + date + total (within rounding)
//   - Perceptual image hash (dHash) against stored hashes

import Foundation
import UIKit

final class DuplicateDetector {

    private let hashStoreURL: URL = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("receipt_hashes.json")
    }()

    private var storedHashes: [StoredHash] = []

    struct StoredHash: Codable {
        let receiptID: UUID
        let merchant:  String
        let date:      String
        let total:     Double
        let imageHash: String?
    }

    init() { load() }

    // MARK: - Public

    func isDuplicate(_ receipt: Receipt, image: UIImage? = nil) async -> Bool {
        // Metadata match
        let metadataMatch = storedHashes.contains { h in
            h.merchant.lowercased() == receipt.merchant.lowercased()
            && h.date == receipt.date
            && abs(h.total - receipt.total) < 0.05
            && h.receiptID != receipt.id
        }
        if metadataMatch { return true }

        // Image hash match
        if let image, let hash = dHash(image) {
            let imageMatch = storedHashes.contains { h in
                guard let storedHash = h.imageHash else { return false }
                return hammingDistance(hash, storedHash) < 10  // threshold
            }
            if imageMatch { return true }
        }

        return false
    }

    func store(_ receipt: Receipt, image: UIImage? = nil) {
        let hash = image.flatMap { dHash($0) }
        let entry = StoredHash(
            receiptID: receipt.id,
            merchant:  receipt.merchant,
            date:      receipt.date,
            total:     receipt.total,
            imageHash: hash
        )
        storedHashes.append(entry)
        save()
    }

    // MARK: - dHash (Difference Hash)
    // Resize to 9x8, compare adjacent pixels, produce 64-bit hash string

    private func dHash(_ image: UIImage) -> String? {
        guard let gray = grayPixels(image, width: 9, height: 8) else { return nil }
        var bits = ""
        for row in 0..<8 {
            for col in 0..<8 {
                let left  = gray[row * 9 + col]
                let right = gray[row * 9 + col + 1]
                bits += left < right ? "1" : "0"
            }
        }
        // Convert bit string to hex
        var hex = ""
        for i in stride(from: 0, to: bits.count, by: 4) {
            let chunk = String(bits.dropFirst(i).prefix(4))
            if let val = UInt8(chunk, radix: 2) {
                hex += String(format: "%X", val)
            }
        }
        return hex
    }

    private func grayPixels(_ image: UIImage, width: Int, height: Int) -> [UInt8]? {
        guard let cgImage = image.cgImage else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    private func hammingDistance(_ a: String, _ b: String) -> Int {
        guard a.count == b.count else { return Int.max }
        return zip(a, b).reduce(0) { $0 + ($1.0 != $1.1 ? 1 : 0) }
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(storedHashes) else { return }
        try? data.write(to: hashStoreURL, options: .atomic)
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: hashStoreURL),
            let hashes = try? JSONDecoder().decode([StoredHash].self, from: data)
        else { return }
        storedHashes = hashes
    }
}
