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
    var guestVotesRanked: [GameGuestVoteEntry] { get }
    var notes: String { get }
    var guestBestFairestVotesScanPDF: Data? { get }
}

enum ExportService {

    static func points(goals: Int, behinds: Int) -> Int {
        goals * 6 + behinds
    }

    static func gameSummaryText(
        game: ExportableGame,
        gradeName: String,
        includeScore: Bool = true,
        includeRestrictedVotes: Bool = true,
        playerName: (UUID) -> String
    ) -> String {
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
                lines.append("- \(GameGoalKickerEntry.displayName(for: e.playerID, playerName: playerName)): \(e.goalsDisplayText)")
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

        if includeRestrictedVotes, !game.guestVotesRanked.isEmpty {
            lines.append("Guest Votes Ranking:")
            for vote in game.guestVotesRanked.sorted(by: { $0.rank < $1.rank }) {
                lines.append("\(vote.rank). \(playerName(vote.playerID))")
            }
            lines.append("")
        }

        let trimmedNotes = (game.notes).trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            lines.append("Notes:")
            lines.append(trimmedNotes)
        }

        if includeRestrictedVotes, game.guestBestFairestVotesScanPDF != nil {
            lines.append("")
            lines.append("Guest Best & Fairest votes scan: attached")
        }

