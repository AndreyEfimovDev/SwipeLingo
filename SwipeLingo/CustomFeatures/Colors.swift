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


