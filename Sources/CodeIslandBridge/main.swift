import Foundation
import AppKit

// MARK: - Code Island Bridge
// Reads hook JSON from a coding agent (Claude Code, Codex, etc.) via stdin,
// maps to Code Island format, sends to the app via Unix domain socket.
// For PermissionRequest: waits for response and outputs to stdout.
//
// Usage: code-island-bridge [--source <id>]   (default --source claude)

let socketPath = "/tmp/code-island.sock"

// Parse CLI args: optional `--source <id>` flag identifies which AI agent
// the hook came from. Defaults to "claude" for backward compatibility.
var providerSource = "claude"
var eventTag: String? = nil
do {
    var i = 1
    let args = CommandLine.arguments
    while i < args.count {
        if args[i] == "--source" && i + 1 < args.count {
            providerSource = args[i + 1]
            i += 2
        } else if args[i] == "--event" && i + 1 < args.count {
            // Cursor/Copilot don't include the event name in stdin — they pass
            // it here. Forwarded automatically by the launcher's "$@".
            eventTag = args[i + 1]
            i += 2
        } else {
            i += 1
        }
    }
}

// Read stdin
let inputData = FileHandle.standardInput.readDataToEndOfFile()
guard !inputData.isEmpty else { exit(1) }

/// Some agents (notably Hermes) emit JSON with RAW control characters — literal
/// newlines/tabs inside string values (e.g. a multi-line assistant_response or a
/// growing conversation_history) that they fail to escape. That makes the whole
/// payload invalid JSON, so the event is dropped and the session hangs (e.g.
/// "infinite thinking" because the Stop never arrives). Re-escape control bytes
/// that occur *inside strings*; structural whitespace between tokens is untouched.
func sanitizeControlChars(_ data: Data) -> Data {
    var out = [UInt8](); out.reserveCapacity(data.count + 16)
    var inString = false, escaped = false
    for b in data {
        if escaped { out.append(b); escaped = false; continue }
        if inString {
            switch b {
            case 0x5C: out.append(b); escaped = true            // backslash → next byte is literal
            case 0x22: out.append(b); inString = false          // closing quote
            case 0x08: out.append(contentsOf: [0x5C, 0x62])     // \b
            case 0x09: out.append(contentsOf: [0x5C, 0x74])     // \t
            case 0x0A: out.append(contentsOf: [0x5C, 0x6E])     // \n
            case 0x0C: out.append(contentsOf: [0x5C, 0x66])     // \f
            case 0x0D: out.append(contentsOf: [0x5C, 0x72])     // \r
            case 0x00...0x1F: out.append(contentsOf: Array(String(format: "\\u%04x", b).utf8))
            default: out.append(b)
            }
        } else {
            if b == 0x22 { inString = true }
            out.append(b)
        }
    }
    return Data(out)
}

// Parse the hook payload. Fall back to a control-char sanitize pass for agents
// that emit raw newlines inside JSON strings.
let payload: [String: Any]
if let p = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any] {
    payload = p
} else if let p = try? JSONSerialization.jsonObject(with: sanitizeControlChars(inputData)) as? [String: Any] {
    payload = p
} else {
    fputs("code-island-bridge: invalid JSON on stdin\n", stderr)
    exit(1)
}

// Determine the raw event name. Most CLIs put it in "hook_event_name";
// Cursor/Copilot omit it and pass it via --event. Then normalize each
// provider's event vocabulary to OUR canonical set so SessionStore — which
// only understands the canonical names — works unchanged.
let rawEvent = payload["hook_event_name"] as? String
    ?? payload["hook_event"] as? String
    ?? payload["type"] as? String
    ?? eventTag
    ?? "Notification"