        return lines.joined(separator: "\n")
    }

    /// Creates a CSV file for a single game and returns its file URL for sharing/saving.
    static func makeGameCSV(
        game: ExportableGame,
        gradeName: String,
        includeRestrictedVotes: Bool = true,
        playerName: (UUID) -> String
    ) throws -> URL {
        let ourTotal = points(goals: game.ourGoals, behinds: game.ourBehinds)
        let theirTotal = points(goals: game.theirGoals, behinds: game.theirBehinds)

        // Simple CSV (one row) + add best players and goal kickers as semicolon-separated
        let best = game.bestPlayersRanked.enumerated()
            .map { "\($0.offset + 1):\(playerName($0.element))" }
            .joined(separator: "; ")
        let guestVotes = includeRestrictedVotes
            ? game.guestVotesRanked
                .sorted(by: { $0.rank < $1.rank })
                .map { "\($0.rank):\(playerName($0.playerID))" }
                .joined(separator: "; ")
            : ""

        let kickers = game.goalKickers
            .map { "\(GameGoalKickerEntry.displayName(for: $0.playerID, playerName: playerName))=\($0.goalsDisplayText)" }
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
            "BestPlayers","GuestVotes","GoalKickers","Notes"
        ].joined(separator: ",")

        let row = [
            esc(gradeName),
            esc(game.date.formatted(Date.FormatStyle.dateTime.year().month(.twoDigits).day(.twoDigits))),
            esc(game.opponent),
            esc(game.venue),
            "\(game.ourGoals)","\(game.ourBehinds)","\(ourTotal)",
            "\(game.theirGoals)","\(game.theirBehinds)","\(theirTotal)",
            esc(best),
            esc(guestVotes),
            esc(kickers),
            esc(game.notes)
        ].joined(separator: ",")

        let csv = header + "\n" + row + "\n"

        let filename = fileSafe("\(gradeName)_\(game.date.formatted(date: Date.FormatStyle.DateStyle.numeric, time: Date.FormatStyle.TimeStyle.omitted))_vs_\(game.opponent).csv")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        try csv.write(to: url, atomically: true, encoding: String.Encoding.utf8)
        return url
    }

    static func makeGameSummaryTextFile(
        game: ExportableGame,
        gradeName: String,
        includeScore: Bool = true,
        includeRestrictedVotes: Bool = true,
        playerName: (UUID) -> String
    ) throws -> URL {
        let text = gameSummaryText(
            game: game,
            gradeName: gradeName,
            includeScore: includeScore,
            includeRestrictedVotes: includeRestrictedVotes,
            playerName: playerName
        )
        let filename = fileSafe("\(gradeName)_\(game.date.formatted(date: .numeric, time: .omitted))_vs_\(game.opponent).txt")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func makeGameSummaryPDF(
        game: ExportableGame,
        gradeName: String,
        includeScore: Bool = true,
        includeRestrictedVotes: Bool = true,
        gameLabel: String? = nil,
        playerName: (UUID) -> String
    ) throws -> URL {
        let summary = gameSummaryText(
            game: game,
            gradeName: gradeName,
            includeScore: includeScore,
            includeRestrictedVotes: includeRestrictedVotes,
            playerName: playerName
        )
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)

        let ourTotal = points(goals: game.ourGoals, behinds: game.ourBehinds)
        let theirTotal = points(goals: game.theirGoals, behinds: game.theirBehinds)
        let scoreMode: String
        if includeScore {
            if ourTotal > theirTotal {
                scoreMode = "W"
            } else if ourTotal < theirTotal {
                scoreMode = "L"
            } else {
                scoreMode = "D"
            }
        } else {
            scoreMode = "V"
        }

        let data = renderer.pdfData { context in
            context.beginPage()

            let insetRect = pageBounds.insetBy(dx: 36, dy: 36)
            let headerRect = CGRect(x: insetRect.minX, y: insetRect.minY, width: insetRect.width, height: 148)

            UIColor.secondarySystemGroupedBackground.setFill()
            UIBezierPath(roundedRect: headerRect, cornerRadius: 18).fill()

            if let gameLabel {
                let gameAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16, weight: .bold),
                    .foregroundColor: UIColor.secondaryLabel
                ]
                NSString(string: gameLabel).draw(in: CGRect(x: headerRect.minX + 16, y: headerRect.minY + 12, width: 140, height: 24), withAttributes: gameAttributes)
            }

            let availableWidth = headerRect.width - 32
            let sideWidth = (availableWidth - 88) / 2
            let leftX = headerRect.minX + 16
            let rightX = leftX + sideWidth + 88
            let contentTop = headerRect.minY + (gameLabel == nil ? 22 : 34)

            let teamFont = UIFont.systemFont(ofSize: 18, weight: .bold)
            let scoreFont = UIFont.systemFont(ofSize: 30, weight: .black)
            let scoreColor = UIColor.label

            let leftTeamRect = CGRect(x: leftX, y: contentTop, width: sideWidth, height: 32)
            let rightTeamRect = CGRect(x: rightX, y: contentTop, width: sideWidth, height: 32)

            let teamAttrs: [NSAttributedString.Key: Any] = [
                .font: teamFont,
                .foregroundColor: UIColor.label
            ]

            NSString(string: gradeName).draw(in: CGRect(x: insetRect.minX, y: insetRect.minY - 28, width: insetRect.width, height: 22), withAttributes: [
                .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: UIColor.label
            ])

            drawCenteredCapsule(text: "Min Man", rect: leftTeamRect, attributes: teamAttrs)
            drawCenteredCapsule(text: game.opponent, rect: rightTeamRect, attributes: teamAttrs)

            let leftScore = includeScore ? "\(game.ourGoals).\(game.ourBehinds) (\(ourTotal))" : ""
            let rightScore = includeScore ? "\(game.theirGoals).\(game.theirBehinds) (\(theirTotal))" : ""

            let scoreAttrs: [NSAttributedString.Key: Any] = [
                .font: scoreFont,
                .foregroundColor: scoreColor
            ]

            if includeScore {
                drawCenteredText(text: leftScore, rect: CGRect(x: leftX, y: leftTeamRect.maxY + 8, width: sideWidth, height: 38), attributes: scoreAttrs)
                drawCenteredText(text: rightScore, rect: CGRect(x: rightX, y: rightTeamRect.maxY + 8, width: sideWidth, height: 38), attributes: scoreAttrs)
            }

            let badgeSize: CGFloat = 72
            let badgeRect = CGRect(
                x: headerRect.midX - (badgeSize / 2),
                y: headerRect.midY - (badgeSize / 2) + (includeScore ? 8 : 0),
                width: badgeSize,
                height: badgeSize
            )
            drawResultBadge(mode: scoreMode, rect: badgeRect)

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineSpacing = 3

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13),
                .paragraphStyle: paragraph
            ]

            let attributed = NSAttributedString(
                string: summary,
                attributes: attributes
            )
            attributed.draw(in: CGRect(x: insetRect.minX, y: headerRect.maxY + 18, width: insetRect.width, height: insetRect.height - headerRect.height - 18))
        }

        let filename = fileSafe("\(gradeName)_\(game.date.formatted(date: .numeric, time: .omitted))_vs_\(game.opponent).pdf")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: Data.WritingOptions.atomic)
        return url
    }

    private static func drawCenteredCapsule(text: String, rect: CGRect, attributes: [NSAttributedString.Key: Any]) {
        UIColor.systemBackground.setFill()
        UIColor.separator.setStroke()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        path.lineWidth = 1
        path.fill()
        path.stroke()
        drawCenteredText(text: text, rect: rect.insetBy(dx: 8, dy: 6), attributes: attributes)
    }

    private static func drawCenteredText(text: String, rect: CGRect, attributes: [NSAttributedString.Key: Any]) {
        let size = (text as NSString).size(withAttributes: attributes)
        let x = rect.midX - (size.width / 2)
        let y = rect.midY - (size.height / 2)
        NSString(string: text).draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
    }

    private static func drawResultBadge(mode: String, rect: CGRect) {
        let fillColor: UIColor
        switch mode {
        case "W": fillColor = .systemGreen
        case "L": fillColor = .systemRed
        case "D": fillColor = .systemOrange
        default: fillColor = .clear
        }

        let badgePath = UIBezierPath(ovalIn: rect)
        fillColor.setFill()
        badgePath.fill()

        if mode != "V" {
            UIColor.white.withAlphaComponent(0.25).setStroke()
            badgePath.lineWidth = 1.5
            badgePath.stroke()
        }

        let textColor: UIColor = mode == "V" ? .label : .white
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: rect.width * 0.44, weight: .black),
            .foregroundColor: textColor
        ]
        drawCenteredText(text: mode, rect: rect, attributes: attributes)
    }

    private static func fileSafe(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return s.components(separatedBy: bad).joined(separator: "-")
            .replacingOccurrences(of: " ", with: "_")
    }
}
