//
//  OnTopButton.swift
//  StartToSwiftUI
//
//  Created by Andrey Efimov on 20.03.2026.
//

import SwiftUI

struct OnTopButton: View {
    
    let isVisible: Bool
    let action: () -> Void
    
    var body: some View {
        if isVisible {
            CircleStrokeButtonView(
                iconName: "control",
                iconFont: .title,
                imageColorPrimary: Color.myColors.myBlue,
                widthIn: 55,
                heightIn: 55,
                completion: action
            )
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }
}
