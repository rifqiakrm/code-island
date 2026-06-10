import AppKit

/// Jumps to the terminal/IDE associated with a session.
/// Supports tab-level jumping for iTerm2, Terminal.app, Ghostty, JetBrains, VS Code/Cursor.
enum TerminalJumper {

    static var isTerminalFocused: Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier else { return false }
        return appNameCache[bundleId] != nil
    }

    private static var appNameCache: [String: String] = [:]

    static func appName(for bundleId: String?) -> String {
        guard let bundleId else { return "Terminal" }
        if let cached = appNameCache[bundleId] { return cached }

        let name: String
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            name = app.localizedName ?? bundleId.components(separatedBy: ".").last ?? "Terminal"
        } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            name = appURL.deletingPathExtension().lastPathComponent
        } else {
            name = bundleId.components(separatedBy: ".").last?.capitalized ?? "Terminal"
        }

        appNameCache[bundleId] = name
        return name
    }

    // MARK: - Jump

    static func jump(to session: Session) {
        let info = session.terminalInfo
        let bundleId = info?.appBundleId ?? ""
        let cwd = session.cwd

        Log.info("TerminalJumper: bundle=\(bundleId) cwd=\(cwd)")

        // Activate the app first
        activateApp(bundleId: bundleId)

        // Then try tab-specific jump based on what we know
        if let itermId = info?.itermSessionId {
            jumpITerm(sessionId: itermId)
        } else if bundleId.contains("iterm") {
            jumpITerm(sessionId: info?.itermSessionId)
        } else if bundleId == "com.apple.Terminal" {
            jumpTerminalApp(cwd: cwd)
        } else if bundleId.contains("ghostty") {
            jumpGhostty(cwd: cwd)
        } else if bundleId.contains("jetbrains") || bundleId.contains("intellij") ||
                    bundleId.contains("idea") || bundleId.contains("webstorm") ||
                    bundleId.contains("pycharm") || bundleId.contains("goland") {
            jumpJetBrains(bundleId: bundleId, cwd: cwd)
        } else if bundleId.contains("VSCode") || bundleId.contains("cursor") ||
                    bundleId.contains("windsurf") || bundleId.contains("code") {
            jumpVSCode(bundleId: bundleId, cwd: cwd)
        }
        // For anything else, activateApp already brought it to front
    }

    // MARK: - App Activation

    private static func activateApp(bundleId: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            app.activate(options: [.activateAllWindows])
        }
    }

    // MARK: - iTerm2 (AppleScript — exact session)

    private static func jumpITerm(sessionId: String?) {
        guard let rawId = sessionId else { return }
        let sessionId = rawId.components(separatedBy: ":").last ?? rawId

        runAppleScript("""
        tell application "iTerm2"
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if unique ID of aSession contains "\(sessionId)" then
                            select aWindow
                            tell aWindow to select aTab
                            select aSession
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """)
    }

    // MARK: - Terminal.app (AppleScript — match by cwd in tab title)

    private static func jumpTerminalApp(cwd: String) {
        let folder = escapeAppleScriptString((cwd as NSString).lastPathComponent)
        runAppleScript("""
        tell application "Terminal"
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    if custom title of aTab contains "\(folder)" or history of aTab contains "\(folder)" then
                        set selected tab of aWindow to aTab
                        set index of aWindow to 1
                        activate
                        return
                    end if
                end repeat
            end repeat
        end tell
        """)
    }

    // MARK: - Ghostty (AppleScript — match window by title)

    private static func jumpGhostty(cwd: String) {
        let folder = escapeAppleScriptString((cwd as NSString).lastPathComponent)
        runAppleScript("""
        tell application "System Events"
            tell process "Ghostty"
                set frontmost to true
                repeat with aWindow in windows
                    if name of aWindow contains "\(folder)" then
                        perform action "AXRaise" of aWindow
                        return
                    end if
                end repeat
            end tell
        end tell
        """)
    }

    // MARK: - JetBrains IDEs (AppleScript — match window by project name)

    private static func jumpJetBrains(bundleId: String, cwd: String) {
        let folder = escapeAppleScriptString((cwd as NSString).lastPathComponent)
        let appName = escapeAppleScriptString(appName(for: bundleId))

        runAppleScript("""
        tell application "System Events"
            tell process "\(appName)"
                set frontmost to true
                repeat with aWindow in windows
                    if name of aWindow contains "\(folder)" then
                        perform action "AXRaise" of aWindow
                        return
                    end if
                end repeat
            end tell
        end tell
        """)
    }

    // MARK: - VS Code / Cursor / Windsurf (AppleScript — match window by folder name)

    private static func jumpVSCode(bundleId: String, cwd: String) {
        let folder = escapeAppleScriptString((cwd as NSString).lastPathComponent)
        let appName = escapeAppleScriptString(appName(for: bundleId))

        runAppleScript("""
        tell application "System Events"
            tell process "\(appName)"
                set frontmost to true
                repeat with aWindow in windows
                    if name of aWindow contains "\(folder)" then
                        perform action "AXRaise" of aWindow
                        return
                    end if
                end repeat
            end tell
        end tell
        """)
    }

    // MARK: - Helpers

    /// Sanitize an arbitrary string before splicing it into AppleScript
    /// source. Without this, a folder name like `foo"; tell app "Finder" to
    /// delete every file --` would break out of the AppleScript string and
    /// execute attacker-controlled code with the Accessibility privileges
    /// Code Island has been granted. `cwd` comes from hook payloads, so a
    /// malicious project (or an injected transcript) could trigger it
    /// (issue #20).
    private static func escapeAppleScriptString(_ raw: String) -> String {
        // Backslash and double-quote are the two chars AppleScript basic
        // strings care about. Strip newlines and other control chars
        // outright — they have no legitimate place in a folder/app name
        // and would terminate the embedded string anyway.
        var out = ""
        out.reserveCapacity(raw.count)
        for scalar in raw.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F {
                // skip control chars (including newlines, tabs, NUL)
                continue
            }
            switch scalar {
            case "\\": out.append("\\\\")
            case "\"": out.append("\\\"")
            default: out.append(Character(scalar))
            }
        }
        return out
    }

    private static func runAppleScript(_ source: String) {
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let error {
                Log.error("TerminalJumper AppleScript: \(error)")
            }
        }
    }
}
