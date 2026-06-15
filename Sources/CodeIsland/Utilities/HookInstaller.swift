import Foundation

/// Installs Code Island hooks into Claude Code's settings.json.
///
/// Safety contract:
/// - If `settings.json` exists but can't be parsed, the installer bails
///   without overwriting (issue #3). User hand-edited config is sacred.
/// - Before any overwrite, the previous file is copied to `.bak`.
/// - We only write when something actually changed (issue #31), so a
///   no-op launch doesn't dirty the user's git repo.
/// - Write failures bubble up — `install()` returns `false` (issue #32).
enum HookInstaller {
    static let bridgePath = "~/.code-island/bin/code-island-bridge"
    static let statusLinePath = "~/.code-island/bin/code-island-statusline"

    @discardableResult
    static func install() -> Bool {
        installBridgeLauncher()   // shared launcher, once
        // Install into the default ~/.claude AND every detected ~/.claude-*
        // profile dir (CLAUDE_CONFIG_DIR targets — Claude reads hooks from each
        // profile's own settings.json). One bad profile doesn't fail the rest.
        var ok = true
        for dir in claudeProfileDirs() {
            if !installHooks(intoClaudeDir: dir) { ok = false }
        }
        return ok
    }

    /// The default `~/.claude` plus any sibling `~/.claude-*` directories that
    /// carry real Claude config (a `settings.json`, `.credentials.json`, or
    /// `projects/`). These are the per-profile `CLAUDE_CONFIG_DIR` targets.
    static func claudeProfileDirs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fm = FileManager.default
        var dirs = [home.appendingPathComponent(".claude")]   // default, always
        let markers = ["settings.json", ".credentials.json", "projects"]
        if let entries = try? fm.contentsOfDirectory(
            at: home, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            for url in entries {
                let name = url.lastPathComponent
                guard name.hasPrefix(".claude-"),
                      (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                      markers.contains(where: { fm.fileExists(atPath: url.appendingPathComponent($0).path) })
                else { continue }
                dirs.append(url)
            }
        }
        return dirs
    }

    @discardableResult
    private static func installHooks(intoClaudeDir claudeDir: URL) -> Bool {
        let settingsPath = claudeDir.appendingPathComponent("settings.json")

        // Create the profile dir if needed (the default ~/.claude may not exist
        // yet; detected ~/.claude-* dirs already do).
        do {
            try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        } catch {
            Log.error("HookInstaller: can't create \(claudeDir.path): \(error)")
            return false
        }

        // Distinguish "file missing" (safe to start fresh) from "file present
        // but malformed" (must not touch). The previous code treated both as
        // "start from {}" and silently wiped the user's hand-edited config.
        let fileExists = FileManager.default.fileExists(atPath: settingsPath.path)
        let existingData: Data?
        if fileExists {
            do {
                existingData = try Data(contentsOf: settingsPath)
            } catch {
                Log.error("HookInstaller: \(settingsPath.path) exists but can't read: \(error). Refusing to overwrite.")
                return false
            }
        } else {
            existingData = nil
        }

        var settings: [String: Any] = [:]
        if let data = existingData, !data.isEmpty {
            guard let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                Log.error("HookInstaller: \(settingsPath.path) is present but not valid JSON. Refusing to overwrite — fix the file by hand or move it aside.")
                return false
            }
            settings = parsed
        }

        // Get or create hooks dict
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        let hookEvents = [
            "SessionStart", "SessionEnd", "UserPromptSubmit",
            "PreToolUse", "PostToolUse", "Notification",
            "Stop", "SubagentStart", "SubagentStop", "PreCompact",
        ]

        let bridgeCommand = FileManager.default.homeDirectoryForCurrentUser.path + "/.code-island/bin/code-island-bridge"

        let permissionHookEvents = ["PermissionRequest"]

        for event in hookEvents {
            addHookEntry(to: &hooks, event: event, command: bridgeCommand, timeout: nil)
        }
        for event in permissionHookEvents {
            addHookEntry(to: &hooks, event: event, command: bridgeCommand, timeout: 300)
        }

