// AboutTabView.swift
// OpenClip
//
// The About preferences tab: app identity, version with the Check for Updates link, extension
// updates, and diagnostics.
// Styled with inset SettingsCards (outside headers, rounded cards, inset hairline dividers).

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Core

@MainActor
struct AboutTab: View {
    @State private var isExporting = false
    @ObservedObject private var extensionUpdateManager = ExtensionUpdateManager.shared
    @ObservedObject private var updateManager = AppUpdateManager.shared

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Identity block
                identityBlock

                SettingsCard("Extension Updates") {
                    SettingsToggleRow(
                        title: "Automatically Update Extensions",
                        subtitle: "Checks the Store once a day.",
                        isOn: $extensionUpdateManager.automaticallyUpdatesExtensions
                    )
                }

                // Diagnostics
                SettingsCard("Diagnostics") {
                    SettingsRow(
                        title: "Logs",
                        subtitle: "Attach these when reporting a problem."
                    ) {
                        HStack(spacing: 10) {
                            Button(isExporting ? String(localized: "Exporting…") : String(localized: "Export…")) {
                                exportLogs()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(SettingsDesignTokens.primaryText)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .settingsGlassCapsule()
                            .contentShape(Capsule())
                            .disabled(isExporting)

                            Button(String(localized: "Reveal")) {
                                LogExporter.showLogsInFinder()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(SettingsDesignTokens.primaryText)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .settingsGlassCapsule()
                            .contentShape(Capsule())
                        }
                    }
                }

                Text("Open source under AGPL-3.0 License")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Pieces

    private var identityBlock: some View {
        VStack(spacing: 6) {
            Image(nsImage: AppIcon.image)
                .resizable()
                .frame(width: 72, height: 72)

            Text(verbatim: "OpenClip Lite")
                .font(.title2.weight(.semibold))
                .foregroundStyle(SettingsDesignTokens.primaryText)

            Text("Version \(version)")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                // Hidden in a build without an update feed; disabled in the Debug build, which
                // never updates itself.
                if AppUpdateManager.isEnabled {
                    Button("Check for Updates") {
                        updateManager.checkForUpdates()
                    }
                    .buttonStyle(.link)
                    .disabled(!updateManager.canPresentUpdate)

                    Text(verbatim: "•")
                        .foregroundStyle(.tertiary)
                }

                Button {
                    openURL("https://github.com/olegy/openclip")
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: "GitHub")
                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.semibold))
                    }
                }
                .buttonStyle(.link)
            }
            .font(.callout)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Helpers

    private func openURL(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }

    private func exportLogs() {
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let tempZipURL = try await LogExporter.exportLogs()
                defer {
                    try? FileManager.default.removeItem(at: tempZipURL)
                }

                let panel = NSSavePanel()
                panel.title = String(localized: "Export Logs")
                panel.nameFieldStringValue = tempZipURL.lastPathComponent
                panel.allowedContentTypes = [.zip]
                panel.canCreateDirectories = true

                if panel.runModal() == .OK, let destinationURL = panel.url {
                    let fileManager = FileManager.default
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        try fileManager.removeItem(at: destinationURL)
                    }
                    try fileManager.copyItem(at: tempZipURL, to: destinationURL)
                }
            } catch {
                SettingsRouter.shared.notifyError(
                    title: String(localized: "Export Logs Failed"),
                    message: error.localizedDescription
                )
            }
        }
    }
}

