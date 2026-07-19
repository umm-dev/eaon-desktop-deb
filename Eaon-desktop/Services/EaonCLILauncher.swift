import Foundation
import SwiftUI

/// Locates a runnable `node dist/cli.js` for the already-built `eaon-cli`
/// package and a `node` binary to run it with, so Eaon Code's embedded
/// terminal (see `EmbeddedTerminalView`) can launch the real CLI instead of
/// a plain shell. Deliberately tolerant: every path here is a best-effort
/// guess at where a dev checkout or a future packaged copy would live —
/// `resolve()` returns nil rather than throwing when nothing is found, and
/// the terminal view falls back to the user's login shell.
enum EaonCLILauncher {
    struct Launch {
        let executable: String
        let arguments: [String]
        let environment: [String]?
        let currentDirectory: String?
    }

    /// Common install locations for a `node` binary, checked in order
    /// before falling back to whatever `PATH` resolves at runtime — GUI
    /// apps on macOS don't inherit the user's shell `PATH`, so `which`
    /// alone isn't reliable here (the actual failure mode this guards
    /// against, seen with nvm/homebrew installs that never launch the app
    /// through a shell).
    private static let commonNodePaths = [
        "/opt/homebrew/bin/node",
        "/usr/local/bin/node",
        NSHomeDirectory() + "/.local/bin/node",
        NSHomeDirectory() + "/.nvm/current/bin/node",
        "/usr/bin/node",
    ]

    private static func findNode() -> String? {
        let fm = FileManager.default
        for path in commonNodePaths where fm.isExecutableFile(atPath: path) {
            return path
        }
        // Last resort: ask a real login shell to resolve it, which picks
        // up nvm/asdf-style shims a fixed path list can't anticipate.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "command -v node"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let output, !output.isEmpty, fm.isExecutableFile(atPath: output) else { return nil }
        return output
    }

    /// Where `dist/cli.js` might live, checked in priority order:
    /// 1. **Installed** (`~/.eaon/cli-app/dist/cli.js`) — the writable copy
    ///    `install()` produces. This is the only location a real end-user
    ///    install ever runs from.
    /// 2. **Dev checkout** — the `eaon-cli` sibling directory next to this
    ///    Swift package's own source, resolved from the source file's own
    ///    on-disk path (`#filePath`) so it works from an Xcode/`swift build`
    ///    run without hardcoding the developer's home directory. Lets this
    ///    app's own developer iterate on the CLI without clicking Install
    ///    after every change.
    ///
    /// Deliberately does NOT count the read-only bundled Resources copy (see
    /// `bundledPayloadDirectory()`) as a runnable entry point — that copy is
    /// install *source*, not something to execute in place. `Status.canInstall`
    /// reports its presence separately so the Settings panel can offer the
    /// Install button.
    private static func findCLIEntryPoint() -> String? {
        let fm = FileManager.default
        let installed = installedDirectory + "/dist/cli.js"
        if fm.fileExists(atPath: installed) {
            return installed
        }
        // #filePath is this source file's own on-disk location at compile
        // time — walking up from Eaon-desktop/Services/ to the repo root
        // and across to eaon-cli/dist/cli.js finds the dev build without
        // any user-specific path.
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // Eaon-desktop
            .deletingLastPathComponent() // repo root
        let devEntryPoint = repoRoot.appendingPathComponent("eaon-cli/dist/cli.js").path
        if fm.fileExists(atPath: devEntryPoint) {
            return devEntryPoint
        }
        return nil
    }

    /// Resolves everything needed to launch eaon-cli in a terminal, or nil
    /// when either `node` or the CLI's built entry point can't be found.
    static func resolve() -> Launch? {
        guard let node = findNode(), let entryPoint = findCLIEntryPoint() else { return nil }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        env["TERM"] = "xterm-256color"
        return Launch(
            executable: node,
            arguments: [entryPoint],
            environment: env.map { "\($0.key)=\($0.value)" },
            currentDirectory: NSHomeDirectory()
        )
    }

    // MARK: - Status / settings surface

