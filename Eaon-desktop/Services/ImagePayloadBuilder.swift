import AppKit

/// Turns a stored image attachment into a base64 payload safe to send to
/// any vision-capable model — normalizing format (so a picked HEIC/GIF/
/// whatever still becomes a PNG every provider accepts) and capping
/// resolution (so a full-size photo doesn't blow past a provider's
/// payload limit or balloon token cost for no visual benefit).
enum ImagePayloadBuilder {
    /// Anthropic's own docs note no vision-quality benefit past this on
    /// the long edge — a reasonable, provider-agnostic cap.
    private static let maxDimension: CGFloat = 1568

    static func build(for attachment: MessageAttachment) -> HistoryImage? {
        guard attachment.kind == .image,
              let image = AttachmentStore.loadImage(for: attachment) else { return nil }

        let resized = resizedIfNeeded(image)
        guard let tiff = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }

        return HistoryImage(base64: png.base64EncodedString(), mimeType: "image/png")
    }

    private static func resizedIfNeeded(_ image: NSImage) -> NSImage {
        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > maxDimension, longEdge > 0 else { return image }

        let scale = maxDimension / longEdge
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)

        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()
        return resized
    }
}
