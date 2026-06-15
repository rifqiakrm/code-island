import SwiftUI
import AppKit

// MARK: - Tabs

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, integrations, sound, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:      return "General"
        case .appearance:   return "Appearance"
        case .integrations: return "Integrations"
        case .sound:        return "Sound"
        case .about:        return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general:      return "gearshape.fill"
        case .appearance:   return "paintpalette.fill"
        case .integrations: return "puzzlepiece.extension.fill"
        case .sound:        return "speaker.wave.2.fill"
        case .about:        return "info.circle.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .general:      return .gray
        case .appearance:   return .purple
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
        case .appearance:
            return "Pick the visual theme for the notch windows."
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
    var onPreviewEvent: ((SoundEvent) -> Void)? = nil
    var onPreviewFile: ((String) -> Void)? = nil
    @State private var soundLibraryVersion = 0   // bump to refresh library list

    @State private var selection: SettingsSection = .general
    @State private var soundReloaded = false

    /// "v1.4.0" when bundled normally; "dev" when run from `swift run` /
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
            case .appearance:   appearanceForm
            case .integrations: integrationsForm
            case .sound:        soundForm
            case .about:        aboutForm
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - General

    /// Two-way binding into the per-provider strict-approval map.
    private func strictBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { settingsStore.isStrict(id) }, set: { settingsStore.setStrict(id, $0) })
    }

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

        Section {
            ForEach(SettingsStore.strictApprovalProviders, id: \.self) { id in
                let provider = AIProvider.from(id)
                Toggle(isOn: strictBinding(id)) {
                    HStack(spacing: 8) {
                        ProviderIcon(provider: provider, size: 15)
                        Text(provider.displayName)
                    }
                }
            }
        } header: {
            Text("Review every action")
        } footer: {
            Text("Gemini, Cursor, Copilot, Kimi, AntiGravity, and Hermes have no selective permission prompt — only blanket \"before every tool\" hooks. Turn one on to pause that agent on every tool call for in-notch approval. Off by default: when on you'll be prompted a lot, and if you don't answer before the hook times out (~5 min) the action proceeds. (Hermes also keeps its own prompt for dangerous commands.)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
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
                    Text("Check for updates daily")
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

    // MARK: - Appearance

    @ViewBuilder
    private var appearanceForm: some View {
        Section {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12),
                          GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(NotchThemeID.allCases) { id in
                    ThemePreviewCard(
                        theme: id.theme,
                        title: id.displayName,
                        selected: settingsStore.notchThemeID == id,
                        action: { settingsStore.notchThemeID = id }
                    )
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Theme")
        } footer: {
            Text(settingsStore.notchThemeID.blurb)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
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
            ForEach(Self.soundEventRows, id: \.event) { row in
                soundEventRow(row)
            }
        }
        .disabled(!settingsStore.soundEnabled)

        Section {
            let library = settingsStore.soundLibraryFiles()
            let _ = soundLibraryVersion   // re-read when this changes
            if library.isEmpty {
                Text("No imported sounds yet.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                ForEach(library, id: \.self) { file in
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundColor(.secondary)
                        Text(file).font(.system(size: 12))
                        Spacer()
                        Button { onPreviewFile?(file) } label: { Image(systemName: "play.circle") }
                            .buttonStyle(.borderless)
                        Button(role: .destructive) {
                            settingsStore.deleteSound(file)
                            soundLibraryVersion += 1
                            onReloadSounds?()
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            Button {
                importSoundFile()
            } label: {
                Label("Add Sound…", systemImage: "plus")
            }
        } header: {
            Text("My Sounds")
        } footer: {
            Text("Import .wav / .mp3 / .m4a / .aiff / .caf, then pick it for any event above. Default = the built-in 8-bit chime.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private static let soundEventRows: [(event: SoundEvent, title: String, subtitle: String)] = [
        (.sessionStart,   "Session start",    "A new agent session begins"),
        (.sessionEnd,     "Session end",      "A session closes"),
        (.completion,     "Task complete",    "The agent finished its turn"),
        (.toolUse,        "Tool use",         "The agent runs a tool"),
        (.error,          "Error",            "Tool failure or error"),
        (.approvalNeeded, "Approval needed",  "Permission or question pending"),
        (.approvalGranted,"Approval granted", "You allowed an action"),
        (.approvalDenied, "Approval denied",  "You denied an action"),
    ]

    @ViewBuilder
    private func soundEventRow(_ row: (event: SoundEvent, title: String, subtitle: String)) -> some View {
        let library = settingsStore.soundLibraryFiles()
        let _ = soundLibraryVersion
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                Text(row.subtitle).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { settingsStore.soundChoice(for: row.event.rawValue) },
                set: { settingsStore.setSoundChoice($0, for: row.event.rawValue) }
            )) {
                Text("Default").tag("default")
                Text("Off").tag("off")
                if !library.isEmpty {
                    Divider()
                    ForEach(library, id: \.self) { Text($0).tag($0) }
                }
            }
            .labelsHidden()
            .frame(width: 150)
            Button { onPreviewEvent?(row.event) } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    /// Native file picker → copy into the library → refresh.
    private func importSoundFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        panel.prompt = "Import"
        if panel.runModal() == .OK {
            for url in panel.urls { settingsStore.importSound(from: url) }
            soundLibraryVersion += 1
            onReloadSounds?()
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
            IntegrationRow(
                title: "Gemini",
                subtitle: "Writes hooks to ~/.gemini/settings.json.",
                accent: Color(red: 0.278, green: 0.588, blue: 0.894),
                install: { ProviderInstaller.installSource("gemini") }
            )
            IntegrationRow(
                title: "Qwen Code",
                subtitle: "Writes hooks to ~/.qwen/settings.json.",
                accent: Color(red: 0.486, green: 0.228, blue: 0.929),
                install: { ProviderInstaller.installSource("qwen") }
            )
            IntegrationRow(
                title: "Qoder",
                subtitle: "Writes hooks to ~/.qoder/settings.json.",
                accent: Color(red: 0.165, green: 0.859, blue: 0.361),
                install: { ProviderInstaller.installSource("qoder") }
            )
            IntegrationRow(
                title: "Factory",
                subtitle: "Writes hooks to ~/.factory/settings.json (droid CLI).",
                accent: Color(red: 0.835, green: 0.416, blue: 0.149),
                install: { ProviderInstaller.installSource("droid") }
            )
            IntegrationRow(
                title: "CodeBuddy",
                subtitle: "Writes hooks to ~/.codebuddy/settings.json.",
                accent: Color(red: 0.424, green: 0.302, blue: 1.000),
                install: { ProviderInstaller.installSource("codebuddy") }
            )
            IntegrationRow(
                title: "Cursor",
                subtitle: "Writes hooks to ~/.cursor/hooks.json.",
                accent: Color(red: 0.60, green: 0.58, blue: 0.54),
                install: { ProviderInstaller.installSource("cursor") }
            )
            IntegrationRow(
                title: "Copilot",
                subtitle: "Writes hooks to ~/.copilot/hooks/codeisland.json.",
                accent: Color(red: 0.800, green: 0.200, blue: 0.400),
                install: { ProviderInstaller.installSource("copilot") }
            )
            IntegrationRow(
                title: "Kimi",
                subtitle: "Appends [[hooks]] blocks to ~/.kimi/config.toml.",
                accent: Color(red: 0.29, green: 0.56, blue: 1.000),
                install: { ProviderInstaller.installSource("kimi") }
            )
            IntegrationRow(
                title: "OpenCode",
                subtitle: "Installs a plugin in ~/.config/opencode and registers it.",
                accent: Color(red: 0.62, green: 0.62, blue: 0.64),
                install: { ProviderInstaller.installSource("opencode") }
            )
            IntegrationRow(
                title: "Cline",
                subtitle: "Writes hook scripts to ~/Documents/Cline/Hooks.",
                accent: Color(red: 0.00, green: 0.70, blue: 0.49),
                install: { ProviderInstaller.installSource("cline") }
            )
            IntegrationRow(
                title: "Kiro",
                subtitle: "Writes an agent to ~/.kiro/agents/codeisland.json (launch: kiro --agent codeisland).",
                accent: Color(red: 0.49, green: 0.36, blue: 1.00),
                install: { ProviderInstaller.installSource("kiro") }
            )
            IntegrationRow(
                title: "Pi",
                subtitle: "Installs a TypeScript extension in ~/.pi/agent/extensions.",
                accent: Color(red: 0.96, green: 0.69, blue: 0.13),
                install: { ProviderInstaller.installSource("pi") }
            )
            IntegrationRow(
                title: "Oh My Pi",
                subtitle: "Installs a TypeScript extension in ~/.omp/agent/extensions.",
                accent: Color(red: 0.13, green: 0.78, blue: 0.74),
                install: { ProviderInstaller.installSource("omp") }
            )
            IntegrationRow(
                title: "AntiGravity",
                subtitle: "Writes a hook group to ~/.gemini/config/hooks.json (restart AntiGravity to load).",
                accent: Color(red: 0.259, green: 0.522, blue: 0.957),
                install: { ProviderInstaller.installSource("antigravity") }
            )
            IntegrationRow(
                title: "Hermes",
                subtitle: "Merges hooks into ~/.hermes/config.yaml (needs `hermes hooks` approval).",
                accent: Color(red: 0.953, green: 0.722, blue: 0.196),
                install: { ProviderInstaller.installSource("hermes") }
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

        Section {
            LinkRow(label: "Support on Ko-fi ☕", url: URL(string: "https://ko-fi.com/rifqiakrm")!)
            LinkRow(label: "Donate via PayPal",   url: URL(string: "https://paypal.me/rifqiakrm")!)
        } header: {
            Text("Support the project")
        } footer: {
            Text("Code Island is free & open source. If you'd like to support development, it's hugely appreciated — and totally optional. ♥")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
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
    let install: () -> Bool

    private enum Status { case idle, success, failure }
    @State private var status: Status = .idle

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
            switch status {
            case .idle:
                Button("Reinstall hooks") { run() }
                    .controlSize(.small)
            case .success:
                Label("Reinstalled", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.green)
                    .transition(.opacity)
            case .failure:
                Label("Failed — check the log", systemImage: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.red)
                    .transition(.opacity)
            }
        }
    }

    private func run() {
        let ok = install()
        withAnimation { status = ok ? .success : .failure }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { status = .idle }
        }
    }
}

/// A selectable theme swatch — renders a mini notch window using the theme's
/// real chrome tokens so the picker doubles as a live preview.
private struct ThemePreviewCard: View {
    let theme: NotchTheme
    let title: String
    let selected: Bool
    let action: () -> Void

    private var swatchBackground: Color {
        switch theme.windowFill {
        case .solid(let color):  return color
        case .material:          return Color(red: 0.13, green: 0.13, blue: 0.16)
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    swatchBackground
                    // Mini session card built from the theme's own tokens.
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 6, height: 6)
                        Text("code-island")
                            .font(theme.font(size: 9, weight: .semibold))
                            .foregroundColor(theme.cardForeground.opacity(0.9))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .notchCard(theme, tint: theme.cardHueActive ?? .cyan, active: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 13)
                }
                .frame(height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12),
                                      lineWidth: selected ? 2 : 1)
                )

                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundColor(selected ? .accentColor : .secondary.opacity(0.4))
                }
            }
        }
        .buttonStyle(.plain)
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
