import XCTest

/// Ждёт, пока условие станет истинным, опрашивая его каждые 10 мс.
///
/// Нужен для асинхронных тестов, где результат приходит позже вызова (поток записей, отмена запросов).
/// По истечении таймаута тест падает с указанием строки вызова, а не строки внутри помощника.
///
/// - Parameters:
///   - timeout: Сколько секунд ждать.
///   - file: Файл вызова — для сообщения о падении.
///   - line: Строка вызова — для сообщения о падении.
///   - condition: Проверяемое условие; вызывается на MainActor.
@MainActor
func waitUntil(
    timeout: TimeInterval = 2,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @MainActor () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertTrue(condition(), "условие не выполнилось за \(timeout) с", file: file, line: line)
}