// Per-source event-name normalization. Claude-Code forks (qwen/qoder/droid/
// codebuddy) already speak canonical names → identity (not listed).
let eventNormalization: [String: [String: String]] = [
    "gemini": [
        "BeforeTool": "PreToolUse", "AfterTool": "PostToolUse",
        // Gemini has no Stop/UserPromptSubmit — drive status off the agent turn.
        "BeforeAgent": "UserPromptSubmit", "AfterAgent": "Stop",
    ],
    "cursor": [
        "beforeSubmitPrompt": "UserPromptSubmit",
        "beforeShellExecution": "PreToolUse", "afterShellExecution": "PostToolUse",
        "beforeReadFile": "PreToolUse", "afterFileEdit": "PostToolUse",
        "beforeMCPExecution": "PreToolUse", "afterMCPExecution": "PostToolUse",
        // Cursor fires BOTH afterAgentResponse (carries the reply text) and
        // stop at the end of a turn. Map only afterAgentResponse → Stop so the
        // Finished card gets the reply AND completion fires once, not twice;
        // drop the redundant stop.
        "afterAgentThought": "Notification", "afterAgentResponse": "Stop", "stop": "skip",
    ],
    "copilot": [
        "sessionStart": "SessionStart", "sessionEnd": "SessionEnd",
        "userPromptSubmitted": "UserPromptSubmit",
        "preToolUse": "PreToolUse", "postToolUse": "PostToolUse",
        "agentStop": "Stop",          // the real "agent finished" event
        "errorOccurred": "Notification",
    ],
    "qwen": ["PostToolUseFailure": "skip"],
    "cline": [
        // Cline's Task* lifecycle → our session/turn model. No SessionEnd
        // (process sweep handles teardown); no PermissionRequest (Cline asks
        // in the IDE). Cancel is treated as a turn end so the card settles.
        "TaskStart": "SessionStart", "TaskResume": "UserPromptSubmit",
        "TaskComplete": "Stop", "TaskCancel": "Stop",
    ],
    // Kiro — camelCase; no SessionEnd (process sweep handles teardown).
    "kiro": [
        "agentSpawn": "SessionStart", "userPromptSubmit": "UserPromptSubmit",
        "preToolUse": "PreToolUse", "postToolUse": "PostToolUse", "stop": "Stop",
    ],
    // Pi / Oh My Pi extensions emit canonical names already; just drop PostCompact.
    "pi":  ["PostCompact": "skip"],
    "omp": ["PostCompact": "skip"],
    // Nous Research Hermes (config.yaml hooks). The TURN cycle is driven by the
    // LLM-call events: pre_llm_call carries `user_message` (prompt → thinking),
    // post_llm_call carries `assistant_response` (reply → finished, card STAYS).
    // on_session_start just creates the card; on_session_end is ignored (the PID
    // sweep handles real teardown — mapping it to SessionEnd deleted the card
    // every turn). subagent_stop tracks delegations.
    "hermes": [
        "on_session_start": "SessionStart", "on_session_end": "skip",
        "pre_llm_call": "UserPromptSubmit", "post_llm_call": "Stop",
        "pre_tool_call": "PreToolUse", "post_tool_call": "PostToolUse",
        "subagent_stop": "SubagentStop",
    ],
    // Google AntiGravity (~/.gemini/config/hooks.json). PreInvocation = turn
    // start; PreToolUse/PostToolUse/Stop are already canonical (passthrough).
    "antigravity": [
        "PreInvocation": "UserPromptSubmit", "PostInvocation": "skip",
    ],
    // kimi & opencode emit canonical names already → identity (not listed).
]
// Strict-approval gate. Gemini/Cursor/Copilot/Kimi don't have a selective
// permission event — only blanket "before every tool" hooks. When the user
// opts in (per provider, via ~/.code-island/config.json written by Settings),
// we turn those `before*` events into BLOCKING permission prompts: the bridge
// shows the notch UI and translates the decision back to the tool's own shape.
let permissionGateEvents: [String: Set<String>] = [
    "gemini": ["BeforeTool"],
    "cursor": ["beforeShellExecution", "beforeMCPExecution"],
    "copilot": ["preToolUse"],
    "kimi": ["PreToolUse"],
    "qoder": ["PreToolUse"],       // Qoder has no PermissionRequest; gate in PreToolUse
    "antigravity": ["PreToolUse"],
    "hermes": ["pre_tool_call"],
]
func strictApprovalEnabled(_ source: String) -> Bool {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".code-island/config.json")
    guard let data = try? Data(contentsOf: url),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let map = root["strictApproval"] as? [String: Any] else { return false }
    return (map[source] as? Bool) == true
}
// Hermes' `clarify` rides on pre_tool_call but is a question, not a tool to
// approve — never gate it (it goes through the question-mirror path instead).
let isClarify = providerSource == "hermes" && (payload["tool_name"] as? String) == "clarify"
let isStrictGate = (permissionGateEvents[providerSource]?.contains(rawEvent) ?? false)
    && strictApprovalEnabled(providerSource)
    && !isClarify

