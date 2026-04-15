import SwiftUI
import UIKit

struct ClubTeamProfile: Codable, Equatable {
    var name: String
    var primaryColorHex: String
    var secondaryColorHex: String?
    var tertiaryColorHex: String?
    var venues: [String]

    var sanitizedVenues: [String] {
        Array(
            Set(
                venues
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
        .prefix(3)
        .map { $0 }
    }

    var colorHexes: [String] {
        [primaryColorHex, secondaryColorHex, tertiaryColorHex]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { $0 }
    }
}

struct OppositionTeamProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var primaryColorHex: String
    var secondaryColorHex: String?
    var tertiaryColorHex: String?
    var venues: [String]

    var sanitizedVenues: [String] {
        Array(
            Set(
                venues
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
        .prefix(3)
        .map { $0 }
    }

    var colorHexes: [String] {
        [primaryColorHex, secondaryColorHex, tertiaryColorHex]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { $0 }
    }
}

struct ClubConfiguration: Codable, Equatable {
    var clubTeam: ClubTeamProfile
    var oppositions: [OppositionTeamProfile]

    var sortedOppositions: [OppositionTeamProfile] {
        oppositions
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

enum ClubConfigurationStore {
    private static let key = "settings.clubConfiguration.v1"

    static func load() -> ClubConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(ClubConfiguration.self, from: data) else {
            return defaults
        }
        return sanitize(decoded)
    }

    static func save(_ configuration: ClubConfiguration) {
        let sanitized = sanitize(configuration)
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func sanitize(_ configuration: ClubConfiguration) -> ClubConfiguration {
        var club = configuration.clubTeam
        let clubName = club.name.trimmingCharacters(in: .whitespacesAndNewlines)
        club.name = clubName.isEmpty ? defaults.clubTeam.name : clubName
        if club.primaryColorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            club.primaryColorHex = defaults.clubTeam.primaryColorHex
        }
        club.venues = club.sanitizedVenues

        var seenNames = Set<String>()
        let oppositions = configuration.oppositions.compactMap { opposition -> OppositionTeamProfile? in
            var item = opposition
            item.name = opposition.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.name.isEmpty else { return nil }
            let normalized = item.name.lowercased()
            guard !seenNames.contains(normalized) else { return nil }
            seenNames.insert(normalized)

            if item.primaryColorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                item.primaryColorHex = "#1D4ED8"
            }
            item.venues = item.sanitizedVenues
            return item
        }

        return ClubConfiguration(clubTeam: club, oppositions: oppositions)
    }

    static let defaults: ClubConfiguration = {
        let byName: [String: [String]] = [
            "South Clare": ["Clare", "Mintaro", "Manoora"],
            "North Clare": ["Clare", "Mintaro", "Manoora"],
            "RSMU": ["Riverton", "Mintaro", "Manoora"],
            "BSR": ["Mintaro", "Manoora", "Brinkworth"],
            "BBH": ["Burra", "Mintaro", "Manoora"],
            "Southern Saints": ["Mintaro", "Manoora", "Eudunda"],
            "Blyth/Snowtown": ["Mintaro", "Manoora", "Blyth"]
        ]

        let opponents = byName.keys.sorted().map {
            OppositionTeamProfile(
                id: UUID(),
                name: $0,
                primaryColorHex: "#1D4ED8",
                secondaryColorHex: nil,
                tertiaryColorHex: nil,
                venues: byName[$0] ?? []
            )
        }

        return ClubConfiguration(
            clubTeam: ClubTeamProfile(
                name: "Min Man",
                primaryColorHex: "#0D2759",
                secondaryColorHex: "#FFD100",
                tertiaryColorHex: nil,
                venues: ["Mintaro", "Manoora", "Clare"]
            ),
            oppositions: opponents
        )
    }()
}

enum TeamColorSlot: Int, CaseIterable, Identifiable {
    case primary
    case secondary
    case tertiary

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .primary: return "Primary"
        case .secondary: return "Secondary"
        case .tertiary: return "Tertiary"
        }
    }
}

extension Color {
    init(hex: String, fallback: Color = .blue) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&int) else {
            self = fallback
            return
        }

        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            self = fallback
            return
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }

    func toHex() -> String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let r = Int(round(red * 255))
        let g = Int(round(green * 255))
        let b = Int(round(blue * 255))

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
