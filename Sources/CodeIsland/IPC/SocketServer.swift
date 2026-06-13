import Foundation

/// Unix domain socket server that receives messages from the bridge CLI.
///
/// Wire protocol: each message is a 4-byte big-endian uint32 length prefix
/// followed by exactly that many bytes of JSON. Replaces the previous
/// `n < bufSize` end-of-message heuristic which silently truncated any
/// payload that didn't fit in a single read (issue #1).
///
/// For `PermissionRequest`, the connection stays open after the message is
/// delivered; the response is then framed the same way back to the bridge.
final class SocketServer {
    private let socketPath = "/tmp/code-island.sock"
    private let acceptQueue = DispatchQueue(label: "dev.codeisland.socket.accept", qos: .userInitiated)
    private let clientQueue = DispatchQueue(label: "dev.codeisland.socket.client", qos: .userInitiated, attributes: .concurrent)
    private var serverFd: Int32 = -1
    private var running = false

    var onMessage: ((BridgeMessage, ((BridgeResponse) -> Void)?, ((Data) -> Void)?) -> Void)?

    func start() {
        // Defense in depth: even with SO_NOSIGPIPE per-socket, install a
        // process-level ignore so any miss (or a third-party write to a
        // dead pipe) can't kill the app (issue #4).
        signal(SIGPIPE, SIG_IGN)

        // Remove stale socket file
        unlink(socketPath)

        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            print("[CodeIsland] Failed to create socket: \(String(cString: strerror(errno)))")
            return
        }

        // Allow socket reuse
        var yes: Int32 = 1
        setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        // Bind to Unix path
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        let pathSize = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutableBytes(of: &addr.sun_path) { rawPtr in
            for i in 0..<min(pathBytes.count, pathSize - 1) {
                rawPtr[i] = pathBytes[i]
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            print("[CodeIsland] Failed to bind socket: \(String(cString: strerror(errno)))")
            close(serverFd)
            serverFd = -1
            return
        }

        guard listen(serverFd, 16) == 0 else {
            print("[CodeIsland] Failed to listen: \(String(cString: strerror(errno)))")
            close(serverFd)
            serverFd = -1
            return
        }

        running = true
        Log.info("Socket server listening on \(socketPath)")

        acceptQueue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        running = false
        if serverFd >= 0 {
            close(serverFd)
            serverFd = -1
        }
        unlink(socketPath)
        print("[CodeIsland] Socket server stopped")
    }

    // MARK: - Accept Loop

    private func acceptLoop() {
        while running {
            let clientFd = accept(serverFd, nil, nil)
            guard clientFd >= 0 else {
                let err = errno
                // EBADF / EINVAL = server socket closed during shutdown; exit cleanly.
                if err == EBADF || err == EINVAL || !running {
                    return
                }
                if running {
                    Log.error("Socket: accept error \(err): \(String(cString: strerror(err)))")
                }
                // Avoid 100% CPU spin on fd exhaustion / connection abort (issue #24).
                // Sleep longer when we're out of fds — backing off gives users a
                // chance to recover by closing other apps.
                if err == EMFILE || err == ENFILE {
                    usleep(250_000)
                } else if err != EINTR {
                    usleep(10_000)
                }
                continue
            }

            // Per-socket SIGPIPE suppression — if the peer disconnects between
            // when we accept and when we write the response, write() must
            // return EPIPE instead of raising SIGPIPE (issue #4).
            var on: Int32 = 1
            setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

            Log.info("Socket: accepted client fd=\(clientFd)")
            clientQueue.async { [weak self] in
                self?.handleClient(clientFd)
            }
        }
    }

    // MARK: - Client Handling

