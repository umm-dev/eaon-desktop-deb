import Foundation

/// The single on-disk folder for everything Eaon stores as real files —
/// downloaded local models and message attachments. (Conversations,
/// settings, and API keys live in UserDefaults instead; see
/// `LegacyDefaultsMigrator`.)
///
/// Was named "AquaChat" from before the rename — never user-visible until
/// Settings → General started showing it, so it's renamed here, once, by
/// moving (not copying) any existing "AquaChat" folder into place. A move
/// is atomic and instant on the same volume, unlike copying, which would
/// briefly double disk usage for anyone with gigabytes of downloaded models.
enum AppDataLocation {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let current = base.appendingPathComponent("Eaon", isDirectory: true)
        let legacy = base.appendingPathComponent("AquaChat", isDirectory: true)
        if !FileManager.default.fileExists(atPath: current.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.moveItem(at: legacy, to: current)
        }
        try? FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        return current
    }()
}
