# Code Island Bug Bash — Detailed Explanations

33 confirmed bugs (3 critical · 14 high · 13 medium · 3 low). Each one explains: what the code is trying to do, what actually goes wrong, a concrete walkthrough, and the fix.

---

# CRITICAL

These cause data loss, silent corruption, or break a core feature.

## 1. Truncated payloads fail JSON parse (the "8KB invalid-JSON" bug)

**File:** `Sources/CodeIsland/IPC/SocketServer.swift:113`

### The setup
When a hook fires (e.g. Claude wants to use Bash), the bridge serializes the payload to JSON and pipes it through a Unix socket to the running app. The app's `SocketServer` reads it in `handleClient`:

```swift
while true {
    let n = read(fd, &buffer, bufSize)   // bufSize = 65536
    if n <= 0 { break }
    data.append(...)
    if n < bufSize { break }              // <-- this line
}
```

The logic is "we asked for 65KB; if we got less, the sender is done."

### The bug
That's wrong for SOCK_STREAM. A stream socket is not a message socket — the kernel hands you whatever bytes are *currently available*, regardless of how much the sender is going to send total. A single `read()` can return 4KB or 100 bytes mid-transmission, even though the sender still has gigabytes coming.

The macOS default send buffer for AF_UNIX stream sockets is around 8KB. So when the bridge writes a 30KB payload (e.g. a Bash `tool_input` with a long script), the kernel buffers ~8KB, our server reads it, sees `n < 65536`, breaks the loop, hands a truncated JSON blob to the decoder, and logs "invalid JSON."

### Walkthrough
1. Claude wants to write a 20KB file. Hook fires, bridge sends a `Write` payload to our socket.
2. Bridge's write loop pushes 8KB into the kernel buffer (capacity), blocks until kernel drains.
3. Server's read returns those 8KB. `n=8192 < 65536`, loop breaks.
4. Server tries `JSONDecoder().decode(BridgeMessage.self, from: ...)` — fails because the JSON is truncated.
5. Logs `[ERROR] Socket: invalid JSON`. The hook event is silently dropped. The notch doesn't reflect the tool call.
6. Worse for `PermissionRequest`: bridge intentionally keeps the write side open waiting for the response. Server breaks early, parse fails, closes fd. Bridge sits in `read()` for 300 seconds (its timeout).

### The fix
Length-prefixed framing. Bridge writes a 4-byte uint32 length header before the JSON. Server reads exactly 4 bytes, decodes the length, reads exactly that many bytes. No heuristics, no shutdown coordination, works for any payload size.

```swift
// Bridge
let len = UInt32(messageData.count).bigEndian
write(fd, [len], 4)
write(fd, messageData, messageData.count)

// Server
var lenBuf = Data(count: 4)
read(fd, &lenBuf, 4)
let len = lenBuf.withUnsafeBytes { Int(UInt32(bigEndian: $0.load(as: UInt32.self))) }
var payload = Data(count: len)
// loop read until we've got exactly len bytes
```

---

## 2. `pendingDismissedExternally` leaks socket fds and hangs bridges

**File:** `Sources/CodeIsland/Session/SessionStore.swift:137`

### The setup
When the user answers a permission in the terminal instead of the notch, a follow-up hook event (`PreToolUse`, `PostToolUse`, `Stop`) tells us so. We clear the stale pending UI state:

```swift
if hadPending {
    sessions[sessionId]?.pendingPermission = nil
    sessions[sessionId]?.pendingQuestion = nil
    onEvent.send(.pendingDismissedExternally(sessionId))
}
```

### The bug
The `pendingPermission` and `pendingQuestion` structs carry a `respond` closure. That closure is **the only place we ever call `close(fd)`** on the open socket connection from the bridge. By nilling the pending state, we drop the closure — and the closure is the only handle to the fd. Result: that fd is leaked in our process *and* the bridge sits in `read()` waiting for a response that will never come.

### Walkthrough
1. Claude asks for permission to run Bash. Bridge opens a socket connection and waits.
2. Notch shows the permission prompt with 4 buttons.
3. User ignores the notch and presses `y` in the terminal. Claude continues, fires `PreToolUse` for the next call.
4. Our hook receives PreToolUse; the "is this a progress event" check fires; we nil `pendingPermission`.
5. The `respond` closure is gone — fd is now orphaned in our process. Bridge is still in `read()`, blocked.
6. 300 seconds later the bridge times out, exits, kernel reclaims its end of the socket. Our fd is still open until app exit.
7. Multiply by ~20 dismissed prompts per workday → 20 leaked fds + 20 zombie bridge processes hanging around for 5 minutes each.

Same leak applies to `respondToPermission` (line 354), `respondToQuestion` (line 463), and `deferQuestionToTerminal` (line 480) — when `BridgeResponse` encoding returns `nil`, they early-return without invoking `respond`.

### The fix
Before clearing pending state, capture and call the respond closure with a safe default so the fd closes and the bridge unblocks:

```swift
if hadPending {
    if let pending = sessions[sessionId]?.pendingPermission {
        pending.respond(.deny)   // or .allowOnce — close the fd
    }
    if let pending = sessions[sessionId]?.pendingQuestion,
       let data = BridgeResponse.deferToTerminal() {
        pending.respond(data)
    }
    sessions[sessionId]?.pendingPermission = nil
    sessions[sessionId]?.pendingQuestion = nil
    onEvent.send(.pendingDismissedExternally(sessionId))
}
```

