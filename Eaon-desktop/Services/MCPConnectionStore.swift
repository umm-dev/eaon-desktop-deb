import AppKit
import Foundation

/// Owns every MCP (Model Context Protocol) connection the app has — token
/// storage, connect/disconnect lifecycle, and the live per-service tool
/// lists `ChatViewModel` describes to the model and dispatches calls
/// through. One store for every service (keyed by `MCPServerDefinition.id`)
/// rather than a separate singleton per service — with a dozen real,
/// individually-verified services in `MCPCatalog`, a store-per-service
/// would mean a dozen near-identical files and a hardcoded dispatch chain
/// in `ChatViewModel`; this generalizes the one working pattern instead.
@MainActor
@Observable
final class MCPConnectionStore {
    static let shared = MCPConnectionStore()

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        /// Discovery succeeded but this server doesn't support Dynamic
        /// Client Registration (verified live per server — e.g. Slack),
        /// so there's no way to sign in without a client ID the user
        /// creates themselves in that service's own developer console
        /// first. Distinct from `.failed`: this isn't an error, it's a
        /// real, expected fork in the flow the UI should offer a way
        /// forward for (a client-id field), not just report as broken.
        case needsManualClientId
        case failed(String)
    }

    private struct Connection {
        var state: ConnectionState = .disconnected
        var tools: [MCPTool] = []
        var client: MCPClient?
    }

    private var connections: [String: Connection] = [:]

    private init() {}

    func state(for serverId: String) -> ConnectionState {
        connections[serverId]?.state ?? .disconnected
    }

    func tools(for serverId: String) -> [MCPTool] {
        connections[serverId]?.tools ?? []
    }

    func isConnected(_ serverId: String) -> Bool {
        if case .connected = state(for: serverId) { return true }
        return false
    }

    /// Every currently-connected service, in catalog order — what the
    /// system prompt and tool dispatch actually iterate over.
    var connectedServers: [MCPServerDefinition] {
        MCPCatalog.available.filter { isConnected($0.id) }
    }

    /// Lets the Plugins page show "Connecting…" instead of a bare
    /// disconnected row for the brief window before `reconnectAllAtLaunch`'s
    /// network round-trip resolves.
    func hasStoredToken(_ server: MCPServerDefinition) -> Bool {
        switch server.authMode {
        case .pastedToken:
            return APIKeyStore.loadAPIKey(forAccount: server.tokenAccount) != nil
        case .oauth:
            return MCPOAuthCredentialStore.loadTokens(forAccount: server.tokenAccount) != nil
        }
    }

    /// Called once at app launch. Silent on failure — same philosophy as
    /// `UpdateChecker`'s background check: a stale/expired token shouldn't
    /// greet the user with an error before they've asked for anything, it
    /// should just leave the row showing "Connect"/"Sign in" again.
    func reconnectAllAtLaunch() async {
        for server in MCPCatalog.available where hasStoredToken(server) {
            switch server.authMode {
            case .pastedToken:
                await connect(server: server, token: nil)
            case .oauth:
                await connectOAuth(server: server, interactive: false)
            }
        }
    }

    /// Connects with a freshly-pasted token (persisted only once the
    /// handshake actually succeeds, so a bad paste is never remembered as
    /// if it worked), or reuses the stored one when `token` is nil.
    /// `server.authMode` must be `.pastedToken` — see `connectOAuth` for
    /// the other mode.
    func connect(server: MCPServerDefinition, token: String?) async {
        guard let endpoint = server.endpoint else { return }
        let resolvedToken: String
        if let token {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            resolvedToken = trimmed
        } else if let stored = APIKeyStore.loadAPIKey(forAccount: server.tokenAccount) {
            resolvedToken = stored
        } else {
            return
        }

        await establishConnection(server: server, endpoint: endpoint, token: resolvedToken)
        if token != nil, isConnected(server.id) {
            try? APIKeyStore.saveAPIKey(resolvedToken, forAccount: server.tokenAccount)
        }
    }

    /// Signs in via the MCP spec's OAuth flow (see `MCPOAuth`).
    /// `interactive: true` opens the system browser for a real sign-in
    /// when no valid/refreshable token exists yet (only ever appropriate
    /// in direct response to the user clicking "Sign in" in Settings);
    /// `interactive: false` — used at launch — only attempts a *silent*
    /// token refresh and otherwise leaves the row disconnected rather
    /// than popping a browser window unprompted. `manualClientId` is only
    /// consulted for a server that (per live discovery) doesn't support
    /// Dynamic Client Registration — see `.needsManualClientId`.
    func connectOAuth(server: MCPServerDefinition, interactive: Bool, manualClientId: String? = nil) async {
        guard let endpoint = server.endpoint else { return }
        connections[server.id, default: Connection()].state = .connecting

        do {
            let metadata = try await MCPOAuth.discover(mcpEndpoint: endpoint)
            var credentials = MCPOAuthCredentialStore.loadClientCredentials(forAccount: server.tokenAccount)
            let storedTokens = MCPOAuthCredentialStore.loadTokens(forAccount: server.tokenAccount)

            // A still-valid access token: use it as-is (60s safety margin
            // before its real expiry).
            if let storedTokens, credentials != nil,
               (storedTokens.expiresAt.map { $0 > Date().addingTimeInterval(60) } ?? true) {
                await establishConnection(server: server, endpoint: endpoint, token: storedTokens.accessToken)
                return
            }

            // Expired but refreshable — silent either way, no browser needed.
            if let storedTokens, let refreshToken = storedTokens.refreshToken, let credentials {
                let refreshed = try await MCPOAuth.refresh(metadata: metadata, clientId: credentials.clientId, refreshToken: refreshToken)
                MCPOAuthCredentialStore.saveTokens(refreshed, forAccount: server.tokenAccount)
                await establishConnection(server: server, endpoint: endpoint, token: refreshed.accessToken)
                return
            }

            // Nothing usable — only proceed to a real sign-in when asked.
            guard interactive else {
                connections[server.id] = nil
                return
            }

            // DCR happens once per server and is cached forever after —
            // re-registering on every sign-in would leave orphaned client
            // registrations on the server for no benefit.
            if credentials == nil {
                if metadata.registrationEndpoint != nil {
                    credentials = try await MCPOAuth.register(metadata: metadata, redirectURI: MCPOAuth.redirectURI)
                } else if let manualClientId {
                    let trimmed = manualClientId.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        connections[server.id] = Connection(state: .needsManualClientId, tools: [], client: nil)
                        return
                    }
                    credentials = MCPOAuth.ClientCredentials(clientId: trimmed, clientSecret: nil)
                } else {
                    // No DCR and nothing supplied — a real fork in the
                    // flow, not a failure, so the UI can offer the field
                    // rather than just report an error.
                    connections[server.id] = Connection(state: .needsManualClientId, tools: [], client: nil)
                    return
                }
            }
            guard let clientId = credentials?.clientId else {
                throw MCPOAuth.OAuthError.registrationFailed("no client id was returned.")
            }

            let pkce = MCPOAuth.generatePKCE()
            let state = MCPOAuth.generateState()
            let authURL = MCPOAuth.authorizationURL(metadata: metadata, clientId: clientId, redirectURI: MCPOAuth.redirectURI, pkce: pkce, state: state)

            // `awaitRedirect` races its own listener against an internal
            // timeout, so a user who never completes sign-in doesn't
            // leave this stuck in "Connecting…" forever.
            NSWorkspace.shared.open(authURL)
            let code = try await MCPOAuth.awaitRedirect(expectedState: state)
            let newTokens = try await MCPOAuth.exchangeCode(metadata: metadata, clientId: clientId, code: code, pkce: pkce, redirectURI: MCPOAuth.redirectURI)

            MCPOAuthCredentialStore.save(credentials: credentials!, tokens: newTokens, forAccount: server.tokenAccount)
            await establishConnection(server: server, endpoint: endpoint, token: newTokens.accessToken)
        } catch {
            connections[server.id] = Connection(state: .failed(Self.userMessage(for: error)), tools: [], client: nil)
        }
    }

    /// The part identical regardless of how the token was obtained:
    /// build an `MCPClient`, complete the MCP handshake, list tools, and
    /// record the resulting state.
    private func establishConnection(server: MCPServerDefinition, endpoint: URL, token: String) async {
        connections[server.id, default: Connection()].state = .connecting
        let client = MCPClient(endpoint: endpoint, token: token, authScheme: server.authMode == .oauth ? "Bearer" : server.authScheme, extraHeaders: server.extraHeaders)
        do {
            try await client.connect()
            let fetchedTools = try await client.listTools()
            connections[server.id] = Connection(state: .connected, tools: fetchedTools, client: client)
        } catch {
            connections[server.id] = Connection(state: .failed(Self.userMessage(for: error)), tools: [], client: nil)
        }
    }

    func disconnect(_ server: MCPServerDefinition) {
        connections[server.id] = nil
        switch server.authMode {
        case .pastedToken:
            APIKeyStore.deleteAPIKey(forAccount: server.tokenAccount)
        case .oauth:
            MCPOAuthCredentialStore.delete(forAccount: server.tokenAccount)
        }
    }

    func callTool(server serverId: String, name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        guard let client = connections[serverId]?.client else { throw MCPError.notConnected }
        return try await client.callTool(name: name, arguments: arguments)
    }

    func tool(server serverId: String, named name: String) -> MCPTool? {
        tools(for: serverId).first { $0.name == name }
    }

    /// A self-contained system-prompt block teaching the `eaon:mcp` markup
    /// and listing every connected service's live tool catalog — nil when
    /// nothing is connected. Self-contained because nothing else in the
    /// app currently sends a baseline agent-instruction prompt (chat
    /// requests only ever include the user's own Custom Instructions +
    /// Memory facts — see `ChatViewModel.systemPromptHistory`), so this
    /// has to teach the whole convention on its own, not just describe
    /// what's newly available.
    var agentInstructionBlock: String? {
        let servers = connectedServers.filter { !tools(for: $0.id).isEmpty }
        guard !servers.isEmpty else { return nil }

        let sections = Self.fairlyBudgetedSections(for: servers, toolsByServer: Dictionary(uniqueKeysWithValues: servers.map { ($0.id, tools(for: $0.id)) }))
        let names = servers.map(\.displayName).joined(separator: ", ")

        // One fully-worked example from a REAL connected tool (preferring
        // one with required parameters, so the example shows actual
        // argument names) — models imitate a concrete example far more
        // reliably than they follow the abstract syntax description, and
        // smaller models often only get the call right when they've seen
        // one real invocation.
        var example = ""
        if let firstServer = servers.first {
            let serverTools = tools(for: firstServer.id)
            if let exampleTool = serverTools.first(where: { !$0.requiredParameterNames.isEmpty }) ?? serverTools.first {
                example = """


                For example, this is a complete, correctly-formed call of \(exampleTool.name) on \(firstServer.displayName):

                ```eaon:mcp server="\(firstServer.id)" tool="\(exampleTool.name)"
                \(exampleTool.exampleArgumentsJSON)
                ```
                """
            }
        }

        return """
        You can act on the user's connected services through tools. The connected services are exactly: \(names). No other outside service is connected. To call a tool, use a fenced block naming both the service and the tool:

        ```eaon:mcp server="<server id>" tool="<tool name>"
        {"key": "value"}
        ```

        The block body must be valid JSON with the tool's arguments, using exactly the parameter names listed for that tool below (or an empty {} for a tool with no parameters). Always close the fence with ``` on its own line. After your reply, any eaon:mcp calls execute and their results come back to you in a message beginning "[Tool results". You then continue — this loops until you reply with no tool calls. If a call fails, the error tells you the tool's exact parameters — fix the call and try again. Once the results answer the user's question, ALWAYS finish with a plain-language reply telling the user what you found — never end the conversation on a tool call or raw results. Only call a tool when the user's request genuinely needs it: these are real accounts and not sandboxed (they can create records, send messages, deploy changes, spend money), so never call one speculatively or "just to check."\(example)

        Connected services and their tools (parameters in parentheses; values shown in quotes are the only accepted values):
        \(Self.hardCapped(sections.joined(separator: "\n\n")))
        """
    }

    /// The water-filling allocation in `fairlyBudgetedSections` is the
    /// real, smart mechanism — but it accounts in *shares*, not the exact
    /// bytes a section ends up costing (a truncated section's header line
    /// and "Also available: …" overflow listing are both added after its
    /// per-tool budget check, so they're real cost the share accounting
    /// doesn't see). That underccounting is bounded per server, but with
    /// enough connected servers it still adds up. This is the actual hard
    /// guarantee — cut at the character level with a note, which is safe
    /// specifically because it's the last resort, not the primary
    /// mechanism: everything above already tried to degrade gracefully
    /// per server first.
    private static let truncationNote = "\n…(tool list truncated for length — ask what else is available if you need a tool not listed here)"

    private static func hardCapped(_ text: String) -> String {
        guard text.count > maxCatalogCharacters else { return text }
        // The note itself has to fit inside the cap, not get tacked on
        // after it — appending it unconditionally past an already-full
        // prefix is exactly the kind of "the truncation marker exceeds
        // the limit it's marking" bug this function exists to rule out
        // everywhere else in this file.
        let budgetForText = max(0, maxCatalogCharacters - truncationNote.count)
        return String(text.prefix(budgetForText)) + truncationNote
    }

    /// Splits the shared `maxCatalogCharacters` pool fairly across
    /// connected servers via water-filling: each server's *full,
    /// untruncated* section is computed once; sorted smallest-need-first,
    /// each server gets either its full section (if it fits an equal
    /// share of whatever budget remains among servers not yet settled)
    /// or exactly that share. A small server (Cloudflare's 2 tools) never
    /// gets truncated just because a big one (GitHub's dozen-plus) is
    /// connected alongside it — settling small servers first means the
    /// budget they *don't* need rolls over to whichever server does.
    ///
    /// This replaced `max(1500, total / count)` — a fixed floor that
    /// guaranteed each server at least 1500 characters regardless of how
    /// many were connected, which is fine for 2–3 servers but silently
    /// defeats the "6000 total" guarantee for anyone with more: 5
    /// connected servers floored at 1500 each is 7,500 total, 25% over;
    /// 6 is 9,000, 50% over. The whole point of a hard cap is that it's
    /// actually hard — a floor that scales past it on the very trajectory
    /// this app's own Plugins page encourages (connect more services) was
    /// the direct cause of prompts silently growing past what a request
    /// could carry, surfacing as a fully successful connection (Settings
    /// showing green) paired with the model going completely silent.
    private static func fairlyBudgetedSections(for servers: [MCPServerDefinition], toolsByServer: [String: [MCPTool]]) -> [String] {
        let full = servers.map { server in
            (server: server, tools: toolsByServer[server.id] ?? [], fullText: section(for: server, tools: toolsByServer[server.id] ?? [], budget: .max))
        }

        var remainingBudget = maxCatalogCharacters
        var remainingCount = full.count
        var settled: [String: String] = [:]
        for entry in full.sorted(by: { $0.fullText.count < $1.fullText.count }) {
            let fairShare = remainingBudget / max(1, remainingCount)
            let text = entry.fullText.count <= fairShare
                ? entry.fullText
                : section(for: entry.server, tools: entry.tools, budget: fairShare)
            settled[entry.server.id] = text
            // The actual produced length, not the assumed share — a
            // truncated section's header and "Also available: …" line are
            // real cost added after the per-tool budget check, so they'd
            // otherwise go uncounted here and let later servers over-spend.
            remainingBudget -= text.count
            remainingCount -= 1
        }
        return servers.compactMap { settled[$0.id] }
    }

    /// One server's catalog section, kept within `budget` by listing
    /// overflow tools name-only instead of dropping them: a tool whose
    /// description didn't fit is still callable, and the model still
    /// knows it exists — only the one-line description is sacrificed.
    private static func section(for server: MCPServerDefinition, tools serverTools: [MCPTool], budget: Int) -> String {
        var lines: [String] = []
        var used = 0
        var nameOnly: [String] = []
        for tool in serverTools {
            let line = "  - \(tool.name)\(parameterSummary(tool)): \(boundedDescription(tool.description))"
            if used + line.count <= budget {
                lines.append(line)
                used += line.count
            } else {
                nameOnly.append(tool.name)
            }
        }
        if !nameOnly.isEmpty {
            lines.append("  - Also available on this service (same call syntax, descriptions omitted for length): \(nameOnly.joined(separator: ", "))")
        }
        return "\(server.displayName) (server=\"\(server.id)\"):\n\(lines.joined(separator: "\n"))"
    }

    /// A compact `(name: type, name: type (required))` rendering of a
    /// tool's JSON Schema — not the full schema (some run well past a
    /// hundred lines, and that cost would land on every request while
    /// anything is connected, even turns that never call a tool). Enough
    /// for the model to build correct arguments without either the token
    /// cost or the request-shape risk of forwarding raw schema JSON.
    private static func parameterSummary(_ tool: MCPTool) -> String {
        // MCPTool.parameters already orders required first — when the
        // list overflows the cap below, it's the optional ones that fall
        // off, never a parameter the call can't succeed without.
        let params = tool.parameters
        guard !params.isEmpty else { return "()" }
        var parts = params.prefix(Self.maxSummarizedParameters).map { p -> String in
            // An enum's actual accepted values replace the bare type —
            // "sort: \"stars\"|\"forks\"" prevents the invented-value
            // failures that "sort: string" invites.
            let shownType: String
            if p.enumValues.isEmpty {
                shownType = p.type
            } else {
                let shown = p.enumValues.prefix(4).map { "\"\($0)\"" }.joined(separator: "|")
                shownType = p.enumValues.count > 4 ? shown + "|…" : shown
            }
            return p.isRequired ? "\(p.name): \(shownType) (required)" : "\(p.name): \(shownType)"
        }
        if params.count > Self.maxSummarizedParameters {
            parts.append("+\(params.count - Self.maxSummarizedParameters) more optional")
        }
        return "(" + parts.joined(separator: ", ") + ")"
    }

    /// A few REST-shaped tools take dozens of optional parameters; past
    /// this many, one tool's signature would eat a meaningful slice of
    /// its whole server's catalog budget for parameters almost never
    /// used.
    private static let maxSummarizedParameters = 10

    /// Some servers ship far more than one clean sentence per tool — e.g.
    /// Cloudflare's `execute()` proxies ~2,500 REST endpoints through one
    /// tool, which invites a genuinely long description explaining how to
    /// use it. A single such tool could otherwise dominate the whole
    /// system prompt. One line, hard-capped, is enough for the model to
    /// know what a tool is for; the tool's own JSON Schema (already
    /// summarized above) is what actually disambiguates arguments.
    private static let maxDescriptionCharacters = 220
    private static func boundedDescription(_ description: String?) -> String {
        let text = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return "No description provided." }
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        guard singleLine.count > maxDescriptionCharacters else { return singleLine }
        return String(singleLine.prefix(maxDescriptionCharacters)) + "…"
    }

    /// The shared pool the per-server budgets divide up (see
    /// `agentInstructionBlock`). A hard backstop so the catalog can never
    /// balloon large enough to crowd out a local model's small context
    /// window — which caused replies to go completely empty (no error,
    /// just nothing) when verbose toolsets were connected. Overflow
    /// degrades to name-only tool listings per server, never to whole
    /// servers silently vanishing.
    private static let maxCatalogCharacters = 6000

    private static func userMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Couldn't connect — \(error.localizedDescription)"
    }
}
