import AppKit
import Foundation

/// User-picked logo images for custom (BYOK) provider connections — the one
/// place a provider's icon can differ from `ProviderBrand`'s fixed catalog,
/// since a niche or unlisted brand otherwise falls back to a generic icon
/// that doesn't really look like what the user actually connected.
enum ProviderLogoStore {
    private static let directory: URL = {
        let dir = AppDataLocation.directory.appendingPathComponent("ProviderLogos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// This only ever renders inside a ~36pt circular badge, so there's no
    /// reason to keep a multi-megabyte original around just because that's
    /// what the user happened to pick.
    private static let maxDimension: CGFloat = 256

    private static var cache: [String: NSImage] = [:]

    /// Downscales and writes the picked image as PNG, deleting any previous
    /// logo for this connection first so orphaned files don't pile up one
    /// per change. Returns the stored file name to save on the config, or
    /// nil if the picked file couldn't be read as an image.
    static func saveLogo(from sourceURL: URL, replacing previousFileName: String?, for configId: UUID) -> String? {
        guard let original = NSImage(contentsOf: sourceURL) else { return nil }
        let resized = downscaled(original, maxDimension: maxDimension)
        guard let tiff = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }

        if let previousFileName {
            deleteLogo(fileName: previousFileName)
        }

        let fileName = "\(configId.uuidString)-\(UUID().uuidString).png"
        guard (try? png.write(to: directory.appendingPathComponent(fileName))) != nil else { return nil }
        cache[fileName] = resized
        return fileName
    }

    static func image(fileName: String) -> NSImage? {
        if let cached = cache[fileName] { return cached }
        guard let image = NSImage(contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        cache[fileName] = image
        return image
    }

    static func deleteLogo(fileName: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
        cache[fileName] = nil
    }

    private static func downscaled(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(1, maxDimension / max(size.width, size.height))
        guard scale < 1 else { return image }

        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                    from: NSRect(origin: .zero, size: size),
                    operation: .copy,
                    fraction: 1)
        newImage.unlockFocus()
        return newImage
    }
}
