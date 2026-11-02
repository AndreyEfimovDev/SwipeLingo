import Foundation
import os

/// Системный логгер вместо `print`: его вывод виден не только в консоли Xcode, но и в Console.app на Mac
/// (устройство по кабелю), когда приложение запущено с иконки без Xcode — например, для отладки в авиарежиме.
private let systemLogger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "SwipeLingo", category: "app")

/// Пишет отладочное сообщение в системный лог. Только в DEBUG — в релизе не компилируется.
func log(_ message: String, level: LogLevel = .debug, file: String = #file, function: String = #function, line: Int = #line) {
    #if DEBUG
    let fileName = (file as NSString).lastPathComponent
    // .public: без него динамические строки в Console.app без подключённого отладчика скрываются как <private>.
    systemLogger.log(level: level.osLogType, "\(level.icon, privacy: .public) [\(fileName, privacy: .public):\(line)] \(function, privacy: .public) - \(message, privacy: .public)")
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

    /// Уровень системного лога. debug/info Console.app показывает, только если включить их в меню Action.
    var osLogType: OSLogType {
        switch self {
        case .debug:   return .debug
        case .info:    return .info
        case .warning: return .default
        case .error:   return .error
        }
    }
}
