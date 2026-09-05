import Foundation

enum LogLevel: String {
    case info = "🟢 INFO"
    case warning = "🟠 WARNING"
    case error = "🔴 ERROR"
    case success = "✅ SUCCESS"
    case debug = "🔵 DEBUG"
}

struct Logger {
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static var sequenceNumber: UInt64 = 0
    private static let sequenceLock = NSLock()

    private static func nextSequenceNumber() -> UInt64 {
        sequenceLock.lock()
        defer { sequenceLock.unlock() }
        sequenceNumber += 1
        return sequenceNumber
    }

    static func log(_ message: String, level: LogLevel = .info, function: String = #function, file: String = #file, line: Int = #line) {
        let filename = (file as NSString).lastPathComponent
        let timestamp = timestampFormatter.string(from: Date())
        let seq = nextSequenceNumber()
        let logMessage = "\(timestamp) #\(seq) \(level.rawValue) [\(filename):\(line)] \(function): \(message)"
        print(logMessage)
    }

    static func info(_ message: String) {
        log(message, level: .info)
    }

    static func success(_ message: String) {
        log(message, level: .success)
    }

    static func warning(_ message: String) {
        log(message, level: .warning)
    }

    static func error(_ message: String) {
        log(message, level: .error)
    }

    static func debug(_ message: String) {
        log(message, level: .debug)
    }
}
