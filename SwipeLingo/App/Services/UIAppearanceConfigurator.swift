import SwiftUI

// MARK: - UIAppearanceConfigurator
//
// Глобальная UIKit-конфигурация (UITabBar/UINavigationBar appearance). Вынесен
// из AppView — это забота уровня приложения, а не конкретного экрана: должна
// применяться один раз при старте, до появления первого экрана (включая
// AuthView/OnboardingView, которые показываются раньше AppView).

enum UIAppearanceConfigurator {

    /// Настраивает внешний вид `UITabBar`/`UINavigationBar` через `UIAppearance`-proxy.
    /// Идемпотентна — безопасно вызывать повторно.
    static func configure() {
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithTransparentBackground()
        tabBarAppearance.backgroundColor = UIColor(Color.myColors.myBackground)
        let inactiveColor = UIColor(Color.myColors.myAccent).withAlphaComponent(0.5)
        tabBarAppearance.stackedLayoutAppearance.normal.iconColor    = inactiveColor
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: inactiveColor]
        UITabBar.appearance().standardAppearance   = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithTransparentBackground()
        // ЭКСПЕРИМЕНТ: тест "стеклянного" бара — backgroundColor закомментирован,
        // иначе он рисуется поверх blur и глушит прозрачность.
        // navBarAppearance.backgroundColor = UIColor(Color.myColors.myBackground)
        navBarAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        navBarAppearance.shadowColor = .clear

        let accentColor = UIColor(Color.myColors.myAccent)
        navBarAppearance.largeTitleTextAttributes = [
            .foregroundColor: accentColor,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold)
        ]
        navBarAppearance.titleTextAttributes = [
            .foregroundColor: accentColor,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]

        UINavigationBar.appearance().standardAppearance         = navBarAppearance
        UINavigationBar.appearance().compactAppearance          = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance       = navBarAppearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().tintColor = UIColor(Color.myColors.myBlue)
        UITableView.appearance().backgroundColor = UIColor.clear
    }
}
