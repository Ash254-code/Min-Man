import SwiftUI

struct ClubStyle {

    // MARK: - Club Colours
    static let clubNavy = Color(red: 0.05, green: 0.15, blue: 0.35)
    static let clubYellow = Color(red: 1.0, green: 0.82, blue: 0.0)

    // MARK: - Reusable Style (background + text)
    struct Style {
        let background: Color
        let text: Color
    }

    // MARK: - Helpers
    /// Convenience for RGB 0...255 values
    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255.0, green: g / 255.0, blue: b / 255.0)
    }

    private static func cleanName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Opponent Colours (your mapping)
    static func opponentColours(for name: String) -> (primary: Color, text: Color) {
        switch cleanName(name) {

        case "BSR":
            return (rgb(255, 255, 0), .black)

        case "BBH":
            return (rgb(3, 169, 244), .red)

        case "RSMU":
            return (rgb(13, 13, 13), .white) // near-black

        case "North Clare":
            return (rgb(255, 0, 0), .yellow)

        case "South Clare":
            return (rgb(0, 0, 128), .red)

        case "Southern Saints":
            return (.black, .red)

        case "Blyth/Snowtown":
            return (rgb(100, 100, 100), .blue)

        default:
            return (Color(.systemGray4), .black)
        }
    }

    // ✅ THIS is what OpponentBadge expects
    static func style(for opponent: String) -> Style {
        let c = opponentColours(for: opponent)
        return Style(background: c.primary, text: c.text)
    }

    // Club pill style (Min Man)
    static var ourScoreStyle: Style {
        Style(background: clubNavy, text: clubYellow)
    }
}
