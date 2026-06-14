import Foundation
import AppKit
import Combine

/// Snapshot of a Codex thread from the app-server stream. We only keep the
/// fields we actually consume — id is required, everything else is optional
/// because Codex's notification schema isn't fully stable.
struct CodexThreadInfo: Equatable {
    let id: String
    var name: String?
    var cwd: String?
}

/// Spawns `codex app-server --listen stdio://` as a subprocess and listens for
/// `thread/started` notifications so Code Island can pick up the user-renamed
/// session names that aren't available through hook payloads.
///
/// Scope is intentionally tight — we only consume the few JSON-RPC
/// notifications that carry session metadata. No request/response cycle, no
/// reconnection-state machine; if the subprocess dies we relaunch after a
/// short backoff and that's it. A fuller app-server client (request/response,
/// reconnection) can be layered on here if a richer integration is needed later.
@MainActor
final class CodexAppServerClient: ObservableObject {
    /// Snapshot of every active Codex thread we know about via the app-server
    /// stream. Updated on `thread/started` and pruned on `thread/closed`.
    /// SessionStore mirrors these into proper sessions so resumed Codex
    /// threads show up in the notch immediately — before any hook fires.
    @Published private(set) var threads: [String: CodexThreadInfo] = [:]

    /// Convenience map for code paths that only care about renamed titles.
    var threadNames: [String: String] {
        threads.mapValues { $0.name ?? "" }.filter { !$0.value.isEmpty }
    }

    /// Fires with each thread id the daemon reports as closed/archived.
    /// SessionStore subscribes to clean up sessions — necessary because the
    /// bridge's `agent_pid` for Codex points at the never-dying daemon, so
    /// process-PID sweeps can't detect when a Codex thread has actually ended.
    let closedThreadIds = PassthroughSubject<String, Never>()

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var buffer = Data()
    private var relaunchTask: Task<Void, Never>?
    private var stopped = false

    /// Generation token incremented on every spawn. Stale stdout/stderr
    /// readability handlers from a dead child compare against this and
    /// no-op if it's changed (issue #16).
    private var generation: Int = 0

    /// Spawn-failure tracking for exponential backoff (issue #14).
    private var consecutiveQuickFailures: Int = 0
    private var lastSpawnAt: Date = .distantPast
    /// Once we've hit this many sub-1s lifetimes in a row, stop trying.
    private let maxConsecutiveQuickFailures = 10

