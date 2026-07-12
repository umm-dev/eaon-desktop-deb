import Foundation

/// After a turn finishes, silently asks the same model that just answered
/// to pull out any new, durable fact worth remembering about the user —
/// never shown, never allowed to touch the visible chat, and completely
/// invisible on failure (wrong provider, bad JSON back, network error: all
/// just skip, exactly like the update checker's background check does).
///
/// Deliberately NOT built on tool-calling — this app talks to three very
/// different wire formats (Aqua's own API, several BYOK providers, and
/// local llama.cpp/Ollama/MLX servers whose function-calling support is
/// inconsistent at best) and a memory feature that only sometimes works
/// depending on which model you picked is exactly the gimmick the user
/// explicitly doesn't want. A plain extra completion call, asked to reply
/// with nothing but a JSON array, works identically everywhere.
@MainActor
enum MemoryExtractor {
    static func run(
        userText: String,
        assistantText: String,
        customConfig: CustomProviderConfig?,
        localRecord: LocalModelRecord?,
        aquaApiKey: String?,
        modelId: String
    ) async {
        guard MemoryStore.shared.isEnabled, !MemoryStore.shared.isFull else { return }
        guard !userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let existing = MemoryStore.shared.memories.map(\.text)
        let prompt = buildPrompt(userText: userText, assistantText: assistantText, existing: existing)
        let history: [HistoryTurn] = [
            HistoryTurn(role: "system", content: systemPrompt),
            HistoryTurn(role: "user", content: prompt),
        ]

        guard let raw = await requestRaw(
            history: history,
            customConfig: customConfig,
            localRecord: localRecord,
            aquaApiKey: aquaApiKey,
            modelId: modelId
        ) else { return }

        let facts = parseFacts(from: raw)
        guard !facts.isEmpty else { return }
        MemoryStore.shared.addExtracted(facts)
    }

    // MARK: - Backfill from existing conversations

    /// Mines facts out of chats that already existed before memory was
    /// turned on (or before this ran) — one extraction call per
    /// conversation, sequentially, so each call sees everything found so
    /// far and doesn't re-add the same fact from conversation 2 that
    /// conversation 1 already surfaced. Explicit and opt-in (a button in
    /// Settings, never automatic): this makes a real API call per
    /// conversation, which costs time and — on a paid model — money, so
    /// it only runs when asked for, same philosophy as every other
    /// side-effectful action in this app.
    ///
    struct BackfillResult {
        let conversationsReviewed: Int
        let conversationsTotal: Int
        let factsAdded: Int
        let stoppedEarly: Bool
    }

    /// Stops early if the store fills up (no point spending more calls
    /// once nothing more can be stored) or `isCancelled` reports true
    /// (checked between conversations, not mid-call — an in-flight
    /// request is let to finish rather than aborted, so a cancel never
    /// wastes the network round-trip it already paid for).
    static func runBackfill(
        conversations: [Conversation],
        customConfig: CustomProviderConfig?,
        localRecord: LocalModelRecord?,
        aquaApiKey: String?,
        modelId: String,
        onProgress: @escaping (_ completed: Int, _ total: Int, _ newFactCount: Int) -> Void,
        isCancelled: @escaping () -> Bool
    ) async -> BackfillResult {
        let candidates = conversations.filter { !Self.transcript(for: $0).isEmpty }
        var newFactCount = 0
        var reviewed = 0
        var stoppedEarly = false
        for (index, conversation) in candidates.enumerated() {
            if isCancelled() || MemoryStore.shared.isFull {
                stoppedEarly = true
                break
            }

            let existing = MemoryStore.shared.memories.map(\.text)
            let prompt = backfillPrompt(transcript: Self.transcript(for: conversation), existing: existing)
            let history: [HistoryTurn] = [
                HistoryTurn(role: "system", content: backfillSystemPrompt),
                HistoryTurn(role: "user", content: prompt),
            ]

            if let raw = await requestRaw(history: history, customConfig: customConfig, localRecord: localRecord, aquaApiKey: aquaApiKey, modelId: modelId) {
                let facts = parseFacts(from: raw)
                if !facts.isEmpty {
                    let before = MemoryStore.shared.memories.count
                    MemoryStore.shared.addExtracted(facts)
                    newFactCount += MemoryStore.shared.memories.count - before
                }
            }
            reviewed = index + 1
            onProgress(reviewed, candidates.count, newFactCount)
        }
        return BackfillResult(conversationsReviewed: reviewed, conversationsTotal: candidates.count, factsAdded: newFactCount, stoppedEarly: stoppedEarly)
    }

    /// A capped, speaker-labeled transcript — real user/assistant turns
    /// only (tool-result and error messages are mechanical, not
    /// something a user "said," and would just dilute the extraction
    /// with noise). Capped in characters, not message count, matching
    /// every other request-size guard in this app (see
    /// `MCPConnectionStore.maxCatalogCharacters` for the same reasoning):
    /// an old conversation with hundreds of turns must never itself
    /// become the oversized-request problem this app has already had to
    /// fix more than once elsewhere.
    private static let maxTranscriptCharacters = 8000

    private static func transcript(for conversation: Conversation) -> String {
        let turns = conversation.messages.filter { $0.isToolResult != true && !$0.isError }
        var lines: [String] = []
        var used = 0
        for message in turns {
            let speaker = message.isUser ? "User" : "Assistant"
            let line = "\(speaker): \(message.content)"
            guard used + line.count <= maxTranscriptCharacters else { break }
            lines.append(line)
            used += line.count
        }
        return lines.joined(separator: "\n")
    }

