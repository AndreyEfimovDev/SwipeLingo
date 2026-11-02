import Foundation

// MARK: - PairsPileService
// Определяет PairsSets для PairsPile из уже загруженного среза [PairsSet] и порядок их показа.
//
// Порядок управляется `pile.shuffleMethod` и касается только СЕТОВ внутри пайла. Порядок пар
// внутри сета не меняется никогда: сет состоит из разделов (подряд идущих пар с одним `tag`,
// см. PairsSetPlayerViewModel.pairGroups), перемешивание пар разорвало бы разделы и
// пошаговый показ.

struct PairsPileService {

    /// Сеты пайла в порядке показа.
    /// - Parameters:
    ///   - seed: источник случайности для `.random`: один и тот же seed даёт один и тот же порядок.
    ///     Вызывающая сторона хранит seed на время сессии (иначе порядок менялся бы при каждой
    ///     перерисовке экрана) и обновляет его, когда нужен новый порядок. Для `.sequential`
    ///     игнорируется; значение по умолчанию (0) годится там, где порядок не важен — подсчёты.
    /// - Returns: сеты пайла, найденные в `allSets` (id из `pile.setIds` без сета пропускаются).
    ///   `.sequential` сохраняет порядок `pile.setIds` — порядок добавления сетов в пайл.
    func sets(for pile: PairsPile, from allSets: [PairsSet], seed: UInt64 = 0) -> [PairsSet] {
        let ordered = pile.setIds.compactMap { id in allSets.first { $0.id == id } }
        switch pile.shuffleMethod {
        case .random:
            return shuffled(ordered, seed: seed)
        case .sequential, .prioritized:
            // `.prioritized` в Pairs недоступен в UI (билдер предлагает только Random/Sequential),
            // поэтому трактуем как `.sequential`.
            return ordered
        }
    }

    /// Детерминированная перестановка Фишера–Йетса на генераторе SplitMix64: один и тот же seed —
    /// один и тот же порядок. Намеренно не `shuffled(using:)`: собственная реализация даёт порядок,
    /// не зависящий от версии Swift, и не тянет протокол `RandomNumberGenerator` в изоляцию MainActor.
    private func shuffled<T>(_ items: [T], seed: UInt64) -> [T] {
        guard items.count > 1 else { return items }
        var result = items
        var state = seed

        func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        for i in stride(from: result.count - 1, to: 0, by: -1) {
            let j = Int(next() % UInt64(i + 1))
            result.swapAt(i, j)
        }
        return result
    }
}
