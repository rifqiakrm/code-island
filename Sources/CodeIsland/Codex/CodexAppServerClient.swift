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
/// short backoff and that's it. The reference repo's full client lives at
/// `/Users/user/Projects/CodeIsland/Sources/CodeIslandCore/CodexAppServerClient.swift`
/// if a richer integration is needed later.
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

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var buffer = Data()
    private var relaunchTask: Task<Void, Never>?
    private var stopped = false

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

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.ingest(data: data)
            }
        }

        task.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTermination()
            }
        }

        do {
            try task.run()
            self.process = task
            self.stdoutPipe = stdout
        } catch {
            NSLog("[CodeIsland] Failed to spawn codex app-server: \(error.localizedDescription)")
        }
    }

    private func handleTermination() {
        process = nil
        stdoutPipe = nil
        buffer.removeAll()
        guard !stopped else { return }
        // Relaunch after a short delay so we don't burn CPU on a crashing binary.
        relaunchTask?.cancel()
        relaunchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
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
        case "thread/closed":
            if let id = params["threadId"] as? String {
                threads.removeValue(forKey: id)
            } else if let thread = params["thread"] as? [String: Any],
                      let id = thread["id"] as? String {
                threads.removeValue(forKey: id)
            }
        default:
            break
        }
    }
}