        settings["hooks"] = hooks

        // Compare to existing — skip write entirely if nothing changed
        // (avoids dirtying dotfile repos every launch).
        let newData: Data
        do {
            newData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted])
        } catch {
            Log.error("HookInstaller: failed to serialize settings: \(error)")
            return false
        }
        if let existing = existingData, normalizedJSON(existing) == normalizedJSON(newData) {
            return true   // unchanged — don't dirty the file
        }

        // Back up existing file before overwriting
        if let existing = existingData, !existing.isEmpty {
            let backup = settingsPath.appendingPathExtension("bak")
            try? existing.write(to: backup, options: .atomic)
        }

        do {
            try newData.write(to: settingsPath, options: .atomic)
        } catch {
            Log.error("HookInstaller: failed to write \(settingsPath.path): \(error)")
            return false
        }

        print("[CodeIsland] Hooks installed at \(settingsPath.path)")
        return true
    }

    /// Re-serialize parsed JSON with stable key order so we can compare two
    /// blobs semantically (whitespace + key-order independent).
    private static func normalizedJSON(_ data: Data) -> Data? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    }

    private static func addHookEntry(to hooks: inout [String: Any], event: String, command: String, timeout: Int?) {
        var eventHooks = hooks[event] as? [[String: Any]] ?? []

        // Check if our hook already exists
        let alreadyInstalled = eventHooks.contains { entry in
            guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
            return entryHooks.contains { ($0["command"] as? String)?.contains("code-island") == true }
        }

        guard !alreadyInstalled else { return }

        var hookDef: [String: Any] = [
            "type": "command",
            "command": command,
        ]
        if let timeout {
            hookDef["timeout"] = timeout
        }

        var entry: [String: Any] = ["hooks": [hookDef]]
        if event != "SessionStart" && event != "SessionEnd" && event != "PreCompact" {
            entry["matcher"] = "*"
        }

        eventHooks.append(entry)
        hooks[event] = eventHooks
    }

    private static func installBridgeLauncher() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let binDir = home.appendingPathComponent(".code-island/bin")
        try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let bridgePath = binDir.appendingPathComponent("code-island-bridge")

        let script = [
            "#!/bin/zsh",
            "# code-island-bridge launcher (auto-generated by Code Island)",
            "H=/Contents/Helpers/CodeIslandBridge",
            "for P in \"/Applications/Code Island.app\" \"$HOME/Applications/Code Island.app\"; do",
            "  B=\"${P}${H}\"; [ -x \"$B\" ] && exec \"$B\" \"$@\"",
            "done",
            "D=\"$HOME/Projects/code-island/.build/release/CodeIslandBridge\"",
            "[ -x \"$D\" ] && exec \"$D\" \"$@\"",
            "D=\"$HOME/Projects/code-island/.build/debug/CodeIslandBridge\"",
            "[ -x \"$D\" ] && exec \"$D\" \"$@\"",
            "echo \"code-island-bridge: app not found.\" >&2",
            "exit 127",
        ].joined(separator: "\n")

        try? script.write(to: bridgePath, atomically: true, encoding: .utf8)

        // Make executable
        var attrs = try? FileManager.default.attributesOfItem(atPath: bridgePath.path)
        attrs?[.posixPermissions] = 0o755
        try? FileManager.default.setAttributes(attrs ?? [.posixPermissions: 0o755], ofItemAtPath: bridgePath.path)
    }

    private static func installStatusLine() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let binDir = home.appendingPathComponent(".code-island/bin")
        try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let path = binDir.appendingPathComponent("code-island-statusline")

        let script = """
        #!/bin/bash
        # Claude Code StatusLine Script
        # Auto-configured by Code Island
        input=$(cat)

        # Cache rate limits
        _rl=$(echo "$input" | jq -c '.rate_limits // empty' 2>/dev/null)
        [ -n "$_rl" ] && echo "$_rl" > "\(home.path)/.code-island/cache/rl.json"
        """

        try? script.write(to: path, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    }
}