let hookEvent = isStrictGate
    ? "PermissionRequest"
    : (eventNormalization[providerSource]?[rawEvent] ?? rawEvent)
// Events we don't track (e.g. Qwen's PostToolUseFailure) — drop silently.
if hookEvent == "skip" { exit(0) }

// Some CLIs use camelCase "sessionId" (Copilot) or omit it entirely. Fall
// back to a STABLE per-process id — a random UUID would spawn a new session
// card on every event.
let sessionId = (payload["session_id"] as? String)
    ?? (payload["sessionId"] as? String)
    ?? (payload["conversationId"] as? String)        // AntiGravity
    ?? "\(providerSource)-\(getppid())"
// AntiGravity's tool payload: { toolCall: { name, args: { CommandLine, Cwd } },
// workspacePaths: [...] } — no top-level cwd/tool_name/tool_input.
let agToolCall = payload["toolCall"] as? [String: Any]
let agArgs = agToolCall?["args"] as? [String: Any]
let cwd = (payload["cwd"] as? String)
    ?? (agArgs?["Cwd"] as? String)
    ?? (payload["workspacePaths"] as? [String])?.first

// Extract tool name (Copilot uses camelCase "toolName"). For Cursor's strict
// gate, shell/MCP events carry no tool_name — synthesize a readable label.
func strictGateLabel(_ event: String) -> String? {
    switch event {
    case "beforeShellExecution": return "Shell"
    case "beforeMCPExecution":   return "MCP"
    default:                     return nil
    }
}
let toolName = payload["tool_name"] as? String ?? payload["toolName"] as? String
    ?? (agToolCall?["name"] as? String)              // AntiGravity
    ?? (isStrictGate ? strictGateLabel(rawEvent) : nil)

// Extract tool input as a string summary, plus separate content/path for Write/Edit
var toolInputStr: String? = nil
var toolContent: String? = nil
var toolFilePath: String? = nil
var toolOldString: String? = nil
var toolNewString: String? = nil
// Copilot encodes tool args as a JSON-encoded STRING under "toolArgs".
// Parse it so the extraction below sees a normal object.
var normalizedToolInput = payload["tool_input"] as? [String: Any]
if normalizedToolInput == nil, let argsStr = payload["toolArgs"] as? String,
   let argsData = argsStr.data(using: .utf8),
   let parsed = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
    normalizedToolInput = parsed
}
if let toolInput = normalizedToolInput {
    if let cmd = toolInput["command"] as? String {
        toolInputStr = cmd
    } else if let fp = toolInput["file_path"] as? String {
        toolInputStr = fp
        toolFilePath = fp
    } else if let url = toolInput["url"] as? String {
        toolInputStr = url
        toolFilePath = url
        // For WebFetch: combine url and prompt
        if let prompt = toolInput["prompt"] as? String {
            toolContent = prompt
        }
    } else if let pattern = toolInput["pattern"] as? String {
        toolInputStr = pattern
        toolFilePath = pattern
    } else if let desc = toolInput["description"] as? String {
        toolInputStr = desc
    } else {
        if let data = try? JSONSerialization.data(withJSONObject: toolInput, options: []) {
            toolInputStr = String(data: data, encoding: .utf8)
        }
    }
    // Extract content/edits for Write/Edit tools (only if not already set by WebFetch)
    if toolContent == nil {
        toolContent = toolInput["content"] as? String
    }
    toolOldString = toolInput["old_string"] as? String
    toolNewString = toolInput["new_string"] as? String
} else if let toolInput = payload["tool_input"] as? String {
    toolInputStr = toolInput
}
// Cursor's beforeShellExecution carries the command at the TOP level (not in
// tool_input) — surface it so the strict-approval card shows what's running.
if toolInputStr == nil, let topCommand = payload["command"] as? String {
    toolInputStr = topCommand
}
// AntiGravity's shell tool: toolCall.args.CommandLine.
if toolInputStr == nil, let cl = agArgs?["CommandLine"] as? String {
    toolInputStr = cl
}
// Hermes' `clarify` tool is its AskUserQuestion equivalent — tool_input is
// {question, choices[]}. Reshape into the canonical {questions:[…]} so the
// app's question mirror (the same path Codex's request_user_input uses) renders
// it, with a jump-to-terminal to answer (the hook can't inject the choice).
if providerSource == "hermes", toolName == "clarify",
   let ti = payload["tool_input"] as? [String: Any],
   let q = ti["question"] as? String {
    let options: [[String: Any]] = ((ti["choices"] as? [String]) ?? []).map { ["label": $0] }
    let canonical: [String: Any] = ["questions": [[
        "question": q, "header": "Clarify", "options": options, "multiSelect": false,
    ]]]
    if let d = try? JSONSerialization.data(withJSONObject: canonical) {
        toolInputStr = String(data: d, encoding: .utf8)
    }
}

