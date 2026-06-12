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

    /// One-line description shown under the section title in the hero card.
    var hero: String {
        switch self {
        case .general:
            return "Launch behavior, notch expansion, and update preferences."
        case .integrations:
            return "Auto-install hooks for Claude Code and OpenAI Codex."
        case .sound:
            return "Per-event chimes, master volume, and custom sound packs."
        case .about:
            return "Version, links to source, license, and credits."
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var updateChecker: UpdateChecker
    var onReloadSounds: (() -> Void)? = nil

    @State private var selection: SettingsSection = .general

    /// "v1.1.6" when bundled normally; "dev" when run from `swift run` /
    /// `.build/debug/CodeIsland` (no Info.plist version baked in).
    private var displayVersion: String {
        let v = updateChecker.currentVersion
        return v == "0.0.0" ? "dev" : v
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 240)
        } detail: {
            detail
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 600, idealHeight: 660)
    }

    // MARK: - Sidebar

    @State private var searchText: String = ""

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Search bar — Tahoe System Settings has this at the very top.
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Compact brand row (logo + name + subtitle).
            HStack(spacing: 10) {
                brandLogo
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Code Island")
                        .font(.system(size: 15, weight: .semibold))
                    Text("v\(displayVersion)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Section list — bigger icons, bigger fonts, full-width
            // rounded blue highlight on the selected row.
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredSections, id: \.self) { section in
                        sectionRow(section)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)
        }
        .background(.regularMaterial)
    }

    private var filteredSections: [SettingsSection] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return SettingsSection.allCases }
        return SettingsSection.allCases.filter {
            $0.title.lowercased().contains(q) || $0.hero.lowercased().contains(q)
        }
    }

    private func sectionRow(_ section: SettingsSection) -> some View {
        let selected = selection == section
        return Button { selection = section } label: {
            HStack(spacing: 10) {
                sidebarIcon(for: section)
                Text(section.title)
                    .font(.system(size: 14))
                    .foregroundColor(selected ? .white : .primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.accentColor : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Loads `logo.png` from any of the places it could plausibly live:
    /// the .app's Resources/branding/, the .app's Resources/AppIcon.icns,
    /// or — for `swift run` debug builds — the source tree's
    /// `design/logo.png`. Returns nil if nothing matches; the brand row
    /// falls back to a gradient placeholder.
    private static func loadBrandLogo() -> NSImage? {
        let fm = FileManager.default
        // 1. Bundled via SPM resources or .app/Contents/Resources/branding/
        if let url = Bundle.main.url(forResource: "logo", withExtension: "png", subdirectory: "branding"),
           let img = NSImage(contentsOf: url) { return img }
        if let url = Bundle.main.url(forResource: "logo", withExtension: "png"),
           let img = NSImage(contentsOf: url) { return img }
        // 2. .app's AppIcon.icns (always present in the packaged build)
        if let url = Bundle.main.urlForImageResource("AppIcon"),
           let img = NSImage(contentsOf: url) { return img }
        // 3. Dev convenience: walk up from the executable to find design/logo.png
        var dir = Bundle.main.bundleURL.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("design/logo.png")
            if fm.fileExists(atPath: candidate.path), let img = NSImage(contentsOf: candidate) {
                return img
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    @ViewBuilder
    private var brandLogo: some View {
        if let nsImage = Self.loadBrandLogo() {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.42, green: 0.86, blue: 0.76),
                                 Color(red: 0.27, green: 0.55, blue: 0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                )
        }
    }

    private func sidebarIcon(for section: SettingsSection) -> some View {
        Image(systemName: section.systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(section.accentColor.gradient)
            )
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        Form {
            // Hero card — Tahoe System Settings style. Big rounded-gradient
            // icon, large title, one-line description. Sits in its own
            // Section so the grouped form gives it the proper card chrome.
            Section {
                VStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(selection.accentColor.gradient)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: selection.systemImage)
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundColor(.white)
                        )
                        .shadow(color: selection.accentColor.opacity(0.25), radius: 12, y: 6)
                    VStack(spacing: 6) {
                        Text(selection.title)
                            .font(.system(size: 28, weight: .bold))
                        Text(selection.hero)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }

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
        Section("Version") {
            HStack {
                Text("Code Island")
                Spacer()
                Text("v\(displayVersion)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }

        Section("Links") {
            LinkRow(label: "GitHub repository", url: URL(string: "https://github.com/rifqiakrm/code-island")!)
            LinkRow(label: "Report an issue",   url: URL(string: "https://github.com/rifqiakrm/code-island/issues")!)
            LinkRow(label: "License",           url: URL(string: "https://github.com/rifqiakrm/code-island/blob/main/LICENSE")!)
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
