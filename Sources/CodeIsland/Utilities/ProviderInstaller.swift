import Foundation

/// Descriptor-driven installer for the extra AI providers (Gemini, Qwen,
/// Qoder, Factory/droid, CodeBuddy, Cursor, Copilot). Each provider's hook
/// config differs (format, timeout unit, whether the event name is passed via
/// `--event`); a single engine writes them all from a `Descriptor`.
///
/// Safety contract mirrors `CodexInstaller`: only touch a provider's config if
/// its dir already exists (so we don't conjure config for tools the user
/// doesn't have), merge ONLY our own entries (identified by the "code-island"
/// marker in the command), preserve foreign hooks, back up to `.bak`, and skip
/// the write when nothing changed.
enum ProviderInstaller {

    enum Format {
        case claudeFork   // {"matcher":"*","hooks":[{type,command,timeout}]} per event
        case nested       // {"hooks":[{type,command,timeout}]} per event (no matcher)
        case flat         // [{command}] per event; event name passed via --event
        case copilot      // {version:1, hooks:{event:[{type,bash,timeoutSec}]}}; --event
        case toml         // Kimi: [[hooks]] array-of-tables appended to config.toml
        case opencodePlugin // OpenCode: JS plugin file + register in opencode.json
        case clineScripts // Cline: one executable bash script per event in a dir
        case kiroAgent    // Kiro: agent-scoped JSON ({command,matcher,timeout_ms}); needs `kiro --agent codeisland`
        case piExtension  // Pi / Oh My Pi: a TypeScript extension auto-discovered from the agent's extensions dir
        case hermesYAML   // Nous Hermes: merge a `hooks:` map into ~/.hermes/config.yaml (needs `hermes hooks` approval)
        case antigravityJSON // Google Antigravity: a named hook group in ~/.gemini/config/hooks.json
    }

    enum TimeoutUnit { case seconds, milliseconds }

    struct Descriptor {
        let source: String            // --source value (Factory uses "droid")
        let displayName: String
        let configDirRel: String      // relative to home, e.g. ".gemini"
        let configFileRel: String     // relative to configDir, e.g. "settings.json"
        let format: Format
        let timeoutUnit: TimeoutUnit
        /// Create the config dir if missing (Factory bootstraps it); otherwise
        /// skip silently when the tool isn't installed.
        let createDirIfMissing: Bool
        /// `passEventFlag` formats (flat/copilot) append `--event <name>` per
        /// entry because the tool's stdin omits the event name.
        let events: [(name: String, timeout: Int)]   // timeout in SECONDS
        /// Optional presence-detection paths (relative to home). When set,
        /// `installAll` installs only if ANY exists — used when the tool's
        /// install footprint differs from where we write hooks (e.g. Cline
        /// detected via VS Code globalStorage but hooks go in ~/Documents).
        var detectPaths: [String] = []
    }

    // MARK: - The 7 provider descriptors

    private static let standardEvents: [(String, Int)] = [
        ("UserPromptSubmit", 5), ("PreToolUse", 5), ("PostToolUse", 5),
        ("SessionStart", 5), ("SessionEnd", 5), ("Stop", 5),
        ("SubagentStart", 5), ("SubagentStop", 5), ("Notification", 5), ("PreCompact", 5),
    ]

