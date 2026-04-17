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
    var asksFieldUmpire: Bool
    var asksBoundaryUmpire1: Bool
    var asksBoundaryUmpire2: Bool
    var asksTrainers: Bool
    var asksTrainer1: Bool
    var asksTrainer2: Bool
    var asksTrainer3: Bool
    var asksTrainer4: Bool
    var asksNotes: Bool
    var asksGoalKickers: Bool
    var asksLiveGameView: Bool
    var bestPlayersCount: Int
    var asksGuestBestFairestVotesScan: Bool
    var quarterLengthMinutes: Int

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
        asksFieldUmpire: Bool = true,
        asksBoundaryUmpire1: Bool = true,
        asksBoundaryUmpire2: Bool = true,
        asksTrainers: Bool = true,
        asksTrainer1: Bool = true,
        asksTrainer2: Bool = true,
        asksTrainer3: Bool = true,
        asksTrainer4: Bool = true,
        asksNotes: Bool = true,
        asksGoalKickers: Bool = true,
        asksLiveGameView: Bool = true,
        bestPlayersCount: Int = 6,
        asksGuestBestFairestVotesScan: Bool = false,
        quarterLengthMinutes: Int = 20
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
        self.asksFieldUmpire = asksFieldUmpire
        self.asksBoundaryUmpire1 = asksBoundaryUmpire1
        self.asksBoundaryUmpire2 = asksBoundaryUmpire2
        self.asksTrainers = asksTrainers
        self.asksTrainer1 = asksTrainer1
        self.asksTrainer2 = asksTrainer2
        self.asksTrainer3 = asksTrainer3
        self.asksTrainer4 = asksTrainer4
        self.asksNotes = asksNotes
        self.asksGoalKickers = asksGoalKickers
        self.asksLiveGameView = asksLiveGameView
        self.bestPlayersCount = min(max(bestPlayersCount, 0), 10)
        self.asksGuestBestFairestVotesScan = asksGuestBestFairestVotesScan
        self.quarterLengthMinutes = min(max(quarterLengthMinutes, 10), 30)
    }
}
