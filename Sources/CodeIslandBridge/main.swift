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
do {
    var i = 1
    let args = CommandLine.arguments
    while i < args.count {
        if args[i] == "--source" && i + 1 < args.count {
            providerSource = args[i + 1]
            i += 2
        } else {
            i += 1
        }
    }
}

// Read stdin
let inputData = FileHandle.standardInput.readDataToEndOfFile()
guard !inputData.isEmpty else { exit(1) }

// Parse the hook payload from Claude Code
guard let payload = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any] else {
    fputs("code-island-bridge: invalid JSON on stdin\n", stderr)
    exit(1)
}

// Claude Code uses "hook_event_name" for the event type
let hookEvent = payload["hook_event_name"] as? String
    ?? payload["hook_event"] as? String
    ?? payload["type"] as? String
    ?? "Notification"

let sessionId = payload["session_id"] as? String ?? UUID().uuidString
let cwd = payload["cwd"] as? String

// Extract tool name
let toolName = payload["tool_name"] as? String

// Extract tool input as a string summary, plus separate content/path for Write/Edit
var toolInputStr: String? = nil
var toolContent: String? = nil
var toolFilePath: String? = nil
var toolOldString: String? = nil
var toolNewString: String? = nil
if let toolInput = payload["tool_input"] as? [String: Any] {
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
let userMessage: String? = {
    if hookEvent == "UserPromptSubmit" {
        return payload["prompt"] as? String ?? payload["query"] as? String
    }
    return nil
}()

let assistantMessage: String? = {
    if hookEvent == "Stop" {
        return payload["last_assistant_message"] as? String
    }
    return nil
}()

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
if let model = payload["model"] as? String, !model.isEmpty { message["model"] = model }

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
        FileHandle.standardOutput.write(body)
        try? FileHandle.standardOutput.synchronize()
    }
}

close(fd)
exit(0)
