import AppKit
import Foundation

enum AttachmentKind: String, Codable, Equatable {
    case image
    case file
}

struct MessageAttachment: Identifiable, Codable, Equatable {
    var id: UUID
    var fileName: String
    var kind: AttachmentKind
    var storedFileName: String

    init(id: UUID = UUID(), fileName: String, kind: AttachmentKind, storedFileName: String) {
        self.id = id
        self.fileName = fileName
        self.kind = kind
        self.storedFileName = storedFileName
    }
}

enum AttachmentStore {
    private static let folderName = "Attachments"

    static var directory: URL {
        let attachmentsDir = AppDataLocation.directory.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        return attachmentsDir
    }

    static func importFile(from sourceURL: URL, kind: AttachmentKind) throws -> MessageAttachment {
        let storedName = "\(UUID().uuidString)-\(sourceURL.lastPathComponent)"
        let destination = directory.appendingPathComponent(storedName)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destination)

        return MessageAttachment(
            fileName: sourceURL.lastPathComponent,
            kind: kind,
            storedFileName: storedName
        )
    }

    static func importImageFromPasteboard() throws -> MessageAttachment? {
        let pasteboard = NSPasteboard.general
        guard let image = NSImage(pasteboard: pasteboard) else { return nil }

        let storedName = "\(UUID().uuidString)-pasted-image.png"
        let destination = directory.appendingPathComponent(storedName)

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        try png.write(to: destination)

        return MessageAttachment(
            fileName: "Pasted image.png",
            kind: .image,
            storedFileName: storedName
        )
    }

    /// For image bytes that already exist in memory — a generated image
    /// fetched or decoded elsewhere — rather than a file on disk to copy or
    /// the system pasteboard. Same storage convention as the other two
    /// import paths, so a generated image is indistinguishable from a
    /// pasted or uploaded one everywhere downstream (loading, deletion,
    /// rendering all go through the same `MessageAttachment`).
    static func importImageData(_ data: Data, fileName: String) throws -> MessageAttachment {
        let storedName = "\(UUID().uuidString)-\(fileName)"
        let destination = directory.appendingPathComponent(storedName)
        try data.write(to: destination)
        return MessageAttachment(fileName: fileName, kind: .image, storedFileName: storedName)
    }

    static func fileURL(for attachment: MessageAttachment) -> URL {
        directory.appendingPathComponent(attachment.storedFileName)
    }

    static func loadImage(for attachment: MessageAttachment) -> NSImage? {
        guard attachment.kind == .image else { return nil }
        return NSImage(contentsOf: fileURL(for: attachment))
    }
}
