import AppKit
import SwiftUI

/// Lets models read and act in outside services on the user's behalf, via
/// MCP (Model Context Protocol) servers reached over the internet. Distinct
/// from the local coding agent's file tools: nothing here is sandboxed, so
/// a connection is opt-in per service (this page) and every individual
/// tool call still asks first (see `MCPCallConfirmationDialog`).
///
/// Only ever shows `MCPCatalog.available` — every row here genuinely
/// works. Services that turned out to be blocked (vendor-side, not a gap
/// in this app) were removed rather than kept as a permanently-disabled
/// "Coming soon" row; a tag that never resolves is just clutter.
struct PluginsSettingsView: View {
    @Environment(\.themeColors) private var colors
    @State private var expandedIds: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Plugins")
                .font(AppFont.mono(20, weight: .bold))
                .foregroundColor(colors.textPrimary)
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 4)

            Text("Connect outside services so models can read and act on your behalf, with your consent.")
                .font(AppFont.sans(12))
                .foregroundColor(colors.textSecondary)
                .padding(.horizontal, 32)
                .padding(.bottom, 20)

            ScrollView {
                SettingsCard {
                    VStack(spacing: 0) {
                        ForEach(Array(MCPCatalog.available.enumerated()), id: \.element.id) { index, server in
                            if index > 0 {
                                Divider().overlay(colors.borderSubtle)
                            }
                            PluginRow(
                                server: server,
                                isExpanded: expandedIds.contains(server.id),
                                onToggle: { toggle(server.id) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors.backgroundPrimary)
    }

    private func toggle(_ id: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            if expandedIds.contains(id) {
                expandedIds.remove(id)
            } else {
                expandedIds.insert(id)
            }
        }
    }
}

/// One service's row — a header (badge, name, summary, status, chevron)
/// that expands into its connect UI.
private struct PluginRow: View {
    @Environment(\.themeColors) private var colors
    @Bindable private var store = MCPConnectionStore.shared
    let server: MCPServerDefinition
    let isExpanded: Bool
    let onToggle: () -> Void

    @State private var tokenInput = ""
    @State private var clientIdInput = ""
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                Divider().overlay(colors.borderSubtle).padding(.horizontal, 16)
                connectionControls
                    .padding(16)
            }
        }
    }

    private var header: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                badge
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.displayName)
                        .font(AppFont.mono(14, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                    Text(server.summary)
                        .font(AppFont.sans(12))
                        .foregroundColor(colors.textSecondary)
                }
                Spacer(minLength: 12)
                statusTag
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(colors.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .background(isHovered ? colors.backgroundHover : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var badge: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(colors.borderSubtle, lineWidth: 1))
            .frame(width: 36, height: 36)
            .overlay {
                if let image = BrandLogoLoader.image(named: server.logoAssetName) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(colors.textTertiary)
                }
            }
    }

    @ViewBuilder
    private var statusTag: some View {
        switch store.state(for: server.id) {
        case .connected where hasNoTools:
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                Text("Connected, no tools")
            }
            .font(AppFont.mono(11, weight: .medium))
            .foregroundStyle(.orange)
        case .connected:
            HStack(spacing: 5) {
                Circle().fill(Color(hex: "#34C759")).frame(width: 7, height: 7)
                Text("Connected")
            }
            .font(AppFont.mono(11, weight: .medium))
            .foregroundColor(colors.textSecondary)
        case .connecting:
            ProgressView().controlSize(.small)
        case .needsManualClientId, .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        case .disconnected:
            EmptyView()
        }
    }

    /// True once a connection attempt fully succeeded (no thrown error)
    /// but the server's own `tools/list` came back with nothing — a
    /// state that looked identical to a genuinely working connection
    /// until this was added, which is exactly how Cloudflare's missing
    /// "Account Resources: Read" permission went unnoticed: the app said
    /// "Connected" while the model had literally nothing to call.
    private var hasNoTools: Bool {
        store.isConnected(server.id) && store.tools(for: server.id).isEmpty
    }

    @ViewBuilder
    private var connectionControls: some View {
        switch store.state(for: server.id) {
        case .connected:
            VStack(alignment: .leading, spacing: 10) {
                if hasNoTools {
                    Text("Connected, but \(server.displayName) returned no tools — the model can't actually do anything with it yet. " + (server.tokenHint ?? noToolsFallbackHint))
                        .font(AppFont.mono(12))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text(toolCountLabel)
                        .font(AppFont.mono(12))
                        .foregroundColor(colors.textTertiary)
                    Spacer()
                    Button("Disconnect", role: .destructive) {
                        store.disconnect(server)
                    }
                    .buttonStyle(.bordered)
                }
            }

        case .connecting:
            Text(server.authMode == .oauth ? "Waiting for sign-in to finish in your browser…" : "Verifying your token and listing available tools…")
                .font(AppFont.mono(12))
                .foregroundColor(colors.textTertiary)

        case .needsManualClientId:
            VStack(alignment: .leading, spacing: 10) {
                Text("\(server.displayName) doesn't support automatic sign-in — you'll need to create a client ID once, yourself.")
                    .font(AppFont.mono(12))
                    .foregroundColor(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let setupURL = server.manualClientIdSetupURL {
                    Button {
                        NSWorkspace.shared.open(setupURL)
                    } label: {
                        HStack(spacing: 5) {
                            Text("Create a \(server.displayName) app")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(AppFont.mono(12, weight: .medium))
                        .foregroundColor(colors.link)
                    }
                    .buttonStyle(.plain)
                }

                if let hint = server.manualClientIdHint {
                    Text(hint)
                        .font(AppFont.sans(11))
                        .foregroundColor(colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    TextField("Paste the Client ID", text: $clientIdInput)
                        .textFieldStyle(.plain)
                        .font(AppFont.mono(13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(colors.backgroundInput)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(colors.borderSubtle, lineWidth: 1)
                        )
                        .onSubmit(signInWithClientId)

                    AccentButton(title: "Continue", isDisabled: clientIdInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        signInWithClientId()
                    }
                }
            }

        case .disconnected, .failed:
            VStack(alignment: .leading, spacing: 10) {
                if case .failed(let message) = store.state(for: server.id) {
                    Text(message)
                        .font(AppFont.mono(12))
                        .foregroundColor(colors.destructive)
                }

                switch server.authMode {
                case .oauth:
                    AccentButton(title: "Sign in to \(server.displayName)", isDisabled: false) {
                        signIn()
                    }
                    Text("Opens \(server.displayName) in your browser to sign in — Eaon never sees your password, only a token \(server.displayName) issues afterward.")
                        .font(AppFont.sans(11))
                        .foregroundColor(colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                case .pastedToken:
                    HStack(spacing: 10) {
                        SecureField(server.tokenFieldPlaceholder, text: $tokenInput)
                            .textFieldStyle(.plain)
                            .font(AppFont.mono(13))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(colors.backgroundInput)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(colors.borderSubtle, lineWidth: 1)
                            )
                            .onSubmit(connect)

                        AccentButton(title: "Connect", isDisabled: tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                            connect()
                        }
                    }

                    if let tokenHint = server.tokenHint {
                        Text(tokenHint)
                            .font(AppFont.sans(11))
                            .foregroundColor(colors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let tokenCreationURL = server.tokenCreationURL {
                        Button {
                            NSWorkspace.shared.open(tokenCreationURL)
                        } label: {
                            HStack(spacing: 5) {
                                Text("Create a token")
                                Image(systemName: "arrow.up.right")
                            }
                            .font(AppFont.mono(12, weight: .medium))
                            .foregroundColor(colors.link)
                        }
                        .buttonStyle(.plain)
                        .help(server.tokenCreationURLIsPrefilled
                              ? "Opens \(server.displayName) with the right permissions already selected."
                              : "Opens \(server.displayName)'s dashboard to create one.")
                    }
                }
            }
        }
    }

    private var noToolsFallbackHint: String {
        server.authMode == .oauth ? "Try disconnecting and signing in again." : "Try disconnecting and reconnecting with a different token."
    }

    private var toolCountLabel: String {
        let count = store.tools(for: server.id).count
        return "\(count) tool\(count == 1 ? "" : "s") available"
    }

    private func connect() {
        let trimmed = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            await store.connect(server: server, token: trimmed)
            if store.isConnected(server.id) {
                tokenInput = ""
            }
        }
    }

    private func signIn() {
        Task {
            await store.connectOAuth(server: server, interactive: true)
        }
    }

    private func signInWithClientId() {
        let trimmed = clientIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            await store.connectOAuth(server: server, interactive: true, manualClientId: trimmed)
            if store.isConnected(server.id) {
                clientIdInput = ""
            }
        }
    }
}
