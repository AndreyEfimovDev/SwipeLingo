//
//  NavBarButtonForSheet.swift
//  SwipeLingo
//
//  Created by Andrey Efimov on 16.09.2026.
//

import SwiftUI

/// Текстовая кнопка nav bar (Cancel/Save/Create/Done/Edit) — единый вид на всех экранах.
/// Цвета по стандарту: Cancel — `myRed`, Save/Create — `myBlue` (неактивная — `myAccent.opacity(0.8)`),
/// Done/Edit — `myBlue` (по умолчанию).
struct NavBarButtonForSheet: View {

    let title: String
    let color: Color
    /// Контур капсулы на iOS 18–25 — только в `.sheet`; на экранах, открытых через push, кнопки
    /// бара без контура, как иконки рядом. На iOS 26 не влияет (там форму даёт системная капсула).
    let isOutlined: Bool
    let action: () -> Void

    init(
        title: String = "Done",
        color: Color = Color.myColors.myBlue,
        isOutlined: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.color = color
        self.isOutlined = isOutlined
        self.action = action
    }
        
    var body: some View {
        Button {
            action()
        } label: {
            if #available(iOS 26, *) {
                // Своей обводки нет: форму кнопки даёт системная glass-капсула ToolbarItem —
                // своя обводка поверх неё давала "двойную капсулу".
                label
            } else {
                // iOS 18–25: системной капсулы нет — в .sheet рисуем контур в цвет текста.
                label
                    .overlay(Capsule().stroke(color, lineWidth: 1).opacity(isOutlined ? 1 : 0))
            }
        }
    }

    private var label: some View {
        Text(title)
            .foregroundStyle(color)
            .padding(.horizontal)
            .padding(.vertical, 8)
    }
}

#Preview {
    NavBarButtonForSheet() {}
}
