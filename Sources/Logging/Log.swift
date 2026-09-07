import Foundation

public enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static func from(_ s: String) -> LogLevel? {
        switch s.lowercased() {
        case "debug": return .debug
        case "info":  return .info
        case "warn", "warning": return .warning
        case "error": return .error
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info:  return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

private var globalLogLevel: LogLevel = .info

private let timestampFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm:ss.SSS"
    return fmt
}()
private let timestampLock = NSLock()

public struct Log {
    private let module: String

    public init(module: String) {
        self.module = module
    }

    public static func setLevel(_ level: LogLevel) {
        globalLogLevel = level
    }

    public func debug(_ message: @autoclosure () -> String) { log(.debug, message) }
    public func info(_ message: @autoclosure () -> String) { log(.info, message) }
    public func warning(_ message: @autoclosure () -> String) { log(.warning, message) }
    public func error(_ message: @autoclosure () -> String) { log(.error, message) }

    private func log(_ level: LogLevel, _ message: () -> String) {
        guard level >= globalLogLevel else { return }
        timestampLock.lock()
        let ts = timestampFormatter.string(from: Date())
        timestampLock.unlock()
        fputs("\(ts) [\(level.label)] \(module): \(message())\n", stderr)
    }
}
