import Foundation

/// Global "Always Allow" switch for code execution and MCP tool calls — see
/// `ChatViewModel.confirmRunIfNeeded(path:)` and
/// `confirmMCPCallIfNeeded(server:tool:argumentsJSON:)`, both of which
/// short-circuit to an immediate approval when this is on, skipping their
/// dialog entirely. Defaults to true: a model that stops mid-turn to ask
/// permission for every tool call is exactly the friction this app spent
/// real effort removing elsewhere (turn merging, the activity indicator).
///
/// Deliberately does NOT cover Desktop Control — that gate stays untouched
/// regardless of this setting. Desktop Control can move the mouse and type
/// on this Mac; code execution and MCP calls are still meaningful risk (a
/// pushed commit, a sent email, a charge) but sit one notch below "types on
/// your behalf while you're not looking," so they got the friction-removal
/// this setting provides and Desktop Control didn't.
@MainActor
@Observable
final class AlwaysAllowStore {
    static let shared = AlwaysAllowStore()

    private static let enabledKey = "eaon_always_allow_tool_calls"

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        }
    }

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Self.enabledKey)
    }
}
