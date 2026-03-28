//
//  Views.swift
//  SwipeLingo
//
//  Created by Andrey Efimov on 26.03.2026.
//

import SwiftUI

extension View {
    func myShadow() -> some View {
        self
            .shadow(color: Color.myColors.myShadow.opacity(0.3), radius: 8, x: 0, y: 0)
    }
}

// MARK: - FixedIconLabelStyle
// Standard for all Labels in vertical stacks.
// Fixes the icon width—text always starts on a single vertical line
// regardless of the SF Symbol width.
//
// Usage:
// Label("Title", systemImage: "icon").labelStyle(.fixedIcon)
// or on a container:
// VStack { ... }.labelStyle(.fixedIcon)

struct FixedIconLabelStyle: LabelStyle {
    var iconWidth: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .frame(width: iconWidth, alignment: .center)
            configuration.title
        }
    }
}

extension LabelStyle where Self == FixedIconLabelStyle {
    static var fixedIcon: FixedIconLabelStyle { .init() }
}