// Collect terminal env vars for jump support
var envVars: [String: String] = [:]
let processEnv = ProcessInfo.processInfo.environment

// Pass through iTerm session ID only if we're actually in iTerm
if processEnv["TERM_PROGRAM"] == "iTerm.app", let itermId = processEnv["ITERM_SESSION_ID"] {
    envVars["ITERM_SESSION_ID"] = itermId
}

// Detect terminal app dynamically by walking up the process tree
// to find the first GUI app (the terminal/IDE that spawned our shell)
envVars["_TERM_BUNDLE_ID"] = findParentAppBundleId()

/// Walk up the process tree to find the terminal/IDE app
func findParentAppBundleId() -> String {
    var pid = ProcessInfo.processInfo.processIdentifier

    // Walk up ppid chain, max 20 hops
    for _ in 0..<20 {
        pid = getParentPid(pid)
        if pid <= 1 { break }

        // Check if this pid is a GUI app with a bundle ID
        if let app = NSRunningApplication(processIdentifier: pid),
           let bundleId = app.bundleIdentifier {
            return bundleId
        }
    }

    // Fallback: use __CFBundleIdentifier or TERM_PROGRAM
    if let cf = processEnv["__CFBundleIdentifier"] { return cf }
    return "com.apple.Terminal"
}

/// Get parent PID using sysctl
func getParentPid(_ pid: pid_t) -> pid_t {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.size
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    let result = sysctl(&mib, 4, &info, &size, nil, 0)
    if result == 0 {
        return info.kp_eproc.e_ppid
    }
    return 0
}

// Extract user/assistant messages directly from Claude Code's payload
// AntiGravity puts both prompt and reply only in its transcript.jsonl.
let agTranscriptPath = payload["transcriptPath"] as? String ?? payload["transcript_path"] as? String

let userMessage: String? = {
    if hookEvent == "UserPromptSubmit" {
        // AntiGravity carries no prompt field — read it from the transcript.
        if providerSource == "antigravity", let p = agTranscriptPath {
            return agUserRequestFromTranscript(p)
        }
        // Hermes' pre_llm_call carries the prompt as `user_message`, possibly
        // nested under `extra` — check both.
        let hermesExtra = payload["extra"] as? [String: Any]
        // Claude uses "prompt"; Cursor/others vary.
        return payload["prompt"] as? String ?? payload["query"] as? String
            ?? payload["user_prompt"] as? String ?? payload["message"] as? String
            ?? payload["input"] as? String ?? payload["text"] as? String
            ?? payload["user_message"] as? String              // Hermes (top-level)
            ?? hermesExtra?["user_message"] as? String          // Hermes (in extra)
    }
    return nil
}()