    static let descriptors: [Descriptor] = [
        // BeforeTool gets a long timeout so the optional strict-approval prompt
        // has time to be answered; harmless otherwise (bridge returns instantly
        // when strict mode is off).
        Descriptor(source: "gemini", displayName: "Gemini",
                   configDirRel: ".gemini", configFileRel: "settings.json",
                   format: .nested, timeoutUnit: .milliseconds, createDirIfMissing: false,
                   events: [("SessionStart", 5), ("SessionEnd", 5), ("BeforeTool", 300),
                            ("AfterTool", 5), ("BeforeAgent", 5), ("AfterAgent", 5)]),

        Descriptor(source: "qwen", displayName: "Qwen Code",
                   configDirRel: ".qwen", configFileRel: "settings.json",
                   format: .claudeFork, timeoutUnit: .milliseconds, createDirIfMissing: false,
                   events: standardEvents + [("PostToolUseFailure", 5), ("PermissionRequest", 300)]),

        // Claude-Code forks — permission support differs per tool's docs:
        //  • Qwen + Qoder CLI document a Claude-IDENTICAL PermissionRequest
        //    (hookSpecificOutput.decision.behavior), so our existing Claude
        //    response works as-is. (Qoder's doesn't fire in headless `-p` mode
        //    — that's fine; it just no-ops there.)
        //  • Factory (droid) has NO PermissionRequest — it gates inside
        //    PreToolUse with a different shape. CodeBuddy lists the event but
        //    leaves it undocumented, so subscribing risks a hang. Both omit it.
        Descriptor(source: "qoder", displayName: "Qoder",
                   configDirRel: ".qoder", configFileRel: "settings.json",
                   format: .claudeFork, timeoutUnit: .seconds, createDirIfMissing: false,
                   events: standardEvents + [("PermissionRequest", 300)]),

        Descriptor(source: "droid", displayName: "Factory",
                   configDirRel: ".factory", configFileRel: "settings.json",
                   format: .claudeFork, timeoutUnit: .seconds, createDirIfMissing: true,
                   events: standardEvents),

        Descriptor(source: "codebuddy", displayName: "CodeBuddy",
                   configDirRel: ".codebuddy", configFileRel: "settings.json",
                   format: .claudeFork, timeoutUnit: .seconds, createDirIfMissing: false,
                   events: standardEvents),

        Descriptor(source: "cursor", displayName: "Cursor",
                   configDirRel: ".cursor", configFileRel: "hooks.json",
                   format: .flat, timeoutUnit: .seconds, createDirIfMissing: false,
                   // Shell/MCP execution get long timeouts for the optional
                   // strict-approval prompt (no-op when strict mode is off).
                   events: [("beforeSubmitPrompt", 5), ("beforeShellExecution", 300),
                            ("afterShellExecution", 5), ("beforeReadFile", 5), ("afterFileEdit", 5),
                            ("beforeMCPExecution", 300), ("afterMCPExecution", 5),
                            ("afterAgentThought", 5), ("afterAgentResponse", 5), ("stop", 5)]),

        Descriptor(source: "copilot", displayName: "Copilot",
                   configDirRel: ".copilot", configFileRel: "hooks/codeisland.json",
                   format: .copilot, timeoutUnit: .seconds, createDirIfMissing: false,
                   events: [("sessionStart", 5), ("sessionEnd", 5), ("userPromptSubmitted", 5),
                            ("preToolUse", 300), ("postToolUse", 5), ("errorOccurred", 5)]),

        // Kimi Code CLI — TOML [[hooks]] blocks. Seconds; max timeout 600 (no
        // PermissionRequest event). Don't bootstrap ~/.kimi for non-Kimi users.
        Descriptor(source: "kimi", displayName: "Kimi",
                   configDirRel: ".kimi", configFileRel: "config.toml",
                   format: .toml, timeoutUnit: .seconds, createDirIfMissing: false,
                   events: [("SessionStart", 5), ("SessionEnd", 5), ("UserPromptSubmit", 5),
                            ("PreToolUse", 300), ("PostToolUse", 5), ("Stop", 5),
                            ("SubagentStart", 5), ("SubagentStop", 5),
                            ("Notification", 600), ("PreCompact", 5)]),

        // OpenCode — JS plugin registered in opencode.json. The plugin maps
        // events itself, so `events` is unused here. Only if ~/.config/opencode.
        Descriptor(source: "opencode", displayName: "OpenCode",
                   configDirRel: ".config/opencode", configFileRel: "opencode.json",
                   format: .opencodePlugin, timeoutUnit: .seconds, createDirIfMissing: false,
                   events: []),

        // Cline — executable bash script per event in ~/Documents/Cline/Hooks.
        // Detected via VS Code globalStorage OR ~/Documents/Cline (footprint
        // differs from where we write), so don't litter Documents otherwise.
        Descriptor(source: "cline", displayName: "Cline",
                   configDirRel: "Documents/Cline/Hooks", configFileRel: "",
                   format: .clineScripts, timeoutUnit: .seconds, createDirIfMissing: false,
                   events: [("UserPromptSubmit", 5), ("PreToolUse", 5), ("PostToolUse", 5),
                            ("TaskStart", 5), ("TaskResume", 5), ("TaskCancel", 5),
                            ("TaskComplete", 5), ("PreCompact", 5)],
                   detectPaths: ["Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev",
                                 "Documents/Cline"]),

        // Kiro — agent-scoped JSON; fires only when launched as `kiro --agent codeisland`.
        // Detected on ~/.kiro; hooks land in the auto-created agents/ subdir.
        Descriptor(source: "kiro", displayName: "Kiro",
                   configDirRel: ".kiro/agents", configFileRel: "codeisland.json",
                   format: .kiroAgent, timeoutUnit: .milliseconds, createDirIfMissing: false,
                   events: [("agentSpawn", 5), ("userPromptSubmit", 5),
                            ("preToolUse", 5), ("postToolUse", 5), ("stop", 5)],
                   detectPaths: [".kiro"]),

        // Pi + Oh My Pi — TypeScript extension auto-discovered from the agent's extensions dir.
        Descriptor(source: "pi", displayName: "Pi",
                   configDirRel: ".pi/agent/extensions", configFileRel: "codeisland.ts",
                   format: .piExtension, timeoutUnit: .seconds, createDirIfMissing: false,
                   events: [], detectPaths: [".pi/agent"]),
        Descriptor(source: "omp", displayName: "Oh My Pi",
                   configDirRel: ".omp/agent/extensions", configFileRel: "codeisland.ts",
                   format: .piExtension, timeoutUnit: .seconds, createDirIfMissing: false,
                   events: [], detectPaths: [".omp/agent"]),

        // AntiGravity = Google's Gemini IDE/CLI (NOT a Claude fork — name collision
        // in the reference). Global hooks live in ~/.gemini/config/hooks.json
        // (shared with Gemini CLI's dir, but a different file). Detected via the
        // ~/.gemini/antigravity dir so Gemini-CLI-only users aren't touched.
        Descriptor(source: "antigravity", displayName: "AntiGravity",
                   configDirRel: ".gemini/config", configFileRel: "hooks.json",
                   format: .antigravityJSON, timeoutUnit: .seconds, createDirIfMissing: false,
                   events: [], detectPaths: [".gemini/antigravity"]),
        // Hermes = Nous Research's hermes-agent (NOT the reference's "Claude fork"
        // — name collision). Hooks live in ~/.hermes/config.yaml's `hooks:` map,
        // payload via stdin JSON, and must be approved once via `hermes hooks`
        // (or hooks_auto_accept). No clean turn-end event → session + tool only.
        Descriptor(source: "hermes", displayName: "Hermes",
                   configDirRel: ".hermes", configFileRel: "config.yaml",
                   format: .hermesYAML, timeoutUnit: .seconds, createDirIfMissing: false,
                   events: [("on_session_start", 5),
                            ("pre_llm_call", 5), ("post_llm_call", 5),
                            ("pre_tool_call", 5), ("post_tool_call", 5), ("subagent_stop", 5)]),
    ]

    // MARK: - Entry point

    @discardableResult
    static func installAll() -> Bool {
        var allOK = true
        for d in descriptors where shouldInstall(d) {
            if !install(d) { allOK = false }
        }
        return allOK
    }

