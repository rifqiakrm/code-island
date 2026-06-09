import Foundation

/// Installs Code Island hooks into OpenAI Codex (`$CODEX_HOME/hooks.json`
/// + `config.toml`). Mirrors the structure of `HookInstaller` but writes
/// Codex's nested format and toggles the `[features].hooks = true` flag.
///
/// Returns `false` only when the `config.toml` write fails — it succeeds
/// even if Codex isn't installed yet so the hooks are pre-staged.
enum CodexInstaller {
    /// Path of `$CODEX_HOME`. Honors the env var, expands `~`, falls back to `~/.codex`.
    static var codexHome: URL {
        let raw = (ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "")
            .trimmingCharacters(in: .whitespaces)
        let home = FileManager.default.homeDirectoryForCurrentUser
        if raw.isEmpty { return home.appendingPathComponent(".codex") }
        if raw == "~" { return home }
        if raw.hasPrefix("~/") {
            return home.appendingPathComponent(String(raw.dropFirst(2)))
        }
        return URL(fileURLWithPath: raw)
    }

    /// Returns true if the user appears to have Codex installed (i.e. its CONFIG dir exists).
    /// We don't require Codex to be installed to write hooks, but the UI uses this
    /// signal to decide whether to surface the install button.
    static var isDetected: Bool {
        FileManager.default.fileExists(atPath: codexHome.path)
    }

    @discardableResult
    static func install() -> Bool {
        let dir = codexHome
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // 1. Write hooks.json in Codex's nested format
        writeHooksJSON(in: dir)

        // 2. Toggle `hooks = true` in config.toml (creates [features] if missing)
        enableHooksFeature(in: dir)

        // 3. Install bridge launcher that knows to pass `--source codex`
        installBridgeLauncher()

        print("[CodeIsland] Codex hooks installed at \(dir.path)")
        return true
    }

    // MARK: - hooks.json

    /// Codex's hooks.json is a nested format with no `matcher` field, just an
    /// event-name → array of entries containing `hooks` arrays.
    private static func writeHooksJSON(in codexDir: URL) {
        let bridgeCmd = bridgeCommand()
        let events = [
            "SessionStart", "SessionEnd", "UserPromptSubmit",
            "PreToolUse", "PostToolUse", "Stop",
            "Notification", "SubagentStart", "SubagentStop", "PreCompact",
        ]
        let permissionEvents = ["PermissionRequest"]

        var hooksDict: [String: [[String: Any]]] = [:]
        for ev in events {
            hooksDict[ev] = [["hooks": [["type": "command", "command": bridgeCmd, "timeout": 5]]]]
        }
        for ev in permissionEvents {
            hooksDict[ev] = [["hooks": [["type": "command", "command": bridgeCmd, "timeout": 300]]]]
        }

        let root: [String: Any] = ["hooks": hooksDict]
        let url = codexDir.appendingPathComponent("hooks.json")
        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - config.toml

    /// Ensures `[features]` section exists in config.toml with `hooks = true`.
    /// Replaces an existing `hooks = false` or appends to an existing `[features]` table,
    /// otherwise appends a new section at the end of the file.
    private static func enableHooksFeature(in codexDir: URL) {
        let url = codexDir.appendingPathComponent("config.toml")
        var lines: [String] = []
        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            lines = existing.components(separatedBy: "\n")
        }

        // Find the [features] section bounds
        var featuresStart: Int? = nil
        var featuresEnd: Int? = nil
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[features]" {
                featuresStart = i
            } else if let start = featuresStart, i > start, trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                featuresEnd = i - 1
                break
            }
        }

        if let start = featuresStart {
            // Section exists — look for hooks key inside it
            let end = featuresEnd ?? (lines.count - 1)
            var found = false
            for i in (start + 1)...end {
                let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("hooks") {
                    lines[i] = "hooks = true"
                    found = true
                    break
                }
            }
            if !found {
                lines.insert("hooks = true", at: start + 1)
            }
        } else {
            // No [features] section — append one
            if !lines.isEmpty && !(lines.last?.isEmpty ?? true) {
                lines.append("")
            }
            lines.append("[features]")
            lines.append("hooks = true")
        }

        let output = lines.joined(separator: "\n")
        try? output.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Bridge launcher

    /// Returns the command Codex's hooks.json should invoke. We use a launcher
    /// script under `~/.code-island/bin/` so we can update the binary's
    /// location without re-writing hook configs.
    private static func bridgeCommand() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return "\(home.path)/.code-island/bin/code-island-codex-bridge"
    }

    private static func installBridgeLauncher() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let binDir = home.appendingPathComponent(".code-island/bin")
        try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let launcher = binDir.appendingPathComponent("code-island-codex-bridge")

        // Same launcher script as the Claude bridge but passes `--source codex`
        // before any extra args so the bridge stamps the right provider id.
        let script = [
            "#!/bin/zsh",
            "# code-island-codex-bridge launcher (auto-generated by Code Island)",
            "H=/Contents/Helpers/CodeIslandBridge",
            "for P in \"/Applications/Code Island.app\" \"$HOME/Applications/Code Island.app\"; do",
            "  B=\"${P}${H}\"; [ -x \"$B\" ] && exec \"$B\" --source codex \"$@\"",
            "done",
            "D=\"$HOME/Projects/code-island/.build/release/CodeIslandBridge\"",
            "[ -x \"$D\" ] && exec \"$D\" --source codex \"$@\"",
            "D=\"$HOME/Projects/code-island/.build/debug/CodeIslandBridge\"",
            "[ -x \"$D\" ] && exec \"$D\" --source codex \"$@\"",
            "echo \"code-island-codex-bridge: app not found.\" >&2",
            "exit 127",
        ].joined(separator: "\n")

        try? script.write(to: launcher, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
    }
}
