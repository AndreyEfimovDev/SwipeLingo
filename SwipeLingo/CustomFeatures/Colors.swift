import Foundation
import SwiftUI


// MARK: CUSTOM COLORS

extension Color {
    static let myColors = MyColors()
    static let launch = LaunchColors()
}

struct MyColors {
    
    let myAccent = Color("myAccent")
    let mySecondary = Color.myAccent.opacity(0.8)
    let myBackground = Color("myBackground")
    
    let myShadow = Color("myShadow")
    
    let myBlue = Color("myBlue")
    let myGreen = Color("myGreen")
    let myOrange = Color("myOrange")
    let myPurple = Color("myPurple")
    let myRed = Color("myRed")
    let myYellow = Color("myYellow")
    
    let buttonTextAccent = Color("buttonTextAccent")

}


struct LaunchColors {
    
}

extension Color {
    func verticalGradient() -> LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: self.opacity(0.1), location: 0.0),
                .init(color: self.opacity(0.3), location: 0.3),
                .init(color: self.opacity(0.7), location: 0.7),
                .init(color: self.opacity(1.0), location: 1.0)
            ]),
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