    /// Manual reinstall for one provider (Settings → Integrations button).
    /// Installs even if the tool's dir is absent, pre-staging its config.
    @discardableResult
    static func installSource(_ source: String) -> Bool {
        guard let d = descriptors.first(where: { $0.source == source }) else { return false }
        return install(d)
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private static func configDir(_ d: Descriptor) -> URL {
        home.appendingPathComponent(d.configDirRel)
    }

    /// Install only when the tool is present, unless the descriptor opts into
    /// bootstrapping it. Presence = any `detectPaths` entry exists, else the
    /// config dir exists.
    private static func shouldInstall(_ d: Descriptor) -> Bool {
        if d.createDirIfMissing { return true }
        if !d.detectPaths.isEmpty {
            return d.detectPaths.contains {
                FileManager.default.fileExists(atPath: home.appendingPathComponent($0).path)
            }
        }
        return FileManager.default.fileExists(atPath: configDir(d).path)
    }

    @discardableResult
    static func install(_ d: Descriptor) -> Bool {
        installLauncher(source: d.source)

        // Formats with a non-JSON-file layout handle their own dir creation.
        switch d.format {
        case .toml:           return installKimiTOML(d)
        case .opencodePlugin: return installOpenCodePlugin(d)
        case .clineScripts:   return installClineScripts(d)
        case .piExtension:    return installPiExtension(d)
        case .hermesYAML:     return installHermesYAML(d)
        case .antigravityJSON: return installAntigravityJSON(d)
        case .claudeFork, .nested, .flat, .copilot, .kiroAgent:
            break  // JSON-file path below (kiroAgent reuses the merge writer)
        }

        let fileURL = configDir(d).appendingPathComponent(d.configFileRel)
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            Log.error("ProviderInstaller(\(d.source)): can't create \(fileURL.path): \(error)")
            return false
        }

        let ok: Bool
        switch d.format {
        case .claudeFork, .nested: ok = writeJSONHooks(d, at: fileURL)
        case .flat:                ok = writeFlatHooks(d, at: fileURL)
        case .copilot:             ok = writeCopilotHooks(d, at: fileURL)
        case .kiroAgent:           ok = writeKiroAgent(d, at: fileURL)
        default:                   ok = false  // handled above
        }
        print("[CodeIsland] \(d.displayName) hooks \(ok ? "installed" : "FAILED") at \(fileURL.path)")
        return ok
    }

    // MARK: - Command + launcher

    /// The hook command for a descriptor. For flat/copilot formats the event
    /// name is appended per call site (see writers); this is the bare launcher.
    private static func launcherCommand(_ source: String) -> String {
        "\(home.path)/.code-island/bin/code-island-\(source)-bridge"
    }