let assistantMessage: String? = {
    if hookEvent == "Stop" {
        // AntiGravity carries no reply field — read it from the transcript.
        if providerSource == "antigravity", let p = agTranscriptPath {
            return agAssistantFromTranscript(p)
        }
        // Hermes' post_llm_call carries the reply as `assistant_response`,
        // possibly nested under `extra` — check both.
        let hermesExtra = payload["extra"] as? [String: Any]
        // Cursor's afterAgentResponse carries the reply in "text"/"message";
        // Gemini's AfterAgent uses "prompt_response".
        return payload["last_assistant_message"] as? String
            ?? payload["prompt_response"] as? String
            ?? payload["assistant_response"] as? String          // Hermes (top-level)
            ?? hermesExtra?["assistant_response"] as? String      // Hermes (in extra)
            ?? payload["text"] as? String ?? payload["message"] as? String
    }
    return nil
}()

/// Walk the Claude Code transcript backwards to find the most recent
/// assistant line's `message.model`. Used as a fallback because Claude's
/// hook payload (unlike Codex's) doesn't include the model directly.
func lastModelFromTranscript(_ path: String) -> String? {
    guard let data = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    for line in data.components(separatedBy: "\n").reversed() {
        guard !line.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              json["type"] as? String == "assistant",
              let message = json["message"] as? [String: Any],
              let model = message["model"] as? String,
              !model.isEmpty
        else { continue }
        return model
    }
    return nil
}

func lastAssistantFromTranscript(_ path: String) -> String? {
    guard let data = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    let lines = data.components(separatedBy: "\n")

    // Walk backwards to find the last assistant message with actual text content
    for line in lines.reversed() {
        guard !line.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              json["type"] as? String == "assistant",
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { continue }

        // Collect all text blocks from this message (skip tool_use blocks)
        var texts: [String] = []
        for c in content {
            if c["type"] as? String == "text", let text = c["text"] as? String, !text.isEmpty {
                texts.append(text)
            }
        }

        // Only use this message if it has actual text (not just tool_use)
        if !texts.isEmpty {
            return String(texts.joined(separator: "\n").prefix(500))
        }
    }
    return nil
}

// AntiGravity's hook payloads carry no prompt/reply text — only a transcript
// path. Its transcript.jsonl uses {type, source, content} lines: USER_INPUT
// (wrapped in <USER_REQUEST>…</USER_REQUEST>) for the prompt, PLANNER_RESPONSE
// from MODEL with a `content` string for the assistant's reply.
func agUserRequestFromTranscript(_ path: String) -> String? {
    guard let data = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    for line in data.components(separatedBy: "\n").reversed() {
        guard !line.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              json["type"] as? String == "USER_INPUT",
              var content = json["content"] as? String else { continue }
        // Strip the <USER_REQUEST>…</USER_REQUEST> wrapper and any trailing
        // <ADDITIONAL_METADATA>… block AntiGravity appends.
        if let r = content.range(of: "<USER_REQUEST>"),
           let e = content.range(of: "</USER_REQUEST>") {
            content = String(content[r.upperBound..<e.lowerBound])
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return String(trimmed.prefix(500)) }
    }
    return nil
}

func agAssistantFromTranscript(_ path: String) -> String? {
    guard let data = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    for line in data.components(separatedBy: "\n").reversed() {
        guard !line.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              json["type"] as? String == "PLANNER_RESPONSE",
              json["source"] as? String == "MODEL",
              let content = json["content"] as? String else { continue }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return String(trimmed.prefix(500)) }
    }
    return nil
}

// Build the message for Code Island
var message: [String: Any] = [
    "session_id": sessionId,
    "hook_event": hookEvent,
    "source": providerSource,
]
if let cwd { message["cwd"] = cwd }
if let toolName { message["tool_name"] = toolName }
if let toolInputStr { message["tool_input"] = toolInputStr }
if let toolFilePath { message["tool_file_path"] = toolFilePath }
if let toolContent { message["tool_content"] = toolContent }
if let toolOldString { message["tool_old_string"] = toolOldString }
if let toolNewString { message["tool_new_string"] = toolNewString }

