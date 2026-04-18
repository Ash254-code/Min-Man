import Foundation
import UIKit

/// A minimal interface for games that can be exported by ExportService.
protocol ExportableGame {
    var date: Date { get }
    var opponent: String { get }
    var venue: String { get }
    var ourGoals: Int { get }
    var ourBehinds: Int { get }
    var theirGoals: Int { get }
    var theirBehinds: Int { get }
    var goalKickers: [GameGoalKickerEntry] { get }
    var bestPlayersRanked: [UUID] { get }
    var notes: String { get }
    var guestBestFairestVotesScanPDF: Data? { get }
}

enum ExportService {

    static func points(goals: Int, behinds: Int) -> Int {
        goals * 6 + behinds
    }

    static func gameSummaryText(game: ExportableGame, gradeName: String, includeScore: Bool = true, playerName: (UUID) -> String) -> String {
        let ourTotal = points(goals: game.ourGoals, behinds: game.ourBehinds)
        let theirTotal = points(goals: game.theirGoals, behinds: game.theirBehinds)

        var lines: [String] = []
        lines.append("Grade: \(gradeName)")
        lines.append("Date: \(game.date.formatted(date: Date.FormatStyle.DateStyle.long, time: Date.FormatStyle.TimeStyle.omitted))")
        lines.append("Opponent: \(game.opponent)")
        if !game.venue.isEmpty { lines.append("Venue: \(game.venue)") }
        if includeScore {
            lines.append("Score: \(game.ourGoals).\(game.ourBehinds) (\(ourTotal)) — \(game.theirGoals).\(game.theirBehinds) (\(theirTotal))")
        }
        lines.append("")

        if !game.goalKickers.isEmpty {
            lines.append("Goal Kickers:")
            for e in game.goalKickers.sorted(by: { $0.goals > $1.goals }) {
                lines.append("- \(playerName(e.playerID!)): \(e.goals)")
            }
            lines.append("")
        }

        if !game.bestPlayersRanked.isEmpty {
            lines.append("Best Players:")
            for (idx, pid) in game.bestPlayersRanked.enumerated() {
                lines.append("\(idx + 1). \(playerName(pid))")
            }
            lines.append("")
        }

        let trimmedNotes = (game.notes).trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            lines.append("Notes:")
            lines.append(trimmedNotes)
        }

        if game.guestBestFairestVotesScanPDF != nil {
            lines.append("")
            lines.append("Guest Best & Fairest votes scan: attached")
        }

        return lines.joined(separator: "\n")
    }

    /// Creates a CSV file for a single game and returns its file URL for sharing/saving.
    static func makeGameCSV(game: ExportableGame, gradeName: String, playerName: (UUID) -> String) throws -> URL {
        let ourTotal = points(goals: game.ourGoals, behinds: game.ourBehinds)
        let theirTotal = points(goals: game.theirGoals, behinds: game.theirBehinds)

        // Simple CSV (one row) + add best players and goal kickers as semicolon-separated
        let best = game.bestPlayersRanked.enumerated()
            .map { "\($0.offset + 1):\(playerName($0.element))" }
            .joined(separator: "; ")

        let kickers = game.goalKickers
            .map { "\(playerName($0.playerID!))=\($0.goals)" }
            .joined(separator: "; ")

        func esc(_ s: String) -> String {
            // minimal CSV escaping
            if s.contains(",") || s.contains("\"") || s.contains("\n") {
                return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            return s
        }

        let header = [
            "Grade","Date","Opponent","Venue",
            "OurGoals","OurBehinds","OurTotal",
            "TheirGoals","TheirBehinds","TheirTotal",
            "BestPlayers","GoalKickers","Notes"
        ].joined(separator: ",")

        let row = [
            esc(gradeName),
            esc(game.date.formatted(Date.FormatStyle.dateTime.year().month(.twoDigits).day(.twoDigits))),
            esc(game.opponent),
            esc(game.venue),
            "\(game.ourGoals)","\(game.ourBehinds)","\(ourTotal)",
            "\(game.theirGoals)","\(game.theirBehinds)","\(theirTotal)",
            esc(best),
            esc(kickers),
            esc(game.notes)
        ].joined(separator: ",")

        let csv = header + "\n" + row + "\n"

        let filename = fileSafe("\(gradeName)_\(game.date.formatted(date: Date.FormatStyle.DateStyle.numeric, time: Date.FormatStyle.TimeStyle.omitted))_vs_\(game.opponent).csv")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        try csv.write(to: url, atomically: true, encoding: String.Encoding.utf8)
        return url
    }

    static func makeGameSummaryTextFile(game: ExportableGame, gradeName: String, includeScore: Bool = true, playerName: (UUID) -> String) throws -> URL {
        let text = gameSummaryText(game: game, gradeName: gradeName, includeScore: includeScore, playerName: playerName)
        let filename = fileSafe("\(gradeName)_\(game.date.formatted(date: .numeric, time: .omitted))_vs_\(game.opponent).txt")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func makeGameSummaryPDF(game: ExportableGame, gradeName: String, includeScore: Bool = true, playerName: (UUID) -> String) throws -> URL {
        let summary = gameSummaryText(game: game, gradeName: gradeName, includeScore: includeScore, playerName: playerName)
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter at 72 dpi
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)

        let data = renderer.pdfData { context in
            context.beginPage()

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineSpacing = 3

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13),
                .paragraphStyle: paragraph
            ]

            let insetRect = pageBounds.insetBy(dx: 36, dy: 36)
            let attributed = NSAttributedString(string: summary, attributes: attributes)
            attributed.draw(in: insetRect)
        }

        let filename = fileSafe("\(gradeName)_\(game.date.formatted(date: .numeric, time: .omitted))_vs_\(game.opponent).pdf")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func fileSafe(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return s.components(separatedBy: bad).joined(separator: "-")
            .replacingOccurrences(of: " ", with: "_")
    }
}