Bonus: wrap `fd` in a small RAII class with `deinit { close(fd) }` so dropping the closure auto-closes the fd as a last-line defense.

---

## 3. `~/.claude/settings.json` is silently wiped when unparseable

**File:** `Sources/CodeIsland/Utilities/HookInstaller.swift:18`

### The setup
On every launch, `HookInstaller.install()` runs:

```swift
var settings = readJSON(at: settingsPath) ?? [:]
// ... mutate settings.hooks ...
writeJSON(settings, to: settingsPath)
```

The idea: read the existing JSON, merge our hooks into the `hooks` key, write back.

### The bug
`readJSON` returns `nil` for **any** failure: file missing (legitimate first-run), file unreadable (permission), or file present but malformed (JSON parse error). The `?? [:]` doesn't distinguish — every failure becomes "start with a blank settings dict."

When the user's settings.json is, say, slightly hand-edited with a trailing comma or a `//` comment (Claude Code itself tolerates JSONC), our `readJSON` returns nil, we start from `[:]`, we add our hooks, and we **atomically overwrite the file** with `{"hooks": {...}}`. Their `permissions`, `theme`, `model`, `env`, `statusLine`, MCP server configs, every other hook — all permanently destroyed. No backup. `install()` returns `true` like nothing happened.

### Walkthrough
1. User has `~/.claude/settings.json` with `permissions`, `mcpServers`, custom hooks, and statusLine — hand-tuned over months.
2. User adds a trailing comma somewhere while editing (or a `//` comment that Claude Code accepts).
3. User launches Code Island.
4. `readJSON` calls `JSONSerialization.jsonObject` → throws → caught silently → returns nil.
5. Installer starts from `[:]`, sets `["hooks"] = {...}`, atomically writes back.
6. User's months of config: gone. No warning, no backup, no recovery.

### The fix
Distinguish missing from malformed, and never write blindly:

```swift
let existing: [String: Any]?
if FileManager.default.fileExists(atPath: settingsPath.path) {
    existing = readJSON(at: settingsPath)
    if existing == nil {
        // File exists but is unparseable — DO NOT overwrite.
        Log.error("Won't install hooks: \(settingsPath.path) exists but couldn't be parsed.")
        return false
    }
} else {
    existing = [:]
}
var settings = existing ?? [:]
// Write a .bak before overwriting
try? FileManager.default.copyItem(at: settingsPath, to: settingsPath.appendingPathExtension("bak"))
```

---

# HIGH

These are real production bugs that affect normal use.

## 4. No SIGPIPE handling — writes to a dead bridge crash the app

**File:** `Sources/CodeIsland/IPC/SocketServer.swift:138`

### The setup
When the user clicks Allow/Deny, the respond closure writes the JSON response to the socket. The bridge reads it from stdout. Standard write:

```swift
write(fd, responseBytes, count)
```

### The bug
On macOS, writing to a Unix stream socket whose remote end has been closed raises `SIGPIPE`. The default disposition of SIGPIPE is to **terminate the entire process**. AppKit doesn't install a handler. We don't either. The socket has no `SO_NOSIGPIPE` flag set. `write()` on macOS doesn't accept `MSG_NOSIGNAL` (Linux-only).

So any time a bridge dies between when it sent the request and when the user clicks, our write crashes the whole app.

### Walkthrough
1. Claude asks for permission. Bridge sends request, sits in `read()` with a 300s timeout.
2. User leaves the laptop closed for an hour. Bridge times out, exits.
3. User returns, sees the prompt, clicks Allow.
4. respond closure runs `write(fd, ...)` on a socket whose remote end has been closed for 55 minutes.
5. Kernel sends SIGPIPE. Default handler: process dies.
6. Notch disappears. Menu bar icon disappears. App is gone.

### The fix
In `AppDelegate.applicationDidFinishLaunching`:
```swift
signal(SIGPIPE, SIG_IGN)
```
Plus set `SO_NOSIGPIPE` on each accepted socket so individual writes don't trigger it either:
```swift
var on: Int32 = 1
setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
```

---

## 5. Bypass mode swallows AskUserQuestion answers

**File:** `Sources/CodeIsland/Session/SessionStore.swift:211`

### The setup
Bypass mode (`--dangerously-skip-permissions`) means Claude shouldn't be interrupted for tool approvals. Our handler:

```swift
case "PermissionRequest":
    if message.permissionMode == "bypassPermissions" {
        respond?(BridgeResponse.allow())   // <-- here
        return
    }
    // ... AskUserQuestion detection, normal permission UI ...
```

