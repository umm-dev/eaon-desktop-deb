import SwiftUI

struct AssistantMessageContentView: View {
    let text: String
    let isTyping: Bool
    /// Called with a file path when the user clicks a workspace file card —
    /// nil (the default) leaves plain code-block rendering untouched for any
    /// caller that isn't wired into the workspace panel.
    var onOpenWorkspaceFile: ((String) -> Void)? = nil
    /// Real status text for a local model still loading — nil shows the
    /// plain pulsing dot exactly as before.
    var loadingStatusText: String? = nil

    private var extracted: ReasoningExtractor.Result {
        ReasoningExtractor.extract(from: text)
    }

    private var blocks: [MessageBlock] {
        MessageContentParser.parse(extracted.visibleContent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let reasoning = extracted.reasoning {
                ThinkingDisclosure(reasoning: reasoning, isInProgress: extracted.isReasoningInProgress)
            }

            if blocks.isEmpty {
                // The reasoning disclosure above already communicates "still
                // working" while a <think> block is open or just closed —
                // showing the plain pulsing dot too would say the same thing
                // twice.
                if isTyping, extracted.reasoning == nil {
                    ThinkingIndicator(statusText: loadingStatusText ?? "Thinking…")
                }
            } else {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    blockView(block, index: index)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(nil, value: text)
    }

    @ViewBuilder
    private func blockView(_ block: MessageBlock, index: Int) -> some View {
        let isLast = index == blocks.count - 1
        let showCursor = isTyping && isLast

        switch block {
        case .text(let content):
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MarkdownBlockView(text: content)
            } else if showCursor {
                ThinkingIndicator(statusText: "Thinking…")
            }

        case .code(let language, let code):
            // eaon:* fences are agent tool requests (run/edit/read/ls/mcp) —
            // a small action chip; a fence carrying a file attribute is a
            // workspace file — a compact card (the code itself lives in the
            // workspace panel, the way Cursor/Lovable summarize in chat).
            let fence = WorkspaceParser.fenceInfo(from: language)
            // aqua: is the legacy prefix — old conversations are full of
            // it, and their chips must keep rendering as chips.
            if let fenceLanguage = fence.language,
               fenceLanguage.hasPrefix("eaon:") || fenceLanguage.hasPrefix("aqua:"),
               fenceLanguage != "eaon:write", fenceLanguage != "aqua:write" {
                ToolActionChip(
                    kindToken: fenceLanguage,
                    path: fence.path,
                    toolName: fence.tool,
                    serverId: fence.server,
                    // Only "search" carries anything meaningful in the fence
                    // BODY (the {"query": "..."} JSON) rather than an
                    // attribute — passed through just for that one kind so
                    // e.g. a large eaon:edit body never rides along here.
                    bodyText: fenceLanguage == "eaon:search" ? code : nil,
                    isStreaming: showCursor
                )
            } else if let path = fence.path {
                WorkspaceFileCard(path: path, code: code, isStreaming: showCursor) {
                    onOpenWorkspaceFile?(path)
                }
            } else {
                CodeBlockView(
                    language: language,
                    code: code,
                    showTypingCursor: showCursor
                )
            }
        }
    }
}

/// Inline chip for an agent tool request (run/edit/read/ls). The request is
/// summarized here; its outcome arrives in the following results card and
/// streams into the workspace console.
struct ToolActionChip: View {
    @Environment(\.themeColors) private var colors
    let kindToken: String
    let path: String?
    /// The `tool="..."` attribute — only meaningful for the "mcp" kind.
    var toolName: String? = nil
    /// The `server="..."` attribute — only meaningful for the "mcp" kind.
    /// Drives the real service badge/name shown in place of the generic
    /// icon, now that more than one service can be connected at once.
    var serverId: String? = nil
    /// The fence body — only populated (by the caller) for "search", whose
    /// query lives in its JSON body rather than an attribute. Parsed
    /// leniently since it can be a partial, still-streaming JSON fragment.
    var bodyText: String? = nil
    var isStreaming: Bool = false