    /// Writes `~/.code-island/bin/code-island-<source>-bridge` — a zsh shim that
    /// finds the app's bundled bridge and `exec`s it with `--source <source>`,
    /// forwarding any extra args (e.g. `--event <name>`) via "$@".
    private static func installLauncher(source: String) {
        let binDir = home.appendingPathComponent(".code-island/bin")
        try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let launcher = binDir.appendingPathComponent("code-island-\(source)-bridge")
        let script = [
            "#!/bin/zsh",
            "# code-island-\(source)-bridge launcher (auto-generated by Code Island)",
            "H=/Contents/Helpers/CodeIslandBridge",
            "for P in \"/Applications/Code Island.app\" \"$HOME/Applications/Code Island.app\"; do",
            "  B=\"${P}${H}\"; [ -x \"$B\" ] && exec \"$B\" --source \(source) \"$@\"",
            "done",
            "D=\"$HOME/Projects/code-island/.build/release/CodeIslandBridge\"",
            "[ -x \"$D\" ] && exec \"$D\" --source \(source) \"$@\"",
            "D=\"$HOME/Projects/code-island/.build/debug/CodeIslandBridge\"",
            "[ -x \"$D\" ] && exec \"$D\" --source \(source) \"$@\"",
            "echo \"code-island-\(source)-bridge: app not found.\" >&2",
            "exit 127",
        ].joined(separator: "\n")
        try? script.write(to: launcher, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
    }

    private static func timeoutValue(_ seconds: Int, _ unit: TimeoutUnit) -> Int {
        unit == .milliseconds ? seconds * 1000 : seconds
    }

    private static let marker = "code-island"

    // MARK: - JSON writers

    /// claudeFork + nested: a top-level `hooks` object keyed by event.
    private static func writeJSONHooks(_ d: Descriptor, at url: URL) -> Bool {
        let cmd = launcherCommand(d.source)
        return mergeJSONObject(at: url) { root in
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            for (event, secs) in d.events {
                var entries = (hooks[event] as? [[String: Any]] ?? []).filter { !isOurs($0) }
                let inner: [String: Any] = ["type": "command", "command": cmd,
                                            "timeout": timeoutValue(secs, d.timeoutUnit)]
                var entry: [String: Any] = ["hooks": [inner]]
                if d.format == .claudeFork { entry["matcher"] = "*" }
                entries.append(entry)
                hooks[event] = entries
            }
            root["hooks"] = hooks
        }
    }

    /// flat (Cursor): `hooks` keyed by event → array of `{command}` where the
    /// command carries `--event <eventName>`.
    private static func writeFlatHooks(_ d: Descriptor, at url: URL) -> Bool {
        let base = launcherCommand(d.source)
        return mergeJSONObject(at: url) { root in
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            for (event, _) in d.events {
                var entries = (hooks[event] as? [[String: Any]] ?? []).filter { !isOursFlat($0) }
                entries.append(["command": "\(base) --event \(event)"])
                hooks[event] = entries
            }
            root["hooks"] = hooks
        }
    }

    /// copilot: top-level `version:1` + `hooks` keyed by event → array of
    /// `{type, bash, timeoutSec}` where bash carries `--event <eventName>`.
    private static func writeCopilotHooks(_ d: Descriptor, at url: URL) -> Bool {
        let base = launcherCommand(d.source)
        return mergeJSONObject(at: url) { root in
            if root["version"] == nil { root["version"] = 1 }
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            for (event, secs) in d.events {
                var entries = (hooks[event] as? [[String: Any]] ?? []).filter {
                    !(($0["bash"] as? String)?.contains(marker) ?? false)
                }
                entries.append(["type": "command", "bash": "\(base) --event \(event)", "timeoutSec": secs])
                hooks[event] = entries
            }
            root["hooks"] = hooks
        }
    }

    // MARK: - Merge helpers

    /// Identifies one of OUR claudeFork/nested entries (inner hook command
    /// contains the marker) so reinstalls replace rather than duplicate.
    private static func isOurs(_ entry: [String: Any]) -> Bool {
        guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
        return inner.contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    private static func isOursFlat(_ entry: [String: Any]) -> Bool {
        (entry["command"] as? String)?.contains(marker) == true
    }

    /// Read-modify-write a JSON object file: parse existing (bail if present but
    /// unparseable), apply `mutate`, back up + write only if changed.
    private static func mergeJSONObject(at url: URL, _ mutate: (inout [String: Any]) -> Void) -> Bool {
        var root: [String: Any] = [:]
        let existing = try? Data(contentsOf: url)
        if let data = existing, !data.isEmpty {
            guard let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                Log.error("ProviderInstaller: \(url.path) exists but isn't valid JSON. Refusing to overwrite.")
                return false
            }
            root = parsed
        }
        mutate(&root)

        guard let newData = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]) else {
            Log.error("ProviderInstaller: failed to serialize \(url.path)")
            return false
        }
        if let existing, normalized(existing) == normalized(newData) { return true }
        if let existing, !existing.isEmpty {
            try? existing.write(to: url.appendingPathExtension("bak"), options: .atomic)
        }
        do {
            try newData.write(to: url, options: .atomic)
            return true
        } catch {
            Log.error("ProviderInstaller: failed to write \(url.path): \(error)")
            return false
        }
    }

    private static func normalized(_ data: Data) -> Data? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    }

    // MARK: - Kimi (TOML)

    private static let kimiBegin = "# >>> code-island kimi hooks (auto-generated) >>>"
    private static let kimiEnd   = "# <<< code-island kimi hooks <<<"

    /// Appends a marker-delimited block of `[[hooks]]` tables to config.toml.
    /// Reinstalls replace the prior block (between the markers); foreign TOML is
    /// preserved. A legacy scalar `hooks = …` line (would collide with the
    /// array-of-tables) is commented out.
    private static func installKimiTOML(_ d: Descriptor) -> Bool {
        let fileURL = configDir(d).appendingPathComponent(d.configFileRel)
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let cmd = launcherCommand(d.source)

        var blocks: [String] = []
        for (event, secs) in d.events {
            var lines = ["[[hooks]]", "event = \"\(event)\"",
                         "command = \"\(cmd)\"", "timeout = \(timeoutValue(secs, d.timeoutUnit))"]
            if ["PreToolUse", "PostToolUse", "PostToolUseFailure"].contains(event) {
                lines.append("matcher = \".*\"")
            }
            blocks.append(lines.joined(separator: "\n"))
        }
        let ourSection = ([kimiBegin] + blocks + [kimiEnd]).joined(separator: "\n\n")

        let existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        var body = existing
        // Strip any prior block we wrote (inclusive of markers).
        if let s = body.range(of: kimiBegin), let e = body.range(of: kimiEnd) {
            body.removeSubrange(s.lowerBound..<e.upperBound)
        }
        // Comment out a legacy scalar `hooks = …` (not `[[hooks]]`).
        body = body.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("hooks") && t.contains("=") && !t.hasPrefix("[") {
                return "# [CodeIsland] commented out legacy scalar hooks to avoid TOML conflict\n# \(line)"
            }
            return String(line)
        }.joined(separator: "\n")

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let newText = trimmed.isEmpty ? ourSection + "\n" : trimmed + "\n\n" + ourSection + "\n"

        if newText == existing { return true }
        if !existing.isEmpty {
            try? existing.write(to: fileURL.appendingPathExtension("bak"), atomically: true, encoding: .utf8)
        }
        do {
            try newText.write(to: fileURL, atomically: true, encoding: .utf8)
            print("[CodeIsland] Kimi hooks installed at \(fileURL.path)")
            return true
        } catch {
            Log.error("ProviderInstaller(kimi): write failed: \(error)")
            return false
        }
    }

    // MARK: - OpenCode (JS plugin + config registration)

    /// Writes the plugin JS and adds a `file://` ref to opencode.json's
    /// `plugin` array (preferring an existing .jsonc). Skips silently if the
    /// config exists but can't be parsed (won't corrupt a hand-edited file).
    private static func installOpenCodePlugin(_ d: Descriptor) -> Bool {
        let ocDir = configDir(d)                              // ~/.config/opencode
        let pluginsDir = ocDir.appendingPathComponent("plugins")
        do {
            try FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        } catch {
            Log.error("ProviderInstaller(opencode): can't create \(pluginsDir.path): \(error)")
            return false
        }
        let pluginURL = pluginsDir.appendingPathComponent("codeisland.js")
        // The plugin computes the bridge path at runtime (os.homedir); static.
        if (try? String(contentsOf: pluginURL, encoding: .utf8)) != openCodePluginJS {
            try? openCodePluginJS.write(to: pluginURL, atomically: true, encoding: .utf8)
        }

        // Register in opencode.jsonc if it exists, else opencode.json.
        let jsoncURL = ocDir.appendingPathComponent("opencode.jsonc")
        let configURL = FileManager.default.fileExists(atPath: jsoncURL.path)
            ? jsoncURL : ocDir.appendingPathComponent("opencode.json")
        let ok = registerOpenCodePlugin(at: configURL, pluginPath: pluginURL.path)
        print("[CodeIsland] OpenCode plugin \(ok ? "installed" : "FAILED") (\(pluginURL.path))")
        return ok
    }

    private static func registerOpenCodePlugin(at url: URL, pluginPath: String) -> Bool {
        let ref = "file://\(pluginPath)"
        let existing = try? Data(contentsOf: url)
        var root: [String: Any] = [:]
        if let data = existing, !data.isEmpty {
            let text = String(data: data, encoding: .utf8) ?? ""
            let stripped = stripJSONComments(text)
            guard let parsed = (try? JSONSerialization.jsonObject(
                with: Data(stripped.utf8))) as? [String: Any] else {
                Log.error("ProviderInstaller(opencode): \(url.path) isn't valid JSON(C). Refusing to overwrite.")
                return false
            }
            root = parsed
        }
        if root["$schema"] == nil { root["$schema"] = "https://opencode.ai/config.json" }
        var plugins = (root["plugin"] as? [String] ?? []).filter {
            !$0.contains("codeisland") && !$0.contains("code-island")
        }
        plugins.append(ref)
        root["plugin"] = plugins

        guard let newData = try? JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted]) else { return false }
        if let existing, normalized(existing) == normalized(newData) { return true }
        if let existing, !existing.isEmpty {
            try? existing.write(to: url.appendingPathExtension("bak"), options: .atomic)
        }
        do { try newData.write(to: url, options: .atomic); return true }
        catch { Log.error("ProviderInstaller(opencode): write failed: \(error)"); return false }
    }

    /// String/escape-aware removal of `//` and `/* */` comments so a JSONC
    /// config (and `https://` inside strings) parses correctly.
    private static func stripJSONComments(_ text: String) -> String {
        var out = ""
        var inString = false, escaped = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                i += 1
                continue
            }
            if c == "\"" { inString = true; out.append(c); i += 1; continue }
            if c == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
                while i < chars.count && chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/" && i + 1 < chars.count && chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i += 2
                continue
            }
            out.append(c); i += 1
        }
        return out
    }

    // MARK: - Cline (executable bash scripts)

    /// Writes one executable bash script per event into ~/Documents/Cline/Hooks.
    /// Each pipes stdin to our launcher with `--event <name>`, backgrounds it,
    /// and prints `{"cancel":false}` (Cline blocks on the hook + demands JSON).
    private static func installClineScripts(_ d: Descriptor) -> Bool {
        let hooksDir = configDir(d)                          // ~/Documents/Cline/Hooks
        do {
            try FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        } catch {
            Log.error("ProviderInstaller(cline): can't create \(hooksDir.path): \(error)")
            return false
        }
        let cmd = launcherCommand(d.source)
        var allOK = true
        for (event, _) in d.events {
            let script = [
                "#!/bin/bash",
                "INPUT=$(cat)",
                "printf '%s' \"$INPUT\" | \(cmd) --event \(event) \"$@\" >/dev/null 2>&1 &",
                "printf '{\"cancel\":false}'",
                "",
            ].joined(separator: "\n")
            let fileURL = hooksDir.appendingPathComponent(event)
            let current = try? String(contentsOf: fileURL, encoding: .utf8)
            if current != script {
                do { try script.write(to: fileURL, atomically: true, encoding: .utf8) }
                catch { Log.error("ProviderInstaller(cline): write \(event) failed: \(error)"); allOK = false; continue }
            }
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)
        }
        print("[CodeIsland] Cline hooks \(allOK ? "installed" : "FAILED") at \(hooksDir.path)")
        return allOK
    }

    // MARK: - Hermes (Nous Research — config.yaml `hooks:` map)

    private static let hermesMarker = "# code-island-managed"

    /// Replaces the `hooks:` map in ~/.hermes/config.yaml with our entries.
    /// SAFE: only touches the top-level `hooks:` block, and only if it's empty
    /// (`hooks: {}`) or already ours — bails on user-authored hooks. Backs up
    /// to .bak. Hermes still requires the user to approve via `hermes hooks`
    /// (or set `hooks_auto_accept`) before the hooks fire.
    private static func installHermesYAML(_ d: Descriptor) -> Bool {
        let fileURL = configDir(d).appendingPathComponent(d.configFileRel)   // ~/.hermes/config.yaml
        guard let existing = try? String(contentsOf: fileURL, encoding: .utf8) else {
            Log.info("ProviderInstaller(hermes): no config.yaml — skipping (Hermes not set up)")
            return true
        }
        let cmd = launcherCommand(d.source)
        var block = ["hooks:", "  \(hermesMarker) — regenerated by Code Island"]
        for (event, secs) in d.events {
            block.append("  \(event):")
            block.append("    - command: '\(cmd.replacingOccurrences(of: "'", with: "''"))'")
            block.append("      timeout: \(secs)")
        }
        let ourBlock = block.joined(separator: "\n")

        var lines = existing.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.hasPrefix("hooks:") }) else {
            Log.error("ProviderInstaller(hermes): no top-level `hooks:` key — refusing to add")
            return false
        }
        // Extent of the current hooks block: the key line + following indented lines.
        var end = start + 1
        while end < lines.count, lines[end].hasPrefix(" ") || lines[end].hasPrefix("\t") { end += 1 }
        let current = lines[start..<end].joined(separator: "\n")
        let isEmpty = lines[start].trimmingCharacters(in: .whitespaces) == "hooks: {}"
            || (end == start + 1 && lines[start].trimmingCharacters(in: .whitespaces) == "hooks:")
        guard isEmpty || current.contains(hermesMarker) else {
            Log.error("ProviderInstaller(hermes): config.yaml `hooks:` has user content — not overwriting")
            return false
        }
        lines.replaceSubrange(start..<end, with: [ourBlock])
        let newText = lines.joined(separator: "\n")
        if newText == existing { return true }
        try? existing.write(to: fileURL.appendingPathExtension("bak"), atomically: true, encoding: .utf8)
        do { try newText.write(to: fileURL, atomically: true, encoding: .utf8)
             print("[CodeIsland] Hermes hooks written to \(fileURL.path) (approve via `hermes hooks`)"); return true }
        catch { Log.error("ProviderInstaller(hermes): write failed: \(error)"); return false }
    }

    // MARK: - AntiGravity (Google — ~/.gemini/config/hooks.json named group)

    /// Writes a "code-island" hook group into ~/.gemini/config/hooks.json.
    /// Tool events use `{matcher, hooks:[…]}`; invocation/stop events use bare
    /// `{type,command}`. Event name is passed via `--event` (the payload has no
    /// event-name field). NOTE: Antigravity caches hooks at daemon startup, so
    /// a running session must be restarted to pick these up.
    private static func installAntigravityJSON(_ d: Descriptor) -> Bool {
        let fileURL = configDir(d).appendingPathComponent(d.configFileRel)   // ~/.gemini/config/hooks.json
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let cmd = launcherCommand(d.source)
        func handler(_ event: String) -> [String: Any] {
            ["type": "command", "command": "\(cmd) --event \(event)", "timeout": 10]
        }
        let ok = mergeJSONObject(at: fileURL) { root in
            root["code-island"] = [
                "enabled": true,
                "PreInvocation": [handler("PreInvocation")],
                "Stop": [handler("Stop")],
                "PreToolUse":  [["matcher": "*", "hooks": [handler("PreToolUse")]]],
                "PostToolUse": [["matcher": "*", "hooks": [handler("PostToolUse")]]],
            ]
        }
        print("[CodeIsland] AntiGravity hooks \(ok ? "installed" : "FAILED") in \(fileURL.path) (restart AntiGravity to load)")
        return ok
    }

    // MARK: - Kiro (agent-scoped JSON)

    /// hooks keyed by event → [{command, matcher:"*", timeout_ms}]; seeds the
    /// agent skeleton (requires "name") so `kiro --agent codeisland` works.
    private static func writeKiroAgent(_ d: Descriptor, at url: URL) -> Bool {
        let cmd = launcherCommand(d.source)
        return mergeJSONObject(at: url) { root in
            if root["name"] == nil { root["name"] = "codeisland" }
            if root["description"] == nil {
                root["description"] = "Auto-generated by Code Island — relays Kiro hook events to the macOS notch. Launch with `kiro-cli --agent codeisland`."
            }
            // `matcher` is only valid for the tool events (it matches tool names);
            // adding it to agentSpawn/userPromptSubmit/stop is ignored at best.
            let toolEvents: Set<String> = ["preToolUse", "postToolUse"]
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            for (event, secs) in d.events {
                var entries = (hooks[event] as? [[String: Any]] ?? []).filter {
                    !(($0["command"] as? String)?.contains(marker) ?? false)
                }
                var entry: [String: Any] = ["command": cmd, "timeout_ms": timeoutValue(secs, .milliseconds)]
                if toolEvents.contains(event) { entry["matcher"] = "*" }
                entries.append(entry)
                hooks[event] = entries
            }
            root["hooks"] = hooks
        }
    }

    // MARK: - Pi / Oh My Pi (TypeScript extension)

    private enum PiImportScope { case pi, omp }

    /// Writes a TypeScript extension that shells out to our launcher (JSON on
    /// stdin + --event). Gated on the agent root existing; idempotent.
    private static func installPiExtension(_ d: Descriptor) -> Bool {
        let extDir = configDir(d)                              // ~/.pi/agent/extensions
        do { try FileManager.default.createDirectory(at: extDir, withIntermediateDirectories: true) }
        catch { Log.error("ProviderInstaller(\(d.source)): can't create \(extDir.path): \(error)"); return false }
        let fileURL = extDir.appendingPathComponent(d.configFileRel)
        let src = piExtensionTS(source: d.source, scope: d.source == "omp" ? .omp : .pi)
        if (try? String(contentsOf: fileURL, encoding: .utf8)) != src {
            do { try src.write(to: fileURL, atomically: true, encoding: .utf8) }
            catch { Log.error("ProviderInstaller(\(d.source)): write failed: \(error)"); return false }
        }
        print("[CodeIsland] \(d.displayName) extension installed at \(fileURL.path)")
        return true
    }

    private static func piExtensionTS(source: String, scope: PiImportScope) -> String {
        let launcher = launcherCommand(source)
        let importLine = scope == .omp
            ? #"import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent/extensibility/extensions/types";"#
            : #"import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";"#
        return """
// Code Island \(source) extension — auto-generated. Do not edit.
// Forwards \(source) lifecycle events to the Code Island macOS app by shelling
// out to the per-source launcher (JSON on stdin + --event <canonical>).
import { execFile } from "node:child_process";
\(importLine)

const LAUNCHER = "\(launcher)";

function send(event, payload) {
  try {
    const child = execFile(LAUNCHER, ["--event", event],
      { timeout: 8000, maxBuffer: 1024 * 1024 }, () => {});
    child.stdin.write(JSON.stringify(payload)); child.stdin.end();
  } catch {}
}
function sendAndWait(event, payload, timeoutMs = 300000) {
  return new Promise((resolve) => {
    try {
      const child = execFile(LAUNCHER, ["--event", event],
        { timeout: timeoutMs, maxBuffer: 1024 * 1024 }, (error, stdout) => {
          if (error) { resolve(null); return; }
          try { resolve(JSON.parse(stdout)); } catch { resolve(null); }
        });
      child.stdin.write(JSON.stringify(payload)); child.stdin.end();
    } catch { resolve(null); }
  });
}
const DANGEROUS = [/\\brm\\s+(-rf?|--recursive)/i, /\\bsudo\\b/i, /\\b(chmod|chown)\\b.*777/i];
const isDangerous = (cmd) => DANGEROUS.some((p) => p.test(cmd));
const titled = (n) => (n || "").charAt(0).toUpperCase() + (n || "").slice(1);
function base(sid, cwd, extra) { return { session_id: `\(source)-${sid}`, _source: "\(source)", cwd, ...extra }; }
function lastAssistant(messages) {
  const a = (messages || []).filter((m) => m && m.role === "assistant");
  const last = a[a.length - 1];
  if (!last || !Array.isArray(last.content)) return "";
  return last.content.filter((c) => c && c.type === "text").map((c) => c.text).join("").trim();
}

export default function codeislandExtension(pi: ExtensionAPI) {
  const pending = new Set();
  pi.on("session_start", async (_e, ctx) => {
    const name = pi.getSessionName();
    send("SessionStart", base(ctx.sessionManager.getSessionId(), ctx.cwd, { hook_event_name: "SessionStart", ...(name ? { session_title: name } : {}) }));
  });
  pi.on("session_shutdown", async (_e, ctx) => {
    send("SessionEnd", base(ctx.sessionManager.getSessionId(), ctx.cwd, { hook_event_name: "SessionEnd" }));
  });
  pi.on("before_agent_start", async (event, ctx) => {
    const sid = ctx.sessionManager.getSessionId();
    if (pending.has(`\(source)-${sid}`)) return;
    send("UserPromptSubmit", base(sid, ctx.cwd, { hook_event_name: "UserPromptSubmit", prompt: event.prompt ?? "" }));
  });
  pi.on("agent_end", async (event, ctx) => {
    const sid = ctx.sessionManager.getSessionId();
    if (pending.has(`\(source)-${sid}`)) return;
    const last = lastAssistant(event.messages);
    const name = pi.getSessionName();
    send("Stop", base(sid, ctx.cwd, { hook_event_name: "Stop", last_assistant_message: last || undefined, ...(name ? { session_title: name } : {}) }));
  });
  pi.on("tool_call", async (event, ctx) => {
    const sid = ctx.sessionManager.getSessionId();
    const key = `\(source)-${sid}`;
    const toolName = titled(event.toolName);
    const toolInput = { ...event.input };
    if (event.toolName === "bash" && event.input.command) toolInput.command = event.input.command;
    if ((event.toolName === "edit" || event.toolName === "write") && event.input.path) toolInput.file_path = event.input.path;
    if (event.toolName === "bash" && typeof event.input.command === "string" && isDangerous(event.input.command)) {
      pending.add(key);
      const payload = base(sid, ctx.cwd, { hook_event_name: "PermissionRequest", tool_name: toolName, tool_input: toolInput });
      let resp = null;
      try { resp = await sendAndWait("PermissionRequest", payload); } finally { pending.delete(key); }
      const decision = resp?.hookSpecificOutput?.decision;
      if (decision?.behavior === "deny") return { block: true, reason: "Blocked by Code Island" };
    }
    if (!pending.has(key)) send("PreToolUse", base(sid, ctx.cwd, { hook_event_name: "PreToolUse", tool_name: toolName, tool_input: toolInput }));
    return undefined;
  });
  pi.on("tool_result", async (_e, ctx) => {
    const sid = ctx.sessionManager.getSessionId();
    if (pending.has(`\(source)-${sid}`)) return;
    send("PostToolUse", base(sid, ctx.cwd, { hook_event_name: "PostToolUse" }));
  });
  pi.on("session_before_compact", async (_e, ctx) => {
    send("PreCompact", base(ctx.sessionManager.getSessionId(), ctx.cwd, { hook_event_name: "PreCompact" }));
  });
}
"""
    }

    // MARK: - OpenCode plugin source

    /// The OpenCode plugin: maps OpenCode's event vocabulary → our canonical
    /// events and shells out to code-island-opencode-bridge (JSON on stdin,
    /// `--event <name>`). Blocking events (permission/question) read the
    /// bridge's stdout decision and reply via OpenCode's HTTP API.
    private static let openCodePluginJS = #"""
