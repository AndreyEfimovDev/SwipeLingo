//
//  CircleButtonView.swift
//  StartToSwiftUI
//
//  Created by Andrey Efimov on 08.09.2025.
//


import SwiftUI

struct CircleStrokeButtonView: View {
    
    let iconName: String
    let iconFont: Font
    let isIconColorToChange: Bool
    let imageColorPrimary: Color
    let imageColorSecondary: Color
    let buttonBackground: Color
    let widthIn: CGFloat
    let heightIn: CGFloat
    let isShownCircle: Bool
    let completion: () -> Void
    
    init(
        iconName: String,
        iconFont: Font = .headline,
        isIconColorToChange: Bool = false,
        imageColorPrimary: Color = Color.myColors.myAccent,
        imageColorSecondary: Color = Color.myColors.myBlue,
        buttonBackground: Color = .clear,
        widthIn: CGFloat = 30,
        heightIn: CGFloat = 30,
        isShownCircle: Bool = true,
        completion: @escaping () -> Void
    ) {
        self.iconName = iconName
        self.iconFont = iconFont
        self.isIconColorToChange = isIconColorToChange
        self.imageColorPrimary = imageColorPrimary
        self.imageColorSecondary = imageColorSecondary
        self.buttonBackground = buttonBackground
        self.widthIn = widthIn
        self.heightIn = heightIn
        self.isShownCircle = isShownCircle
        self.completion = completion
    }
    
    var body: some View {
        Button {
            completion()
        } label: {
            Image(systemName: iconName)
                .font(iconFont)
                .foregroundStyle(isIconColorToChange ? imageColorSecondary : imageColorPrimary)
                .frame(width: widthIn, height: widthIn)
                .background(.ultraThinMaterial.opacity(0.4), in: .circle)
                .overlay(
                    Circle()
                        .fill(buttonBackground)
                        .stroke(imageColorPrimary, lineWidth: 1)
                        .opacity(isShownCircle ? 1 : 0)
                )
        }
        .accessibilityIdentifier(iconName)
    }
}

#Preview {
    NavigationStack {
        ZStack {
            Color.yellow
            VStack {
                CircleStrokeButtonView(iconName: "lines.measurement.horizontal") {
                    
                }
                CircleStrokeButtonView(iconName: "plus", isIconColorToChange: true, imageColorPrimary: Color.myColors.myBlue, imageColorSecondary: Color.myColors.myRed) {
                    
                }
                CircleStrokeButtonView(iconName: "plus", isIconColorToChange: false, imageColorPrimary: Color.myColors.myBlue, imageColorSecondary: Color.myColors.myRed) {
                    
                }
                
                CircleStrokeButtonView(iconName: "arrow.up", isIconColorToChange: false, imageColorPrimary: Color.myColors.myBlue, imageColorSecondary: Color.myColors.myRed, widthIn: 55, heightIn: 55) {
                    
                }
                
                List {
                    ForEach(0...50, id: \.self) { index in
                    Text("\(index)")
                    }
                }
            }
            
        }
        .navigationTitle("Header")
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                CircleStrokeButtonView(
                    iconName: "gearshape",
                    isShownCircle: false) {
                        
                    }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                
                CircleStrokeButtonView(
                    iconName: "plus",
                    isShownCircle: false) {
                        
                    }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                
                CircleStrokeButtonView(
                    iconName: "line.3.horizontal.decrease",
                    isShownCircle: false) {
                    }
            }
        }
    }
}
