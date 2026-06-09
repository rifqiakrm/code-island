import Foundation

/// Codex doesn't support Claude's `updatedPermissions` shape — sending it back
/// produces an `unsupported updatedPermissions` error. The Codex-native way to
/// persist an "always allow" decision is to append a `prefix_rule(...)` block
/// to `~/.codex/rules/codeisland.rules`. Codex consults this file on every
/// permission request and auto-approves matching tool calls.
enum CodexPermissionRules {
    /// Returns the directory `$CODEX_HOME` resolves to (honors the env var,
    /// expands `~`, falls back to `~/.codex`). Mirrors the helper in
    /// `CodexInstaller`.
    private static var codexHome: URL {
        let raw = (ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "")
            .trimmingCharacters(in: .whitespaces)
        let home = FileManager.default.homeDirectoryForCurrentUser
        if raw.isEmpty { return home.appendingPathComponent(".codex") }
        if raw == "~" { return home }
        if raw.hasPrefix("~/") { return home.appendingPathComponent(String(raw.dropFirst(2))) }
        return URL(fileURLWithPath: raw)
    }

    /// Persist an "always allow" rule for a tool call. Returns true if the
    /// rule was written (or already exists), false if there's nothing usable
    /// to pattern on (e.g. a Bash event with no command string).
    ///
    /// - For `Bash`: the first 3 tokens of the command become the prefix
    ///   (`git commit -m "..."` → `["git", "commit", "-m"]`). This is the
    ///   same heuristic the reference repo uses.
    /// - For other tools: we fall back to matching on the tool name alone
    ///   so that `Write` / `Read` / etc. can be allow-listed too.
    /// - When `broad == true`, we widen the match to just the first token
    ///   (Bash: `["git"]` matches all git commands; other tools: same as
    ///   normal). We can't write a wildcard rule — Codex rejects empty
    ///   patterns — so true "bypass everything" isn't possible. This is the
    ///   closest practical equivalent: allow the whole tool family.
    @discardableResult
    static func persistAlwaysAllow(toolName: String, toolInput: String?, broad: Bool = false) -> Bool {
        let rulesDir = codexHome.appendingPathComponent("rules")
        let rulesFile = rulesDir.appendingPathComponent("codeisland.rules")
        try? FileManager.default.createDirectory(at: rulesDir, withIntermediateDirectories: true)

        var pattern = prefixPattern(toolName: toolName, toolInput: toolInput)
        if broad && !pattern.isEmpty {
            pattern = [pattern[0]]
        }
        guard !pattern.isEmpty else { return false }

        let block = ruleBlock(for: pattern, broad: broad)
        let patternLine = patternLineFor(pattern: pattern)

        let existing = (try? String(contentsOf: rulesFile, encoding: .utf8)) ?? ""
        if existing.contains(patternLine), existing.contains(#"decision = "allow""#) {
            return true
        }

        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let updated = existing + separator + block
        do {
            try updated.write(to: rulesFile, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Pattern building

    private static func prefixPattern(toolName: String, toolInput: String?) -> [String] {
        if toolName.lowercased() == "bash", let cmd = toolInput {
            return shellPrefix(from: cmd, maxTokens: 3)
        }
        // Fall back to the tool name so `Write`/`Read`/etc. can be allow-listed.
        return [toolName]
    }

    /// Extract the first N whitespace-separated tokens from a shell command,
    /// preserving quoted segments (so `git commit -m "fix bug"` → ["git","commit","-m"]).
    private static func shellPrefix(from command: String, maxTokens: Int) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        for ch in command {
            if ch == "'" && !inDouble { inSingle.toggle(); current.append(ch); continue }
            if ch == "\"" && !inSingle { inDouble.toggle(); current.append(ch); continue }
            if ch.isWhitespace && !inSingle && !inDouble {
                if !current.isEmpty { tokens.append(current); current = "" }
                if tokens.count >= maxTokens { break }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty && tokens.count < maxTokens { tokens.append(current) }
        return tokens
    }

    // MARK: - TOML formatting

    private static func patternLineFor(pattern: [String]) -> String {
        "pattern = [\(pattern.map(quotedRuleString).joined(separator: ", "))]"
    }

    private static func ruleBlock(for pattern: [String], broad: Bool) -> String {
        let label = broad ? "Bypass" : "Always Allow"
        return """
        # Added by Code Island when "\(label)" was clicked for Codex.
        prefix_rule(
            \(patternLineFor(pattern: pattern)),
            decision = "allow",
            justification = "Allowed from Code Island \(label)",
        )

        """
    }

    private static func quotedRuleString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