    /// Everything the Settings UI needs to report on and control the CLI —
    /// whether it's runnable right now, where it lives, and its version.
    struct Status {
        /// The resolved `node` binary, or nil if none was found.
        let nodePath: String?
        /// The built `dist/cli.js` actually used to LAUNCH the CLI (Eaon
        /// Code, `resolve()`) — prefers the real install, falls back to a
        /// sibling dev checkout so this app's own developer never has to
        /// reinstall after every change. NOT what Install/Update are based
        /// on — see `installedVersion` for that.
        let entryPoint: String?
        /// The `eaon-cli` project directory (parent of `dist/`), or nil.
        let cliDirectory: String?
        /// The version of whatever `entryPoint` actually resolves to — for
        /// display (the header's "vX") and the "Run it in any terminal"
        /// commands, not for deciding whether to offer Install/Update.
        let version: String?
        /// The version of the REAL writable install at `installedDirectory`
        /// specifically — nil when nothing is installed there, regardless
        /// of whether a dev checkout happens to satisfy `entryPoint`
        /// instead. This is what Install/Update actually compare against.
        let installedVersion: String?
        /// The bundled copy's own version, whether or not anything is
        /// installed yet — `nil` in a dev build with nothing bundled.
        let bundledVersion: String?

        /// Both halves present → Eaon Code can launch the real CLI.
        var isReady: Bool { nodePath != nil && entryPoint != nil }

        /// True when nothing is installed at `installedDirectory` yet AND a
        /// bundled copy exists to install — independent of whether a dev
        /// checkout lets `entryPoint`/`isReady` already succeed, so the
        /// Install button still offers a REAL install on a developer's own
        /// machine instead of silently no-opping just because a sibling
        /// checkout happens to already make the CLI launchable.
        var canInstall: Bool { installedVersion == nil && bundledVersion != nil }

        /// Non-nil exactly when something is already installed AND the copy
        /// bundled in this app build is newer than THAT install — the
        /// Settings panel shows the Update button (instead of Install) when
        /// this is set. Compares against `installedVersion`, not `version`,
        /// so a dev-checkout fallback satisfying `entryPoint` can never
        /// mask a real pending update (or manufacture a fake one).
        var updateAvailable: String? {
            guard let installed = installedVersion, let bundled = bundledVersion,
                  EaonCLILauncher.isNewerVersion(bundled, than: installed) else { return nil }
            return bundled
        }
    }

