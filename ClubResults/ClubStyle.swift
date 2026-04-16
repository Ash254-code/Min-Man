import SwiftUI
import UIKit

struct ClubStyle {

    // MARK: - Club Colours
    static let clubNavy = Color(red: 0.05, green: 0.15, blue: 0.35)
    static let clubYellow = Color(red: 1.0, green: 0.82, blue: 0.0)

    // MARK: - Reusable Style (background + text)
    struct Style {
        let background: Color
        let text: Color
        let border: Color
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
        return Style(background: c.primary, text: c.text, border: c.text)
    }

    // Club pill style (Min Man)
    static var ourScoreStyle: Style {
        Style(background: clubNavy, text: clubYellow, border: clubYellow)
    }


    static func style(primaryHex: String, secondaryHex: String?, tertiaryHex: String?, fallback: Style) -> Style {
        let primary = Color(hex: primaryHex, fallback: fallback.background)

        let cleanedSecondary = secondaryHex?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let secondary = cleanedSecondary.isEmpty
            ? fallback.text
            : Color(hex: cleanedSecondary, fallback: fallback.text)

        let cleanedTertiary = tertiaryHex?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let border = cleanedTertiary.isEmpty
            ? secondary
            : Color(hex: cleanedTertiary, fallback: secondary)

        return Style(background: primary, text: secondary, border: border)
    }

    static func style(for teamName: String, configuration: ClubConfiguration) -> Style {
        let normalized = cleanName(teamName)

        if normalized.caseInsensitiveCompare(configuration.clubTeam.name) == .orderedSame {
            return style(
                primaryHex: configuration.clubTeam.primaryColorHex,
                secondaryHex: configuration.clubTeam.secondaryColorHex,
                tertiaryHex: configuration.clubTeam.tertiaryColorHex,
                fallback: ourScoreStyle
            )
        }

        if let opposition = configuration.oppositions.first(where: { cleanName($0.name).caseInsensitiveCompare(normalized) == .orderedSame }) {
            return style(
                primaryHex: opposition.primaryColorHex,
                secondaryHex: opposition.secondaryColorHex,
                tertiaryHex: opposition.tertiaryColorHex,
                fallback: style(for: opposition.name)
            )
        }

        return style(for: normalized)
    }

    static func standardPillWidth(configuration: ClubConfiguration, fontTextStyle: UIFont.TextStyle = .headline) -> CGFloat {
        let names = [configuration.clubTeam.name] + configuration.oppositions.map(\.name)
        let font = UIFont.preferredFont(forTextStyle: fontTextStyle)

        let textWidths = names.map { name in
            let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = cleaned.isEmpty ? "Team" : cleaned
            return (value as NSString).size(withAttributes: [.font: font]).width
        }

        let longest = textWidths.max() ?? 0
        let padded = longest + 28
        return min(max(padded, 120), 280)
    }

}