// Capture our parent PID. The bridge is launched directly by the AI agent
// (the launcher script `exec`s into the bridge, so getppid() returns the
// agent itself). The app uses this to detect when the agent has exited so
// the session can be removed from the notch.
message["agent_pid"] = Int(getppid())
if !envVars.isEmpty { message["_env"] = envVars }
// Claude multi-profile: when launched with a custom CLAUDE_CONFIG_DIR (e.g.
// ~/.claude-work), tag the session with the profile name ("work") so the notch
// can tell profiles apart. The hook subprocess inherits CLAUDE_CONFIG_DIR.
if providerSource == "claude",
   let cfgDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !cfgDir.isEmpty {
    var base = (cfgDir as NSString).lastPathComponent
    if base != ".claude" {
        if base.hasPrefix(".claude-") { base = String(base.dropFirst(8)) }   // ".claude-".count
        else if base.hasPrefix(".") { base = String(base.dropFirst()) }
        if !base.isEmpty { message["profile"] = base }
    }
}
if let userMessage { message["user_message"] = userMessage }
if let assistantMessage { message["assistant_message"] = assistantMessage }
if let permMode = payload["permission_mode"] as? String { message["permission_mode"] = permMode }
if let sessionTitle = payload["session_title"] as? String, !sessionTitle.isEmpty {
    message["session_title"] = sessionTitle
}
if let effort = payload["effort"] as? [String: Any], let level = effort["level"] as? String {
    message["effort_level"] = level
}
if let durationMs = payload["duration_ms"] as? Int { message["duration_ms"] = durationMs }
// Codex emits `model` at the top level. Claude doesn't — we have to
// dig it out of the transcript file (each assistant line carries
// `message.model`). Try top-level first, fall back to transcript.
if let model = payload["model"] as? String, !model.isEmpty {
    message["model"] = model
} else if let transcriptPath = payload["transcript_path"] as? String,
          let model = lastModelFromTranscript(transcriptPath) {
    message["model"] = model
}

// Serialize
guard let messageData = try? JSONSerialization.data(withJSONObject: message) else { exit(1) }

// SIGPIPE → ignored. We'd rather have write() return EPIPE so we can
// exit cleanly than have the kernel deliver a signal we don't handle.
signal(SIGPIPE, SIG_IGN)

// Connect to Unix socket
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(1) }

// Per-socket SIGPIPE suppression — belt-and-braces with the signal handler.
var noSigPipe: Int32 = 1
setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let pathBytes = Array(socketPath.utf8)
withUnsafeMutableBytes(of: &addr.sun_path) { rawPtr in
    for i in 0..<min(pathBytes.count, rawPtr.count - 1) {
        rawPtr[i] = pathBytes[i]
    }
}

let connected = withUnsafePointer(to: &addr) { ptr in
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}

guard connected == 0 else {
    close(fd)
    exit(1)
}

// MARK: - Framed I/O helpers

func writeAll(fd: Int32, bytes: UnsafePointer<UInt8>, count: Int) -> Bool {
    var sent = 0
    while sent < count {
        let n = write(fd, bytes.advanced(by: sent), count - sent)
        if n > 0 {
            sent += n
        } else if errno == EINTR {
            continue
        } else {
            return false
        }
    }
    return true
}

func writeFramed(fd: Int32, payload: Data) -> Bool {
    let len = UInt32(payload.count)
    let header: [UInt8] = [
        UInt8((len >> 24) & 0xFF),
        UInt8((len >> 16) & 0xFF),
        UInt8((len >> 8) & 0xFF),
        UInt8(len & 0xFF),
    ]
    let okHeader = header.withUnsafeBufferPointer { writeAll(fd: fd, bytes: $0.baseAddress!, count: 4) }
    guard okHeader else { return false }
    return payload.withUnsafeBytes { raw -> Bool in
        guard let base = raw.baseAddress else { return false }
        return writeAll(fd: fd, bytes: base.assumingMemoryBound(to: UInt8.self), count: payload.count)
    }
}

