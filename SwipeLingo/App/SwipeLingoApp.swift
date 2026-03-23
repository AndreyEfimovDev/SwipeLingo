//
//  SwipeLingoApp.swift
//  SwipeLingo
//
//  Created by Andrey Efimov on 11.02.2026.
//

import SwiftUI
import SwiftData
import ComposableArchitecture

@main
struct SwipeLingoApp: App {
    var body: some Scene {
        WindowGroup {
            AppView(
                store: Store(initialState: AppFeature.State()) {
                    AppFeature()
                }
            )
        }
        .modelContainer(for: [
            Card.self,
            CardSet.self,
            Collection.self,
            Pile.self,
            EnglishPlusCard.self
        ])
    }
}