    /// Plain dot-separated integer comparison — same idea as
    /// `UpdateChecker.isVersion(_:newerThan:)`, duplicated in miniature
    /// rather than shared, since that one lives on the `@MainActor`
    /// `UpdateChecker` and this type is deliberately actor-free (its whole
    /// point is being safe to call from a background thread). Works for
    /// both this app's CalVer (2026.3.1) and eaon-cli's semver (0.1.1) —
    /// it's just component-wise integer comparison either way.
    fileprivate static func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(a.count, b.count)
        for i in 0..<count {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Blocking (spawns a login shell to resolve `node` as a last resort) —
    /// call off the main thread. Used by the Settings CLI panel.
    static func status() -> Status {
        let node = findNode()
        let entryPoint = findCLIEntryPoint()
        let directory = cliDirectory(fromEntryPoint: entryPoint)
        let bundledDir = bundledPayloadDirectory()
        // Specifically the real install — NOT `directory`/`entryPoint`,
        // which may resolve to a dev checkout instead. Read directly rather
        // than reusing `cliDirectory(fromEntryPoint:)`'s fallback logic.
        let installedVersion: String? = FileManager.default.fileExists(atPath: installedDirectory + "/dist/cli.js")
            ? readVersion(inDirectory: installedDirectory)
            : nil
        return Status(
            nodePath: node,
            entryPoint: entryPoint,
            cliDirectory: directory,
            version: directory.flatMap(readVersion(inDirectory:)),
            installedVersion: installedVersion,
            bundledVersion: bundledDir.flatMap(readVersion(inDirectory:))
        )
    }

    // MARK: - Install

    /// The writable copy `install()` produces `dist/cli.js` runs from —
    /// distinct from `configDirectory` (`~/.eaon/cli`), which is the CLI's
    /// own config/session storage, not its program files.
    static var installedDirectory: String {
        NSHomeDirectory() + "/.eaon/cli-app"
    }

    /// Where a global `eaon` shim script gets written. Not guaranteed to be
    /// on `PATH` (macOS shells don't add `~/.local/bin` by default) — the
    /// Settings panel says so plainly rather than pretending this always works.
    static var globalCommandPath: String {
        NSHomeDirectory() + "/.local/bin/eaon"
    }

    /// The read-only, pre-built `eaon-cli` copy shipped inside the app
    /// bundle (`Contents/Resources/eaon-cli/`, added by `build-installer.sh`)
    /// — the install source. Nil in an Xcode/`swift build` dev run, where
    /// there's nothing bundled and `findCLIEntryPoint()`'s dev-checkout
    /// fallback is used directly instead.
    private static func bundledPayloadDirectory() -> String? {
        guard let resourceURL = Bundle.main.url(forResource: "eaon-cli", withExtension: nil) else { return nil }
        let entryPoint = resourceURL.appendingPathComponent("dist/cli.js").path
        return FileManager.default.fileExists(atPath: entryPoint) ? resourceURL.path : nil
    }

    enum InstallError: LocalizedError {
        case noBundledPayload
        case copyFailed(Error)

        var errorDescription: String? {
            switch self {
            case .noBundledPayload:
                return "This build doesn't have Eaon CLI bundled — nothing to install."
            case .copyFailed(let error):
                return "Couldn't install Eaon CLI: \(error.localizedDescription)"
            }
        }
    }

    /// Copies the bundled CLI to `installedDirectory` and writes the global
    /// `eaon` shim. Pure file I/O — no network, no npm — so it's fast and
    /// works offline. Call off the main thread.
    ///
    /// Also what `update()` calls: an update to a newer bundled copy is the
    /// exact same operation as a fresh install (wipe `installedDirectory`,
    /// recopy, rewrite the shim) — the CLI's config/sessions live in the
    /// separate `configDirectory` (`~/.eaon/cli`) and are never touched.
    static func install() throws {
        guard let source = bundledPayloadDirectory() else { throw InstallError.noBundledPayload }
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: installedDirectory) {
                try fm.removeItem(atPath: installedDirectory)
            }
            try fm.createDirectory(
                atPath: (installedDirectory as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try fm.copyItem(atPath: source, toPath: installedDirectory)
            try writeGlobalShim()
        } catch {
            throw InstallError.copyFailed(error)
        }
    }

    /// Updates an already-installed CLI to the version bundled in this app
    /// build — see `Status.updateAvailable` for when this is actually
    /// offered. Named separately from `install()` for a clear call site
    /// even though the operation is identical; call off the main thread.
    static func update() throws {
        try install()
    }

    /// Removes both the installed copy and the global shim. Leaves the
    /// bundled payload untouched, so Install can run again afterward.
    static func uninstall() {
        let fm = FileManager.default
        try? fm.removeItem(atPath: installedDirectory)
        try? fm.removeItem(atPath: globalCommandPath)
    }

    /// A POSIX shim rather than a hardcoded `node` path, so it keeps working
    /// if the user's Node install moves (nvm version switch, a later Homebrew
    /// upgrade, …) — mirrors `commonNodePaths`' search order in shell form.
    private static func writeGlobalShim() throws {
        let fm = FileManager.default
        let binDir = (globalCommandPath as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        let script = """
        #!/bin/sh
        # Written by Eaon.app's "Install Eaon CLI" — safe to delete.
        for candidate in /opt/homebrew/bin/node /usr/local/bin/node "$HOME/.local/bin/node" "$HOME/.nvm/current/bin/node" /usr/bin/node; do
          if [ -x "$candidate" ]; then NODE="$candidate"; break; fi
        done
        if [ -z "$NODE" ]; then NODE=$(command -v node); fi
        if [ -z "$NODE" ]; then
          echo "eaon: Node.js not found. Install it (e.g. brew install node) and try again." >&2
          exit 1
        fi
        exec "$NODE" "\(installedDirectory)/dist/cli.js" "$@"
        """
        try script.write(toFile: globalCommandPath, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: globalCommandPath)
    }

    /// Where the CLI's own config + sessions live (`~/.eaon/cli/`) — the same
    /// path the Node CLI's `platform.ts configDir()` computes, so the app and
    /// the CLI point at the exact same file.
    static var configDirectory: String {
        NSHomeDirectory() + "/.eaon/cli"
    }

    static var configFilePath: String {
        configDirectory + "/config.json"
    }

    /// The `eaon-cli` directory: prefer walking up from a resolved entry
    /// point (`.../eaon-cli/dist/cli.js` → `.../eaon-cli`), else fall back to
    /// the dev-checkout location next to this source file so the Settings
    /// panel can still show "how to build it" before a first build exists.
    private static func cliDirectory(fromEntryPoint entryPoint: String?) -> String? {
        if let entryPoint {
            // .../eaon-cli/dist/cli.js → .../eaon-cli
            let dir = URL(fileURLWithPath: entryPoint)
                .deletingLastPathComponent() // dist
                .deletingLastPathComponent() // eaon-cli
            return dir.path
        }
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // Eaon-desktop
            .deletingLastPathComponent() // repo root
        let devDir = repoRoot.appendingPathComponent("eaon-cli").path
        return FileManager.default.fileExists(atPath: devDir) ? devDir : nil
    }

    private static func readVersion(inDirectory directory: String) -> String? {
        let packageJSON = directory + "/package.json"
        guard let data = FileManager.default.contents(atPath: packageJSON),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String else { return nil }
        return version
    }
}

/// Drives the floating "Eaon CLI update available" card — same idea as
/// `UpdateChecker`, just for the CLI's bundled-copy install instead of a
/// network download. `EaonCLILauncher` itself stays a plain, actor-free
/// enum (it's called off the main thread elsewhere); this is the
/// `@MainActor` UI-facing wrapper around it.
@MainActor
@Observable
final class EaonCLIUpdateStore {
    static let shared = EaonCLIUpdateStore()

    enum UpdateState: Equatable {
        case idle
        case updating
        case done
        case failed(String)
    }

    /// Non-nil exactly while the card should be showing — the newer
    /// bundled version.
    private(set) var available: String?
    private(set) var state: UpdateState = .idle

    private static let snoozedVersionKey = "eaon_cli_update_snoozed_version"
    private static let snoozeUntilKey = "eaon_cli_update_snooze_until"

    private init() {}

    /// Background check (launch): silent unless something's actually
    /// installed already AND a genuinely newer, non-snoozed bundled copy
    /// exists. A first-time install (nothing installed yet) is discovered
    /// via Settings, not this card — nobody needs to be interrupted with a
    /// popup for a feature they've never turned on.
    func checkOnLaunch() async {
        let status = await Task.detached { EaonCLILauncher.status() }.value
        guard let newer = status.updateAvailable, !Self.isSnoozed(newer) else { return }
        withAnimation(.uiEaseOut(duration: 0.45)) { available = newer }
    }

    /// Hides the card and stays quiet about THIS version for 24 hours —
    /// same per-version (not global) snooze as the app's own update card.
    func remindLater() {
        guard let available else { return }
        UserDefaults.standard.set(available, forKey: Self.snoozedVersionKey)
        UserDefaults.standard.set(Date().addingTimeInterval(24 * 60 * 60), forKey: Self.snoozeUntilKey)
        withAnimation(.uiEaseOut(duration: 0.35)) { self.available = nil }
        state = .idle
    }

    private static func isSnoozed(_ version: String) -> Bool {
        guard UserDefaults.standard.string(forKey: snoozedVersionKey) == version,
              let until = UserDefaults.standard.object(forKey: snoozeUntilKey) as? Date else { return false }
        return Date() < until
    }

    /// Copies the newer bundled CLI over the installed one — pure local
    /// file I/O, so this finishes almost instantly rather than needing a
    /// real download-progress state. Config/sessions are untouched (see
    /// `EaonCLILauncher.install`'s doc comment) — the card says so.
    func updateNow() {
        guard available != nil else { return }
        guard state != .updating else { return }
        state = .updating
        Task {
            do {
                try await Task.detached { try EaonCLILauncher.update() }.value
                state = .done
                // Let the UI show "Updated" for a beat before it vanishes,
                // same as the app's own "Restarting…" pause.
                try? await Task.sleep(nanoseconds: 900_000_000)
                withAnimation(.uiEaseOut(duration: 0.35)) { available = nil }
                state = .idle
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
