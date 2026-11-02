//
//  NavBarButtonForSheet.swift
//  SwipeLingo
//
//  Created by Andrey Efimov on 16.09.2026.
//

import SwiftUI

struct NavBarButtonForSheet: View {

    let title: String
    let color: Color
    let action: () -> Void

    init(
        title: String = "Done",
        color: Color = Color.myColors.myAccent,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.color = color
        self.action = action
    }
        
    var body: some View {
        Button {
            action()
        } label: {
            // Своей Capsule-обводки нет: форму кнопки даёт системная glass-капсула
            // ToolbarItem (iOS 26) — своя обводка поверх неё давала "двойную капсулу".
            Text(title)
                .foregroundStyle(color)
                .padding(.horizontal)
                .padding(.vertical, 8)
            // .background(Color.clear, in: Capsule())
            // .overlay(
            //     Capsule()
            //         .stroke(Color.myColors.myAccent.opacity(0.35), lineWidth: 1)
            // )
        }
    }
}

#Preview {
    NavBarButtonForSheet() {}
}
