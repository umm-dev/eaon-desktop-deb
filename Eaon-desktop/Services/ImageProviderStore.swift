import Foundation

/// Which wire shape an image-generation connection speaks. Unlike chat's
/// three formats, image generation only really has two real shapes in the
/// wild — no separate `googleGemini`/`anthropicMessages` equivalent exists
/// here (neither speaks image generation the same way).
enum ImageWireFormat: String, Codable, CaseIterable, Identifiable {
    case openAICompatible
    case automatic1111

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible: return "Cloud API (OpenAI-style)"
        case .automatic1111: return "Local Server"
        }
    }

    var helpText: String {
        switch self {
        case .openAICompatible:
            return "A real cloud image API — OpenAI's DALL-E/gpt-image, or another provider speaking the same /images/generations shape."
        case .automatic1111:
            return "A Stable Diffusion server already running on this Mac — Automatic1111's WebUI, DrawThings (with its API server turned on), or ComfyUI in Automatic1111-compatible mode. Point this at its address, usually http://127.0.0.1:7860."
        }
    }
}

/// One user-configured image-generation connection — a cloud key (BYOK) or
/// a local Stable Diffusion server. Deliberately its own small store rather
/// than folded into `CustomProviderConfig`: image generation is a single
/// request/response with no streaming, no conversation history, and no
/// tool-calling, so it doesn't need any of the machinery that config and
/// its surrounding chat pipeline carry.
struct ImageProviderConfig: Identifiable, Codable, Equatable {
    var id = UUID()
    var displayName: String
    var baseURL: String
    var format: ImageWireFormat
    /// For `.openAICompatible`, real model ids the connection can generate
    /// with (e.g. "dall-e-3"). For `.automatic1111`, there's no per-request
    /// model — whatever's loaded in the local tool is what runs — so this
    /// is just a label the user picks for their one local model, purely so
    /// it has a selectable entry in the model picker.
    var modelIDs: [String]
    var createdAt = Date()

    var trimmedModelIDs: [String] {
        modelIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

extension ImageProviderConfig {
    func generate(model: String, prompt: String, apiKey: String?) async throws -> GeneratedImageResult {
        switch format {
        case .openAICompatible:
            return try await OpenAICompatibleImageFormat.generate(baseURL: baseURL, model: model, prompt: prompt, apiKey: apiKey)
        case .automatic1111:
            return try await Automatic1111ImageFormat.generate(baseURL: baseURL, prompt: prompt)
        }
    }
}

/// Mirrors `CustomProviderStore`'s exact shape (save/remove/apiKey/
/// config(owning:)) — same established pattern, same UserDefaults +
/// per-connection Keychain-account API key storage, just for image
/// connections instead of chat ones.
@MainActor
@Observable
final class ImageProviderStore {
    static let shared = ImageProviderStore()

    private let storageKey = "eaon_image_providers"
    private(set) var configs: [ImageProviderConfig] = []

    private init() {
        load()
    }

    var sortedConfigs: [ImageProviderConfig] {
        configs.sorted { $0.createdAt < $1.createdAt }
    }

    func config(owning modelId: String) -> ImageProviderConfig? {
        configs.first { $0.trimmedModelIDs.contains(modelId) }
    }

    /// Mirrors `CustomProviderStore.syntheticModels` — every configured
    /// connection's model ids, shaped like `APIModel` so they merge into
    /// the same picker/routing machinery the rest of the app already uses.
    var syntheticModels: [APIModel] {
        configs.flatMap { config in
            config.trimmedModelIDs.map { modelId in
                APIModel(id: modelId, name: nil, type: "image", tier: nil)
            }
        }
    }

    func apiKey(for configId: UUID) -> String? {
        APIKeyStore.loadAPIKey(forAccount: keychainAccount(for: configId))
    }

    func save(_ config: ImageProviderConfig, apiKey: String) throws {
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
        } else {
            configs.append(config)
        }
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            try APIKeyStore.saveAPIKey(trimmedKey, forAccount: keychainAccount(for: config.id))
        }
        persist()
    }

    func remove(_ id: UUID) {
        configs.removeAll { $0.id == id }
        APIKeyStore.deleteAPIKey(forAccount: keychainAccount(for: id))
        persist()
    }

    private func keychainAccount(for id: UUID) -> String {
        "image-provider-\(id.uuidString)"
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ImageProviderConfig].self, from: data) else { return }
        configs = decoded
    }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