func readExactly(fd: Int32, count: Int) -> Data? {
    var buf = Data(count: count)
    var got = 0
    let ok = buf.withUnsafeMutableBytes { raw -> Bool in
        guard let base = raw.baseAddress else { return false }
        while got < count {
            let n = read(fd, base.advanced(by: got), count - got)
            if n > 0 { got += n }
            else if n == 0 { return false }
            else if errno == EINTR { continue }
            else { return false }
        }
        return true
    }
    return ok ? buf : nil
}

// Send length-prefixed JSON
guard writeFramed(fd: fd, payload: messageData) else {
    close(fd)
    exit(1)
}

// For permission requests, wait for framed response
if hookEvent == "PermissionRequest" {
    var timeout = timeval(tv_sec: 300, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    guard let header = readExactly(fd: fd, count: 4) else {
        close(fd); exit(1)
    }
    let len: UInt32 = header.withUnsafeBytes { raw in
        let p = raw.bindMemory(to: UInt8.self)
        return (UInt32(p[0]) << 24) | (UInt32(p[1]) << 16) | (UInt32(p[2]) << 8) | UInt32(p[3])
    }
    if len > 0, len <= 4 * 1024 * 1024, let body = readExactly(fd: fd, count: Int(len)) {
        // For a strict-approval gate, the app replies in OUR (Claude) shape;
        // translate it to the tool's native permission response before writing
        // to stdout. Real PermissionRequest providers (Claude/Codex/Qwen/Qoder/
        // OpenCode) already speak this shape, so pass their response through.
        let out = isStrictGate ? translateStrictDecision(source: providerSource, appResponse: body) : body
        FileHandle.standardOutput.write(out)
        try? FileHandle.standardOutput.synchronize()
    }
}

close(fd)
exit(0)

/// Maps the app's Claude-shaped decision → the gated tool's native response.
/// Default to "allow" if anything is unparseable (matches each tool's fail-open
/// behavior; better than silently denying the user's work).
func translateStrictDecision(source: String, appResponse: Data) -> Data {
    var behavior = "allow"
    if let root = try? JSONSerialization.jsonObject(with: appResponse) as? [String: Any],
       let hso = root["hookSpecificOutput"] as? [String: Any],
       let decision = hso["decision"] as? [String: Any],
       let b = decision["behavior"] as? String {
        behavior = b   // "allow" | "deny" | "ask"
    }
    let deny = behavior == "deny"
    let ask = behavior == "ask"
    let reason = "Denied in Code Island"
    let json: String
    switch source {
    case "gemini":
        // Gemini has no "ask" — treat it as allow.
        json = deny ? "{\"decision\":\"deny\",\"reason\":\"\(reason)\"}" : "{\"decision\":\"allow\"}"
    case "cursor":
        if deny { json = "{\"permission\":\"deny\",\"agent_message\":\"\(reason)\"}" }
        else if ask { json = "{\"permission\":\"ask\"}" }
        else { json = "{\"permission\":\"allow\"}" }
    case "antigravity":
        if deny { json = "{\"decision\":\"deny\",\"reason\":\"\(reason)\"}" }
        else if ask { json = "{\"decision\":\"ask\"}" }
        else { json = "{\"decision\":\"allow\"}" }
    case "hermes":
        // Hermes pre_tool_call blocks on {"decision":"block"}; anything else
        // (incl. an empty object) lets the tool proceed. No "ask" concept.
        if deny { json = "{\"decision\":\"block\",\"reason\":\"\(reason)\"}" }
        else { json = "{}" }
    case "copilot":
        if deny { json = "{\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"\(reason)\"}" }
        else if ask { json = "{\"permissionDecision\":\"ask\"}" }
        else { json = "{\"permissionDecision\":\"allow\"}" }
    case "kimi", "qoder":
        // Identical Claude-style PreToolUse permissionDecision shape.
        if deny { json = "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"\(reason)\"}}" }
        else { json = "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"allow\"}}" }
    default:
        return appResponse
    }
    return Data(json.utf8)
}