// code-island-opencode plugin — auto-generated by Code Island. Do not edit.
import { execFile } from "child_process";
import { homedir } from "os";
import { join } from "path";

const BRIDGE = join(homedir(), ".code-island", "bin", "code-island-opencode-bridge");

function send(canonicalEvent, payload) {
  try {
    const child = execFile(BRIDGE, ["--source", "opencode", "--event", canonicalEvent],
      { timeout: 8000, maxBuffer: 1024 * 1024 }, () => {});
    child.stdin.write(JSON.stringify(payload));
    child.stdin.end();
  } catch {}
}

function sendAndWait(canonicalEvent, payload, timeoutMs = 300000) {
  return new Promise((resolve) => {
    try {
      const child = execFile(BRIDGE, ["--source", "opencode", "--event", canonicalEvent],
        { timeout: timeoutMs, maxBuffer: 1024 * 1024 }, (error, stdout) => {
          if (error) { resolve(null); return; }
          try { resolve(JSON.parse(stdout)); } catch { resolve(null); }
        });
      child.stdin.write(JSON.stringify(payload));
      child.stdin.end();
    } catch { resolve(null); }
  });
}

export default {
  id: "codeisland",
  server: async ({ client, serverUrl }) => {
    const serverPort = serverUrl ? (parseInt(serverUrl.port) || 4096) : 4096;
    const heyApi = client?._client;

    const sessionCwd = new Map();
    const msgRoles = new Map();
    const lastAssistant = new Map();

    function base(sid, extra) {
      return { session_id: `opencode-${sid}`, _source: "opencode", ...extra };
    }

    async function replyPermission(requestId, reply, reason) {
      try {
        if (typeof heyApi?.request === "function") {
          await heyApi.request({ method: "POST", url: "/permission/{requestID}/reply",
            path: { requestID: requestId }, body: { reply, message: reason } });
          return;
        }
      } catch {}
      try {
        await fetch(`http://localhost:${serverPort}/permission/${requestId}/reply`, {
          method: "POST", headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ reply, message: reason }) });
      } catch {}
    }

    async function replyQuestion(requestId, answers) {
      try {
        if (typeof heyApi?.request === "function") {
          await heyApi.request({ method: "POST", url: "/question/{requestID}/reply",
            path: { requestID: requestId }, body: { answers } });
          return;
        }
      } catch {}
      try {
        await fetch(`http://localhost:${serverPort}/question/${requestId}/reply`, {
          method: "POST", headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ answers }) });
      } catch {}
    }

    async function rejectQuestion(requestId) {
      try {
        if (typeof heyApi?.request === "function") {
          await heyApi.request({ method: "POST", url: "/question/{requestID}/reject",
            path: { requestID: requestId } });
          return;
        }
      } catch {}
      try {
        await fetch(`http://localhost:${serverPort}/question/${requestId}/reject`, {
          method: "POST", headers: { "Content-Type": "application/json" } });
      } catch {}
    }

    return {
      "event": async ({ event }) => {
        const t = event.type;
        const p = event.properties || {};

        if (t === "session.created" && p.info) {
          sessionCwd.set(p.info.id, p.info.directory || "");
          send("SessionStart", base(p.info.id, { hook_event_name: "SessionStart", cwd: p.info.directory || "" }));
          return;
        }
        if (t === "session.deleted" && p.info) {
          sessionCwd.delete(p.info.id); lastAssistant.delete(p.info.id);
          send("SessionEnd", base(p.info.id, { hook_event_name: "SessionEnd" }));
          return;
        }
        if (t === "session.updated" && p.info?.time?.archived) {
          sessionCwd.delete(p.info.id); lastAssistant.delete(p.info.id);
          send("SessionEnd", base(p.info.id, { hook_event_name: "SessionEnd" }));
          return;
        }

        if (t === "session.status" && p.sessionID && p.status?.type === "idle") {
          send("Stop", base(p.sessionID, { hook_event_name: "Stop",
            cwd: sessionCwd.get(p.sessionID),
            last_assistant_message: lastAssistant.get(p.sessionID) || undefined }));
          return;
        }

        if (t === "message.updated" && p.info?.id && p.info?.sessionID) {
          msgRoles.set(p.info.id, { role: p.info.role, sessionID: p.info.sessionID });
          if (msgRoles.size > 200) msgRoles.delete(msgRoles.keys().next().value);
          return;
        }
        if (t === "message.part.updated" && p.part?.type === "text" && p.part?.messageID) {
          const meta = msgRoles.get(p.part.messageID);
          if (!meta) return;
          const text = p.part.text || "";
          if (meta.role === "user" && text) {
            send("UserPromptSubmit", base(meta.sessionID, { hook_event_name: "UserPromptSubmit",
              cwd: sessionCwd.get(meta.sessionID), prompt: text }));
          } else if (meta.role === "assistant" && text) {
            lastAssistant.set(meta.sessionID, text);
          }
          return;
        }

        if (t === "message.part.updated" && p.part?.type === "tool" && p.part?.sessionID) {
          const st = p.part.state?.status;
          const tool = (p.part.tool || "");
          const toolName = tool.charAt(0).toUpperCase() + tool.slice(1);
          const cwd = sessionCwd.get(p.part.sessionID);
          if (st === "running" || st === "pending") {
            send("PreToolUse", base(p.part.sessionID, { hook_event_name: "PreToolUse",
              cwd, tool_name: toolName, tool_input: p.part.state?.input || {} }));
          } else if (st === "completed" || st === "error") {
            send("PostToolUse", base(p.part.sessionID, { hook_event_name: "PostToolUse",
              cwd, tool_name: toolName }));
          }
          return;
        }

        if (t === "permission.asked" && p.id && p.sessionID) {
          const perm = p.permission || "";
          const toolName = perm.charAt(0).toUpperCase() + perm.slice(1);
          const patterns = p.patterns || [];
          const toolInput = { patterns, metadata: p.metadata };
          if (perm === "bash" && patterns.length) toolInput.command = patterns.join(" && ");
          if ((perm === "edit" || perm === "write") && patterns.length) toolInput.file_path = patterns[0];
          const payload = base(p.sessionID, { hook_event_name: "PermissionRequest",
            cwd: sessionCwd.get(p.sessionID), tool_name: toolName, tool_input: toolInput });
          const resp = await sendAndWait("PermissionRequest", payload);
          const decision = resp?.hookSpecificOutput?.decision;
          const behavior = decision?.behavior;
          if (!behavior) return;
          const hasUpdated = decision?.updatedPermissions != null;
          const reply = (behavior === "always" || (behavior === "allow" && hasUpdated)) ? "always"
            : behavior === "allow" ? "once" : "reject";
          await replyPermission(p.id, reply, decision?.reason);
          return;
        }
        if (t === "permission.replied" && p.sessionID) {
          send("PostToolUse", base(p.sessionID, { hook_event_name: "PostToolUse",
            cwd: sessionCwd.get(p.sessionID) }));
          return;
        }

        if (t === "question.asked" && p.id && p.sessionID) {
          const questions = (p.questions || []).map((q) => ({
            question: q.question || "", header: q.header || "",
            options: (q.options || []).map((o) => ({ label: o.label, description: o.description })),
            multiSelect: q.multiple || false }));
          const payload = base(p.sessionID, { hook_event_name: "PermissionRequest",
            cwd: sessionCwd.get(p.sessionID), tool_name: "AskUserQuestion",
            tool_input: { questions } });
          const resp = await sendAndWait("PermissionRequest", payload);
          const decision = resp?.hookSpecificOutput?.decision;
          if (!decision) return;
          if (decision.behavior === "deny") { await rejectQuestion(p.id); return; }
          const answers = decision?.updatedInput?.answers;
          if (!answers) return;
          await replyQuestion(p.id, Object.values(answers).map((v) => [v]));
          return;
        }
        if ((t === "question.replied" || t === "question.rejected") && p.sessionID) {
          send("PostToolUse", base(p.sessionID, { hook_event_name: "PostToolUse",
            cwd: sessionCwd.get(p.sessionID) }));
          return;
        }
      },
    };
  },
};
"""#
}
