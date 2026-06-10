import Foundation

/// Codex doesn't support Claude's `updatedPermissions` shape — sending it back
/// produces an `unsupported updatedPermissions` error. The Codex-native way to
/// persist an "always allow" decision is to append a `prefix_rule(...)` block
/// to `~/.codex/rules/codeisland.rules`. Codex consults this file on every
/// permission request and auto-approves matching tool calls.
enum CodexPermissionRules {
    /// Returns the directory `$CODEX_HOME` resolves to.
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
    /// rule was written (or already exists), false if the rule isn't
    /// representable as a Codex prefix_rule.
    ///
    /// - Bash: first 3 tokens of the parsed command become the prefix.
    /// - Non-Bash (Write/Read/Edit/…): NOT persistable. Codex matches
    ///   prefix_rule against shell-command tokens, not tool names, so a
    ///   rule like `pattern = ["Write"]` never matches anything. We return
    ///   false and the caller falls back to a one-shot allow (issue #17).
    /// - broad=true (Bypass): drop to the first token only.
    /// - Patterns are validated as printable ASCII to keep the TOML file
    ///   parseable (issue #19) and all quote chars are stripped from
    ///   tokens (issue #18).
    @discardableResult
    static func persistAlwaysAllow(toolName: String, toolInput: String?, broad: Bool = false) -> Bool {
        // Non-Bash tools can't be persisted via prefix_rule — see #17.
        guard toolName.lowercased() == "bash" else { return false }
        guard let cmd = toolInput, !cmd.isEmpty else { return false }

        var pattern = shellPrefix(from: cmd, maxTokens: 3)
        if broad && !pattern.isEmpty {
            pattern = [pattern[0]]
        }
        guard !pattern.isEmpty else { return false }

        // Validate every token is plain printable ASCII. Anything else
        // (newlines from heredocs, tabs, control chars, non-ASCII) would
        // either silently mis-quote in TOML or produce an invalid rules
        // file that Codex refuses to load — losing every previously-good
        // rule along with it (issue #19).
        guard pattern.allSatisfy(isSafePatternToken) else {
            Log.info("CodexPermissionRules: refusing to persist rule containing non-printable / non-ASCII tokens")
            return false
        }

        let rulesDir = codexHome.appendingPathComponent("rules")
        let rulesFile = rulesDir.appendingPathComponent("codeisland.rules")
        do {
            try FileManager.default.createDirectory(at: rulesDir, withIntermediateDirectories: true)
        } catch {
            Log.error("CodexPermissionRules: can't create \(rulesDir.path): \(error)")
            return false
        }

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
            Log.error("CodexPermissionRules: failed to write \(rulesFile.path): \(error)")
            return false
        }
    }

    /// Plain printable ASCII (0x20–0x7E), excluding the chars TOML can't
    /// quote unambiguously inside a basic string. Backslash is allowed —
    /// we escape it in `quotedRuleString`.
    private static func isSafePatternToken(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        return token.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x20 && scalar.value <= 0x7E
        }
    }

    // MARK: - Pattern building

    /// Extract the first N whitespace-separated tokens from a shell command.
    /// Quote characters act purely as delimiters and do NOT appear inside
    /// the produced tokens — Codex compares against the parsed argv (which
    /// has quotes stripped) so storing them here meant our rule never
    /// matched (issue #18). `git commit -m "fix"` → `["git","commit","-m"]`.
    /// We also unterminate-tolerantly close any open quote at EOF.
    private static func shellPrefix(from command: String, maxTokens: Int) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        for ch in command {
            if ch == "'" && !inDouble { inSingle.toggle(); continue }
            if ch == "\"" && !inSingle { inDouble.toggle(); continue }
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
