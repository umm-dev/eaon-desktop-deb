# How Eaon updates work, and how to ship one

## How it works

- On every launch, the app fetches one small JSON file (the **update
  manifest**) from `UpdateChecker.manifestURL`
  (`Eaon-desktop/Services/UpdateChecker.swift`).
- If the manifest's `latestVersion` is newer than the app's own
  `AppVersion.current`, the "New Version" card appears (bottom-right) with
  **Remind Me Later / Update Now**.
- **Update Now** downloads the `.zip` at `downloadURL`, hands it to
  `SelfUpdateInstaller`
  (`Eaon-desktop/Services/SelfUpdateInstaller.swift`), and — once verified —
  swaps it into place and relaunches automatically. No manual quit-and-drag.
  See that file's header comment for the exact safety mechanics (nothing is
  touched on disk until the download is verified complete and the bundle
  checks out; a failed swap rolls back immediately).
- **Remind Me Later** snoozes *that version* for 24 hours. A newer version
  published during the snooze still prompts.
- An unreachable server or malformed manifest is a silent no-op — users are
  never shown update errors they didn't ask for. (Settings → General →
  "Check for Updates" is the manual check, and that one does report its
  outcome either way.)

## One-time setup

1. Pick a stable HTTPS URL for the manifest (any static host: your site,
   GitHub releases/raw, S3, …).
2. Put that URL in `UpdateChecker.manifestURL`. Until you do, checks fail
   silently and nobody is ever prompted.

## Shipping a release

1. Add an entry to `CHANGELOG.md` describing what's in the release —
   this is also where the manifest's `releaseNotes` text comes from, so
   write it for the card, not just for developers.
2. Bump `AppVersion.current` in `UpdateChecker.swift` to the new version.
   Do this **before** building — the version baked into the binary you're
   about to ship must match what the manifest will announce, or a
   freshly-updated app immediately thinks it needs to update again.

   Versioning is `YYYY.MINOR.PATCH`, not semver. Default to a PATCH bump
   (`2026.1.1` → `2026.1.2`) — that covers bug fixes, new features, even a
   large batch of them (a whole audit's worth of fixes bundled into one
   release is still PATCH). Reserve the MINOR bump (`2026.1.2` →
   `2026.2.0`) specifically for a UI overhaul or comparably sweeping
   visual/structural redesign — not just "a lot of changes." When in
   doubt, PATCH is the safer default; confirm with the user before a
   MINOR bump if it's not clearly a visual overhaul.
3. Run `./build-installer.sh` — it produces two files from the same build:
   - `dist/Eaon-<version>.dmg` — the drag-to-Applications installer, for
     first-time downloads from the website. Without a paid Apple Developer
     ID + notarization, downloaders see Gatekeeper's "unidentified
     developer" warning and must right-click → Open the first time — a
     real limit of unsigned distribution, not a bug in the installer.
   - `dist/Eaon-<version>.zip` — what the in-app self-updater downloads.
     This one doesn't hit the Gatekeeper prompt again, since it isn't
     downloaded through a browser.

   Upload **both** files to your host.
4. Edit the hosted manifest JSON (shape in `update-manifest.sample.json`):
   - `latestVersion` — the new version, e.g. `"2026.1.1"`
   - `downloadURL` — the uploaded **`.zip`**'s URL (not the dmg — that one's
     only for the website's own download link)
   - `releaseNotes` — the changelog entry's highlights, plain text, `\n`
     for line breaks

Every already-installed copy sees the new manifest on its next launch and
shows the card. That's the whole pipeline — no rebuild of anything
server-side, just one JSON edit plus two file uploads.

## Known limits (deliberate, for now)

- The build is **ad-hoc signed**, not Developer ID-signed or notarized —
  that needs a paid Apple Developer account. First-time `.dmg` downloads
  still hit Gatekeeper's warning; this doesn't change until that's in
  place.
- The manifest and download are trusted on the honor system (HTTPS only,
  no cryptographic signature — `SelfUpdateInstaller` validates that the
  downloaded bundle is a *complete, well-formed* Eaon.app, but not that it
  was published by you specifically). Fine for now; closing this properly
  means either a Developer ID + notarization or adopting
  [Sparkle](https://sparkle-project.org)'s EdDSA-signed appcasts.
