import Foundation

/// One turn in a request's message history sent to any provider. `images`
/// is empty for every system/tool-result/memory turn and any user turn
/// without an attachment the active model can actually see — only when
/// it's non-empty does a completion path build a real multi-part vision
/// payload instead of plain text.
struct HistoryTurn {
    let role: String
    let content: String
    var images: [HistoryImage]

    init(role: String, content: String, images: [HistoryImage] = []) {
        self.role = role
        self.content = content
        self.images = images
    }
}

struct HistoryImage: Equatable {
    let base64: String
    let mimeType: String
}

extension HistoryTurn {
    /// OpenAI-compatible `{role, content}` shape — content is a plain
    /// string when there's no image, or a content-parts array when there
    /// is. Every OpenAI-compatible endpoint (including Aqua's own) accepts
    /// either shape.
    var openAICompatibleJSON: [String: Any] {
        guard !images.isEmpty else { return ["role": role, "content": content] }
        var parts: [[String: Any]] = []
        if !content.isEmpty {
            parts.append(["type": "text", "text": content])
        }
        for image in images {
            parts.append(["type": "image_url", "image_url": ["url": "data:\(image.mimeType);base64,\(image.base64)"]])
        }
        return ["role": role, "content": parts]
    }
}
