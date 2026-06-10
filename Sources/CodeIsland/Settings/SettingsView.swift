import SwiftUI
import AppKit

// MARK: - Tabs

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, integrations, sound, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:      return "General"
        case .integrations: return "Integrations"
        case .sound:        return "Sound"
        case .about:        return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general:      return "gearshape.fill"
        case .integrations: return "puzzlepiece.extension.fill"
        case .sound:        return "speaker.wave.2.fill"
        case .about:        return "info.circle.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .general:      return .gray
        case .integrations: return .blue
        case .sound:        return .green
        case .about:        return .blue
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var updateChecker: UpdateChecker
    var onReloadSounds: (() -> Void)? = nil

    @State private var selection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 240)
        } detail: {
            detail
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 8) {
                            sidebarIcon(for: selection)
                            Text(selection.title)
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                }
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 560, idealHeight: 620)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(SettingsSection.allCases) { section in
                Label {
                    Text(section.title)
                        .font(.system(size: 13))
                } icon: {
                    sidebarIcon(for: section)
                }
                .tag(section)
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarIcon(for section: SettingsSection) -> some View {
        Image(systemName: section.systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(section.accentColor.gradient)
            )
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        Form {
            switch selection {
            case .general:      generalForm
            case .integrations: integrationsForm
            case .sound:        soundForm
            case .about:        aboutForm
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - General

    @ViewBuilder
    private var generalForm: some View {
        Section("System") {
            Toggle(isOn: $settingsStore.launchAtLogin) {
                Text("Launch at Login")
            }
        }

        Section("Behavior") {
            Toggle(isOn: $settingsStore.autoExpandOnPermission) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-expand on permission request")
                    Text("Pop the notch open whenever a session is waiting for your approval.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }

        Section("Updates") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current version")
                    Text("v\(updateChecker.currentVersion)" + (updateChecker.latestVersion.map { "  ·  latest on GitHub: v\($0)" } ?? ""))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    Task { await updateChecker.checkForUpdates(showNoUpdateAlert: true) }
                } label: {
                    if updateChecker.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Check Now")
                    }
                }
                .disabled(updateChecker.isChecking)
            }

            Toggle(isOn: Binding(
                get: { updateChecker.autoCheckEnabled },
                set: { updateChecker.autoCheckEnabled = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check for updates weekly")
                    if let last = updateChecker.lastCheckedAt {
                        Text("Last checked \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Hasn't checked yet")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Sound

    @ViewBuilder
    private var soundForm: some View {
        Section("Master") {
            Toggle(isOn: $settingsStore.soundEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable sounds")
                    Text("Play notification chimes for session events.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            HStack {
                Text("Volume")
                Spacer()
                Slider(value: $settingsStore.soundVolume, in: 0...1)
                    .frame(width: 220)
            }
            .disabled(!settingsStore.soundEnabled)
        }

        Section("Events") {
            Toggle("Session start / end", isOn: $settingsStore.soundSessionStart)
            Toggle("Completion",          isOn: $settingsStore.soundCompletion)
            Toggle("Tool use",            isOn: $settingsStore.soundToolUse)
            Toggle("Error",               isOn: $settingsStore.soundError)
            Toggle("Permission",          isOn: $settingsStore.soundPermission)
        }
        .disabled(!settingsStore.soundEnabled)

        Section("Custom Sound Pack") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Drop audio files (.wav / .mp3 / .m4a) into the sound packs folder named after the event:")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("session-start, session-end, completion, tool-use, error,\napproval-needed, approval-granted, approval-denied")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Open Folder") { openSoundPacksFolder() }
                    Button("Reload") { onReloadSounds?() }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Integrations

    @ViewBuilder
    private var integrationsForm: some View {
        Section {
            IntegrationRow(
                title: "Claude Code",
                subtitle: "Writes hooks to ~/.claude/settings.json.",
                accent: Color(red: 0.85, green: 0.47, blue: 0.34),
                install: { HookInstaller.install() }
            )
            IntegrationRow(
                title: "Codex",
                subtitle: "Writes ~/.codex/hooks.json and toggles [features].hooks = true.",
                accent: Color(red: 0.88, green: 0.88, blue: 0.88),
                install: { CodexInstaller.install() }
            )
        } header: {
            Text("Providers")
        } footer: {
            Text("Hooks auto-install every time Code Island launches. Use these buttons only if you need to refresh or re-pair after deleting config files.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }

        Section("Bridge") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Socket")
                    Text("Path used by the bridge to talk to the app.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("/tmp/code-island.sock")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - About

    @ViewBuilder
    private var aboutForm: some View {
        Section {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                    .frame(width: 54, height: 54)
                    .overlay(
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text("Code Island")
                        .font(.system(size: 18, weight: .bold))
                    Text("v1.0.4")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("The notch dashboard for your AI coding agents.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }

        Section("Links") {
            LinkRow(label: "GitHub repository", url: URL(string: "https://github.com/rifqiakrm/code-island")!)
            LinkRow(label: "Report an issue",   url: URL(string: "https://github.com/rifqiakrm/code-island/issues")!)
        }
    }

    private func openSoundPacksFolder() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".code-island/sound-packs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
}

// MARK: - Small reusable building blocks

private struct IntegrationRow: View {
    let title: String
    let subtitle: String
    let accent: Color
    let install: () -> Void

    var body: some View {
        HStack {
            Circle()
                .fill(accent)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Reinstall hooks", action: install)
                .controlSize(.small)
        }
    }
}

private struct LinkRow: View {
    let label: String
    let url: URL
    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack {
                Text(label)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
