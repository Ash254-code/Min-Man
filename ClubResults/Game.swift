import Foundation
import SwiftData

@Model
final class Game: Identifiable {
    // Identity
    @Attribute(.unique) var id: UUID

    // Relations
    var gradeID: UUID

    // Core details
    var date: Date
    var opponent: String
    var venue: String

    // Scores (AFL style)
    var ourGoals: Int
    var ourBehinds: Int
    var theirGoals: Int
    var theirBehinds: Int

    // Goal kickers and best players
    var goalKickers: [GameGoalKickerEntry]
    var bestPlayersRanked: [UUID]
    var guestVotesRanked: [GameGuestVoteEntry]

    // Staff and officials
    var headCoachName: String
    var assistantCoachName: String
    var teamManagerName: String
    var runnerName: String
    var goalUmpireName: String
    var fieldUmpireName: String
    var boundaryUmpire1Name: String
    var boundaryUmpire2Name: String
    var waterBoy1Name: String
    var waterBoy2Name: String
    var waterBoy3Name: String
    var waterBoy4Name: String
    var trainers: [String]

    // Notes
    var notes: String
    var guestBestFairestVotesScanPDF: Data?
    var isDraft: Bool

    init(
        id: UUID = UUID(),
        gradeID: UUID,
        date: Date,
        opponent: String,
        venue: String,
        ourGoals: Int,
        ourBehinds: Int,
        theirGoals: Int,
        theirBehinds: Int,
        goalKickers: [GameGoalKickerEntry],
        bestPlayersRanked: [UUID],
        guestVotesRanked: [GameGuestVoteEntry] = [],
        headCoachName: String = "",
        assistantCoachName: String = "",
        teamManagerName: String = "",
        runnerName: String = "",
        goalUmpireName: String = "",
        fieldUmpireName: String = "",
        boundaryUmpire1Name: String = "",
        boundaryUmpire2Name: String = "",
        waterBoy1Name: String = "",
        waterBoy2Name: String = "",
        waterBoy3Name: String = "",
        waterBoy4Name: String = "",
        trainers: [String] = [],
        notes: String,
        guestBestFairestVotesScanPDF: Data? = nil,
        isDraft: Bool = false
    ) {
        self.id = id
        self.gradeID = gradeID
        self.date = date
        self.opponent = opponent
        self.venue = venue
        self.ourGoals = ourGoals
        self.ourBehinds = ourBehinds
        self.theirGoals = theirGoals
        self.theirBehinds = theirBehinds
        self.goalKickers = goalKickers
        self.bestPlayersRanked = bestPlayersRanked
        self.guestVotesRanked = guestVotesRanked
        self.headCoachName = headCoachName
        self.assistantCoachName = assistantCoachName
        self.teamManagerName = teamManagerName
        self.runnerName = runnerName
        self.goalUmpireName = goalUmpireName
        self.fieldUmpireName = fieldUmpireName
        self.boundaryUmpire1Name = boundaryUmpire1Name
        self.boundaryUmpire2Name = boundaryUmpire2Name
        self.waterBoy1Name = waterBoy1Name
        self.waterBoy2Name = waterBoy2Name
        self.waterBoy3Name = waterBoy3Name
        self.waterBoy4Name = waterBoy4Name
        self.trainers = trainers
        self.notes = notes
        self.guestBestFairestVotesScanPDF = guestBestFairestVotesScanPDF
        self.isDraft = isDraft
    }

    var ourScore: Int { ourGoals * 6 + ourBehinds }
    var theirScore: Int { theirGoals * 6 + theirBehinds }
}

// Nested type representing a goal kicker entry stored with a game
struct GameGoalKickerEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var playerID: UUID?
    var goals: Int
    var points: Int = 0

    init(id: UUID = UUID(), playerID: UUID?, goals: Int, points: Int = 0) {
        self.id = id
        self.playerID = playerID
        self.goals = goals
        self.points = points
    }

    enum CodingKeys: String, CodingKey {
        case id
        case playerID
        case goals
        case points
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        playerID = try container.decodeIfPresent(UUID.self, forKey: .playerID)
        goals = try container.decodeIfPresent(Int.self, forKey: .goals) ?? 0
        points = try container.decodeIfPresent(Int.self, forKey: .points) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(playerID, forKey: .playerID)
        try container.encode(goals, forKey: .goals)
        try container.encode(points, forKey: .points)
    }
}

struct GameGuestVoteEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var rank: Int
    var playerID: UUID
}

extension Game: ExportableGame {}
