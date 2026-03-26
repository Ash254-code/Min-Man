import SwiftUI

enum Theme {
    // Club colours
    static let clubNavy   = Color(red: 0.05, green: 0.15, blue: 0.35)
    static let clubYellow = Color(red: 1.0, green: 0.82, blue: 0.0)

    // Light mode: BLUE pill / yellow text
    // Dark mode: YELLOW pill / blue text
    static func primary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? clubYellow : clubNavy
    }

    static func onPrimary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? clubNavy : clubYellow
    }
}
