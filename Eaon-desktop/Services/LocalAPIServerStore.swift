import Foundation

/// Settings for Eaon's own local API server — see `LocalAPIServer` for the
/// actual listener. Off by default: unlike `AlwaysAllowStore`, turning this
/// on opens a real listening network port, so it gets the same "off by
/// default, full disclosure" treatment as Computer Control rather than the
/// always-on-by-default treatment given to pure friction-removal settings.
@MainActor
@Observable
final class LocalAPIServerStore {
    static let shared = LocalAPIServerStore()

    private static let enabledKey = "eaon_local_api_server_enabled"
    private static let portKey = "eaon_local_api_server_port"
    private static let requireAPIKeyKey = "eaon_local_api_server_require_key"
    private static let apiKeyKey = "eaon_local_api_server_key"

    /// Starts/stops the real listener as a side effect — see
    /// `LocalAPIServer.applySettings()`. This is the one property in this
    /// store that isn't just a passive preference.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            LocalAPIServer.shared.applySettings()
        }
    }

    /// 1234 — matches LM Studio's own default local-server port, so a
    /// script or tool already configured to look there for a local
    /// OpenAI-compatible server finds Eaon without any extra setup.
    var port: Int {
        didSet {
            guard port != oldValue else { return }
            UserDefaults.standard.set(port, forKey: Self.portKey)
            LocalAPIServer.shared.applySettings()
        }
    }

    /// Whether callers must send `Authorization: Bearer <apiKey>`. On by
    /// default — the listener only ever binds to the loopback interface
    /// (never reachable from the network), but any other process running
    /// as this same user could otherwise reach it silently.
    var requireAPIKey: Bool {
        didSet {
            guard requireAPIKey != oldValue else { return }
            UserDefaults.standard.set(requireAPIKey, forKey: Self.requireAPIKeyKey)
        }
    }

    var apiKey: String {
        didSet {
            guard apiKey != oldValue else { return }
            UserDefaults.standard.set(apiKey, forKey: Self.apiKeyKey)
        }
    }

    var baseURL: String {
        "http://127.0.0.1:\(port)/v1"
    }

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let storedPort = UserDefaults.standard.integer(forKey: Self.portKey)
        port = storedPort == 0 ? 1234 : storedPort
        requireAPIKey = UserDefaults.standard.object(forKey: Self.requireAPIKeyKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Self.requireAPIKeyKey)
        if let existingKey = UserDefaults.standard.string(forKey: Self.apiKeyKey), !existingKey.isEmpty {
            apiKey = existingKey
        } else {
            apiKey = Self.generateKey()
            UserDefaults.standard.set(apiKey, forKey: Self.apiKeyKey)
        }
    }

    func regenerateAPIKey() {
        apiKey = Self.generateKey()
    }

    private static func generateKey() -> String {
        "eaon-local-" + (0..<24).map { _ in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! }.reduce(into: "") { $0.append($1) }
    }
}
