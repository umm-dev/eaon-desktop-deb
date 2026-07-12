import Foundation

/// Wraps `reasoning_content`/`reasoning` SSE delta fields — the shape
/// DeepSeek's own API (and a few other hosted-reasoning-model providers)
/// send reasoning in, as a field separate from `content` — in the same
/// `<think>…</think>` markers Ollama's OpenAI-compatible endpoint emits
/// inline, verified live, for local reasoning models (DeepSeek-R1, QwQ).
/// One instance per streaming call. Feeding everything through the same
/// markers means `ReasoningExtractor` (see `AssistantMessageContentView`)
/// is the one place that has to know what a "thinking" block looks like,
/// regardless of which of these two real shapes a given provider sent.
final class ReasoningDeltaBridge {
    private var isOpen = false

    /// Call once per delta. Returns the text to append to the stream, or
    /// nil when this delta carried neither field.
    func text(reasoning: String?, content: String?) -> String? {
        var out = ""
        if let reasoning, !reasoning.isEmpty {
            if !isOpen { out += "<think>"; isOpen = true }
            out += reasoning
        }
        if let content, !content.isEmpty {
            if isOpen { out += "</think>"; isOpen = false }
            out += content
        }
        return out.isEmpty ? nil : out
    }

    /// A response that gets cut off mid-thought must not leave a dangling,
    /// never-closed tag behind — call once after the stream ends.
    func closeIfNeeded() -> String? {
        guard isOpen else { return nil }
        isOpen = false
        return "</think>"
    }
}
