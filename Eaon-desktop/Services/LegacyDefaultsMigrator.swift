import Foundation

/// Carries UserDefaults forward across the app's identity changes.
///
/// An unbundled executable's defaults domain is its process name, so the
/// AquaChat → Eaon-desktop binary rename silently stranded everything
/// (including the entire persisted conversation list) in
/// `~/Library/Preferences/AquaChat.plist` — discovered on disk, not
/// hypothetical. Packaging into a real .app moves the domain a third time
/// (to the bundle identifier). This migrates the first launch after each
/// such move instead of quietly starting the user over from nothing.
enum LegacyDefaultsMigrator {
    /// Ordered newest-identity-first, so the most recent data wins when
    /// more than one old domain exists.
    private static let legacyDomainNames = ["Eaon-desktop", "AquaChat"]

    /// The key whose contents mean "this domain holds real user data" —
    /// the conversation list, the one thing whose silent loss matters most.
    private static let sentinelKey = "aqua_conversations"

    /// One-shot guard. Without it, a user who later chooses "delete all my
    /// data" (which legitimately writes an empty list) would get their old
    /// chats silently resurrected from a stale legacy plist on next launch.
    private static let migrationDoneKey = "legacy_defaults_migration_done_v1"

    static func migrateIfNeeded() {
        let standard = UserDefaults.standard
        guard !standard.bool(forKey: migrationDoneKey) else { return }
        defer { standard.set(true, forKey: migrationDoneKey) }

        // "Key exists" is NOT enough here: sessions run between the rename
        // and this migration existing had already written an *empty*
        // conversation list into the new domain (verified on disk — an
        // 86-byte blob sitting next to the real 190KB one), so emptiness,
        // not presence, is the real test of whether there's data to save.
        guard jsonArrayIsEmptyOrMissing(standard.object(forKey: sentinelKey)) else { return }

        for domainName in legacyDomainNames {
            guard let legacy = standard.persistentDomain(forName: domainName),
                  !jsonArrayIsEmptyOrMissing(legacy[sentinelKey]) else { continue }
            for (key, value) in legacy {
                let current = standard.object(forKey: key)
                // Fill gaps; additionally replace a value the post-rename
                // sessions left as an empty array (conversations, projects)
                // when the legacy domain has the real, non-empty one.
                if current == nil {
                    standard.set(value, forKey: key)
                } else if jsonArrayIsEmptyOrMissing(current), !jsonArrayIsEmptyOrMissing(value) {
                    standard.set(value, forKey: key)
                }
            }
            // Deliberately leaves the old plist in place — this copies
            // rather than moves, so a downgrade or mistake here can never
            // destroy the original data.
            return
        }
    }

    /// True for nil, or for a Data value that decodes as an empty JSON
    /// array ("[]") — how an emptied conversations/projects list is stored.
    /// Anything unparseable is treated as real data, never overwritten.
    private static func jsonArrayIsEmptyOrMissing(_ value: Any?) -> Bool {
        guard let value else { return true }
        guard let data = value as? Data,
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return false }
        return array.isEmpty
    }
}
