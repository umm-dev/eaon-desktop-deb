import AppKit
import SwiftUI

/// The "General" settings pane — app identity and support links. Previously
/// this tab fell through to a generic placeholder ("Configuration options
/// will appear here"); this is the real content.
struct GeneralSettingsView: View {
    @Environment(\.themeColors) private var colors
    @Bindable private var updateChecker = UpdateChecker.shared

    // The dev build is a bare executable with no Info.plist, so the bundle
    // never has a version — `AppVersion.current` is the source of truth.
    private var appVersion: String { AppVersion.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("General")
                .font(AppFont.mono(20, weight: .bold))
                .foregroundColor(colors.textPrimary)
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    aboutCard
                    updatesCard
                    dataFolderCard
                    supportCard
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors.backgroundPrimary)
    }

    private var aboutCard: some View {
        SettingsCard {
            HStack(spacing: 16) {
                AquaMark(size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    AquaWordmark(size: 18)
                    Text("Unified Free AI API Platform for Top Models")
                        .font(AppFont.sans(12))
                        .foregroundColor(colors.textSecondary)
                    Text("Version \(appVersion)")
                        .font(AppFont.mono(11))
                        .foregroundColor(colors.textTertiary)
                }

                Spacer(minLength: 0)

                Button {
                    NSWorkspace.shared.open(URL(string: "https://eaon.dev")!)
                } label: {
                    HStack(spacing: 5) {
                        Text("eaon.dev")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(AppFont.mono(12, weight: .medium))
                    .foregroundColor(colors.link)
                }
                .buttonStyle(.plain)
            }
            .padding(18)
        }
    }

    private var updatesCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Automatic Update Check")
                            .font(AppFont.mono(13, weight: .semibold))
                            .foregroundColor(colors.textPrimary)
                        Text("Checks for a newer version on startup, and periodically while Eaon stays open.")
                            .font(AppFont.sans(11))
                            .foregroundColor(colors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: $updateChecker.isAutoCheckEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(AppearanceSettings.shared.accentColor)
                }
                .padding(16)

                Divider().overlay(colors.borderSubtle)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Check for Updates")
                            .font(AppFont.mono(14, weight: .semibold))
                            .foregroundColor(colors.textPrimary)
                        if let result = updateChecker.lastManualCheckResult {
                            Text(result)
                                .font(AppFont.mono(12))
                                .foregroundColor(colors.textSecondary)
                        } else {
                            Text("Check if a newer version of Eaon is available right now.")
                                .font(AppFont.mono(12))
                                .foregroundColor(colors.textSecondary)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await updateChecker.checkManually() }
                    } label: {
                        HStack(spacing: 6) {
                            if updateChecker.isCheckingManually {
                                ProgressView().controlSize(.small)
                            }
                            Text("Check for Updates")
                                .font(AppFont.mono(12, weight: .semibold))
                                .foregroundColor(colors.textPrimary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().stroke(colors.borderMedium, lineWidth: 1))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(updateChecker.isCheckingManually)
                }
                .padding(18)
            }
        }
    }

    /// "Downloaded local models and file attachments" — deliberately not
    /// "messages": conversations actually live in UserDefaults (see
    /// `LegacyDefaultsMigrator`), not this folder, so claiming otherwise
    /// here would just be wrong.
    private var dataFolderCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("App Data")
                            .font(AppFont.mono(14, weight: .semibold))
                            .foregroundColor(colors.textPrimary)
                        Text("Downloaded local models and file attachments.")
                            .font(AppFont.mono(12))
                            .foregroundColor(colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([AppDataLocation.directory])
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                            Text("Show in Finder")
                        }
                        .font(AppFont.mono(12, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().stroke(colors.borderMedium, lineWidth: 1))
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                .padding(18)

                Divider().overlay(colors.borderSubtle)

                HStack(spacing: 8) {
                    Text(AppDataLocation.directory.path)
                        .font(AppFont.mono(11))
                        .foregroundColor(colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(AppDataLocation.directory.path, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundColor(colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy path")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
    }

    private var supportCard: some View {
        SettingsCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Need help?")
                        .font(AppFont.mono(14, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                    Text("support@eaon.dev")
                        .font(AppFont.mono(12))
                        .foregroundColor(colors.textSecondary)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(string: "mailto:support@eaon.dev")!)
                } label: {
                    Text("Email us")
                        .font(AppFont.mono(12, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().stroke(colors.borderMedium, lineWidth: 1))
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(18)
        }
    }

}
