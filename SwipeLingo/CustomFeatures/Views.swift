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
