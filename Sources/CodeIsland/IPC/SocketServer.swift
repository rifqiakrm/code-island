import Foundation

/// Unix domain socket server that receives messages from the bridge CLI.
final class SocketServer {
    private let socketPath = "/tmp/code-island.sock"
    private let acceptQueue = DispatchQueue(label: "dev.codeisland.socket.accept", qos: .userInitiated)
    private let clientQueue = DispatchQueue(label: "dev.codeisland.socket.client", qos: .userInitiated, attributes: .concurrent)
    private var serverFd: Int32 = -1
    private var running = false

    var onMessage: ((BridgeMessage, ((BridgeResponse) -> Void)?, ((Data) -> Void)?) -> Void)?

    func start() {
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
                if running {
                    print("[CodeIsland] Accept error: \(String(cString: strerror(errno)))")
                }
                continue
            }

            Log.info("Socket: accepted client fd=\(clientFd)")
            clientQueue.async { [weak self] in
                self?.handleClient(clientFd)
            }
        }
    }

    // MARK: - Client Handling

    private func handleClient(_ fd: Int32) {
        // Read all available data (may come in chunks)
        var allData = Data()
        let bufSize = 65536
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }

        // Set a short read timeout so we don't block forever on partial reads
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        while true {
            let n = read(fd, buf, bufSize)
            if n > 0 {
                allData.append(buf, count: n)
                // If we got less than buffer, we likely have everything
                if n < bufSize { break }
            } else {
                break
            }
        }

        Log.info("Socket: read \(allData.count) bytes from fd=\(fd)")

        guard !allData.isEmpty else {
            Log.error("Socket: empty data from client")
            close(fd)
            return
        }

        guard let message = try? JSONDecoder().decode(BridgeMessage.self, from: allData) else {
            Log.error("Socket: invalid JSON: \(String(data: allData.prefix(300), encoding: .utf8) ?? "?")")
            close(fd)
            return
        }

        let isPermission = message.hookEvent == "PermissionRequest"

        let respond: ((BridgeResponse) -> Void)? = isPermission ? { response in
            Log.info("Socket: writing response to fd=\(fd)")
            if let responseData = try? JSONEncoder().encode(response) {
                let written = responseData.withUnsafeBytes { ptr in
                    write(fd, ptr.baseAddress!, responseData.count)
                }
                Log.info("Socket: wrote \(written) bytes to fd=\(fd)")
            }
            close(fd)
        } : nil

        // Raw data responder for question answers (custom JSON)
        let respondRaw: ((Data) -> Void)? = isPermission ? { rawData in
            Log.info("Socket: writing raw response to fd=\(fd), \(rawData.count) bytes")
            rawData.withUnsafeBytes { ptr in
                _ = write(fd, ptr.baseAddress!, rawData.count)
            }
            close(fd)
        } : nil

        Log.info("Socket: parsed message hookEvent=\(message.hookEvent) session=\(message.sessionId.prefix(8)) permissionMode=\(message.permissionMode ?? "nil") toolName=\(message.toolName ?? "nil")")

        DispatchQueue.main.async { [weak self] in
            self?.onMessage?(message, respond, respondRaw)
        }

        if !isPermission {
            close(fd)
        }
    }
}
