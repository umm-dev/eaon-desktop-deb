import Foundation

struct MemoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// Durable, user-visible facts Eaon remembers across conversations — the
/// user's own manual entries, plus anything `MemoryExtractor` silently
/// pulled out of a chat. Off by default: nothing is stored or sent until
/// the user turns it on in Settings.
@MainActor
@Observable
final class MemoryStore {
    static let shared = MemoryStore()

    /// Kept low enough that the injected system message stays a short,
    /// skimmable list rather than quietly ballooning every request's
    /// prompt — a memory feature that bloats every single chat isn't a
    /// quality experience, it's a tax on it.
    static let maxMemories = 100

    private static let memoriesKey = "eaon_memories"
    private static let enabledKey = "eaon_memory_enabled"
    private static let autoLearnEnabledKey = "eaon_memory_autolearn_enabled"

    private(set) var memories: [MemoryItem] = []
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        }
    }
    /// Whether a message you send silently triggers `MemoryExtractor` to
    /// look for new facts — separate from `isEnabled`, which only
    /// controls whether facts already saved get used in chats. Turning
    /// this off stops the ongoing background extraction call after every
    /// message while everything already remembered keeps working; it has
    /// no effect on the explicit, one-time "Learn from your existing
    /// chats" backfill, which isn't automatic and stays available either
    /// way. Defaults to true (matching the only behavior this app had
    /// before this setting existed) so adding it doesn't silently change
    /// anything for someone who never touches it.
    var isAutoLearnEnabled: Bool {
        didSet {
            guard isAutoLearnEnabled != oldValue else { return }
            UserDefaults.standard.set(isAutoLearnEnabled, forKey: Self.autoLearnEnabledKey)
        }
    }

    var isFull: Bool { memories.count >= Self.maxMemories }

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        isAutoLearnEnabled = UserDefaults.standard.object(forKey: Self.autoLearnEnabledKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Self.autoLearnEnabledKey)
        if let data = UserDefaults.standard.data(forKey: Self.memoriesKey),
           let decoded = try? JSONDecoder().decode([MemoryItem].self, from: data) {
            memories = decoded.sorted { $0.createdAt > $1.createdAt }
        }
    }

    /// Adds facts pulled from a conversation, silently skipping anything
    /// that's a near-duplicate of something already stored — a plain
    /// case-insensitive containment check, not embeddings: this list is
    /// meant to stay short and human-readable, not grow an entry for every
    /// slight rephrasing of the same fact.
    func addExtracted(_ facts: [String]) {
        var didAdd = false
        for fact in facts {
            guard memories.count < Self.maxMemories else { break }
            guard !isDuplicate(of: fact) else { continue }
            memories.insert(MemoryItem(text: fact), at: 0)
            didAdd = true
        }
        if didAdd { persist() }
    }

    @discardableResult
    func addManual(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, memories.count < Self.maxMemories, !isDuplicate(of: trimmed) else { return false }
        memories.insert(MemoryItem(text: trimmed), at: 0)
        persist()
        return true
    }

    func remove(_ id: UUID) {
        memories.removeAll { $0.id == id }
        persist()
    }

    func clearAll() {
        guard !memories.isEmpty else { return }
        memories.removeAll()
        persist()
    }

    private func isDuplicate(of fact: String) -> Bool {
        memories.contains {
            $0.text.localizedCaseInsensitiveContains(fact) || fact.localizedCaseInsensitiveContains($0.text)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(memories) else { return }
        UserDefaults.standard.set(data, forKey: Self.memoriesKey)
    }
}
