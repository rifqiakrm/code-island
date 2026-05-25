import Foundation
import AppKit

// MARK: - Code Island Bridge
// Reads hook JSON from Claude Code via stdin, maps to Code Island format,
// sends to the app via Unix domain socket.
// For PermissionRequest: waits for response and outputs to stdout.

let socketPath = "/tmp/code-island.sock"

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
]
if let cwd { message["cwd"] = cwd }
if let toolName { message["tool_name"] = toolName }
if let toolInputStr { message["tool_input"] = toolInputStr }
if let toolFilePath { message["tool_file_path"] = toolFilePath }
if let toolContent { message["tool_content"] = toolContent }
if let toolOldString { message["tool_old_string"] = toolOldString }
if let toolNewString { message["tool_new_string"] = toolNewString }
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

// Serialize
guard let messageData = try? JSONSerialization.data(withJSONObject: message) else { exit(1) }

// Connect to Unix socket
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(1) }

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

// Send message
messageData.withUnsafeBytes { ptr in
    _ = write(fd, ptr.baseAddress!, messageData.count)
}

// For permission requests, wait for response
if hookEvent == "PermissionRequest" {
    var timeout = timeval(tv_sec: 300, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    // Read all bytes — response may come in multiple chunks
    var responseData = Data()
    var buffer = [UInt8](repeating: 0, count: 65536)
    while true {
        let bytesRead = read(fd, &buffer, buffer.count)
        if bytesRead <= 0 { break }
        responseData.append(Data(bytes: buffer, count: bytesRead))
        // Check if it looks like complete JSON (last char is })
        if responseData.last == 0x7D /* } */ { break }
    }

    if !responseData.isEmpty {
        FileHandle.standardOutput.write(responseData)
        try? FileHandle.standardOutput.synchronize()
    }
}

close(fd)
exit(0)
