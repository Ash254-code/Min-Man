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

    // Notes
    var notes: String
    var guestBestFairestVotesScanPDF: Data?

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
        notes: String,
        guestBestFairestVotesScanPDF: Data? = nil
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
        self.notes = notes
        self.guestBestFairestVotesScanPDF = guestBestFairestVotesScanPDF
    }

    var ourScore: Int { ourGoals * 6 + ourBehinds }
    var theirScore: Int { theirGoals * 6 + theirBehinds }
}

// Nested type representing a goal kicker entry stored with a game
struct GameGoalKickerEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var playerID: UUID?
    var goals: Int
}