    private static let backfillSystemPrompt = """
    You silently extract durable facts worth remembering about a user, from an existing chat transcript, for a \
    personalization feature. Reply with ONLY a JSON array of short strings (no markdown, no commentary) — new \
    facts not already known. Reply with [] if nothing new and durable was found.
    Only include things like: the user's name, role, location, ongoing projects, stated preferences, or a \
    significant event they explicitly shared. Never include one-off requests, facts about the assistant, \
    anything already in the known list, or speculation.
    """

    private static func backfillPrompt(transcript: String, existing: [String]) -> String {
        let known = existing.isEmpty ? "(nothing yet)" : existing.map { "- \($0)" }.joined(separator: "\n")
        return """
        Already known about the user:
        \(known)

        Chat transcript:
        \(transcript)

        JSON array of NEW durable facts, or []:
        """
    }

    private static let systemPrompt = """
    You silently extract durable facts worth remembering about a user, from one exchange of a chat, for a \
    personalization feature. Reply with ONLY a JSON array of short strings (no markdown, no commentary) — new \
    facts not already known. Reply with [] if nothing new and durable was mentioned.
    Only include things like: the user's name, role, location, ongoing projects, stated preferences, or a \
    significant event they explicitly shared. Never include one-off requests, facts about the assistant, \
    anything already in the known list, or speculation.
    """

    private static func buildPrompt(userText: String, assistantText: String, existing: [String]) -> String {
        let known = existing.isEmpty ? "(nothing yet)" : existing.map { "- \($0)" }.joined(separator: "\n")
        return """
        Already known about the user:
        \(known)

        Latest exchange:
        User: \(userText)
        Assistant: \(assistantText)

        JSON array of NEW durable facts, or []:
        """
    }

    private static func parseFacts(from raw: String) -> [String] {
        guard let jsonText = Self.extractJSONArray(from: raw),
              let data = jsonText.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return array
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count < 300 }
    }

    /// Finds a JSON array's exact substring anywhere in `text` — tracking
    /// bracket depth and skipping over quoted-string contents (so a
    /// literal "[" or "]" inside a fact string, or in trailing prose,
    /// doesn't throw off the boundary) — rather than requiring the whole
    /// reply to be pure JSON. Models reliably ignore "reply with ONLY
    /// JSON, no commentary" — the exact same lesson that motivated
    /// switching tool-calling to a native mechanism: text-format
    /// instructions aren't dependable, especially on weaker/local models
    /// — so this has to tolerate a preamble ("Sure, here's what I
    /// found:") or a trailing note instead of silently discarding real
    /// facts every time one shows up, which is what a bare
    /// `hasPrefix("```")` check did before this.
    private static func extractJSONArray(from text: String) -> String? {
        guard let start = text.firstIndex(of: "[") else { return nil }
        var depth = 0
        var inString = false
        var isEscaped = false
        var index = start
        while index < text.endIndex {
            let char = text[index]
            if isEscaped {
                isEscaped = false
            } else if char == "\\" {
                isEscaped = true
            } else if char == "\"" {
                inString.toggle()
            } else if !inString {
                if char == "[" {
                    depth += 1
                } else if char == "]" {
                    depth -= 1
                    if depth == 0 { return String(text[start...index]) }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    // MARK: - One-shot completion (reuses the same tested wire-format code the real chat path uses)

    private static func requestRaw(
        history: [HistoryTurn],
        customConfig: CustomProviderConfig?,
        localRecord: LocalModelRecord?,
        aquaApiKey: String?,
        modelId: String
    ) async -> String? {
        var collected = ""
        let typewriter = TypewriterStreamController { collected = $0 }

        do {
            if let customConfig, let key = CustomProviderStore.shared.apiKey(for: customConfig.id) {
                try await CustomProviderAPIService().streamCompletion(
                    config: customConfig, apiKey: key, modelId: modelId, history: history, typewriter: typewriter
                )
            } else if let localRecord {
                let baseURL = try await LocalAIManager.shared.ensureReady(for: localRecord)
                let ephemeralConfig = CustomProviderConfig(
                    brand: ModelCatalog.brand(for: localRecord.requestModelId),
                    baseURL: baseURL.absoluteString,
                    format: .openAICompatible,
                    modelIDs: [localRecord.requestModelId]
                )
                try await CustomProviderAPIService().streamCompletion(
                    config: ephemeralConfig, apiKey: "local-no-key", modelId: localRecord.requestModelId,
                    history: history, typewriter: typewriter
                )
            } else if let aquaApiKey {
                try await requestAquaRaw(apiKey: aquaApiKey, modelId: modelId, history: history, typewriter: typewriter)
            } else {
                return nil
            }
        } catch {
            return nil
        }

        await typewriter.waitUntilCaughtUp()
        return collected.isEmpty ? nil : collected
    }

    private static func requestAquaRaw(
        apiKey: String,
        modelId: String,
        history: [HistoryTurn],
        typewriter: TypewriterStreamController
    ) async throws {
        var request = URLRequest(url: AquaAPI.chatCompletionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let apiMessages = history.map(\.openAICompatibleJSON)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelId, "messages": apiMessages, "stream": true,
        ])

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else { continue }
            typewriter.append(content)
        }
        typewriter.markStreamFinished()
    }
}
