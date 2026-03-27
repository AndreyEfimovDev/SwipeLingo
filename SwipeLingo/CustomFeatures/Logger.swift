import Foundation

func log(_ message: String, level: LogLevel = .debug, file: String = #file, function: String = #function, line: Int = #line) {
    #if DEBUG
    let fileName = (file as NSString).lastPathComponent
    print("\(level.icon) [\(fileName):\(line)] \(function) - \(message)")
    #endif
}

// MARK: - LogLevel
enum LogLevel {
    case debug, info, warning, error

    var icon: String {
        switch self {
        case .debug:   return "🔥"
        case .info:    return "ℹ️"
        case .warning: return "⚠️"
        case .error:   return "❌"
        }
    }
}