    private var kind: String { String(kindToken.dropFirst("eaon:".count)) }
    private var server: MCPServerDefinition? { serverId.flatMap(MCPCatalog.definition(for:)) }

    private var searchQuery: String? {
        guard let bodyText, let data = bodyText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = object["query"] as? String, !query.isEmpty else { return nil }
        return query
    }

    private var icon: String {
        switch kind {
        case "run": return "play.fill"
        case "edit": return "pencil"
        case "read": return "eye"
        case "mcp": return "bolt.horizontal.circle"
        case "search": return "magnifyingglass"
        default: return "list.bullet"
        }
    }

    private var label: String {
        switch kind {
        case "run": return "Run \(path ?? "")"
        case "edit": return "Edit \(path ?? "")"
        case "read": return "Read \(path ?? "")"
        case "ls", "list": return "List files"
        case "mcp":
            let toolText = toolName ?? "tool"
            return server.map { "\($0.displayName) · \(toolText)" } ?? "Call \(toolText)"
        case "search": return "Search: \(searchQuery ?? "…")"
        default: return kindToken
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if kind == "mcp", let server, let image = BrandLogoLoader.image(named: server.logoAssetName) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(colors.backgroundChipSecondary)
                    )
            } else {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(colors.backgroundChipSecondary)
                    )
            }
            Text(label.trimmingCharacters(in: .whitespaces))
                .font(AppFont.mono(12, weight: .medium))
                .foregroundStyle(colors.textPrimary)
                .lineLimit(1)
            if isStreaming {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(colors.backgroundChip)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(colors.borderSubtle, lineWidth: 1)
        )
    }
}

