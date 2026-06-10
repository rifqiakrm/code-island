import Foundation

/// Installs Code Island hooks into OpenAI Codex (`$CODEX_HOME/hooks.json`
/// + `config.toml`).
///
/// Safety contract:
/// - hooks.json: read existing, merge ONLY Code Island's own entries,
///   preserve foreign hooks (issue #12). Backup to .bak before overwrite.
/// - config.toml: detect `features.hooks` even when the user wrote it as a
///   dotted key or inline table, and refuse to append a conflicting
///   `[features]` block that would make Codex reject the whole file
///   (issue #13).
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
    static var isDetected: Bool {
        FileManager.default.fileExists(atPath: codexHome.path)
    }

    @discardableResult
    static func install() -> Bool {
        let dir = codexHome
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            Log.error("CodexInstaller: can't create \(dir.path): \(error)")
            return false
        }

        let hooksOK = writeHooksJSON(in: dir)
        let tomlOK = enableHooksFeature(in: dir)
        installBridgeLauncher()

        print("[CodeIsland] Codex hooks installed at \(dir.path)")
        return hooksOK && tomlOK
    }

    // MARK: - hooks.json (merge, don't overwrite)

    /// Merges Code Island's hooks into an existing hooks.json. Foreign
    /// entries (user customizations, other tools) are left alone.
    /// Returns false if read/write fails.
    @discardableResult
    private static func writeHooksJSON(in codexDir: URL) -> Bool {
        let bridgeCmd = bridgeCommand()
        let events = [
            "SessionStart", "SessionEnd", "UserPromptSubmit",
            "PreToolUse", "PostToolUse", "Stop",
            "Notification", "SubagentStart", "SubagentStop", "PreCompact",
        ]
        let permissionEvents = ["PermissionRequest"]

        let url = codexDir.appendingPathComponent("hooks.json")

        // Load existing root, if any. Bail if present-but-malformed.
        var root: [String: Any] = [:]
        let existingData = try? Data(contentsOf: url)
        if let data = existingData, !data.isEmpty {
            guard let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                Log.error("CodexInstaller: \(url.path) exists but isn't valid JSON. Refusing to overwrite.")
                return false
            }
            root = parsed
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for ev in events {
            mergeCodeIslandEntry(in: &hooks, event: ev, command: bridgeCmd, timeout: 5)
        }
        for ev in permissionEvents {
            mergeCodeIslandEntry(in: &hooks, event: ev, command: bridgeCmd, timeout: 300)
        }
        root["hooks"] = hooks

        let newData: Data
        do {
            newData = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
        } catch {
            Log.error("CodexInstaller: failed to serialize hooks.json: \(error)")
            return false
        }

        // Skip the write if nothing actually changed.
        if let existing = existingData, normalizedJSON(existing) == normalizedJSON(newData) {
            return true
        }

        if let existing = existingData, !existing.isEmpty {
            try? existing.write(to: url.appendingPathExtension("bak"), options: .atomic)
        }

        do {
            try newData.write(to: url, options: .atomic)
            return true
        } catch {
            Log.error("CodexInstaller: failed to write \(url.path): \(error)")
            return false
        }
    }

    /// Inserts or updates Code Island's entry for `event` while leaving any
    /// foreign entries (user customizations, other tools) intact.
    private static func mergeCodeIslandEntry(in hooks: inout [String: Any], event: String, command: String, timeout: Int) {
        var entries = hooks[event] as? [[String: Any]] ?? []

        let isOurs: ([String: Any]) -> Bool = { entry in
            guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
            return inner.contains { ($0["command"] as? String)?.contains("code-island") == true }
        }

        let ourEntry: [String: Any] = [
            "hooks": [["type": "command", "command": command, "timeout": timeout]]
        ]

        if let idx = entries.firstIndex(where: isOurs) {
            entries[idx] = ourEntry
        } else {
            entries.append(ourEntry)
        }
        hooks[event] = entries
    }

    private static func normalizedJSON(_ data: Data) -> Data? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    }

    // MARK: - config.toml (don't double-define [features])

    /// Ensures `features.hooks = true` is set in config.toml without
    /// creating a duplicate `features` table. Returns false only on a
    /// detected conflict we refuse to resolve.
    @discardableResult
    private static func enableHooksFeature(in codexDir: URL) -> Bool {
        let url = codexDir.appendingPathComponent("config.toml")
        var lines: [String] = []
        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            lines = existing.components(separatedBy: "\n")
        }

        // Detect every form of "features" the user could have written:
        //   [features]                          (table header)
        //   features.hooks = true               (dotted key)
        //   features = { hooks = true }         (inline table)
        //   ["features"]                        (quoted header)
        var featuresHeader: Int? = nil
        var hasDottedFeatures = false
        var hasInlineFeatures = false
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip pure comments
            if trimmed.hasPrefix("#") { continue }
            if trimmed == "[features]" || trimmed == "[\"features\"]" {
                featuresHeader = i
            } else if trimmed.hasPrefix("features.") || trimmed.hasPrefix("\"features\".") {
                hasDottedFeatures = true
            } else if trimmed.hasPrefix("features ") || trimmed.hasPrefix("features=") {
                // Likely inline table form: features = { ... }
                hasInlineFeatures = true
            }
        }

        // If the user is using dotted or inline forms, surgical edit is
        // risky (we don't have a real TOML parser). Either patch in place
        // when possible, or bail with a clear log instead of corrupting
        // the file by appending a conflicting [features] block.
        if hasInlineFeatures {
            Log.error("CodexInstaller: config.toml uses inline `features = { … }` form. Refusing to add a [features] section that would conflict. Set `features.hooks = true` manually or convert to a [features] table.")
            return false
        }
        if hasDottedFeatures && featuresHeader == nil {
            // Dotted keys are fine — just ensure features.hooks is true.
            return upsertDottedHooks(lines: &lines, url: url)
        }

        if let start = featuresHeader {
            // Find section end (next [section] header or EOF)
            var end = lines.count - 1
            for i in (start + 1)..<lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("[") && t.hasSuffix("]") {
                    end = i - 1
                    break
                }
            }
            var found = false
            for i in (start + 1)...end {
                let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("hooks") {
                    if lines[i] != "hooks = true" {
                        lines[i] = "hooks = true"
                    } else {
                        return true  // nothing to do
                    }
                    found = true
                    break
                }
            }
            if !found {
                lines.insert("hooks = true", at: start + 1)
            }
        } else {
            // No [features] anywhere — append a fresh section
            if !lines.isEmpty && !(lines.last?.isEmpty ?? true) {
                lines.append("")
            }
            lines.append("[features]")
            lines.append("hooks = true")
        }

        let output = lines.joined(separator: "\n")
        do {
            try output.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            Log.error("CodexInstaller: failed to write \(url.path): \(error)")
            return false
        }
    }

    /// Idempotently sets `features.hooks = true` for dotted-key configs.
    private static func upsertDottedHooks(lines: inout [String], url: URL) -> Bool {
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("features.hooks") {
                if lines[i] != "features.hooks = true" {
                    lines[i] = "features.hooks = true"
                } else {
                    return true
                }
                let output = lines.joined(separator: "\n")
                do {
                    try output.write(to: url, atomically: true, encoding: .utf8)
                    return true
                } catch {
                    Log.error("CodexInstaller: failed to write \(url.path): \(error)")
                    return false
                }
            }
        }
        // No features.hooks line — append it
        if !lines.isEmpty && !(lines.last?.isEmpty ?? true) {
            lines.append("")
        }
        lines.append("features.hooks = true")
        let output = lines.joined(separator: "\n")
        do {
            try output.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            Log.error("CodexInstaller: failed to write \(url.path): \(error)")
            return false
        }
    }

    // MARK: - Bridge launcher

    private static func bridgeCommand() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return "\(home.path)/.code-island/bin/code-island-codex-bridge"
    }

    private static func installBridgeLauncher() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let binDir = home.appendingPathComponent(".code-island/bin")
        try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let launcher = binDir.appendingPathComponent("code-island-codex-bridge")

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
