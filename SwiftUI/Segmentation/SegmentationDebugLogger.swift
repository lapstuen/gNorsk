import Foundation

final class SegmentationDebugLogger {
    static let shared = SegmentationDebugLogger()

    private let queue = DispatchQueue(label: "SegmentationDebugLogger.queue", qos: .utility)

    private var logURL: URL {
        let fm = FileManager.default
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        return dir.appendingPathComponent("SegmentationDebug.log")
    }

    func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        queue.async {
            do {
                let url = self.logURL
                if !FileManager.default.fileExists(atPath: url.path) {
                    try line.data(using: .utf8)?.write(to: url, options: .atomic)
                } else {
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    if let data = line.data(using: .utf8) {
                        try handle.write(contentsOf: data)
                    }
                }
            } catch {
                print("❌ SegmentationDebugLogger write failed: \(error)")
            }
        }
        print("📝 LOG: \(message)")
    }

    func logEvent(_ name: String, metadata: [String: Any]? = nil) {
        var msg = "EVENT: \(name)"
        if let metadata = metadata {
            let pretty = metadata.map { "\($0): \($1)" }.joined(separator: ", ")
            msg += " { \(pretty) }"
        }
        log(msg)
    }

    func logCallStack(prefix: String = "STACK") {
        let stack = Thread.callStackSymbols.joined(separator: "\n")
        log("\(prefix):\n\(stack)")
    }
}