/// Chat-side stand-in for a file the model created: filename, live line
/// count, and a click-through into the workspace panel's editor.
struct WorkspaceFileCard: View {
    @Environment(\.themeColors) private var colors
    let path: String
    let code: String
    var isStreaming: Bool = false
    var onOpen: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: WorkspaceFileIcon.systemName(forPath: path))
                    .font(.system(size: 13))
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(colors.backgroundChipSecondary)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(path)
                        .font(AppFont.mono(12.5, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(AppFont.mono(11))
                        .foregroundStyle(colors.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                if isStreaming {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(colors.textTertiary)
                }
            }
            .padding(10)
            .frame(maxWidth: 420, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? colors.backgroundHover : colors.backgroundChip)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(colors.borderSubtle, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open in workspace")
    }

    private var subtitle: String {
        let lines = code.isEmpty ? 0 : code.components(separatedBy: "\n").count
        return isStreaming
            ? "Writing… \(lines) line\(lines == 1 ? "" : "s")"
            : "\(lines) line\(lines == 1 ? "" : "s") · Open in workspace"
    }
}

/// A soft pulsing dot shown while the assistant is preparing its first
/// tokens — optionally paired with real status text (e.g. a local model
/// still loading into memory) rather than leaving that wait unexplained.
struct ThinkingIndicator: View {
    @Environment(\.themeColors) private var colors
    @State private var pulse = false
    var statusText: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(colors.textPrimary)
                .frame(width: 9, height: 9)
                .opacity(pulse ? 0.25 : 0.9)
                .scaleEffect(pulse ? 0.85 : 1.0)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)

            if let statusText {
                WaveText(text: statusText, font: AppFont.mono(13), color: colors.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .onAppear { pulse = true }
    }
}

/// Each letter bobs up and down in a small rolling wave, staggered so
/// neighboring letters are out of phase — a Stagger of a Float, in
/// animation-vocabulary terms; there's no single named term for the
/// combination. This is one of the few places continuous motion is
/// actually the point rather than something to restrain: it exists to
/// keep saying "still working" for as long as it's on screen, so unlike
/// a button press or a dropdown, looping indefinitely is correct here.
/// Amplitude and speed stay deliberately small regardless, since this
/// runs constantly, every generation, all day — the more often
/// something is seen, the subtler it should be.
private struct WaveText: View {
    let text: String
    let font: Font
    let color: Color
    @State private var animate = false

    /// Emil's "strong ease-in-out" cubic-bezier (0.77, 0, 0.175, 1) rather
    /// than the built-in easeInOut, which reads flat next to a curve with
    /// real acceleration at both ends.
    private var waveCurve: Animation {
        .timingCurve(0.77, 0, 0.175, 1, duration: 0.7)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(font)
                    .foregroundStyle(color)
                    .offset(y: animate ? -2 : 1.5)
                    .animation(
                        waveCurve.repeatForever(autoreverses: true).delay(Double(index) * 0.045),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

/// Splits a raw streamed message on its first `<think>…</think>` block —
/// the chain-of-thought a reasoning model (DeepSeek-R1, QwQ, and other
/// local reasoning models served through Ollama) emits inline ahead of its
/// real answer. Left alone, that block would render as literal `<think>`
/// text in the middle of the reply; extracting it here lets
/// `ThinkingDisclosure` show it behind a click instead. Streaming-side
/// providers that send reasoning as its own `reasoning_content`/`reasoning`
/// field (DeepSeek's own API) get wrapped in the same tag by
/// `ReasoningDeltaBridge` before the text ever reaches here, so this one
/// routine covers both real shapes.
enum ReasoningExtractor {
    struct Result {
        let reasoning: String?
        let visibleContent: String
        /// True while `<think>` has opened but `</think>` hasn't arrived
        /// yet — the model is still reasoning, not the final answer.
        let isReasoningInProgress: Bool
    }

    static func extract(from raw: String) -> Result {
        guard let openRange = raw.range(of: "<think>") else {
            return Result(reasoning: nil, visibleContent: raw, isReasoningInProgress: false)
        }

        let before = String(raw[raw.startIndex..<openRange.lowerBound])
        let afterOpen = raw[openRange.upperBound...]

        if let closeRange = afterOpen.range(of: "</think>") {
            let reasoning = String(afterOpen[afterOpen.startIndex..<closeRange.lowerBound])
            let after = String(afterOpen[closeRange.upperBound...])
            // Straight concatenation would squish "before" and "after"
            // together with no separator on the rare model that emits real
            // content on both sides of the block with no whitespace of its
            // own around the tags.
            let trimmedBefore = before.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedAfter = after.trimmingCharacters(in: .whitespacesAndNewlines)
            let visible = [trimmedBefore, trimmedAfter].filter { !$0.isEmpty }.joined(separator: "\n\n")
            return Result(
                reasoning: reasoning.trimmingCharacters(in: .whitespacesAndNewlines),
                visibleContent: visible,
                isReasoningInProgress: false
            )
        }

        return Result(
            reasoning: String(afterOpen).trimmingCharacters(in: .whitespacesAndNewlines),
            visibleContent: before.trimmingCharacters(in: .whitespacesAndNewlines),
            isReasoningInProgress: true
        )
    }
}

/// A model's reasoning trace, collapsed behind a click by default — the
/// reasoning is background work on the way to the real answer, not the
/// message itself, and is often long enough that showing it inline
/// unconditionally would bury the answer under it. Click the row to open
/// it; it stays open once you do, even after the model finishes.
struct ThinkingDisclosure: View {
    @Environment(\.themeColors) private var colors
    let reasoning: String
    let isInProgress: Bool
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(colors.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeOut(duration: 0.16), value: isExpanded)

                    if isInProgress {
                        WaveText(text: "Thinking…", font: AppFont.mono(13), color: colors.textSecondary)
                    } else {
                        Text("Thinking")
                            .font(AppFont.mono(13))
                            .foregroundStyle(colors.textSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(reasoning)
                    .font(AppFont.mono(12))
                    .foregroundStyle(colors.textTertiary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 10)
                    .padding(.vertical, 8)
                    .padding(.trailing, 4)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(colors.borderSubtle)
                            .frame(width: 2)
                    }
                    .padding(.top, 8)
                    .padding(.leading, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
    }
}