### The bug
`AskUserQuestion` also arrives as a `PermissionRequest` event (Claude's API quirk). The bypass shortcut fires for it too — we send a bare `allow()` with no `updatedInput.answers`. Claude's contract: when `tool_name == "AskUserQuestion"`, the response must include the user's answers, otherwise Claude proceeds with no input and the assistant sees blank answers.

So in bypass mode, every interactive question is silently auto-allowed with no answer. The user never gets asked. Claude continues as if the user said "<empty>". The actual AskUserQuestion handling below is unreachable while bypass is on.

### Walkthrough
1. User runs Claude with `--dangerously-skip-permissions` for an autonomous task.
2. Claude hits a fork: "should I use REST or GraphQL?" Calls `AskUserQuestion`.
3. Our hook receives `PermissionRequest`, sees `permissionMode == "bypassPermissions"`, allows immediately.
4. Claude sees no answer. Picks something arbitrary or proceeds based on no signal.
5. User wonders why their autonomous run made bizarre choices.

### The fix
Skip the bypass shortcut for AskUserQuestion:
```swift
if message.permissionMode == "bypassPermissions" && message.toolName != "AskUserQuestion" {
    respond?(BridgeResponse.allow())
    return
}
```

---

## 6. Non-deterministic permission/question queue order

**File:** `Sources/CodeIsland/Session/SessionStore.swift:438`

### The setup
When multiple sessions queue up permissions, we surface them one at a time:
```swift
func nextPendingPermission() -> String? {
    sessions.first(where: { $0.value.pendingPermission != nil })?.key
}
```

### The bug
`sessions` is `[String: Session]`. Swift dictionary iteration order is unspecified and unstable across mutations. `first(where:)` returns whichever the dictionary feels like enumerating first today. After responding to one and looking up the next, the order can change. Two queued prompts can appear in arbitrary, non-FIFO order, and that order can flip mid-session.

### Walkthrough
1. Session A asks permission at 10:00.
2. Session B asks permission at 10:01.
3. User finishes whatever they were doing at 10:05. Notch shows... B? A? It's a coin flip.
4. User responds. Notch shows the other one. From the user's perspective, the queue is random.

### The fix
Track enqueue time:
```swift
struct PendingPermission {
    // ... existing fields ...
    let requestedAt: Date
}
```
Then sort:
```swift
func nextPendingPermission() -> String? {
    sessions.values
        .filter { $0.pendingPermission != nil }
        .min(by: { $0.pendingPermission!.requestedAt < $1.pendingPermission!.requestedAt })?
        .id
}
```

---

## 7. New permission request silently replaces the one the user is deciding on

**File:** `Sources/CodeIsland/Notch/NotchWindowController.swift:90`

### The setup
When a permission event arrives, the controller pops the notch into permission mode:
```swift
case .permissionRequested(let sessionId):
    viewModel.showPermission(sessionId: sessionId)
```

### The bug
This runs unconditionally. If the user is mid-decision on session A's permission and a request arrives for session B, the UI swaps instantly to B — no animation, no badge, no warning. A button tap can race the swap and apply to the wrong session: user reads "Bash: rm -rf /" for A, taps Deny, the UI swaps to B (innocuous Read) just as the tap registers, and our handler denies B instead of A. A still proceeds because we never sent a response.

### Walkthrough
1. Notch shows session A's Bash prompt: `rm -rf node_modules`.
2. User reads it, decides to Allow.
3. Session B fires a Read permission for `~/.zshrc`. Notch swaps to B.
4. User's finger lands on the button. The button position now corresponds to "Deny" for B.
5. Session A: no response sent, bridge waits 300s, eventually times out. Tool call proceeds anyway because Claude doesn't get an explicit deny in time.
6. Session B: denied, but the user thought they were allowing A.

### The fix
Only swap when the notch isn't already showing a permission/question:
```swift
case .permissionRequested(let sessionId):
    switch viewModel.state {
    case .permission, .question: break   // already showing one; let the queue drain
    default: viewModel.showPermission(sessionId: sessionId)
    }
```
After the current one resolves, `nextPendingPermission()` picks up B.

---

## 8. SessionEnd's deferred removal can delete a freshly-recreated session

**File:** `Sources/CodeIsland/Session/SessionStore.swift:152`

### The setup
When a session ends, we mark it completed and remove it 5 seconds later:
```swift
case "SessionEnd":
    sessions[sessionId]?.status = .completed
    Task {
        try? await Task.sleep(for: .seconds(5))
        sessions.removeValue(forKey: sessionId)
    }
```

The 5s grace exists so users see a "Done" state briefly.

### The bug
The Task captures `sessionId` by value and removes unconditionally. If the user resumes the same session ID within 5 seconds (Claude `--resume <id>` is common), `SessionStart` recreates the session, then the old removal Task fires and deletes the new one. Codex thread IDs can also repeat. There's no cancellation handle, no re-check.

### Walkthrough
1. User exits Claude session `abc123`. SessionEnd fires. Task scheduled to remove `abc123` at t+5s.
2. 2 seconds later: user types `claude --resume abc123`. SessionStart fires. New Session created with same ID.
3. t+5s: Task fires `removeValue(forKey: "abc123")`. Brand new session deleted.
4. User sees the resumed session vanish from the notch even though their agent is alive.

### The fix
Re-check at removal time:
```swift
Task {
    try? await Task.sleep(for: .seconds(5))
    if sessions[sessionId]?.status == .completed {
        sessions.removeValue(forKey: sessionId)
    }
}
```
Better: store the Task on the Session, cancel it in `ensureSession` when the ID reactivates.

---

## 9. Sweep's 2s deferred removal has the same recreate-collision bug

**File:** `Sources/CodeIsland/Session/SessionStore.swift:77`

### The setup
Same pattern as #8 but in `sweepClosedAgents`: mark completed, sleep 2s, remove.

### The bug
Same root cause: no re-check. With the sweep running every 5s, the window is small but easy to hit, especially for Codex where the 5-min idle timeout can fire while the agent is mid-tool, and a late PostToolUse "resurrects" the session — see bug #11.

### The fix
Same: re-check `sessions[id]?.status == .completed` before `removeValue`.

---

## 10. Late hook events resurrect a `.completed` session, then it gets deleted

**File:** `Sources/CodeIsland/Session/SessionStore.swift:144`

### The setup
`handleMessage` calls `ensureSession` (which creates one if missing) then runs the per-event switch — which freely mutates `status` to `.thinking`, `.toolUse`, etc.

### The bug
There's no check for "is this session already completed?". After `SessionEnd` or the sweep marks `.completed` with a removal Task pending, a late buffered hook (sockets are async, hooks can arrive out of order, OS scheduling delays) bounces the status back to `.thinking`. The notch briefly shows the session as alive. Then the pending removal Task fires anyway, killing it. From the user's view: a session appears for a fraction of a second and vanishes.

### Walkthrough
1. SessionEnd for `abc123`. Status = `.completed`. Removal scheduled for t+5s.
2. t+1s: a buffered PostToolUse arrives (it was queued in the socket while SessionEnd was being processed).
3. `handleMessage` processes it. Status = `.thinking`. Notch shows session as active.
4. t+5s: Removal Task fires. Session vanishes.
5. User: "why did that flash?"

### The fix
After `ensureSession`, guard:
```swift
if sessions[sessionId]?.status == .completed {
    return   // ignore late event
}
```
Or treat the late event as a restart: cancel the pending removal Task and reset the timer.

---

## 11. Codex 5-min idle timeout kills sessions mid-tool

**File:** `Sources/CodeIsland/Session/SessionStore.swift:68`

### The setup
We added a 5-min inactivity sweep for Codex (since PID detection doesn't work for it):
```swift
if session.source == "codex" {
    if now.timeIntervalSince(session.lastActivityAt) > codexIdleThreshold {
        shouldClose = true
    }
}
```

### The bug
`lastActivityAt` is only stamped on hook arrival. Codex fires `PreToolUse` when it starts a tool, then nothing until `PostToolUse` when the tool finishes. For a long shell command (a big git push, slow npm install, large file analysis, or a `request_user_input` the user takes their time on), 5 minutes can pass with zero hooks. Our sweep then marks the session completed mid-tool. PostToolUse arrives later → resurrect-then-die (bug #10) — or worse, the response never makes it back to Codex and the bridge times out.

### Walkthrough
1. Codex runs `git push --force` to a huge remote. Pre-tool fires at t=0.
2. Push takes 6 minutes (large LFS objects, slow network).
3. t=5min: sweep checks `lastActivityAt`, fires the idle threshold, marks the session completed.
4. Notch removes the session.
5. t=6min: git push finishes, PostToolUse fires. Session is gone; either resurrected briefly and immediately killed, or our store ignores it. The bridge's response is potentially never delivered.

### The fix
Only apply the idle check when the session is idle (not mid-tool):
```swift
if session.source == "codex" && session.status == .idle {
    if now.timeIntervalSince(session.lastActivityAt) > codexIdleThreshold {
        shouldClose = true
    }
}
```
Or: stamp `lastActivityAt` continuously while a tool is running.

---

## 12. Codex `hooks.json` is fully overwritten, destroying user/third-party hooks

**File:** `Sources/CodeIsland/Utilities/CodexInstaller.swift:52`

### The setup
`writeHooksJSON` builds a fresh dict and writes it to `~/.codex/hooks.json` every launch:
```swift
var hooksDict: [String: [[String: Any]]] = [:]
for ev in events {
    hooksDict[ev] = [["hooks": [["command": bridgeCmd, "type": "command", "timeout": 5]]]]
}
try data.write(to: url, options: .atomic)
```

No read, no merge, no idempotency check.

### The bug
Unlike `HookInstaller` (which reads existing settings.json and merges), this just overwrites. Any hook a user added — for Codex personal customization, or for another tool — is obliterated on every launch.

### Walkthrough
1. User adds a custom hook to `~/.codex/hooks.json` that runs a script on `SessionStart`.
2. Launches Code Island.
3. `writeHooksJSON` builds a dict containing only Code Island's bridge invocation, writes the file.
4. User's custom hook: gone.

### The fix
Read existing `hooks.json`, merge only the entries whose `command` contains `code-island`, leave foreign entries alone. Mirror `HookInstaller.addHookEntry`'s `alreadyInstalled` check so we don't rewrite our own entries each launch either.

---

## 13. `[features]` detection misses dotted/inline forms and corrupts config.toml

**File:** `Sources/CodeIsland/Utilities/CodexInstaller.swift:93`

### The setup
We enable `hooks` in Codex's `config.toml`. Scanner looks for `[features]`:
```swift
if trimmed == "[features]" { featuresStart = i }
```

If not found, append `[features]\nhooks = true` at the end.

### The bug
TOML accepts other syntaxes for the same key:
- `features.hooks = true` (dotted key)
- `features = { hooks = true }` (inline table)
- `["features"]` (quoted key)

None match our literal `"[features]"` check. If the user (or another tool) wrote one of these, our scanner returns `featuresStart = nil`, we happily append a `[features]\nhooks = true` block, and now the file has TWO definitions of `features` — TOML forbids redefining a table. Codex refuses to load `config.toml` entirely, and the user is locked out of Codex until they manually repair it.

### Walkthrough
1. User has `features.hooks = false` in their config.toml.
2. Code Island launches, scanner doesn't see `[features]` line.
3. We append `[features]\nhooks = true`.
4. Codex parses config.toml on next run: "duplicate definition of 'features'". Refuses to start.
5. User: "why does codex refuse to start now?"

### The fix
Detect dotted/inline forms too:
```swift
let hasFeaturesPrefix = lines.contains { line in
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed.hasPrefix("features.") || trimmed.hasPrefix("features ") || trimmed.hasPrefix("features=")
}
if hasFeaturesPrefix && featuresStart == nil {
    Log.warn("config.toml uses dotted/inline features form; refusing to append")
    return
}
```

---

## 14. Codex app-server respawn has no backoff or retry cap

**File:** `Sources/CodeIsland/Codex/CodexAppServerClient.swift:135`

### The setup
When the spawned `codex app-server` subprocess dies, we relaunch:
```swift
relaunchTask = Task { @MainActor [weak self] in
    try? await Task.sleep(for: .seconds(5))
    guard let self, !self.stopped else { return }
    self.spawn()
}
```

### The bug
Fixed 5s delay, no consideration of why it died, no cap on retries. If the codex binary itself is broken (version mismatch, missing auth, dependency on a moved file), every 5 seconds for the entire app lifetime we fork a new process that dies in milliseconds. CLAUDE.md claims "short backoff and that's it" but it's actually a tight retry loop forever — wasting CPU, fork()s, fds, and flooding `Console.app`.

### The fix
Exponential backoff with a cap and a failure threshold:
```swift
private var consecutiveFailures = 0
private var lastSpawnAt = Date()

private func handleTermination() {
    let lifetime = Date().timeIntervalSince(lastSpawnAt)
    if lifetime < 30 {
        consecutiveFailures += 1
    } else {
        consecutiveFailures = 0
    }
    if consecutiveFailures > 10 {
        Log.error("Codex app-server keeps dying — giving up")
        return
    }
    let delay = min(pow(2.0, Double(consecutiveFailures)) * 5, 300)
    // sleep delay, then spawn
}
```

---

## 15. Codex app-server stderr is never drained — child can deadlock

**File:** `Sources/CodeIsland/Codex/CodexAppServerClient.swift:106`

### The setup
We attach a pipe for stderr but don't read it:
```swift
let stderr = Pipe()
task.standardError = stderr
```

### The bug
macOS pipe buffers are 16–64 KB. When stderr fills, the child's next `write(2)` to it blocks. Codex app-server logs to stderr on initialization, errors, telemetry, and any chatty build. Once stderr buffer is full, the child blocks on the next stderr write, which means it ALSO can't make progress on stdout (because writes are interleaved on the same thread). The whole subprocess wedges. We stop receiving thread/started/closed events. Our relaunch path never triggers because the child hasn't terminated.

### Walkthrough
1. Codex app-server has a build with chatty stderr logging — say, 200 bytes per JSON-RPC message.
2. Over time, stderr fills the 32KB pipe buffer.
3. Next stderr write blocks.
4. Subprocess wedges. Our stdout reader sees nothing. Threads dict goes stale.
5. Sessions stop appearing in the notch even though Codex is technically running.

### The fix
Either drain stderr:
```swift
stderr.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    if !data.isEmpty, let s = String(data: data, encoding: .utf8) {
        NSLog("[codex-app-server stderr] %@", s)
    }
}
```
Or send stderr to `/dev/null`:
```swift
task.standardError = FileHandle.nullDevice
```

---

## 16. Stale stdout handler corrupts buffer across Codex app-server respawn

**File:** `Sources/CodeIsland/Codex/CodexAppServerClient.swift:135`

### The setup
On termination, we null the references:
```swift
process = nil
stdoutPipe = nil
```

### The bug
We never clear the old pipe's `readabilityHandler`. Foundation keeps the FileHandle alive until EOF is drained — and the closure inside the handler captures `self`, so it can fire again after termination. It dispatches `Task { @MainActor self?.ingest(data: data) }` onto the same `self.buffer`. Meanwhile, the new spawn's handler also dispatches `ingest` onto the same buffer. A half-written JSON line from the old process gets prefixed onto bytes from the new process. `handleLine` sees malformed JSON, drops it silently, and we miss `thread/started` events.

### The fix
Explicitly clear the handler:
```swift
stdoutPipe?.fileHandleForReading.readabilityHandler = nil
stdoutPipe = nil
```
Plus stamp each spawn with a generation token; readability handler closures check the token and no-op if stale.

---

## 17. Codex `prefix_rule` for non-Bash tools never matches

**File:** `Sources/CodeIsland/Utilities/CodexPermissionRules.swift:73`

### The setup
"Allow All" for Codex writes a `prefix_rule` to `~/.codex/rules/codeisland.rules`:
```swift
if toolName.lowercased() == "bash", let cmd = toolInput {
    return shellPrefix(from: cmd, maxTokens: 3)
}
return [toolName]   // fallback for Write, Read, Edit, etc.
```

### The bug
Codex's `prefix_rule` matches shell-command token prefixes, not tool names. A rule with `pattern = ["Write"]` means "match commands starting with the literal word `Write`" — which no shell command does. So clicking "Allow All" for `Write` writes a rule that will never match anything. The next `Write` call re-prompts.

### Walkthrough
1. Claude wants to write a file. Notch shows permission.
2. User clicks "Allow All". Rule written: `prefix_rule(pattern = ["Write"], decision = "allow")`.
3. Notch confirms the one-shot allow.
4. Claude writes another file. Notch prompts again. User: "I clicked Allow All!"

### The fix
Either restrict "Allow All" to Bash on Codex sessions, or relabel the button for non-Bash tools ("Allow once for this file"). At minimum, surface in the UI that Allow All isn't persisted for non-Bash Codex tools.

---

## 18. Codex shell prefix tokens contain literal quote characters

**File:** `Sources/CodeIsland/Utilities/CodexPermissionRules.swift:84`

### The setup
`shellPrefix` parses a Bash command into tokens for the rule. When it encounters a quote:
```swift
if ch == "\"" && !inSingle { inDouble.toggle(); current.append(ch); continue }
```

### The bug
The quote character is *appended* to the current token. So `git commit -m "fix"` produces tokens `["git", "commit", "-m", "\"fix\""]`. Codex matches the rule against the parsed argv (quotes already stripped by the shell), so it sees `["git", "commit", "-m", "fix"]`. Our token `"\"fix\""` ≠ `fix`. Rule never matches. User clicks "Allow All", and on the very next `git commit -m "..."` they're prompted again.

This breaks Allow All for any Bash command with a quoted segment in the first 3 tokens: `git commit`, `bash -c`, anything with quoted paths.

### The fix
Don't append the quote — treat it as a delimiter:
```swift
if ch == "\"" && !inSingle { inDouble.toggle(); continue }
if ch == "'" && !inDouble { inSingle.toggle(); continue }
```

---

## 19. Multiline/control-char Bash commands break the entire rules file

**File:** `Sources/CodeIsland/Utilities/CodexPermissionRules.swift:116`

### The setup
TOML string escaping in `quotedRuleString`:
```swift
let escaped = value
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
return "\"\(escaped)\""
```

### The bug
TOML basic strings forbid raw newlines and U+0000–U+001F/U+007F. We escape `\` and `"`, nothing else. `shellPrefix` happily produces tokens containing literal newlines/tabs (heredocs, multi-line `-c '…'` scripts, any agent that hands the bridge a script body with embedded newlines).

The resulting `codeisland.rules` becomes invalid TOML. Codex's loader rejects ALL rules including ones that were previously fine. User's Allow All history: silently gone until they manually find and repair the file.

### The fix
Escape all control chars via `\uXXXX`, or validate input is printable ASCII before writing:
```swift
guard value.allSatisfy({ ch in
    let scalar = ch.unicodeScalars.first!.value
    return scalar >= 0x20 && scalar < 0x7F
}) else { return false }
```

---

## 20. AppleScript command injection via cwd / folder name

**File:** `Sources/CodeIsland/Terminal/TerminalJumper.swift:99`

### The setup
TerminalJumper builds AppleScript by string interpolation:
```swift
let script = """
tell application "Terminal"
    do script "cd \(folder)"
end tell
"""
NSAppleScript(source: script).executeAndReturnError(&error)
```

### The bug
`folder` comes from `session.cwd.lastPathComponent`. If a project folder is named `foo" or true) or (name of x is "y`, the interpolation breaks the script — at best it errors, at worst it executes arbitrary AppleScript via System Events with the Accessibility privileges the user granted Code Island. Since `cwd` originates from hook payloads, a malicious project (or a transcript file pulled from disk) can trigger this.

### Walkthrough
1. User clones a malicious repo to a folder named `proj"; tell application "Finder" to delete every file of folder "Documents" --` (or similar).
2. Claude runs in that folder. Hook payload's cwd contains the malicious name.
3. User clicks the session card in the notch to jump.
4. TerminalJumper interpolates the name into AppleScript.
5. AppleScript executes the injected code with full system access.

### The fix
Sanitize before interpolation:
```swift
func escapeAppleScriptString(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
     .replacingOccurrences(of: "\"", with: "\\\"")
     .filter { !$0.isNewline }
}
```
Or use `NSAppleEventDescriptor` parameters instead of source interpolation.

---

## 21. Update checker mis-orders pre-release vs release versions

**File:** `Sources/CodeIsland/Utilities/UpdateChecker.swift:100`

### The setup
Version comparison:
```swift
if let li = Int(l), let ci = Int(c) {
    if li != ci { return li > ci }
} else if l != c {
    return l > c   // string compare fallback
}
```

### The bug
For `latest=1.0.0` vs `current=1.0.0-beta`: when comparing the last segment, `"0"` vs `"0-beta"`. Neither parses as Int. String compare: `"0" < "0-beta"` (Swift treats prefix as less). So `isNewer` returns false. A user on `1.0.0-beta` never gets notified about GA `1.0.0`.

Reverse case (`latest=1.0.0-beta`, `current=1.0.0`): string compare says beta is newer than GA.

### The fix
Strip pre-release suffix before numeric compare, and treat presence of `-` as lower precedence:
```swift
let lCore = latest.split(separator: "-").first.map(String.init) ?? latest
let cCore = current.split(separator: "-").first.map(String.init) ?? current
// numeric compare lCore vs cCore...
// if equal cores, the one without "-" wins
```

---

## 22. Rate-limited keychain probe burns refresh-token rotations

**File:** `Sources/CodeIsland/Usage/ClaudeCredentials.swift:85`

### The setup
We probe Anthropic's API with the access token. If `.unauthorized`, refresh. The current code:
```swift
switch probeResult {
case .success: return .success(token)
case .scopeInsufficient: return .failed(...)
default: break   // falls through to refresh for everything else
}
return try await refreshClaudeToken(...)
```

### The bug
`default` catches `.rateLimited` (HTTP 429) and `.otherError` (5xx, timeouts) too. Falling through to refresh means we call Anthropic's token-refresh endpoint, which *rotates the refresh token on every call*. A 429 or transient 5xx — neither of which has anything to do with the access token being invalid — costs us a rotation.

Worse: Claude CLI also has the old refresh token in its keychain. A rotation race between Code Island and the CLI can leave one of them stuck with a dead refresh token, eventually locking the user out and forcing `claude /login`.

### The fix
Only refresh on actual auth failure:
```swift
switch probeResult {
case .success: return .success(token)
case .scopeInsufficient: return .failed(...)
case .unauthorized: break   // ← only refresh here
case .rateLimited, .otherError(let err): return .failed(err)
}
return try await refreshClaudeToken(...)
```

---

# MEDIUM

These are real bugs but lower-impact or less frequent than the highs.

## 23. Server fd leaks via dropped permission responder closures

**File:** `Sources/CodeIsland/IPC/SocketServer.swift:144` · Same root cause as bug #2 (lifetime cluster — fix together).

For PermissionRequest, `close(fd)` only happens inside the respond closure. Any path that drops the closure without calling it leaks the fd. **Fix:** wrap fd in an RAII class with `deinit { close(fd) }`, OR always call respond before dropping.

---

## 24. Accept loop spins at 100% CPU when `accept()` fails

**File:** `Sources/CodeIsland/IPC/SocketServer.swift:79`

`accept()` returning -1 with errno != EINTR (typically EMFILE/ENFILE under fd exhaustion — which we'll hit thanks to bugs #2/#23) triggers an immediate retry with no backoff. Burns a CPU core indefinitely. **Fix:** `usleep(10_000)` on non-fatal accept errors; longer for EMFILE/ENFILE.

---

## 25. Codex `request_user_input` Submit silently discards the user's answer

**File:** `Sources/CodeIsland/Session/SessionStore.swift:462`

The Codex question UI shows pill options, a custom text field, and a Submit button. On submit, we build an `allowWithAnswers` payload — but the Codex respond closure (line 186) ignores its data and only calls `TerminalJumper.jump`. The user's selections and typed text go in the trash with no UI hint. **Fix:** for Codex sessions, relabel the button to "Open Codex to answer" and hide the text field (since we can't actually pass an answer back via hook).

---

## 26. Question answers joined with `|` collide with user input containing `|`

**File:** `Sources/CodeIsland/Notch/Views/QuestionView.swift:271`

```swift
let answers = questions.map { selections[$0.id] }.joined(separator: "|")
```
Any answer containing `|` (`find . | grep foo`, regex alternation `A|B`) splits incorrectly downstream. Multi-select uses `", "` (with space) but Claude expects `","` (no space) per CLAUDE.md. **Fix:** pass `[String: String]` directly from view → SessionStore. If a delimiter is unavoidable, use U+001F (unit separator) or JSON-encode.

---

## 27. Finished-card auto-collapse never re-arms when blocked by hover

**File:** `Sources/CodeIsland/Notch/NotchViewModel.swift:159`

`showFinished` schedules ONE 3s auto-collapse. If `isHovered == true` when the timer fires, the body just `return`s. There's no re-schedule. A parked cursor leaves the finished card on screen forever. **Fix:** if predicate fails because of hover, restart with a 0.6s delay and re-check until `!isHovered`. Or hard-collapse at 15s regardless.

---

## 28. FinishedView outer onTapGesture swallows taps meant for chrome buttons

**File:** `Sources/CodeIsland/Notch/Views/FinishedView.swift:201`

The outer VStack has `.contentShape(Rectangle()).onTapGesture { TerminalJumper.jump(…) }`. Sound, gear, dismiss, expand buttons are inside that same VStack. SwiftUI's hit testing absorbs near-misses on the small buttons — user thought they were dismissing, they actually opened the terminal. **Fix:** move the tap gesture to the inner session-header subregion only.

---

## 29. PID reuse keeps dead Claude sessions alive forever

**File:** `Sources/CodeIsland/Session/SessionStore.swift:60`

Sweep treats any non-ESRCH from `kill(pid, 0)` as "alive". macOS recycles pids quickly; once the agent dies and the kernel reassigns the pid to anything (a daemon, a brand-new app), the session looks alive indefinitely. Codex has the idle timer as backup; Claude has none, and SessionEnd is known-unreliable. **Fix:** capture process start time alongside the pid (`KERN_PROC_PID → kp_proc.p_starttime`); verify it matches on each probe.

---

## 30. (Duplicate of #14 at a different line in the same area — fix together.)

---

## 31. TOML/JSON re-sorted on every launch — dirties git, surprises users

**File:** `Sources/CodeIsland/Utilities/HookInstaller.swift:147`

`JSONSerialization` with `.sortedKeys` rewrites `~/.claude/settings.json` keys into alphabetic order on every install. Dotfile repos see a constant diff. Claude Code might think the file changed mid-session. **Fix:** diff before writing; only write when something actually changed. Drop `.sortedKeys`.

---

## 32. Hook installer write failures swallowed; `install()` always returns true

**File:** `Sources/CodeIsland/Utilities/HookInstaller.swift:49`

`try?` everywhere, `install()` returns `true` unconditionally. Onboarding keys off this Bool per CLAUDE.md and always shows success. Same pattern in `CodexInstaller`. **Fix:** propagate errors, return `false` and log when any required write fails.

---

## 33. (Duplicate of #19 — multi-line Bash → invalid TOML at a different line.)

---

## 34. Failed update check still bumps `lastCheckedAt`, suppressing retries for 7 days

**File:** `Sources/CodeIsland/Utilities/UpdateChecker.swift:53`

A `defer` block writes `lastCheckedAt = Date()` on every path including HTTP timeouts, non-200, errors. A single offline launch effectively disables update notifications for a week. **Fix:** only persist `lastCheckedAt` on successful fetch. On error, store a short-lived retry timestamp (1h) instead.

---

## 35. (Duplicate of #12 at a different line — Codex hooks.json overwrite.)

---

# LOW

## 36. Codex app-server never receives `initialize`

**File:** `Sources/CodeIsland/Codex/CodexAppServerClient.swift:110`

Most JSON-RPC servers require an `initialize` handshake before notifications stream. We attach stdin but never write to it. If Codex's `app-server` follows the LSP convention, the threads dict stays empty forever — silently broken. **Fix:** send `initialize` on spawn (if Codex requires it); close stdin if we don't intend to write.

---

## 37. `applyCodexThreads` emits `sessionStarted` zero or twice

**File:** `Sources/CodeIsland/Session/SessionStore.swift:407`

`applyCodexThreads` emits `sessionStarted` on create. `ensureSession` (the hook path) doesn't. Depending on whether `thread/started` or the first hook arrives first, subscribers (sounds, metrics) see 0 or 2 events for the same id. **Fix:** add an `announcedStart: Bool` on Session and only emit once.

---

## 38. `applyCodexThreads` cwd-update guard checks for literal `"~"`

**File:** `Sources/CodeIsland/Session/SessionStore.swift:430`

`sessions[id]?.cwd == "~"` only updates cwd when it's the literal placeholder, but `ensureSession` resolves to the real home path. Once a hook arrives with the real cwd, the placeholder is gone and a more specific cwd from the app-server (e.g. the project subdir) is never applied. **Fix:** compare against `FileManager.default.homeDirectoryForCurrentUser.path` or introduce an explicit `cwdIsPlaceholder` flag.

---

## 39. Rate-limit formatter drops hours/minutes once ≥24h

**File:** `Sources/CodeIsland/Utilities/RateLimitStore.swift:16`

```swift
if hours >= 24 { return "\(hours / 24)d" }
```
Both `25h59m` and `47h59m` display as `1d`. Int truncation also jumps from `23h59m` straight to `1d` in one tick, which looks like the bar got worse. **Fix:** `"\(hours / 24)d\(hours % 24)h"` for ≥24h, or use `DateComponentsFormatter`.

---

# Suggested order of operations

Fix these five first — they cluster on the same fragile area (IPC + permission lifecycle) and unblock everything else:

1. **`SessionStore.swift:137`** — `pendingDismissedExternally` fd leak (critical). Causes the bridge to hang, leaks fds, accumulates zombie hook processes, feeds the accept-loop CPU spin.
2. **`SocketServer.swift:113`** — `n < bufSize` framing bug (critical). The "8KB invalid-JSON" symptom. Length-prefixed framing removes the awkward shutdown coupling with PermissionRequest.
3. **`HookInstaller.swift:18`** — silent wipe of `~/.claude/settings.json` (critical). Runs every launch, can permanently destroy hand-edited config. One-line guard now, follow up with `.bak` + propagated errors.
4. **`SocketServer.swift:138`** — install `SIGPIPE` ignore + `SO_NOSIGPIPE` (high). 3-line fix, very high upside.
5. **`SessionStore.swift:211`** — bypass mode swallows AskUserQuestion answers (high). Tiny fix, surprising bug.

After this batch, tackle the Codex hooks/TOML cluster (#12, #13, #18, #19) since they all corrupt user config and share fix patterns, then the session-lifecycle group (#8, #9, #10, #11) which all need the same "re-check before deferred removal" pattern.
