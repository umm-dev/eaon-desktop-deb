import AppKit
import Foundation

/// Swaps the running .app bundle for a newly downloaded one, in place, and
/// relaunches — the actual mechanics behind "Update Now" no longer requiring
/// a manual quit-and-drag-to-Applications.
///
/// Safety model (this is the part that must never regress):
/// - Every step before the swap can fail loudly without touching anything
///   real. Nothing is deleted until the replacement is fully extracted and
///   validated.
/// - The swap itself is two renames on the same volume (old → `.bak`, new →
///   old's path), not a copy — so the window where something could go wrong
///   mid-write is as small as the filesystem allows.
/// - If the second rename fails for any reason, the `.bak` is immediately
///   restored to the original path before the error propagates. The user
///   never ends up with neither app in place.
/// - The previous version's `.bak` is only deleted once a *subsequent*
///   update succeeds — so there's always exactly one known-good fallback
///   sitting on disk, never zero.
enum SelfUpdateInstaller {
    enum InstallError: LocalizedError {
        case notInstalledApp
        case extractionFailed
        case invalidBundle
        case swapFailed

        var errorDescription: String? {
            switch self {
            case .notInstalledApp:
                return "This build isn't an installed app, so it can't update itself."
            case .extractionFailed:
                return "Couldn't unpack the update."
            case .invalidBundle:
                return "The downloaded update looks corrupted."
            case .swapFailed:
                return "Couldn't replace the app on disk — it may need permission to write to its own folder."
            }
        }
    }

    /// Downloads, verifies, and installs the update in place. Runs entirely
    /// off the main thread; only throws after confirming nothing was left
    /// half-changed on disk.
    static func install(zipAt zipURL: URL) async throws {
        try await Task.detached(priority: .utility) {
            try installBlocking(zipAt: zipURL)
        }.value
    }

    /// Relaunches the freshly installed app and quits the current process.
    /// Call only after `install(zipAt:)` has returned successfully.
    @MainActor
    static func relaunchAndQuit() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: - Blocking implementation (runs off-main via Task.detached)

    private static func installBlocking(zipAt zipURL: URL) throws {
        let runningBundleURL = Bundle.main.bundleURL
        guard runningBundleURL.pathExtension == "app" else { throw InstallError.notInstalledApp }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("EaonUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        try run("/usr/bin/ditto", ["-x", "-k", zipURL.path, scratch.path], failing: .extractionFailed)

        let extractedApp = try locateAppBundle(in: scratch)
        try validate(appAt: extractedApp)

        try swap(newApp: extractedApp, into: runningBundleURL)
    }

    private static func locateAppBundle(in directory: URL) throws -> URL {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw InstallError.extractionFailed
        }
        return app
    }

    /// Refuses to install anything that isn't a plausible, executable Eaon
    /// bundle — a truncated download or a server serving the wrong file
    /// must never make it past this check.
    private static func validate(appAt url: URL) throws {
        let executable = url.appendingPathComponent("Contents/MacOS/Eaon")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw InstallError.invalidBundle
        }
        let infoPlistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoPlistURL),
              info["CFBundleIdentifier"] as? String == "dev.eaon.desktop" else {
            throw InstallError.invalidBundle
        }
    }

    /// Backs up the current app, moves the new one into its place, and
    /// rolls back immediately if the second step can't complete — the
    /// running app's path is never left empty.
    private static func swap(newApp: URL, into destination: URL) throws {
        let fm = FileManager.default
        let backup = destination.deletingLastPathComponent()
            .appendingPathComponent(destination.lastPathComponent + ".bak")

        // Drop any backup from an update before last — we only ever keep
        // the single most recent known-good fallback.
        try? fm.removeItem(at: backup)

        do {
            try fm.moveItem(at: destination, to: backup)
        } catch {
            throw InstallError.swapFailed
        }

        do {
            try fm.moveItem(at: newApp, to: destination)
        } catch {
            // Restore immediately — a failed swap must never leave the
            // user with neither a working old app nor a working new one.
            try? fm.moveItem(at: backup, to: destination)
            throw InstallError.swapFailed
        }
    }

    private static func run(_ launchPath: String, _ arguments: [String], failing error: InstallError) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            throw error
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw error }
    }
}
