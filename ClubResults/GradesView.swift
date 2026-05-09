import Foundation
import SwiftData

@Model
final class Grade {
    var id: UUID
    var name: String
    var isActive: Bool
    var displayOrder: Int

    // New-game wizard toggles per grade.
    var asksHeadCoach: Bool
    var asksAssistantCoach: Bool
    var asksTeamManager: Bool
    var asksRunner: Bool
    var asksGoalUmpire: Bool
    var asksTimeKeeper: Bool = true
    var asksFieldUmpire: Bool
    var asksBoundaryUmpire1: Bool
    var asksBoundaryUmpire2: Bool
    var asksWaterBoy1: Bool
    var asksWaterBoy2: Bool
    var asksWaterBoy3: Bool
    var asksWaterBoy4: Bool
    var asksTrainers: Bool
    var asksTrainer1: Bool
    var asksTrainer2: Bool
    var asksTrainer3: Bool
    var asksTrainer4: Bool
    var asksNotes: Bool
    var asksScore: Bool
    var asksLiveGameView: Bool
    var asksGoalKickers: Bool
    var tracksPlayersPerTeam: Bool
    var playersPerTeam: Int
    var bestPlayersCount: Int
    var asksGuestBestFairestVotesScan: Bool
    var guestBestPlayersCount: Int
    var bestPlayersVotes: [Int]
    var guestBestPlayersVotes: [Int]
    var allowsLiveGameView: Bool
    var quarterLengthMinutes: Int
    var timeOnEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        isActive: Bool = true,
        displayOrder: Int = 0,
        asksHeadCoach: Bool = true,
        asksAssistantCoach: Bool = true,
        asksTeamManager: Bool = true,
        asksRunner: Bool = true,
        asksGoalUmpire: Bool = true,
        asksTimeKeeper: Bool = true,
        asksFieldUmpire: Bool = true,
        asksBoundaryUmpire1: Bool = true,
        asksBoundaryUmpire2: Bool = true,
        asksWaterBoy1: Bool = false,
        asksWaterBoy2: Bool = false,
        asksWaterBoy3: Bool = false,
        asksWaterBoy4: Bool = false,
        asksTrainers: Bool = true,
        asksTrainer1: Bool = true,
        asksTrainer2: Bool = true,
        asksTrainer3: Bool = true,
        asksTrainer4: Bool = true,
        asksNotes: Bool = true,
        asksScore: Bool = true,
        asksLiveGameView: Bool = true,
        asksGoalKickers: Bool = true,
        tracksPlayersPerTeam: Bool? = nil,
        playersPerTeam: Int? = nil,
        bestPlayersCount: Int = 6,
        asksGuestBestFairestVotesScan: Bool = true,
        guestBestPlayersCount: Int = 3,
        bestPlayersVotes: [Int]? = nil,
        guestBestPlayersVotes: [Int]? = nil,
        allowsLiveGameView: Bool = true,
        quarterLengthMinutes: Int = 20,
        timeOnEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.displayOrder = displayOrder
        self.asksHeadCoach = asksHeadCoach
        self.asksAssistantCoach = asksAssistantCoach
        self.asksTeamManager = asksTeamManager
        self.asksRunner = asksRunner
        self.asksGoalUmpire = asksGoalUmpire
        self.asksTimeKeeper = asksTimeKeeper
        self.asksFieldUmpire = asksFieldUmpire
        self.asksBoundaryUmpire1 = asksBoundaryUmpire1
        self.asksBoundaryUmpire2 = asksBoundaryUmpire2
        self.asksWaterBoy1 = asksWaterBoy1
        self.asksWaterBoy2 = asksWaterBoy2
        self.asksWaterBoy3 = asksWaterBoy3
        self.asksWaterBoy4 = asksWaterBoy4
        self.asksTrainers = asksTrainers
        self.asksTrainer1 = asksTrainer1
        self.asksTrainer2 = asksTrainer2
        self.asksTrainer3 = asksTrainer3
        self.asksTrainer4 = asksTrainer4
        self.asksNotes = asksNotes
        self.asksScore = asksScore
        self.asksLiveGameView = asksLiveGameView
        self.asksGoalKickers = asksGoalKickers
        self.tracksPlayersPerTeam = tracksPlayersPerTeam ?? Grade.defaultTracksPlayersPerTeam(for: name)
        let resolvedPlayersPerTeam = playersPerTeam ?? Grade.defaultPlayersPerTeam(for: name)
        self.playersPerTeam = min(max(resolvedPlayersPerTeam, 1), 60)
        let normalizedBestPlayersCount = min(max(bestPlayersCount, 0), 10)
        let normalizedGuestBestPlayersCount = min(max(guestBestPlayersCount, 1), 10)
        self.bestPlayersCount = normalizedBestPlayersCount
        self.asksGuestBestFairestVotesScan = asksGuestBestFairestVotesScan
        self.guestBestPlayersCount = normalizedGuestBestPlayersCount
        self.bestPlayersVotes = Grade.normalizedVotes(bestPlayersVotes, count: normalizedBestPlayersCount)
        self.guestBestPlayersVotes = Grade.normalizedGuestVotes(guestBestPlayersVotes, count: normalizedGuestBestPlayersCount)
        self.allowsLiveGameView = allowsLiveGameView
        self.quarterLengthMinutes = min(max(quarterLengthMinutes, 10), 30)
        self.timeOnEnabled = timeOnEnabled
    }

    static func normalizedVotes(_ votes: [Int]?, count: Int) -> [Int] {
        normalizedVotes(votes, count: count, fallback: Array((0..<count).map { max(count - $0 - 1, 0) }))
    }

    static func normalizedGuestVotes(_ votes: [Int]?, count: Int) -> [Int] {
        normalizedVotes(votes, count: count, fallback: Array((0..<count).map { max(count - $0, 1) }))
    }

    private static func normalizedVotes(_ votes: [Int]?, count: Int, fallback: [Int]) -> [Int] {
        guard count > 0 else { return [] }
        let defaults = Array(fallback.prefix(count))
        guard let votes else { return defaults }
        var normalized = Array(votes.prefix(count)).map { max($0, 0) }
        if normalized.count < count {
            normalized.append(contentsOf: defaults.dropFirst(normalized.count))
        }
        return normalized
    }

    static func defaultAsksTimeKeeper(for gradeName: String) -> Bool {
        let normalizedName = gradeName
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "-", with: " ")
        return !normalizedName.contains("under 9") && !normalizedName.contains("under 12")
    }

    static func defaultTimeOnEnabled(for gradeName: String) -> Bool {
        let normalizedName = gradeName
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedName == "a grade"
    }

    static func defaultTracksPlayersPerTeam(for gradeName: String) -> Bool {
        let normalizedName = gradeName
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedName.contains("under 9") || normalizedName.contains("under 12") {
            return false
        }

        return true
    }

    static func defaultPlayersPerTeam(for gradeName: String) -> Int {
        let normalizedName = gradeName
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedName.contains("a grade") || normalizedName.contains("b grade") {
            return 21
        }

        if normalizedName.contains("under 14")
            || normalizedName.contains("under 17")
            || normalizedName.contains("under 9")
            || normalizedName.contains("under 12") {
            return 22
        }

        return 22
    }
}
