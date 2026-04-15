import Foundation
import SwiftData

@Model
final class Grade {
    var id: UUID
    var name: String
    var isActive: Bool
    var displayOrder: Int
    var asksAssistantCoach: Bool
    var asksTeamManager: Bool
    var asksRunner: Bool
    var asksGoalUmpire: Bool
    var asksBoundaryUmpires: Bool
    var asksTrainers: Bool
    var asksNotes: Bool
    var asksGoalKickers: Bool
    var asksBestPlayers: Bool
    var asksGuestBestFairestVotesScan: Bool

    init(
        id: UUID = UUID(),
        name: String,
        isActive: Bool = true,
        displayOrder: Int = 0,
        asksAssistantCoach: Bool = true,
        asksTeamManager: Bool = true,
        asksRunner: Bool = true,
        asksGoalUmpire: Bool = true,
        asksBoundaryUmpires: Bool = true,
        asksTrainers: Bool = true,
        asksNotes: Bool = true,
        asksGoalKickers: Bool = true,
        asksBestPlayers: Bool = true,
        asksGuestBestFairestVotesScan: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.displayOrder = displayOrder
        self.asksAssistantCoach = asksAssistantCoach
        self.asksTeamManager = asksTeamManager
        self.asksRunner = asksRunner
        self.asksGoalUmpire = asksGoalUmpire
        self.asksBoundaryUmpires = asksBoundaryUmpires
        self.asksTrainers = asksTrainers
        self.asksNotes = asksNotes
        self.asksGoalKickers = asksGoalKickers
        self.asksBestPlayers = asksBestPlayers
        self.asksGuestBestFairestVotesScan = asksGuestBestFairestVotesScan
    }
}