    /// Common install paths for the `codex` CLI in priority order. Mirrors the
    /// approach the reference repo uses for the Claude CLI — we deliberately
    /// don't shell out to `which` because LaunchServices gives a GUI app a
    /// stripped PATH (`/usr/bin:/bin:/usr/sbin:/sbin`) that misses every
    /// Homebrew / nvm / Bun / npm install.
    private static func locateCodexBinary() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.bun/bin/codex",
            "\(home)/.npm-global/bin/codex",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Fall back to scanning common nvm node version directories.
        let nvmRoot = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmRoot) {
            for version in versions.sorted(by: >) {
                let candidate = "\(nvmRoot)/\(version)/bin/codex"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    func start() {
        stopped = false
        spawn()
    }

    func stop() {
        stopped = true
        relaunchTask?.cancel()
        process?.terminate()
        process = nil
    }

    private func spawn() {
        guard let executablePath = Self.locateCodexBinary() else {
            // Codex isn't installed in any known location. Stay quiet — the
            // rest of the app still works fine via hooks.
            return
        }
        NSLog("[CodeIsland] Spawning codex app-server from \(executablePath)")
        generation += 1
        let gen = generation
        lastSpawnAt = Date()

        let task = Process()
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = ["app-server"]

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr
        // App-server reads JSON-RPC requests from stdin, but we don't send any —
        // we're a passive notification consumer. Wire a dummy pipe so the child
        // doesn't block trying to talk to a closed handle.
        task.standardInput = Pipe()

        // Drain stderr so the child doesn't deadlock when its pipe buffer
        // fills (issue #15). Stale handlers from a previous spawn check the
        // generation token and no-op (issue #16).
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == gen else { return }
                self.ingest(data: data)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let s = String(data: data, encoding: .utf8) {
                NSLog("[codex app-server stderr] %@", s.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        task.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTermination(gen: gen)
            }
        }

        do {
            try task.run()
            self.process = task
            self.stdoutPipe = stdout
            self.stderrPipe = stderr
            sendInitializeHandshake()
        } catch {
            NSLog("[CodeIsland] Failed to spawn codex app-server: \(error.localizedDescription)")
        }
    }

    /// Send `initialize` request + `initialized` notification per the
    /// Codex JSON-RPC schema. Without this handshake some app-server
    /// builds keep notifications gated and the threads dict stays empty
    /// (issue #36).
    private func sendInitializeHandshake() {
        guard let stdin = (process?.standardInput as? Pipe)?.fileHandleForWriting else { return }
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.1.0"
        let initRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "code-island",
                    "title": "Code Island",
                    "version": version
                ]
            ]
        ]
        let initializedNote: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "initialized",
            "params": [:]
        ]
        for msg in [initRequest, initializedNote] {
            guard let data = try? JSONSerialization.data(withJSONObject: msg) else { continue }
            try? stdin.write(contentsOf: data)
            try? stdin.write(contentsOf: Data([0x0A]))  // newline terminator
        }
    }

    private func handleTermination(gen: Int) {
        // Ignore terminations from a stale generation — handleTermination
        // can race with a fresh spawn if Foundation dispatches the prior
        // child's handler after we've already replaced it.
        guard gen == generation else { return }

        // Detach the readability handlers explicitly so the old FileHandle's
        // closures can be released and don't bleed bytes from this dead
        // child into the buffer of the next spawn (issue #16).
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
        buffer.removeAll()

        guard !stopped else { return }

        // Exponential backoff with a quick-failure cap (issue #14). Lifetime
        // less than 30s counts as a quick failure; otherwise reset. After N
        // consecutive quick failures we give up to avoid a tight fork loop
        // when the binary is broken.
        let lifetime = Date().timeIntervalSince(lastSpawnAt)
        if lifetime < 30 {
            consecutiveQuickFailures += 1
        } else {
            consecutiveQuickFailures = 0
        }
        if consecutiveQuickFailures >= maxConsecutiveQuickFailures {
            NSLog("[CodeIsland] codex app-server has died %d times in a row — giving up", consecutiveQuickFailures)
            return
        }

        let delaySeconds = min(pow(2.0, Double(consecutiveQuickFailures)) * 5, 300)
        NSLog("[CodeIsland] codex app-server died (lifetime=%.1fs); relaunching in %.0fs (failure #%d)", lifetime, delaySeconds, consecutiveQuickFailures)
        relaunchTask?.cancel()
        relaunchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard let self, !self.stopped else { return }
            self.spawn()
        }
    }

    private func ingest(data: Data) {
        buffer.append(data)
        // Newline-delimited JSON — split on `\n`, keep the trailing partial
        // segment for the next ingest call.
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: 0..<nl)
            buffer.removeSubrange(0...nl)
            if line.isEmpty { continue }
            handleLine(line)
        }
    }

    private func handleLine(_ line: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        // Notifications carry a `method` and `params` but no `id`.
        guard let method = json["method"] as? String,
              let params = json["params"] as? [String: Any] else { return }

        switch method {
        case "thread/started":
            // Codex's thread/started payload nests fields under "thread"; some
            // builds emit them at the top level. Tolerate both.
            let thread = (params["thread"] as? [String: Any]) ?? params
            guard let id = thread["id"] as? String, !id.isEmpty else { return }
            var info = threads[id] ?? CodexThreadInfo(id: id)
            if let name = thread["name"] as? String, !name.isEmpty {
                info.name = name
            } else if let preview = thread["preview"] as? String, !preview.isEmpty {
                info.name = preview
            }
            if let cwd = thread["cwd"] as? String, !cwd.isEmpty {
                info.cwd = cwd
            }
            threads[id] = info
        case "thread/closed", "thread/archived":
            let closedId: String? = {
                if let id = params["threadId"] as? String { return id }
                if let thread = params["thread"] as? [String: Any],
                   let id = thread["id"] as? String { return id }
                return nil
            }()
            if let id = closedId {
                threads.removeValue(forKey: id)
                closedThreadIds.send(id)
                NSLog("[CodeIsland] Codex thread closed: \(id)")
            }
        default:
            break
        }
    }
}
