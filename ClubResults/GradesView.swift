import Foundation
import SwiftData

@Model
final class Grade {
    var id: UUID
    var name: String
    var isActive: Bool
    var displayOrder: Int
    var asksHeadCoach: Bool
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

<<<<<<< HEAD
    // New-game wizard field visibility defaults (all ON by default)
    var showHeadCoach: Bool
    var showAssistantCoach: Bool
    var showTeamManager: Bool
    var showRunner: Bool
    var showFieldUmpire: Bool
    var showGoalUmpire: Bool
    var showBoundaryUmpire1: Bool
    var showBoundaryUmpire2: Bool
    var showTrainer1: Bool
    var showTrainer2: Bool
    var showTrainer3: Bool
    var showTrainer4: Bool
    var showGuestBestAndFairestVotes: Bool
    var showGoalKickers: Bool
    var numberOfBestPlayers: Int

=======
>>>>>>> redesign-new-game-wizard-with-toggles
    init(
        id: UUID = UUID(),
        name: String,
        isActive: Bool = true,
        displayOrder: Int = 0,
<<<<<<< HEAD
        showHeadCoach: Bool = true,
        showAssistantCoach: Bool = true,
        showTeamManager: Bool = true,
        showRunner: Bool = true,
        showFieldUmpire: Bool = true,
        showGoalUmpire: Bool = true,
        showBoundaryUmpire1: Bool = true,
        showBoundaryUmpire2: Bool = true,
        showTrainer1: Bool = true,
        showTrainer2: Bool = true,
        showTrainer3: Bool = true,
        showTrainer4: Bool = true,
        showGuestBestAndFairestVotes: Bool = true,
        showGoalKickers: Bool = true,
        numberOfBestPlayers: Int = 6
=======
        asksHeadCoach: Bool = true,
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
>>>>>>> redesign-new-game-wizard-with-toggles
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.displayOrder = displayOrder
<<<<<<< HEAD
        self.showHeadCoach = showHeadCoach
        self.showAssistantCoach = showAssistantCoach
        self.showTeamManager = showTeamManager
        self.showRunner = showRunner
        self.showFieldUmpire = showFieldUmpire
        self.showGoalUmpire = showGoalUmpire
        self.showBoundaryUmpire1 = showBoundaryUmpire1
        self.showBoundaryUmpire2 = showBoundaryUmpire2
        self.showTrainer1 = showTrainer1
        self.showTrainer2 = showTrainer2
        self.showTrainer3 = showTrainer3
        self.showTrainer4 = showTrainer4
        self.showGuestBestAndFairestVotes = showGuestBestAndFairestVotes
        self.showGoalKickers = showGoalKickers
        self.numberOfBestPlayers = max(1, min(10, numberOfBestPlayers))
=======
        self.asksHeadCoach = asksHeadCoach
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
>>>>>>> redesign-new-game-wizard-with-toggles
    }
}
