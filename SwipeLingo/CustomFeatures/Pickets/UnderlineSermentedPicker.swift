//
//  HorizontalSermentedSmoothPicker.swift
//  StartToSwiftUI
//
//  Создано Andrey Efimov 31.08.2025.
//

import SwiftUI

struct UnderlineSermentedPicker<T: Hashable>: View {
    
    @Binding var selection: T?
    let allItems: [T]
    let titleForCase: (T) -> String
    
    // Цвета
    var selectedFont: Font = .footnote
    var selectedTextColor: Color = Color.myColors.myBlue
    var unselectedTextColor: Color = Color.myColors.myAccent
    var selectedBackground: Color = Color.myColors.myBlue.opacity(0.1)
    var unselectedBackground: Color = .clear

    // параметры для опциональных значений
    var showNilOption: Bool = true
    var nilTitle: String = "None"
    
    @Namespace private var namespace

    var body: some View {
        HStack(alignment: .top) {
            // Опциональная nil-кнопка
            if showNilOption {
                VStack(spacing: 5) {
                    Text(nilTitle)
                        .font(selectedFont)
                        .frame(maxWidth: .infinity)
                        .fontWeight(.medium)
                    
                    if selection == nil {
                        RoundedRectangle(cornerRadius: 2)
                            .frame(height: 1.5)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .padding(.top, 8)
                .foregroundStyle(selection == nil ? selectedTextColor : unselectedTextColor)
                .background(.black.opacity(0.001))
                .onTapGesture {
                    selection = nil
                }
            }
            
            // Обычные кнопки для значений enum
            ForEach(allItems, id: \.self) { item in
                VStack(spacing: 5) {
                    Text(titleForCase(item))
                        .font(selectedFont)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                    
                    if selection == item {
                        RoundedRectangle(cornerRadius: 2)
                            .frame(height: 1.5)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .padding(.top, 8)
                .foregroundStyle(selection == item ? selectedTextColor : unselectedTextColor)
                .background(.black.opacity(0.001))
                .onTapGesture {
                    selection = item
                }
            }
        }
        .animation(.smooth, value: selection)
    }
}
