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
    var asksBoundaryUmpire1: Bool
    var asksBoundaryUmpire2: Bool
    var asksTrainers: Bool
    var asksNotes: Bool
    var asksGoalKickers: Bool
    var bestPlayersCount: Int
    var asksGuestBestFairestVotesScan: Bool

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
        asksBoundaryUmpire1: Bool = true,
        asksBoundaryUmpire2: Bool = true,
        asksTrainers: Bool = true,
        asksNotes: Bool = true,
        asksGoalKickers: Bool = true,
        bestPlayersCount: Int = 6,
        asksGuestBestFairestVotesScan: Bool = false
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
        self.asksBoundaryUmpire1 = asksBoundaryUmpire1
        self.asksBoundaryUmpire2 = asksBoundaryUmpire2
        self.asksTrainers = asksTrainers
        self.asksNotes = asksNotes
        self.asksGoalKickers = asksGoalKickers
        self.bestPlayersCount = min(max(bestPlayersCount, 0), 10)
        self.asksGuestBestFairestVotesScan = asksGuestBestFairestVotesScan
    }
}
