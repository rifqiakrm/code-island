import Foundation

enum Log {
    private static let logFile: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".code-island/debug.log")
    }()

    static func info(_ msg: String) {
        write("INFO", msg)
    }

    static func error(_ msg: String) {
        write("ERROR", msg)
    }

    private static func write(_ level: String, _ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(ts)] [\(level)] \(msg)\n"
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(to: logFile, atomically: true, encoding: .utf8)
        }
    }
}
