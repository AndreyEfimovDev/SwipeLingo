import ComposableArchitecture
import SwiftUI

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {}

    enum Action {}

    var body: some ReducerOf<Self> {
        Reduce { _, _ in
            .none
        }
    }
}

struct AppView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        // Placeholder — will be replaced by TabView with
        // StudyFeature, LibraryFeature, PreferencesFeature in Stage 2
        Text("SwipeLingo")
    }
}