    private func handleClient(_ fd: Int32) {
        // 30s ceiling on the framed read so a misbehaving peer can't park a worker.
        var timeout = timeval(tv_sec: 30, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // 1. Read 4-byte length prefix
        guard let len = readUInt32BE(fd: fd) else {
            Log.error("Socket: failed to read length prefix from fd=\(fd)")
            close(fd)
            return
        }
        // Sanity cap: refuse anything larger than 4 MB.
        guard len > 0, len <= 4 * 1024 * 1024 else {
            Log.error("Socket: implausible message length \(len) on fd=\(fd)")
            close(fd)
            return
        }

        // 2. Read exactly `len` bytes of payload
        guard let payload = readExactly(fd: fd, count: Int(len)) else {
            Log.error("Socket: short read of \(len)-byte payload on fd=\(fd)")
            close(fd)
            return
        }

        Log.info("Socket: read \(payload.count) bytes from fd=\(fd)")

        guard let message = try? JSONDecoder().decode(BridgeMessage.self, from: payload) else {
            Log.error("Socket: invalid JSON: \(String(data: payload.prefix(300), encoding: .utf8) ?? "?")")
            close(fd)
            return
        }

        let isPermission = message.hookEvent == "PermissionRequest"

        // Both responders are guaranteed to call close(fd). SessionStore
        // also guarantees one of them runs (issue #2).
        let respond: ((BridgeResponse) -> Void)? = isPermission ? { [weak self] response in
            Log.info("Socket: writing response to fd=\(fd)")
            if let responseData = try? JSONEncoder().encode(response) {
                self?.writeFramed(fd: fd, payload: responseData)
            }
            close(fd)
        } : nil

        let respondRaw: ((Data) -> Void)? = isPermission ? { [weak self] rawData in
            Log.info("Socket: writing raw response to fd=\(fd), \(rawData.count) bytes")
            self?.writeFramed(fd: fd, payload: rawData)
            close(fd)
        } : nil

        Log.info("Socket: parsed message source=\(message.source ?? "nil") hookEvent=\(message.hookEvent) session=\(message.sessionId.prefix(12)) permissionMode=\(message.permissionMode ?? "nil") toolName=\(message.toolName ?? "nil") effort=\(message.effortLevel ?? "nil") durationMs=\(message.durationMs.map(String.init) ?? "nil") userMessage=\(message.userMessage?.prefix(40) ?? "nil")")

        DispatchQueue.main.async { [weak self] in
            self?.onMessage?(message, respond, respondRaw)
        }

        if !isPermission {
            close(fd)
        }
    }

    // MARK: - Framed read/write helpers

    /// Read exactly 4 bytes and decode as big-endian UInt32. Returns nil on
    /// short read or error.
    private func readUInt32BE(fd: Int32) -> UInt32? {
        guard let bytes = readExactly(fd: fd, count: 4) else { return nil }
        return bytes.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            return (UInt32(p[0]) << 24) | (UInt32(p[1]) << 16) | (UInt32(p[2]) << 8) | UInt32(p[3])
        }
    }

    /// Read exactly `count` bytes. Loops until satisfied or a short/error read
    /// terminates. Returns nil if EOF arrives before `count` bytes.
    private func readExactly(fd: Int32, count: Int) -> Data? {
        var data = Data(count: count)
        var got = 0
        let ok: Bool = data.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            while got < count {
                let n = read(fd, base.advanced(by: got), count - got)
                if n > 0 {
                    got += n
                } else if n == 0 {
                    return false  // EOF
                } else if errno == EINTR {
                    continue
                } else {
                    return false  // error
                }
            }
            return true
        }
        return ok ? data : nil
    }

    /// Write a length-prefixed frame. Loops until all bytes are written.
    /// Errors are logged but not raised — caller has already done its job.
    private func writeFramed(fd: Int32, payload: Data) {
        var header = [UInt8](repeating: 0, count: 4)
        let len = UInt32(payload.count)
        header[0] = UInt8((len >> 24) & 0xFF)
        header[1] = UInt8((len >> 16) & 0xFF)
        header[2] = UInt8((len >> 8) & 0xFF)
        header[3] = UInt8(len & 0xFF)
        writeAll(fd: fd, bytes: header, count: 4)
        payload.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                writeAll(fd: fd, bytes: base.assumingMemoryBound(to: UInt8.self), count: payload.count)
            }
        }
    }

    private func writeAll(fd: Int32, bytes: UnsafePointer<UInt8>, count: Int) {
        var sent = 0
        while sent < count {
            let n = write(fd, bytes.advanced(by: sent), count - sent)
            if n > 0 {
                sent += n
            } else if errno == EINTR {
                continue
            } else {
                let err = errno
                if err != EPIPE {
                    Log.error("Socket: write failed at \(sent)/\(count): \(String(cString: strerror(err)))")
                }
                return
            }
        }
    }
}
