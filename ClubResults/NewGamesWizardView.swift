import SwiftUI
import SwiftData
import UIKit
import AudioToolbox
import MessageUI
#if canImport(VisionKit)
import VisionKit
#endif
#if canImport(AVFoundation)
import AVFoundation
internal import Combine
#endif

// Local model for goal kickers used by this wizard
private struct WizardGoalKickerEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var playerID: UUID?
    var goals: Int
}

struct NewGameWizardPreviewData {
    static let minimal = (
        venue: "Main Oval",
        opposition: "Redbacks",
        players: ["Tom Hill", "Jack Stone"],
        coaches: ["Ben Coach"],
        trainers: [String](),
        selectedPlayers: [String](),
        selectedCoaches: [String](),
        selectedTrainers: [String]()
    )

    static let large = (
        venue: "Memorial Park",
        opposition: "South Districts",
        players: [
            "Tom Hill", "Jack Stone", "Sam Reed", "Will Parker", "Luke Mason",
            "Ben Smith", "Josh Taylor", "Max Young", "Noah White", "Liam Brown",
            "Cooper Green", "Ethan Hall", "Hudson King", "Mason Scott", "Levi Ward",
            "Aiden Bell", "Zac Cook", "Ned Price", "Harry Long", "Alex West",
            "Owen Lee", "Isaac Adams", "Joel Baker", "Finn Carter", "Ryan Evans",
            "Ty Fox", "Hugo Grant", "Bailey Jones", "Mitchell Kerr", "Oscar Lane"
        ],
        coaches: ["Ben Coach", "Rob Assistant"],
        trainers: ["Trainer 1", "Trainer 2", "Trainer 3", "Trainer 4"],
        selectedPlayers: ["Tom Hill", "Jack Stone"],
        selectedCoaches: ["Ben Coach"],
        selectedTrainers: [String]()
    )
}

struct NewGameWizardPreviewContainer: View {
    let step: NewGameWizardStep
    let data: (
        venue: String,
        opposition: String,
        players: [String],
        coaches: [String],
        trainers: [String],
        selectedPlayers: [String],
        selectedCoaches: [String],
        selectedTrainers: [String]
    )

    var body: some View {
        NavigationStack {
            NewGameWizardView(
                previewStep: step,
                previewVenue: data.venue,
                previewOpposition: data.opposition,
                previewAvailablePlayers: data.players,
                previewAvailableCoaches: data.coaches,
                previewAvailableTrainers: data.trainers,
                previewSelectedPlayers: data.selectedPlayers,
                previewSelectedCoaches: data.selectedCoaches,
                previewSelectedTrainers: data.selectedTrainers
            )
        }
    }
}

#Preview("Details - Empty") {
    NewGameWizardPreviewContainer(
        step: .details,
        data: NewGameWizardPreviewData.minimal
    )
}

#Preview("Players - Large List") {
    NewGameWizardPreviewContainer(
        step: .players,
        data: NewGameWizardPreviewData.large
    )
}

#Preview("Coaches") {
    NewGameWizardPreviewContainer(
        step: .coaches,
        data: NewGameWizardPreviewData.large
    )
}

#Preview("Trainers - None Selected") {
    NewGameWizardPreviewContainer(
        step: .trainers,
        data: NewGameWizardPreviewData.minimal
    )
}

#Preview("Dark Mode") {
    NewGameWizardPreviewContainer(
        step: .players,
        data: NewGameWizardPreviewData.large
    )
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    NewGameWizardPreviewContainer(
        step: .players,
        data: NewGameWizardPreviewData.large
    )
    .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}

enum NewGameWizardStep {
    case details
    case coaches
    case boundaryUmpires
    case players
    case trainers
    case bestPlayers
    case guestVotes
    case review

    fileprivate var wizardStep: NewGameWizardView.Step {
        switch self {
        case .details: .setup
        case .coaches: .staff
        case .boundaryUmpires: .officials
        case .players: .goals
        case .trainers: .medical
        case .bestPlayers: .best
        case .guestVotes: .votes
        case .review: .review
        }
    }
}

struct NewGameWizardView: View {
    let initialGradeID: UUID?
    let draftGameID: UUID?
    let reopenLiveViewOnAppear: Bool
    let onBackToHomeFromLive: ((UUID) -> Void)?
    var previewStep: NewGameWizardStep? = nil
    var previewVenue: String? = nil
    var previewOpposition: String? = nil
    var previewAvailablePlayers: [String]? = nil
    var previewAvailableCoaches: [String]? = nil
    var previewAvailableTrainers: [String]? = nil
    var previewSelectedPlayers: [String]? = nil
    var previewSelectedCoaches: [String]? = nil
    var previewSelectedTrainers: [String]? = nil

    init(
        initialGradeID: UUID? = nil,
        draftGameID: UUID? = nil,
        reopenLiveViewOnAppear: Bool = false,
        onBackToHomeFromLive: ((UUID) -> Void)? = nil,
        previewStep: NewGameWizardStep? = nil,
        previewVenue: String? = nil,
        previewOpposition: String? = nil,
        previewAvailablePlayers: [String]? = nil,
        previewAvailableCoaches: [String]? = nil,
        previewAvailableTrainers: [String]? = nil,
        previewSelectedPlayers: [String]? = nil,
        previewSelectedCoaches: [String]? = nil,
        previewSelectedTrainers: [String]? = nil
    ) {
        self.initialGradeID = initialGradeID
        self.draftGameID = draftGameID
        self.reopenLiveViewOnAppear = reopenLiveViewOnAppear
        self.onBackToHomeFromLive = onBackToHomeFromLive
        self.previewStep = previewStep
        self.previewVenue = previewVenue
        self.previewOpposition = previewOpposition
        self.previewAvailablePlayers = previewAvailablePlayers
        self.previewAvailableCoaches = previewAvailableCoaches
        self.previewAvailableTrainers = previewAvailableTrainers
        self.previewSelectedPlayers = previewSelectedPlayers
        self.previewSelectedCoaches = previewSelectedCoaches
        self.previewSelectedTrainers = previewSelectedTrainers
    }

    // MARK: - Club Colours
    private let clubNavy = Color(red: 0.05, green: 0.15, blue: 0.35)
    private let clubYellow = Color(red: 1.0, green: 0.82, blue: 0.0)

    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext
    @Environment(\.dismiss) private var dismiss   // ✅ allow Cancel / dismiss sheet
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Query private var grades: [Grade]
    @Query private var games: [Game]
    @Query(sort: \Player.name) private var players: [Player]
    @Query(sort: [SortDescriptor(\Contact.name)]) private var contacts: [Contact]
    @Query private var reportRecipients: [ReportRecipient]

    // ✅ stored defaults per grade + role
    @Query private var staffDefaults: [StaffDefault]

    // ✅ UPDATED: first screen is Setup (grade + date + opponent + venue)
    enum Step: Int { case setup, staff, officials, medical, score, goals, best, votes, review }
    private enum EntryMode {
        case postGame
        case live
    }
    private enum DataEntrySelection: String, CaseIterable, Identifiable {
        case postGame = "Post Game"
        case liveGame = "Live Game"

        var id: String { rawValue }
    }
    private enum GameCountSelection: String, CaseIterable, Identifiable {
        case one
        case two

        var id: String { rawValue }
        var label: String { self == .one ? "One game" : "Two games" }
    }
    @State private var step: Step = .setup
    @State private var entryMode: EntryMode?
    @State private var dataEntrySelection: DataEntrySelection?
    @State private var liveGameSession = LiveGameSessionState()
    @State private var editingGame: Game?

    // MARK: Setup
    @State private var gradeID: UUID?
    @State private var date = Date()
    @State private var gameCountSelection: GameCountSelection?

    @State private var clubConfiguration: ClubConfiguration = ClubConfigurationStore.load()

    // MARK: Selections (dropdowns)
    @State private var opponentName: String = ""
    @State private var venueName: String = ""

    // MARK: Staff
    @State private var headCoachName: String = ""
    @State private var assCoachName: String = ""
    @State private var teamManagerName: String = ""
    @State private var runnerName: String = ""

    @State private var goalUmpireName: String = ""
    @State private var fieldUmpireName: String = ""

    // Boundary umpires are chosen from a configured grade's players, or entered manually.
    @State private var boundaryUmpire1Name: String = ""
    @State private var boundaryUmpire2Name: String = ""

    @State private var trainer1Name: String = ""
    @State private var trainer2Name: String = ""
    @State private var trainer3Name: String = ""
    @State private var trainer4Name: String = ""

    @State private var notes = ""
    @State private var game2HeadCoachName: String = ""
    @State private var game2AssCoachName: String = ""
    @State private var game2TeamManagerName: String = ""
    @State private var game2RunnerName: String = ""
    @State private var game2GoalUmpireName: String = ""
    @State private var game2FieldUmpireName: String = ""
    @State private var game2BoundaryUmpire1Name: String = ""
    @State private var game2BoundaryUmpire2Name: String = ""
    @State private var game2Trainer1Name: String = ""
    @State private var game2Trainer2Name: String = ""
    @State private var game2Trainer3Name: String = ""
    @State private var game2Trainer4Name: String = ""

    // MARK: Score (AFL: goals * 6 + behinds)
    @State private var ourGoals = 0
    @State private var ourBehinds = 0
    @State private var theirGoals = 0
    @State private var theirBehinds = 0

    @State private var periodMinutes = 20
    @State private var remainingSeconds = 20 * 60
    @State private var isTimerRunning = false

    private var ourScore: Int { ourGoals * 6 + ourBehinds }
    private var theirScore: Int { theirGoals * 6 + theirBehinds }

    // MARK: Goals + best players
    @State private var goalKickers: [WizardGoalKickerEntry] = []
    @State private var goalKickerPickerPrompt: UUID?
    @State private var goalKickerPickerDetent: PresentationDetent = .large
    @State private var bestRanked: [UUID?] = Array(repeating: nil, count: 6)
    @State private var bestRankedGame2: [UUID?] = Array(repeating: nil, count: 6)
    @State private var bestPlayerPickerPrompt: Int?
    @State private var bestPlayerPickerGameNumber: Int = 1
    @State private var bestPlayerPickerDetent: PresentationDetent = .large
    @State private var showAddPlayerFromBestPicker = false
    @State private var addPlayerErrorMessage: String?
    @State private var showAddPlayerError = false
    @State private var guestVotesRanked: [UUID?] = Array(repeating: nil, count: 6)
    @State private var guestVotesRankedGame2: [UUID?] = Array(repeating: nil, count: 6)
    @State private var guestVotePickerPrompt: Int?
    @State private var guestVotePickerGameNumber: Int = 1
    @State private var guestVotePickerDetent: PresentationDetent = .large
    @State private var guestBestFairestVotesScanPDF: Data?
    @State private var showVotesScanner = false
    @State private var showGuestVotesScanPrompt = false
    @State private var scannerErrorMessage: String?
    @State private var hasAutoPromptedVotesScanner = false

    private enum LiveDraftResumeStore {
        private static let statePrefix = "liveDraft.state."

        private struct StoredState: Codable {
            var periodMinutes: Int
            var secondsRemaining: Int
            var pointScorers: [UUID: Int]
            var rushedPoints: Int
            var periodSnapshots: [StoredSnapshot]
            var scoreEvents: [StoredScoreEvent]?
            var backgroundCountdownStart: Date?
        }

        private struct StoredScoreEvent: Codable {
            var x: Double
            var margin: Int
        }

        private struct StoredSnapshot: Codable {
            var label: String
            var ourGoals: Int
            var ourBehinds: Int
            var theirGoals: Int
            var theirBehinds: Int
        }

        static func save(_ session: LiveGameSessionState, for gameID: UUID, continueCountdownInBackground: Bool) {
            let state = StoredState(
                periodMinutes: session.periodMinutes,
                secondsRemaining: session.secondsRemaining,
                pointScorers: session.pointScorers,
                rushedPoints: session.rushedPoints,
                periodSnapshots: session.periodSnapshots.map {
                    StoredSnapshot(
                        label: $0.label,
                        ourGoals: $0.ourGoals,
                        ourBehinds: $0.ourBehinds,
                        theirGoals: $0.theirGoals,
                        theirBehinds: $0.theirBehinds
                    )
                },
                scoreEvents: session.scoreEvents.map {
                    StoredScoreEvent(x: $0.x, margin: $0.margin)
                },
                backgroundCountdownStart: continueCountdownInBackground ? Date() : nil
            )
            guard let data = try? JSONEncoder().encode(state) else { return }
            UserDefaults.standard.set(data, forKey: statePrefix + gameID.uuidString)
        }

        static func load(for gameID: UUID) -> LiveGameSessionState? {
            let key = statePrefix + gameID.uuidString
            guard let data = UserDefaults.standard.data(forKey: key),
                  let stored = try? JSONDecoder().decode(StoredState.self, from: data) else {
                return nil
            }

            var session = LiveGameSessionState()
            session.periodMinutes = stored.periodMinutes
            session.secondsRemaining = max(0, stored.secondsRemaining)
            session.pointScorers = stored.pointScorers
            session.rushedPoints = stored.rushedPoints
            session.periodSnapshots = stored.periodSnapshots.map {
                PeriodSnapshot(
                    label: $0.label,
                    ourGoals: $0.ourGoals,
                    ourBehinds: $0.ourBehinds,
                    theirGoals: $0.theirGoals,
                    theirBehinds: $0.theirBehinds
                )
            }
            session.scoreEvents = (stored.scoreEvents ?? []).map {
                ScoreEvent(x: $0.x, margin: $0.margin)
            }
            session.isInitialized = true

            if let start = stored.backgroundCountdownStart {
                let elapsed = Int(Date().timeIntervalSince(start))
                session.secondsRemaining = max(0, session.secondsRemaining - max(0, elapsed))
                session.shouldAutoResumeTimer = session.secondsRemaining > 0
            }

            clear(for: gameID)
            return session
        }

        static func clear(for gameID: UUID) {
            UserDefaults.standard.removeObject(forKey: statePrefix + gameID.uuidString)
        }
    }
    @State private var hasAppliedInitialGrade = false
    @State private var hasAppliedDraftRestore = false
    @State private var isRestoringDraft = false
    @State private var suppressNextGradeChangeReset = false
    @State private var reportAttachmentURL: URL?
    @State private var pendingEmailRecipients: [String] = []
    @State private var pendingTextRecipients: [String] = []
    @State private var showMailComposer = false
    @State private var showMessageComposer = false
    @State private var sendStatusMessage: String?

    private var isPreviewMode: Bool { previewStep != nil }
    private var currentStep: Step { previewStep?.wizardStep ?? step }
    private var previewPlayers: [Player] {
        (previewAvailablePlayers ?? []).enumerated().map { idx, name in
            Player(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", idx + 1)) ?? UUID(), name: name, isActive: true)
        }
    }

    // MARK: Helpers
    private func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func normalizePlayerName(_ s: String) -> String {
        clean(s)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private var finalOpponent: String { clean(opponentName) }
    private var finalVenue: String { clean(venueName) }

    private var finalHeadCoach: String { clean(headCoachName) }
    private var finalAssCoach: String { clean(assCoachName) }
    private var finalTeamManager: String { clean(teamManagerName) }
    private var finalRunner: String { clean(runnerName) }

    private var finalGoalUmpire: String { clean(goalUmpireName) }
    private var finalFieldUmpire: String { clean(fieldUmpireName) }
    private var finalGame2HeadCoach: String { clean(game2HeadCoachName) }
    private var finalGame2AssCoach: String { clean(game2AssCoachName) }
    private var finalGame2TeamManager: String { clean(game2TeamManagerName) }
    private var finalGame2Runner: String { clean(game2RunnerName) }
    private var finalGame2GoalUmpire: String { clean(game2GoalUmpireName) }
    private var finalGame2FieldUmpire: String { clean(game2FieldUmpireName) }

    private func playerName(for id: UUID?) -> String {
        guard let id else { return "" }
        return eligiblePlayers.first(where: { $0.id == id })?.name
            ?? players.first(where: { $0.id == id })?.name
            ?? ""
    }
    private func playerName(_ id: UUID) -> String {
        playerName(for: id)
    }
    private var finalBoundary1: String {
        clean(boundaryUmpire1Name)
    }
    private var finalBoundary2: String {
        clean(boundaryUmpire2Name)
    }
    private var finalGame2Boundary1: String {
        clean(game2BoundaryUmpire1Name)
    }
    private var finalGame2Boundary2: String {
        clean(game2BoundaryUmpire2Name)
    }
    private var selectedTrainerNames: [String] {
        [trainer1Name, trainer2Name, trainer3Name, trainer4Name]
            .map(clean)
            .filter { !$0.isEmpty }
    }
    private var selectedGame2TrainerNames: [String] {
        [game2Trainer1Name, game2Trainer2Name, game2Trainer3Name, game2Trainer4Name]
            .map(clean)
            .filter { !$0.isEmpty }
    }

    private var opponentNames: [String] {
        clubConfiguration.sortedOppositions.map(\.name)
    }

    private var selectedOpposition: OppositionTeamProfile? {
        clubConfiguration.sortedOppositions.first(where: { $0.name == finalOpponent })
    }

    private var venuesForSelection: [String] {
        let combined = clubConfiguration.clubTeam.sanitizedVenues + (selectedOpposition?.sanitizedVenues ?? [])
        var seen = Set<String>()
        return combined.filter { seen.insert($0).inserted }
    }

    private var standardPillWidth: CGFloat {
        ClubStyle.standardPillWidth(configuration: clubConfiguration)
    }

    private var ourTeamScoreStyle: ClubStyle.Style {
        ClubStyle.style(for: clubConfiguration.clubTeam.name, configuration: clubConfiguration)
    }

    private var opponentScoreStyle: ClubStyle.Style {
        let opponent = finalOpponent.isEmpty ? "Opponent" : finalOpponent
        return ClubStyle.style(for: opponent, configuration: clubConfiguration)
    }

    private var setupPickerExpandedDetent: PresentationDetent {
        PickerSheetPresentation.expandedDetent(isCompactLayout: isCompactLayout)
    }

    private var selectorPickerRowHeight: CGFloat { isCompactLayout ? 56 : 72 }

    private var selectorPickerHeaderAndPaddingHeight: CGFloat { isCompactLayout ? 112 : 132 }

    private var goalKickerPickerOptionsCount: Int {
        eligiblePlayers.count + 1 // "Select…" + players
    }

    private var goalKickerPickerHeight: CGFloat {
        PickerSheetPresentation.preferredHeight(
            optionCount: goalKickerPickerOptionsCount,
            rowHeight: selectorPickerRowHeight,
            chromeHeight: selectorPickerHeaderAndPaddingHeight,
            minVisibleRows: 3,
            isCompactLayout: isCompactLayout
        )
    }

    private var bestPlayerPickerOptionsCount: Int {
        eligiblePlayers.count + 1 // "Select…" + players
    }

    private var bestPlayerPickerHeight: CGFloat {
        PickerSheetPresentation.preferredHeight(
            optionCount: bestPlayerPickerOptionsCount,
            rowHeight: selectorPickerRowHeight,
            chromeHeight: selectorPickerHeaderAndPaddingHeight,
            minVisibleRows: 3,
            isCompactLayout: isCompactLayout
        )
    }

    // MARK: Defaults (from SwiftData)
    private func defaultStaffName(for role: StaffRole, gradeID: UUID?) -> String? {
        guard let gradeID else { return nil }
        return staffDefaults.first(where: { $0.gradeID == gradeID && $0.role == role })?.name
    }

    private enum StaffFieldKey: String, CaseIterable {
        case headCoach
        case assistantCoach
        case teamManager
        case runner
        case goalUmpire
        case fieldUmpire
        case boundaryUmpire1
        case boundaryUmpire2
        case trainer1
        case trainer2
        case trainer3
        case trainer4
    }

    private func persistedLastSelection(for field: StaffFieldKey, gradeID: UUID?) -> String? {
        guard let gradeID else { return nil }
        let key = "lastStaffSelection.\(gradeID.uuidString).\(field.rawValue)"
        let saved = UserDefaults.standard.string(forKey: key) ?? ""
        let cleaned = clean(saved)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func saveLastSelection(_ value: String, for field: StaffFieldKey, gradeID: UUID?) {
        guard let gradeID else { return }
        let key = "lastStaffSelection.\(gradeID.uuidString).\(field.rawValue)"
        let cleaned = clean(value)
        if cleaned.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(cleaned, forKey: key)
        }
    }

    private func assignDefault(for field: StaffFieldKey, role: StaffRole, gradeID: UUID?, assign: (String) -> Void) {
        let lastSelected = persistedLastSelection(for: field, gradeID: gradeID)
        let roleDefault = defaultStaffName(for: role, gradeID: gradeID)
        assign(lastSelected ?? roleDefault ?? "")
    }

    private func applyDefaults(for gradeID: UUID?) {
        assignDefault(for: .headCoach, role: .headCoach, gradeID: gradeID) { headCoachName = $0 }
        assignDefault(for: .assistantCoach, role: .assistantCoach, gradeID: gradeID) { assCoachName = $0 }
        assignDefault(for: .teamManager, role: .teamManager, gradeID: gradeID) { teamManagerName = $0 }
        assignDefault(for: .runner, role: .runner, gradeID: gradeID) { runnerName = $0 }
        assignDefault(for: .goalUmpire, role: .goalUmpire, gradeID: gradeID) { goalUmpireName = $0 }
        assignDefault(for: .fieldUmpire, role: .fieldUmpire, gradeID: gradeID) { fieldUmpireName = $0 }
        assignDefault(for: .boundaryUmpire1, role: .boundaryUmpire, gradeID: gradeID) { boundaryUmpire1Name = $0 }
        assignDefault(for: .boundaryUmpire2, role: .boundaryUmpire, gradeID: gradeID) { boundaryUmpire2Name = $0 }
        assignDefault(for: .trainer1, role: .trainer, gradeID: gradeID) { trainer1Name = $0 }
        assignDefault(for: .trainer2, role: .trainer, gradeID: gradeID) { trainer2Name = $0 }
        assignDefault(for: .trainer3, role: .trainer, gradeID: gradeID) { trainer3Name = $0 }
        assignDefault(for: .trainer4, role: .trainer, gradeID: gradeID) { trainer4Name = $0 }
        assignDefault(for: .headCoach, role: .headCoach, gradeID: gradeID) { game2HeadCoachName = $0 }
        assignDefault(for: .assistantCoach, role: .assistantCoach, gradeID: gradeID) { game2AssCoachName = $0 }
        assignDefault(for: .teamManager, role: .teamManager, gradeID: gradeID) { game2TeamManagerName = $0 }
        assignDefault(for: .runner, role: .runner, gradeID: gradeID) { game2RunnerName = $0 }
        assignDefault(for: .goalUmpire, role: .goalUmpire, gradeID: gradeID) { game2GoalUmpireName = $0 }
        assignDefault(for: .fieldUmpire, role: .fieldUmpire, gradeID: gradeID) { game2FieldUmpireName = $0 }
        assignDefault(for: .boundaryUmpire1, role: .boundaryUmpire, gradeID: gradeID) { game2BoundaryUmpire1Name = $0 }
        assignDefault(for: .boundaryUmpire2, role: .boundaryUmpire, gradeID: gradeID) { game2BoundaryUmpire2Name = $0 }
        assignDefault(for: .trainer1, role: .trainer, gradeID: gradeID) { game2Trainer1Name = $0 }
        assignDefault(for: .trainer2, role: .trainer, gradeID: gradeID) { game2Trainer2Name = $0 }
        assignDefault(for: .trainer3, role: .trainer, gradeID: gradeID) { game2Trainer3Name = $0 }
        assignDefault(for: .trainer4, role: .trainer, gradeID: gradeID) { game2Trainer4Name = $0 }
        if let gradeID, let grade = resolvedGrades.first(where: { $0.id == gradeID }) {
            periodMinutes = min(max(grade.quarterLengthMinutes, 10), 30)
            if !isTimerRunning {
                remainingSeconds = periodMinutes * 60
            }
        }
    }

    private func persistCurrentStaffSelections(for gradeID: UUID?) {
        saveLastSelection(headCoachName, for: .headCoach, gradeID: gradeID)
        saveLastSelection(assCoachName, for: .assistantCoach, gradeID: gradeID)
        saveLastSelection(teamManagerName, for: .teamManager, gradeID: gradeID)
        saveLastSelection(runnerName, for: .runner, gradeID: gradeID)
        saveLastSelection(goalUmpireName, for: .goalUmpire, gradeID: gradeID)
        saveLastSelection(fieldUmpireName, for: .fieldUmpire, gradeID: gradeID)
        saveLastSelection(boundaryUmpire1Name, for: .boundaryUmpire1, gradeID: gradeID)
        saveLastSelection(boundaryUmpire2Name, for: .boundaryUmpire2, gradeID: gradeID)
        saveLastSelection(trainer1Name, for: .trainer1, gradeID: gradeID)
        saveLastSelection(trainer2Name, for: .trainer2, gradeID: gradeID)
        saveLastSelection(trainer3Name, for: .trainer3, gradeID: gradeID)
        saveLastSelection(trainer4Name, for: .trainer4, gradeID: gradeID)
        if isTwoGameFlow {
            saveLastSelection(game2HeadCoachName, for: .headCoach, gradeID: gradeID)
            saveLastSelection(game2AssCoachName, for: .assistantCoach, gradeID: gradeID)
            saveLastSelection(game2TeamManagerName, for: .teamManager, gradeID: gradeID)
            saveLastSelection(game2RunnerName, for: .runner, gradeID: gradeID)
            saveLastSelection(game2GoalUmpireName, for: .goalUmpire, gradeID: gradeID)
            saveLastSelection(game2FieldUmpireName, for: .fieldUmpire, gradeID: gradeID)
            saveLastSelection(game2BoundaryUmpire1Name, for: .boundaryUmpire1, gradeID: gradeID)
            saveLastSelection(game2BoundaryUmpire2Name, for: .boundaryUmpire2, gradeID: gradeID)
            saveLastSelection(game2Trainer1Name, for: .trainer1, gradeID: gradeID)
            saveLastSelection(game2Trainer2Name, for: .trainer2, gradeID: gradeID)
            saveLastSelection(game2Trainer3Name, for: .trainer3, gradeID: gradeID)
            saveLastSelection(game2Trainer4Name, for: .trainer4, gradeID: gradeID)
        }
    }

    // MARK: Ordering helpers
    private var resolvedGrades: [Grade] {
        resolvedConfiguredGrades(from: grades)
    }

    private var selectedGradeName: String {
        guard let gid = gradeID else { return "Not selected" }
        return resolvedGrades.first(where: { $0.id == gid })?.name ?? "Unknown grade"
    }

    private var eligiblePlayers: [Player] {
        if isPreviewMode {
            return previewPlayers
        }
        guard let gid = gradeID else { return [] }
        return players.filter { $0.isActive && $0.gradeIDs.contains(gid) }
    }

    private var isCompactLayout: Bool { horizontalSizeClass == .compact }

    private var wizardPrimaryTitleFont: Font {
        .system(size: isCompactLayout ? 40 : 52, weight: .bold)
    }

    private var wizardSecondaryTitleFont: Font {
        .system(size: isCompactLayout ? 22 : 30, weight: .semibold)
    }

    private var wizardStepSubtitleFont: Font {
        .system(size: isCompactLayout ? 16 : 20, weight: .semibold)
    }

    private var wizardBodyFont: Font {
        .system(size: isCompactLayout ? 20 : 24, weight: .regular)
    }

    private var currentStepSubtitle: String {
        switch currentStep {
        case .setup: return "Game Details"
        case .staff: return "Coaches"
        case .officials: return "Officials"
        case .medical: return "Medical & Notes"
        case .score: return supportsLiveGameView ? "Live Scoring" : "Final Score"
        case .goals: return "Goal Kickers"
        case .best: return "Best Players"
        case .votes: return "Guest Votes"
        case .review: return "Review & Save"
        }
    }

    private var wizardHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: isCompactLayout ? 2 : 4) {
                Text("New Game")
                    .font(wizardPrimaryTitleFont)

                Text(currentStepSubtitle)
                    .font(wizardStepSubtitleFont)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(selectedGradeName)
                .font(wizardSecondaryTitleFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, isCompactLayout ? 20 : 28)
        .padding(.top, isCompactLayout ? 8 : 14)
        .padding(.bottom, isCompactLayout ? 12 : 16)
    }

    private var selectedGrade: Grade? {
        guard let gid = gradeID else { return nil }
        return resolvedGrades.first(where: { $0.id == gid })
    }

    private var shouldAskGameCount: Bool {
        guard let grade = selectedGrade else { return false }
        let normalized = grade.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "under 9's" || normalized == "under 12's"
    }

    private var isTwoGameFlow: Bool {
        gameCountSelection == .two
    }

    private var defaultGameCountSelection: GameCountSelection? {
        shouldAskGameCount ? nil : .one
    }

    private var requiredBestPlayersCount: Int {
        min(max(selectedGrade?.bestPlayersCount ?? 6, 0), 10)
    }

    private var shouldAskGuestVotes: Bool {
        guard let grade = selectedGrade else { return false }
        return grade.asksGuestBestFairestVotesScan && grade.guestBestPlayersCount > 0
    }

    private var requiredGuestBestPlayersCount: Int {
        guard shouldAskGuestVotes else { return 0 }
        return min(max(selectedGrade?.guestBestPlayersCount ?? 3, 0), 10)
    }

    private var supportsLiveGameView: Bool {
        guard let grade = selectedGrade else { return true }
        return grade.asksLiveGameView && grade.allowsLiveGameView
    }

    private var shouldAskForEntryMode: Bool {
        supportsLiveGameView
    }

    private var availableDataEntryOptions: [DataEntrySelection] {
        supportsLiveGameView ? DataEntrySelection.allCases : [.postGame]
    }

    private var isLastStepInFlow: Bool {
        activeSteps.last == step
    }

    private var activeSteps: [Step] {
        guard let grade = selectedGrade else { return [.setup] }

        var steps: [Step] = [.setup]
        if grade.asksHeadCoach ||
            grade.asksAssistantCoach ||
            grade.asksTeamManager ||
            grade.asksRunner {
            steps.append(.staff)
        }
        if grade.asksGoalUmpire ||
            grade.asksFieldUmpire ||
            grade.asksBoundaryUmpire1 ||
            grade.asksBoundaryUmpire2 {
            steps.append(.officials)
        }
        if grade.asksTrainer1 ||
            grade.asksTrainer2 ||
            grade.asksTrainer3 ||
            grade.asksTrainer4 {
            steps.append(.medical)
        }
        if entryMode == .live {
            steps.append(.score)
        } else if grade.asksScore {
            steps.append(.score)
        }
        if grade.asksGoalKickers && entryMode != .live { steps.append(.goals) }
        if grade.bestPlayersCount > 0 { steps.append(.best) }
        if grade.asksGuestBestFairestVotesScan && grade.guestBestPlayersCount > 0 { steps.append(.votes) }
        return steps
    }

    private var entryModeTriggerStep: Step {
        if !shouldAskForEntryMode { return .setup }
        if activeSteps.contains(.officials) { return .officials }
        if activeSteps.contains(.medical) { return .medical }
        if activeSteps.contains(.officials) { return .officials }
        if activeSteps.contains(.staff) { return .staff }
        return .setup
    }

    // MARK: - Uniform row styling
    private func rowLabel(_ title: String) -> some View {
        Text(title)
            .font(wizardBodyFont)
    }

    private func rowValue(_ text: String) -> some View {
        Text(text.isEmpty ? "Select…" : text)
            .font(wizardBodyFont)
            .foregroundStyle(text.isEmpty ? .secondary : .primary)
    }

    private var selectorListFont: Font {
        .system(size: isCompactLayout ? 24 : 28, weight: .semibold)
    }

    @ViewBuilder
    private func selectorListRow(title: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(selectorListFont)
                .foregroundStyle(.primary)
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: isCompactLayout ? 22 : 26, weight: .semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, isCompactLayout ? 8 : 12)
        .contentShape(Rectangle())
    }

    // MARK: Goal allocation helpers
    private var totalAllocatedGoals: Int { goalKickers.reduce(0) { $0 + $1.goals } }

    private func maxAllowedGoals(for entry: WizardGoalKickerEntry) -> Int {
        let remaining = ourGoals - (totalAllocatedGoals - entry.goals)
        return max(0, remaining)
    }

    private func goalKickerEntry(for id: UUID?) -> WizardGoalKickerEntry? {
        guard let id else { return nil }
        return goalKickers.first(where: { $0.id == id })
    }

    private func selectedGoalKickerPlayerID(for entryID: UUID?) -> UUID? {
        goalKickerEntry(for: entryID)?.playerID
    }

    private func setGoalKickerPlayer(_ playerID: UUID?, for entryID: UUID?) {
        guard let entryID, let idx = goalKickers.firstIndex(where: { $0.id == entryID }) else { return }
        goalKickers[idx].playerID = playerID
    }

    private func selectedBestPlayerID(for rankIndex: Int?) -> UUID? {
        guard let rankIndex, bestRanked.indices.contains(rankIndex) else { return nil }
        let source = bestPlayerPickerGameNumber == 2 ? bestRankedGame2 : bestRanked
        return source[rankIndex]
    }

    private func clearBestPlayer(at rankIndex: Int?) {
        guard let rankIndex else { return }
        if bestPlayerPickerGameNumber == 2 {
            guard bestRankedGame2.indices.contains(rankIndex) else { return }
            bestRankedGame2[rankIndex] = nil
        } else {
            guard bestRanked.indices.contains(rankIndex) else { return }
            bestRanked[rankIndex] = nil
        }
    }

    private func selectedGuestVotePlayerID(for rankIndex: Int?) -> UUID? {
        guard let rankIndex, guestVotesRanked.indices.contains(rankIndex) else { return nil }
        let source = guestVotePickerGameNumber == 2 ? guestVotesRankedGame2 : guestVotesRanked
        return source[rankIndex]
    }

    private func clearGuestVote(at rankIndex: Int?) {
        guard let rankIndex else { return }
        if guestVotePickerGameNumber == 2 {
            guard guestVotesRankedGame2.indices.contains(rankIndex) else { return }
            guestVotesRankedGame2[rankIndex] = nil
        } else {
            guard guestVotesRanked.indices.contains(rankIndex) else { return }
            guestVotesRanked[rankIndex] = nil
        }
    }

    // MARK: Validation
    private var canProceed: Bool {
        switch step {

        case .setup:
            return gradeID != nil &&
                   !finalOpponent.isEmpty &&
                   !finalVenue.isEmpty &&
                   (!shouldAskGameCount || gameCountSelection != nil) &&
                   (!shouldAskForEntryMode || dataEntrySelection != nil)

        case .staff:
            let asksHeadCoach = selectedGrade?.asksHeadCoach ?? true
            let asksAssistantCoach = selectedGrade?.asksAssistantCoach ?? true
            let asksTeamManager = selectedGrade?.asksTeamManager ?? true
            let asksRunner = selectedGrade?.asksRunner ?? true

            let coachingOK =
                (!asksHeadCoach || !finalHeadCoach.isEmpty) &&
                (!asksAssistantCoach || !finalAssCoach.isEmpty) &&
                (!asksTeamManager || !finalTeamManager.isEmpty) &&
                (!asksRunner || !finalRunner.isEmpty)

            if !isTwoGameFlow { return coachingOK }
            let coachingGame2OK =
                (!asksHeadCoach || !finalGame2HeadCoach.isEmpty) &&
                (!asksAssistantCoach || !finalGame2AssCoach.isEmpty) &&
                (!asksTeamManager || !finalGame2TeamManager.isEmpty) &&
                (!asksRunner || !finalGame2Runner.isEmpty)

            return coachingOK && coachingGame2OK

        case .officials:
            let asksGoalUmpire = selectedGrade?.asksGoalUmpire ?? true
            let asksFieldUmpire = selectedGrade?.asksFieldUmpire ?? true
            let asksBoundaryUmpire1 = selectedGrade?.asksBoundaryUmpire1 ?? true
            let asksBoundaryUmpire2 = selectedGrade?.asksBoundaryUmpire2 ?? true

            let officialsCompleted =
                (!asksGoalUmpire || !finalGoalUmpire.isEmpty) &&
                (!asksFieldUmpire || !finalFieldUmpire.isEmpty) &&
                (!asksBoundaryUmpire1 || !finalBoundary1.isEmpty) &&
                (!asksBoundaryUmpire2 || !finalBoundary2.isEmpty)

            let boundarySelectionIsUnique =
                !(asksBoundaryUmpire1 && asksBoundaryUmpire2 &&
                  !finalBoundary1.isEmpty && finalBoundary1 == finalBoundary2)

            if !isTwoGameFlow { return officialsCompleted && boundarySelectionIsUnique }
            let officialsGame2Completed =
                (!asksGoalUmpire || !finalGame2GoalUmpire.isEmpty) &&
                (!asksFieldUmpire || !finalGame2FieldUmpire.isEmpty) &&
                (!asksBoundaryUmpire1 || !finalGame2Boundary1.isEmpty) &&
                (!asksBoundaryUmpire2 || !finalGame2Boundary2.isEmpty)

            let boundaryGame2SelectionIsUnique =
                !(asksBoundaryUmpire1 && asksBoundaryUmpire2 &&
                  !finalGame2Boundary1.isEmpty && finalGame2Boundary1 == finalGame2Boundary2)

            return officialsCompleted && boundarySelectionIsUnique && officialsGame2Completed && boundaryGame2SelectionIsUnique

        case .medical:
            // This step is informational/optional; never block navigation here.
            return true

        case .score:
            return true

        case .goals:
            return remainingGoalsToAllocate == 0
                && !hasDuplicateGoalKickers
                && (goalKickers.isEmpty || allGoalKickersSelected)

        case .best:
            let ids = bestRanked.compactMap { $0 }
            let game1OK = ids.count == requiredBestPlayersCount && Set(ids).count == requiredBestPlayersCount
            if !isTwoGameFlow { return game1OK }
            let game2IDs = bestRankedGame2.compactMap { $0 }
            let game2OK = game2IDs.count == requiredBestPlayersCount && Set(game2IDs).count == requiredBestPlayersCount
            return game1OK && game2OK

        case .votes:
            let ids = guestVotesRanked.compactMap { $0 }
            let game1OK = ids.count == requiredGuestBestPlayersCount && Set(ids).count == requiredGuestBestPlayersCount
            if !isTwoGameFlow { return game1OK }
            let game2IDs = guestVotesRankedGame2.compactMap { $0 }
            let game2OK = game2IDs.count == requiredGuestBestPlayersCount && Set(game2IDs).count == requiredGuestBestPlayersCount
            return game1OK && game2OK

        case .review:
            return true
        }
    }

    private var canProceedOnCurrentStep: Bool {
        canProceed
    }

    private func startLiveSessionIfNeeded() {
        let configuredPeriod = min(max(selectedGrade?.quarterLengthMinutes ?? 20, 10), 30)
        liveGameSession.configureIfNeeded(initialPeriodMinutes: configuredPeriod)
    }

    private var displayedSteps: [Step] {
        isPreviewMode ? [currentStep] : activeSteps
    }

    private var stepSelectionBinding: Binding<Int> {
        Binding(
            get: { displayedSteps.firstIndex(of: currentStep) ?? 0 },
            set: { newIndex in
                guard displayedSteps.indices.contains(newIndex) else { return }
                let newStep = displayedSteps[newIndex]
                move(to: newStep)
            }
        )
    }

    @ViewBuilder
    private func stepView(for wizardStep: Step) -> some View {
        switch wizardStep {
        case .setup: setupStep
        case .staff: staffStep
        case .officials: officialsStep
        case .medical: medicalStep
        case .score: scoreStep
        case .goals: goalsStep
        case .best: bestStep
        case .votes: votesStep
        case .review: reviewStep
        }
    }

    // MARK: Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if currentStep != .score {
                    wizardHeader
                }

                if currentStep != .score {
                    ProgressView(
                        value: Double(activeSteps.firstIndex(of: currentStep) ?? 0),
                        total: Double(max(activeSteps.count - 1, 1))
                    )
                    .padding(.horizontal)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                }

                TabView(selection: stepSelectionBinding) {
                    ForEach(Array(displayedSteps.enumerated()), id: \.offset) { index, wizardStep in
                        stepView(for: wizardStep)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !isPreviewMode && currentStep != .score {
                    HStack {
                        if currentStep == .setup {
                            Button("Cancel") { dismiss() }
                        } else {
                            Button("Back") { back() }
                        }

                        Spacer()

                        if isLastStepInFlow {
                            Button("Save") {
                                _ = saveGame(asDraft: false, dismissOnSuccess: true)
                            }
                            .disabled(!canProceedOnCurrentStep)
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("Next") { next() }
                                .disabled(!canProceedOnCurrentStep)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .font(.system(size: isCompactLayout ? 24 : 28, weight: .semibold))
                    .controlSize(isCompactLayout ? .large : .extraLarge)
                    .padding(.horizontal, isCompactLayout ? 18 : 26)
                    .padding(.vertical, isCompactLayout ? 14 : 18)
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle(
                currentStep == .score
                    ? (supportsLiveGameView ? "Live Game View" : "Final Score")
                    : ""
            )
            .navigationBarTitleDisplayMode(.inline)

            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !isPreviewMode && currentStep == .score {
                        Button("Pause") {
                            pauseAndSaveLiveDraftThenReturnHome()
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.26), value: currentStep)
        // ✅ Seed staff + defaults once
        .onAppear {
            StaffSeeder.seedIfNeeded(modelContext: dataContext, grades: grades)
            clubConfiguration = ClubConfigurationStore.load()
            if !opponentName.isEmpty && !opponentNames.contains(opponentName) {
                opponentName = ""
                venueName = ""
            }
            applyDefaults(for: gradeID)
            applyPreviewStateIfNeeded()
        }
        // ✅ When user changes grade, auto-fill defaults from last selected values (or seeded defaults)
        .onChange(of: gradeID) { _, newGrade in
            if suppressNextGradeChangeReset {
                suppressNextGradeChangeReset = false
                return
            }
            guard !isRestoringDraft else { return }
            applyDefaults(for: newGrade)
            syncBestPlayersSelectionCount()
            syncGuestVotesSelectionCount()
            gameCountSelection = defaultGameCountSelection
            step = .setup
            entryMode = nil
            dataEntrySelection = supportsLiveGameView ? nil : .postGame
            liveGameSession = LiveGameSessionState()
            editingGame = nil
            guestBestFairestVotesScanPDF = nil
            guestVotesRanked = Array(repeating: nil, count: requiredGuestBestPlayersCount)
            guestVotesRankedGame2 = Array(repeating: nil, count: requiredGuestBestPlayersCount)
            hasAutoPromptedVotesScanner = false
        }
        .onAppear {
            guard !hasAppliedInitialGrade else { return }
            hasAppliedInitialGrade = true
            if let initialGradeID {
                gradeID = initialGradeID
                applyDefaults(for: initialGradeID)
                syncBestPlayersSelectionCount()
                syncGuestVotesSelectionCount()
            }
            applyPreviewStateIfNeeded()
            restoreDraftIfNeeded()
        }
        .sheet(isPresented: $showMailComposer) {
            if let attachmentURL = reportAttachmentURL {
                MailComposeView(
                    recipients: pendingEmailRecipients,
                    subject: "Min-Man Game Report",
                    body: "Attached is the game report PDF.",
                    attachmentURL: attachmentURL
                ) {
                    showMailComposer = false
                    beginTextSendIfNeeded()
                }
            }
        }
        .sheet(isPresented: $showMessageComposer) {
            if let attachmentURL = reportAttachmentURL {
                MessageComposeView(
                    recipients: pendingTextRecipients,
                    body: "Min-Man game report attached.",
                    attachmentURL: attachmentURL
                ) {
                    showMessageComposer = false
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showVotesScanner) {
            VotesScannerSheet { data in
                guestBestFairestVotesScanPDF = data
                showVotesScanner = false
                hasAutoPromptedVotesScanner = true
                if step == .votes {
                    proceedFromVotesStep()
                }
            } onCancel: {
                showVotesScanner = false
                hasAutoPromptedVotesScanner = true
                if step == .votes {
                    proceedFromVotesStep()
                }
            }
        }
        .alert("Scanner unavailable", isPresented: Binding(
            get: { scannerErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    scannerErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                scannerErrorMessage = nil
                hasAutoPromptedVotesScanner = true
            }
        } message: {
            Text(scannerErrorMessage ?? "")
        }
        .confirmationDialog(
            "Scan guest votes?",
            isPresented: $showGuestVotesScanPrompt,
            titleVisibility: .visible
        ) {
            Button("Scan now") {
                openVotesScanner()
            }
            Button("Skip without scan") {
                proceedFromVotesStep()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Manual guest votes are already saved in the ranking. You can optionally attach a scan.")
        }
        .alert(
            "Report status",
            isPresented: Binding(
                get: { sendStatusMessage != nil },
                set: { if !$0 { sendStatusMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                let shouldDismiss = sendStatusMessage?.contains("Game saved") == true
                sendStatusMessage = nil
                if shouldDismiss { dismiss() }
            }
        } message: {
            Text(sendStatusMessage ?? "")
        }
    }

    private func pauseAndSaveLiveDraftThenReturnHome() {
        guard let gid = gradeID else {
            dismiss()
            return
        }

        let savedGame = saveGame(asDraft: true, dismissOnSuccess: false, enforceCompletionRequirements: false)
        if let savedGame {
            LiveDraftResumeStore.save(liveGameSession, for: savedGame.id, continueCountdownInBackground: true)
        }
        onBackToHomeFromLive?(gid)
        dismiss()
    }

    private func discardLiveDraftThenReturnHome() {
        guard let gid = gradeID else {
            dismiss()
            return
        }

        var clearedDraftIDs: Set<UUID> = []

        if let editingGame, editingGame.isDraft {
            clearedDraftIDs.insert(editingGame.id)
            dataContext.delete(editingGame)
            self.editingGame = nil
        }

        if let draftGameID,
           let persistedDraft = games.first(where: { $0.id == draftGameID && $0.isDraft }) {
            clearedDraftIDs.insert(persistedDraft.id)
            if editingGame?.id != persistedDraft.id {
                dataContext.delete(persistedDraft)
            }
        }

        if !clearedDraftIDs.isEmpty {
            do { try dataContext.save() }
            catch { print("❌ Failed to discard draft game: \(error)") }
        }

        for gameID in clearedDraftIDs {
            LiveDraftResumeStore.clear(for: gameID)
        }

        onBackToHomeFromLive?(gid)
        dismiss()
    }

    private func next() {
        if step == .votes {
            showGuestVotesScanPrompt = true
            return
        }

        if isLastStepInFlow {
            _ = saveGame(asDraft: false, dismissOnSuccess: true)
            return
        }

        if shouldAskForEntryMode && step == entryModeTriggerStep && entryMode == nil {
            entryMode = dataEntrySelection == .liveGame ? .live : .postGame
        }

        if shouldAskForEntryMode && step == entryModeTriggerStep && entryMode == .live {
            startLiveSessionIfNeeded()
        }

        guard let currentIndex = activeSteps.firstIndex(of: step) else { return }
        let nextIndex = currentIndex + 1
        guard activeSteps.indices.contains(nextIndex) else { return }
        move(to: activeSteps[nextIndex])
    }

    private func proceedFromVotesStep() {
        if isLastStepInFlow {
            _ = saveGame(asDraft: false, dismissOnSuccess: true)
            return
        }

        guard let currentIndex = activeSteps.firstIndex(of: .votes) else { return }
        let nextIndex = currentIndex + 1
        guard activeSteps.indices.contains(nextIndex) else { return }
        move(to: activeSteps[nextIndex])
    }

    private func back() {
        guard let currentIndex = activeSteps.firstIndex(of: step), currentIndex > 0 else { return }
        move(to: activeSteps[currentIndex - 1])
    }

    private func proceedAfterLiveSave() {
        if activeSteps.contains(.best) {
            move(to: .best)
        } else if activeSteps.contains(.votes) {
            move(to: .votes)
        } else {
            _ = saveGame(asDraft: false, dismissOnSuccess: true)
        }
    }

    private func move(to newStep: Step) {
        withAnimation(.easeInOut(duration: 0.3)) {
            step = newStep
        }
    }

    private func applyPreviewStateIfNeeded() {
        guard isPreviewMode else { return }

        step = previewStep?.wizardStep ?? step
        entryMode = .postGame
        dataEntrySelection = .postGame

        if let previewVenue {
            venueName = previewVenue
        }
        if let previewOpposition {
            opponentName = previewOpposition
        }

        let selectedCoaches = previewSelectedCoaches ?? previewAvailableCoaches ?? []
        headCoachName = selectedCoaches.indices.contains(0) ? selectedCoaches[0] : ""
        assCoachName = selectedCoaches.indices.contains(1) ? selectedCoaches[1] : ""

        let selectedTrainers = previewSelectedTrainers ?? previewAvailableTrainers ?? []
        trainer1Name = selectedTrainers.indices.contains(0) ? selectedTrainers[0] : ""
        trainer2Name = selectedTrainers.indices.contains(1) ? selectedTrainers[1] : ""
        trainer3Name = selectedTrainers.indices.contains(2) ? selectedTrainers[2] : ""
        trainer4Name = selectedTrainers.indices.contains(3) ? selectedTrainers[3] : ""

        let selectedPlayerNames = Set(previewSelectedPlayers ?? [])
        let selectedPlayerIDs = previewPlayers
            .filter { selectedPlayerNames.contains($0.name) }
            .map(\.id)

        if !selectedPlayerIDs.isEmpty {
            goalKickers = selectedPlayerIDs.map { WizardGoalKickerEntry(playerID: $0, goals: 1) }
            syncBestPlayersSelectionCount()
            syncGuestVotesSelectionCount()
            for idx in bestRanked.indices {
                bestRanked[idx] = idx < selectedPlayerIDs.count ? selectedPlayerIDs[idx] : nil
            }
            for idx in guestVotesRanked.indices {
                guestVotesRanked[idx] = idx < selectedPlayerIDs.count ? selectedPlayerIDs[idx] : nil
            }
        }
    }

    private func restoreDraftIfNeeded() {
        guard !hasAppliedDraftRestore else { return }
        hasAppliedDraftRestore = true
        guard let draftGameID else { return }
        guard let draft = games.first(where: { $0.id == draftGameID && $0.isDraft }) else { return }

        isRestoringDraft = true
        suppressNextGradeChangeReset = true
        editingGame = draft
        gradeID = draft.gradeID
        gameCountSelection = defaultGameCountSelection
        date = draft.date
        opponentName = draft.opponent
        venueName = draft.venue
        ourGoals = draft.ourGoals
        ourBehinds = draft.ourBehinds
        theirGoals = draft.theirGoals
        theirBehinds = draft.theirBehinds
        goalKickers = draft.goalKickers.map { kickerEntry in
            WizardGoalKickerEntry(playerID: kickerEntry.playerID, goals: kickerEntry.goals)
        }
        headCoachName = draft.headCoachName
        assCoachName = draft.assistantCoachName
        teamManagerName = draft.teamManagerName
        runnerName = draft.runnerName
        goalUmpireName = draft.goalUmpireName
        fieldUmpireName = draft.fieldUmpireName
        boundaryUmpire1Name = draft.boundaryUmpire1Name
        boundaryUmpire2Name = draft.boundaryUmpire2Name
        trainer1Name = draft.trainers.indices.contains(0) ? draft.trainers[0] : ""
        trainer2Name = draft.trainers.indices.contains(1) ? draft.trainers[1] : ""
        trainer3Name = draft.trainers.indices.contains(2) ? draft.trainers[2] : ""
        trainer4Name = draft.trainers.indices.contains(3) ? draft.trainers[3] : ""
        notes = draft.notes
        guestBestFairestVotesScanPDF = draft.guestBestFairestVotesScanPDF

        syncBestPlayersSelectionCount()
        let bestIDs = draft.bestPlayersRanked
        for idx in bestRanked.indices {
            bestRanked[idx] = bestIDs.indices.contains(idx) ? bestIDs[idx] : nil
        }
        syncGuestVotesSelectionCount()
        let guestVotesByRank = Dictionary(uniqueKeysWithValues: draft.guestVotesRanked.map { ($0.rank, $0.playerID) })
        for idx in guestVotesRanked.indices {
            guestVotesRanked[idx] = guestVotesByRank[idx + 1]
        }

        if reopenLiveViewOnAppear {
            entryMode = .live
            dataEntrySelection = .liveGame
            startLiveSessionIfNeeded()
            if let resumedSession = LiveDraftResumeStore.load(for: draft.id) {
                liveGameSession = resumedSession
            }
            move(to: .score)
            isRestoringDraft = false
        } else {
            entryMode = .postGame
            dataEntrySelection = .postGame
            isRestoringDraft = false
        }
    }

    // MARK: Steps

    // ✅ NEW: Setup step (Grade + Date + Opponent + Venue)
    // Uses the SAME Form styling you had on the Grade screen.
    private var setupStep: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let _ = gradeID {
                    StaffCard(title: "Players", systemImage: "person.3.fill") {
                        Text(
                            eligiblePlayers.isEmpty
                                ? "No active players assigned to this grade yet. Add players first."
                                : "\(eligiblePlayers.count) eligible players"
                        )
                        .font(wizardBodyFont)
                        .foregroundStyle(.secondary)
                    }
                }

                StaffCard(title: "Game Details", systemImage: "calendar") {
                    DatePicker("Date & time", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .font(wizardBodyFont)

                    HStack(spacing: 12) {
                        rowLabel("Opponent")
                        Spacer()
                        setupMenuButton(title: opponentName.isEmpty ? "Select…" : opponentName) {
                            Button("Select…") { opponentName = "" }
                            ForEach(opponentNames, id: \.self) { opposition in
                                Button(opposition) {
                                    opponentName = opposition
                                    if !venuesForSelection.contains(venueName) {
                                        venueName = ""
                                    }
                                }
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        rowLabel("Venue")
                        Spacer()
                        setupMenuButton(
                            title: venueName.isEmpty ? "Select…" : venueName,
                            isDisabled: venuesForSelection.isEmpty
                        ) {
                            Button("Select…") { venueName = "" }
                            ForEach(venuesForSelection, id: \.self) { venue in
                                Button(venue) {
                                    venueName = venue
                                }
                            }
                        }
                    }

                    if shouldAskGameCount {
                        HStack(spacing: 12) {
                            rowLabel("How many games?")
                            Spacer()
                            setupMenuButton(title: gameCountSelection?.label ?? "Select…") {
                                ForEach(GameCountSelection.allCases) { option in
                                    Button(option.label) {
                                        gameCountSelection = option
                                    }
                                }
                            }
                        }
                    }

                    if shouldAskForEntryMode {
                        HStack(spacing: 12) {
                            rowLabel("Data Entry")
                            Spacer()
                            HStack(spacing: 8) {
                                ForEach(availableDataEntryOptions) { option in
                                    setupChoiceButton(
                                        title: option.rawValue,
                                        isSelected: dataEntrySelection == option
                                    ) {
                                        dataEntrySelection = option
                                        entryMode = option == .liveGame ? .live : .postGame
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .dynamicTypeSize(.large ... .accessibility2)
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func setupMenuButton<Content: View>(
        title: String,
        isDisabled: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(wizardBodyFont)
                    .foregroundStyle(title == "Select…" ? .secondary : .primary)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: isCompactLayout ? 13 : 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, isCompactLayout ? 14 : 18)
            .padding(.vertical, isCompactLayout ? 10 : 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func setupChoiceButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(wizardBodyFont)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)
                .padding(.horizontal, isCompactLayout ? 12 : 14)
                .padding(.vertical, isCompactLayout ? 8 : 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    // Staff step (coaching only)
    private var staffStep: some View {
        ScrollView {
            VStack(spacing: 14) {

                StaffCard(title: isTwoGameFlow ? "Game 1 · Coaching" : "Coaching", systemImage: "person.2.fill") {
                    if selectedGrade?.asksHeadCoach ?? true {
                        StaffPickerField(title: "Head Coach", role: .headCoach, gradeID: gradeID, value: $headCoachName)
                    }
                    if selectedGrade?.asksAssistantCoach ?? true {
                        StaffPickerField(title: "Assistant Coach", role: .assistantCoach, gradeID: gradeID, value: $assCoachName)
                    }
                    if selectedGrade?.asksTeamManager ?? true {
                        StaffPickerField(title: "Team Manager", role: .teamManager, gradeID: gradeID, value: $teamManagerName)
                    }
                    if selectedGrade?.asksRunner ?? true {
                        StaffPickerField(title: "Runner", role: .runner, gradeID: gradeID, value: $runnerName)
                    }
                }

                if isTwoGameFlow {
                    StaffCard(title: "Game 2 · Coaching", systemImage: "person.2.fill") {
                        if selectedGrade?.asksHeadCoach ?? true {
                            StaffPickerField(title: "Head Coach", role: .headCoach, gradeID: gradeID, value: $game2HeadCoachName)
                        }
                        if selectedGrade?.asksAssistantCoach ?? true {
                            StaffPickerField(title: "Assistant Coach", role: .assistantCoach, gradeID: gradeID, value: $game2AssCoachName)
                        }
                        if selectedGrade?.asksTeamManager ?? true {
                            StaffPickerField(title: "Team Manager", role: .teamManager, gradeID: gradeID, value: $game2TeamManagerName)
                        }
                        if selectedGrade?.asksRunner ?? true {
                            StaffPickerField(title: "Runner", role: .runner, gradeID: gradeID, value: $game2RunnerName)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var officialsStep: some View {
        ScrollView {
            VStack(spacing: 14) {
                StaffCard(title: isTwoGameFlow ? "Game 1 · Officials" : "Officials", systemImage: "flag.fill") {
                    if selectedGrade?.asksGoalUmpire ?? true {
                        StaffPickerField(title: "Goal Umpire", role: .goalUmpire, gradeID: gradeID, value: $goalUmpireName)
                    }
                    if selectedGrade?.asksFieldUmpire ?? true {
                        StaffPickerField(title: "Field Umpire", role: .fieldUmpire, gradeID: gradeID, value: $fieldUmpireName)
                    }

                    let asksBoundaryUmpire1 = selectedGrade?.asksBoundaryUmpire1 ?? true
                    let asksBoundaryUmpire2 = selectedGrade?.asksBoundaryUmpire2 ?? true

                    if asksBoundaryUmpire1 {
                        StaffPickerField(
                            title: "Umpire 1",
                            role: .boundaryUmpire,
                            gradeID: gradeID,
                            value: $boundaryUmpire1Name
                        )
                    }

                    if asksBoundaryUmpire2 {
                        StaffPickerField(
                            title: "Umpire 2",
                            role: .boundaryUmpire,
                            gradeID: gradeID,
                            value: $boundaryUmpire2Name
                        )
                    }

                    if asksBoundaryUmpire1, asksBoundaryUmpire2, !finalBoundary1.isEmpty, finalBoundary1 == finalBoundary2 {
                        Text("Umpire 1 and 2 can’t be the same.")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.top, 6)
                    }
                }

                if isTwoGameFlow {
                    StaffCard(title: "Game 2 · Officials", systemImage: "flag.fill") {
                        if selectedGrade?.asksGoalUmpire ?? true {
                            StaffPickerField(title: "Goal Umpire", role: .goalUmpire, gradeID: gradeID, value: $game2GoalUmpireName)
                        }
                        if selectedGrade?.asksFieldUmpire ?? true {
                            StaffPickerField(title: "Field Umpire", role: .fieldUmpire, gradeID: gradeID, value: $game2FieldUmpireName)
                        }

                        let asksBoundaryUmpire1 = selectedGrade?.asksBoundaryUmpire1 ?? true
                        let asksBoundaryUmpire2 = selectedGrade?.asksBoundaryUmpire2 ?? true

                        if asksBoundaryUmpire1 {
                            StaffPickerField(
                                title: "Umpire 1",
                                role: .boundaryUmpire,
                                gradeID: gradeID,
                                value: $game2BoundaryUmpire1Name
                            )
                        }

                        if asksBoundaryUmpire2 {
                            StaffPickerField(
                                title: "Umpire 2",
                                role: .boundaryUmpire,
                                gradeID: gradeID,
                                value: $game2BoundaryUmpire2Name
                            )
                        }

                        if asksBoundaryUmpire1, asksBoundaryUmpire2, !finalGame2Boundary1.isEmpty, finalGame2Boundary1 == finalGame2Boundary2 {
                            Text("Umpire 1 and 2 can’t be the same.")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.top, 6)
                        }
                    }
                }

            }
            .padding(.horizontal, isCompactLayout ? 16 : 26)
            .padding(.top, isCompactLayout ? 12 : 18)
            .padding(.bottom, isCompactLayout ? 28 : 36)
        }
        .font(wizardBodyFont)
        .dynamicTypeSize(.large ... .accessibility2)
        .background(Color(.systemGroupedBackground))
    }

    private var medicalStep: some View {
        ScrollView {
            VStack(spacing: 14) {
                StaffCard(title: isTwoGameFlow ? "Game 1 · Medical & Trainers" : "Medical & Trainers", systemImage: "cross.case.fill") {
                    if selectedGrade?.asksTrainer1 ?? true {
                        StaffPickerField(title: "Trainer 1", role: .trainer, gradeID: gradeID, value: $trainer1Name)
                    }
                    if selectedGrade?.asksTrainer2 ?? true {
                        StaffPickerField(title: "Trainer 2", role: .trainer, gradeID: gradeID, value: $trainer2Name)
                    }
                    if selectedGrade?.asksTrainer3 ?? true {
                        StaffPickerField(title: "Trainer 3", role: .trainer, gradeID: gradeID, value: $trainer3Name)
                    }
                    if selectedGrade?.asksTrainer4 ?? true {
                        StaffPickerField(title: "Trainer 4", role: .trainer, gradeID: gradeID, value: $trainer4Name)
                    }
                    if !(selectedGrade?.asksTrainer1 ?? true) &&
                        !(selectedGrade?.asksTrainer2 ?? true) &&
                        !(selectedGrade?.asksTrainer3 ?? true) &&
                        !(selectedGrade?.asksTrainer4 ?? true) {
                        Text("Trainer fields are disabled for this grade.")
                            .foregroundStyle(.secondary)
                    }
                }

                if isTwoGameFlow {
                    StaffCard(title: "Game 2 · Medical & Trainers", systemImage: "cross.case.fill") {
                        if selectedGrade?.asksTrainer1 ?? true {
                            StaffPickerField(title: "Trainer 1", role: .trainer, gradeID: gradeID, value: $game2Trainer1Name)
                        }
                        if selectedGrade?.asksTrainer2 ?? true {
                            StaffPickerField(title: "Trainer 2", role: .trainer, gradeID: gradeID, value: $game2Trainer2Name)
                        }
                        if selectedGrade?.asksTrainer3 ?? true {
                            StaffPickerField(title: "Trainer 3", role: .trainer, gradeID: gradeID, value: $game2Trainer3Name)
                        }
                        if selectedGrade?.asksTrainer4 ?? true {
                            StaffPickerField(title: "Trainer 4", role: .trainer, gradeID: gradeID, value: $game2Trainer4Name)
                        }
                        if !(selectedGrade?.asksTrainer1 ?? true) &&
                            !(selectedGrade?.asksTrainer2 ?? true) &&
                            !(selectedGrade?.asksTrainer3 ?? true) &&
                            !(selectedGrade?.asksTrainer4 ?? true) {
                            Text("Trainer fields are disabled for this grade.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if selectedGrade?.asksNotes ?? true {
                    StaffCard(title: "Notes", systemImage: "note.text") {
                        TextField("Notes (optional)", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, isCompactLayout ? 16 : 26)
            .padding(.top, isCompactLayout ? 12 : 18)
            .padding(.bottom, isCompactLayout ? 28 : 36)
        }
        .font(wizardBodyFont)
        .dynamicTypeSize(.large ... .accessibility2)
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private var scoreStep: some View {
        if supportsLiveGameView {
            liveGameStep
        } else {
            postGameScoreStep
        }
    }

    private var liveGameStep: some View {
        LiveGameView(
            date: $date,
            ourGoals: $ourGoals,
            ourBehinds: $ourBehinds,
            theirGoals: $theirGoals,
            theirBehinds: $theirBehinds,
            goalKickers: $goalKickers,
            bestRanked: $bestRanked,
            liveSession: $liveGameSession,
            initialPeriodMinutes: min(max(selectedGrade?.quarterLengthMinutes ?? 20, 10), 30),
            requiredBestPlayersCount: requiredBestPlayersCount,
            ourTeamName: clubConfiguration.clubTeam.name,
            oppTeamName: finalOpponent.isEmpty ? "Opponent" : finalOpponent,
            ourStyle: ClubStyle.style(for: clubConfiguration.clubTeam.name, configuration: clubConfiguration),
            oppStyle: ClubStyle.style(for: finalOpponent.isEmpty ? "Opponent" : finalOpponent, configuration: clubConfiguration),
            eligiblePlayers: eligiblePlayers,
            playerName: { playerID in
                players.first(where: { $0.id == playerID })?.name ?? "Unknown"
            },
            onSaveAndContinue: {
                _ = saveGame(asDraft: true, dismissOnSuccess: false, enforceCompletionRequirements: false)
                proceedAfterLiveSave()
            },
            onBackToHome: {
                pauseAndSaveLiveDraftThenReturnHome()
            },
            onCancelAndDiscard: {
                discardLiveDraftThenReturnHome()
            },
            onCollapse: {
                pauseAndSaveLiveDraftThenReturnHome()
            }
        )
    }

    private var postGameScoreStep: some View {
        Form {
            Section("Final score") {
                scoreEntryRow(title: clubConfiguration.clubTeam.name, goals: $ourGoals, behinds: $ourBehinds)
                scoreEntryRow(title: finalOpponent.isEmpty ? "Opponent" : finalOpponent, goals: $theirGoals, behinds: $theirBehinds)
            }

            Section("Totals") {
                HStack {
                    Text(clubConfiguration.clubTeam.name)
                    Spacer()
                    Text("\(ourGoals).\(ourBehinds) (\(ourScore))")
                        .font(.headline)
                }
                HStack {
                    Text(finalOpponent.isEmpty ? "Opponent" : finalOpponent)
                    Spacer()
                    Text("\(theirGoals).\(theirBehinds) (\(theirScore))")
                        .font(.headline)
                }
            }

            Section {
                Button("Save and Continue") { next() }
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .environment(\.defaultMinListRowHeight, isCompactLayout ? 56 : 72)
    }

    private func scoreEntryRow(title: String, goals: Binding<Int>, behinds: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Stepper("Goals: \(goals.wrappedValue)", value: goals, in: 0...50)
            Stepper("Behinds: \(behinds.wrappedValue)", value: behinds, in: 0...50)
        }
        .padding(.vertical, 4)
    }

    private var timerTick: Timer.TimerPublisher {
        Timer.publish(every: 1, on: .main, in: .common)
    }

    private var periodMinutesEditor: Binding<String> {
        Binding(
            get: { String(periodMinutes) },
            set: { newValue in
                let digitsOnly = newValue.filter(\.isNumber)
                guard let value = Int(digitsOnly), (1...99).contains(value) else { return }
                periodMinutes = value
            }
        )
    }

    private var liveGoalScorersSummary: [(name: String, goals: Int)] {
        let grouped = Dictionary(grouping: goalKickers.compactMap { entry -> (String, Int)? in
            guard
                let playerID = entry.playerID,
                let player = players.first(where: { $0.id == playerID }),
                entry.goals > 0
            else { return nil }
            return (player.name, entry.goals)
        }, by: { $0.0 })

        return grouped
            .map { (name, entries) in (name: name, goals: entries.reduce(0) { $0 + $1.1 }) }
            .sorted { $0.goals > $1.goals }
    }

    private var formattedClock: String {
        let safeSeconds = max(0, remainingSeconds)
        let minutes = safeSeconds / 60
        let seconds = safeSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func timerCard(width: CGFloat, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Timer")
                    .font(.title3.weight(.semibold))
                Spacer()
                HStack(spacing: 8) {
                    Text("Period minutes")
                        .foregroundStyle(.secondary)
                    TextField("20", text: periodMinutesEditor)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                    Stepper("", value: $periodMinutes, in: 1...99)
                        .labelsHidden()
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(formattedClock)
                    .font(.system(size: isCompactLayout ? 52 : 68, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Spacer()
            }

            HStack(spacing: 10) {
                Button("Start") { isTimerRunning = remainingSeconds > 0 }
                    .buttonStyle(.borderedProminent)
                Button("Pause") { isTimerRunning = false }
                    .buttonStyle(.bordered)
                Button("Reset") {
                    isTimerRunning = false
                    remainingSeconds = periodMinutes * 60
                }
                .buttonStyle(.bordered)
            }
            .font(.headline)
            .controlSize(.large)
        }
        .padding(18)
        .frame(maxWidth: width, minHeight: minHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var goalScorersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Goal scorers")
                .font(.title3.weight(.bold))

            if liveGoalScorersSummary.isEmpty {
                Text("No goal scorers yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(liveGoalScorersSummary, id: \.name) { scorer in
                    HStack {
                        Text(scorer.name)
                        Spacer()
                        Text("\(scorer.goals)")
                            .fontWeight(.bold)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func scoreboardCard(minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Scoreboard")
                .font(.title2.weight(.bold))

            HStack(alignment: .top, spacing: 16) {
                teamScoreColumn(
                    title: clubConfiguration.clubTeam.name,
                    style: ourTeamScoreStyle,
                    goals: ourGoals,
                    behinds: ourBehinds,
                    total: ourScore,
                    goalsBinding: $ourGoals,
                    behindsBinding: $ourBehinds
                )

                teamScoreColumn(
                    title: finalOpponent.isEmpty ? "Opponent" : finalOpponent,
                    style: opponentScoreStyle,
                    goals: theirGoals,
                    behinds: theirBehinds,
                    total: theirScore,
                    goalsBinding: $theirGoals,
                    behindsBinding: $theirBehinds
                )
            }

            HStack(spacing: 14) {
                eventButton(
                    title: "Goal",
                    color: ClubStyle.style(for: clubConfiguration.clubTeam.name, configuration: clubConfiguration).background,
                    action: { ourGoals += 1 }
                )
                eventButton(
                    title: "Point",
                    color: ClubStyle.style(for: clubConfiguration.clubTeam.name, configuration: clubConfiguration).background,
                    action: { ourBehinds += 1 }
                )
                eventButton(
                    title: "Goal",
                    color: ClubStyle.style(for: finalOpponent.isEmpty ? "Opponent" : finalOpponent, configuration: clubConfiguration).background,
                    action: { theirGoals += 1 }
                )
                eventButton(
                    title: "Point",
                    color: ClubStyle.style(for: finalOpponent.isEmpty ? "Opponent" : finalOpponent, configuration: clubConfiguration).background,
                    action: { theirBehinds += 1 }
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func teamScoreColumn(
        title: String,
        style: ClubStyle.Style,
        goals: Int,
        behinds: Int,
        total: Int,
        goalsBinding: Binding<Int>,
        behindsBinding: Binding<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ScorePill(title, style: style, fixedWidth: standardPillWidth)

            Text("\(goals).\(behinds)")
                .font(.system(size: isCompactLayout ? 36 : 54, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text("\(total)")
                .font(.system(size: isCompactLayout ? 56 : 88, weight: .black, design: .rounded))
                .monospacedDigit()

            HStack(spacing: 12) {
                Stepper("Goals: \(goals)", value: goalsBinding, in: 0...50)
                Stepper("Points: \(behinds)", value: behindsBinding, in: 0...50)
            }
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: isCompactLayout ? 18 : 24, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, isCompactLayout ? 14 : 18)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color.opacity(0.85))
        )
        .foregroundStyle(.white)
    }

    private var goalsStep: some View {
        Form {
            Section("Goals summary") {
                HStack { Text("Our goals (from score)"); Spacer(); Text("\(ourGoals)").font(.headline) }
                HStack { Text("Allocated to kickers"); Spacer(); Text("\(totalGoalsKicked)").font(.headline) }
                HStack {
                    Text(overAllocatedGoals ? "Over allocated" : "Remaining to allocate")
                    Spacer()
                    Text("\(abs(remainingGoalsToAllocate))")
                        .font(.headline)
                        .foregroundStyle(overAllocatedGoals ? .red : .primary)
                }
                if hasDuplicateGoalKickers {
                    Text("Same player selected more than once.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Goal kickers") {
                if eligiblePlayers.isEmpty {
                    Text("Add players to this grade first.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($goalKickers) { $entry in
                        HStack(spacing: 12) {
                            Button {
                                goalKickerPickerPrompt = entry.id
                            } label: {
                                HStack(spacing: 12) {
                                    rowLabel("Player")
                                    Spacer()
                                    rowValue(playerName(for: entry.playerID))
                                        .lineLimit(1)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: isCompactLayout ? 14 : 18, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer(minLength: 8)

                            Text("\(entry.goals)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(clubYellow)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(clubNavy)
                                )

                            Stepper(value: $entry.goals, in: 0...maxAllowedGoals(for: entry)) {
                                EmptyView()
                            }
                            .labelsHidden()
                        }
                    }
                    .onDelete { idx in goalKickers.remove(atOffsets: idx) }

                    Button("Add goal kicker") {
                        goalKickers.append(WizardGoalKickerEntry(playerID: nil, goals: 1))
                    }
                }
            }
        }
        .font(wizardBodyFont)
        .environment(\.defaultMinListRowHeight, isCompactLayout ? 56 : 72)
        .dynamicTypeSize(.large ... .accessibility2)
        .scrollContentBackground(.hidden)
        .sheet(
            isPresented: Binding(
                get: { goalKickerPickerPrompt != nil },
                set: { if !$0 { goalKickerPickerPrompt = nil } }
            )
        ) {
            NavigationStack {
                List {
                    Button {
                        setGoalKickerPlayer(nil, for: goalKickerPickerPrompt)
                        goalKickerPickerPrompt = nil
                    } label: {
                        selectorListRow(
                            title: "Select…",
                            selected: selectedGoalKickerPlayerID(for: goalKickerPickerPrompt) == nil
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(eligiblePlayers) { player in
                        Button {
                            setGoalKickerPlayer(player.id, for: goalKickerPickerPrompt)
                            goalKickerPickerPrompt = nil
                        } label: {
                            selectorListRow(
                                title: player.name,
                                selected: selectedGoalKickerPlayerID(for: goalKickerPickerPrompt) == player.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Select Player")
                .navigationBarTitleDisplayMode(.inline)
                .environment(\.defaultMinListRowHeight, isCompactLayout ? 56 : 72)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { goalKickerPickerPrompt = nil }
                    }
                }
            }
            .presentationDetents([.height(goalKickerPickerHeight), setupPickerExpandedDetent], selection: $goalKickerPickerDetent)
            .presentationDragIndicator(.visible)
            .onAppear {
                goalKickerPickerDetent = setupPickerExpandedDetent
            }
            .onChange(of: goalKickerPickerPrompt) { _, _ in
                goalKickerPickerDetent = setupPickerExpandedDetent
            }
        }
    }

    private var bestStep: some View {
        Form {
            Section(isTwoGameFlow ? "Game 1 · Best players (ranked 1–\(requiredBestPlayersCount))" : "Best players (ranked 1–\(requiredBestPlayersCount))") {
                if eligiblePlayers.isEmpty {
                    Text("Add players to this grade first.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(0..<requiredBestPlayersCount, id: \.self) { idx in
                        Button {
                            bestPlayerPickerGameNumber = 1
                            bestPlayerPickerPrompt = idx
                        } label: {
                            HStack(spacing: 12) {
                                rowLabel(bestLabel(for: idx))
                                Spacer()
                                rowValue(playerName(for: bestRanked[idx]))
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: isCompactLayout ? 14 : 18, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if hasDuplicateBestPlayers {
                        Text("Duplicate players selected. Each rank must be a different player.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            if isTwoGameFlow {
                Section("Game 2 · Best players (ranked 1–\(requiredBestPlayersCount))") {
                    ForEach(0..<requiredBestPlayersCount, id: \.self) { idx in
                        Button {
                            bestPlayerPickerGameNumber = 2
                            bestPlayerPickerPrompt = idx
                        } label: {
                            HStack(spacing: 12) {
                                rowLabel(bestLabel(for: idx))
                                Spacer()
                                rowValue(playerName(for: bestRankedGame2[idx]))
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: isCompactLayout ? 14 : 18, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if hasDuplicateBestPlayersGame2 {
                        Text("Duplicate players selected. Each rank must be a different player.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .font(wizardBodyFont)
        .environment(\.defaultMinListRowHeight, isCompactLayout ? 56 : 72)
        .dynamicTypeSize(.large ... .accessibility2)
        .scrollContentBackground(.hidden)
        .sheet(
            isPresented: Binding(
                get: { bestPlayerPickerPrompt != nil },
                set: { if !$0 { bestPlayerPickerPrompt = nil } }
            )
        ) {
            NavigationStack {
                List {
                    Button {
                        clearBestPlayer(at: bestPlayerPickerPrompt)
                        bestPlayerPickerPrompt = nil
                    } label: {
                        selectorListRow(
                            title: "Select…",
                            selected: selectedBestPlayerID(for: bestPlayerPickerPrompt) == nil
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(eligiblePlayers) { player in
                        Button {
                            if let rank = bestPlayerPickerPrompt {
                                setBestPlayer(player.id, at: rank, gameNumber: bestPlayerPickerGameNumber)
                            }
                            bestPlayerPickerPrompt = nil
                        } label: {
                            selectorListRow(
                                title: player.name,
                                selected: selectedBestPlayerID(for: bestPlayerPickerPrompt) == player.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(isTwoGameFlow ? "Select Best Player · Game \(bestPlayerPickerGameNumber)" : "Select Best Player")
                .navigationBarTitleDisplayMode(.inline)
                .environment(\.defaultMinListRowHeight, isCompactLayout ? 56 : 72)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { bestPlayerPickerPrompt = nil }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showAddPlayerFromBestPicker = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add Player")
                        .disabled(isPreviewMode)
                    }
                }
                .sheet(isPresented: $showAddPlayerFromBestPicker) {
                    PlayerAddView(
                        activeGrades: resolvedGrades.filter(\.isActive),
                        existingPlayers: players,
                        preselectedGradeID: gradeID,
                        onSave: createAndSavePlayerFromBestPicker(name:number:gradeIDs:)
                    )
                }
                .alert("Could not save player", isPresented: $showAddPlayerError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(addPlayerErrorMessage ?? "Please try again.")
                }
            }
            .presentationDetents([.height(bestPlayerPickerHeight), setupPickerExpandedDetent], selection: $bestPlayerPickerDetent)
            .presentationDragIndicator(.visible)
            .onAppear {
                bestPlayerPickerDetent = setupPickerExpandedDetent
            }
            .onChange(of: bestPlayerPickerPrompt) { _, _ in
                bestPlayerPickerDetent = setupPickerExpandedDetent
            }
        }
    }

    private var reviewStep: some View {
        Form {
            Section("Game Summary") {
                Text("Opponent: \(finalOpponent)")
                Text("Venue: \(finalVenue)")
                Text("Date: \(date.formatted(date: .abbreviated, time: .omitted))")

                if let gid = gradeID, let g = resolvedGrades.first(where: { $0.id == gid }) {
                    Text("Grade: \(g.name)")
                }

                Text("\(ourGoals).\(ourBehinds) (\(ourScore))  –  \(theirGoals).\(theirBehinds) (\(theirScore))")
                    .font(.headline)
            }

            if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Notes") { Text(notes) }
            }
        }
        .font(wizardBodyFont)
        .environment(\.defaultMinListRowHeight, isCompactLayout ? 56 : 72)
        .dynamicTypeSize(.large ... .accessibility2)
        .scrollContentBackground(.hidden)
    }

    private var votesStep: some View {
        Form {
            Section(isTwoGameFlow ? "Game 1 · Guest votes (ranked 1–\(requiredGuestBestPlayersCount))" : "Guest votes (ranked 1–\(requiredGuestBestPlayersCount))") {
                if eligiblePlayers.isEmpty {
                    Text("Add players to this grade first.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(0..<requiredGuestBestPlayersCount, id: \.self) { idx in
                        Button {
                            guestVotePickerGameNumber = 1
                            guestVotePickerPrompt = idx
                        } label: {
                            HStack(spacing: 12) {
                                rowLabel(bestLabel(for: idx))
                                Spacer()
                                rowValue(playerName(for: guestVotesRanked[idx]))
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: isCompactLayout ? 14 : 18, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if hasDuplicateGuestVotes {
                        Text("Duplicate players selected. Each rank must be a different player.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            if isTwoGameFlow {
                Section("Game 2 · Guest votes (ranked 1–\(requiredGuestBestPlayersCount))") {
                    ForEach(0..<requiredGuestBestPlayersCount, id: \.self) { idx in
                        Button {
                            guestVotePickerGameNumber = 2
                            guestVotePickerPrompt = idx
                        } label: {
                            HStack(spacing: 12) {
                                rowLabel(bestLabel(for: idx))
                                Spacer()
                                rowValue(playerName(for: guestVotesRankedGame2[idx]))
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: isCompactLayout ? 14 : 18, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if hasDuplicateGuestVotesGame2 {
                        Text("Duplicate players selected. Each rank must be a different player.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Optional scan attachment") {
                if guestBestFairestVotesScanPDF == nil {
                    Text("You can attach a guest votes scan after manual entry.")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Votes scan captured", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Button(guestBestFairestVotesScanPDF == nil ? "Scan votes" : "Rescan votes") {
                    openVotesScanner()
                }
            }
        }
        .font(wizardBodyFont)
        .environment(\.defaultMinListRowHeight, isCompactLayout ? 56 : 72)
        .dynamicTypeSize(.large ... .accessibility2)
        .scrollContentBackground(.hidden)
        .sheet(
            isPresented: Binding(
                get: { guestVotePickerPrompt != nil },
                set: { if !$0 { guestVotePickerPrompt = nil } }
            )
        ) {
            NavigationStack {
                List {
                    Button {
                        clearGuestVote(at: guestVotePickerPrompt)
                        guestVotePickerPrompt = nil
                    } label: {
                        selectorListRow(
                            title: "Select…",
                            selected: selectedGuestVotePlayerID(for: guestVotePickerPrompt) == nil
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(eligiblePlayers) { player in
                        Button {
                            if let rank = guestVotePickerPrompt {
                                setGuestVotePlayer(player.id, at: rank, gameNumber: guestVotePickerGameNumber)
                            }
                            guestVotePickerPrompt = nil
                        } label: {
                            selectorListRow(
                                title: player.name,
                                selected: selectedGuestVotePlayerID(for: guestVotePickerPrompt) == player.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(isTwoGameFlow ? "Select Guest Vote · Game \(guestVotePickerGameNumber)" : "Select Guest Vote")
                .navigationBarTitleDisplayMode(.inline)
                .environment(\.defaultMinListRowHeight, isCompactLayout ? 56 : 72)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { guestVotePickerPrompt = nil }
                    }
                }
            }
            .presentationDetents([.height(bestPlayerPickerHeight), setupPickerExpandedDetent], selection: $guestVotePickerDetent)
            .presentationDragIndicator(.visible)
            .onAppear {
                guestVotePickerDetent = setupPickerExpandedDetent
            }
            .onChange(of: guestVotePickerPrompt) { _, _ in
                guestVotePickerDetent = setupPickerExpandedDetent
            }
        }
    }

    private func openVotesScanner() {
#if canImport(VisionKit) && canImport(AVFoundation)
        guard VNDocumentCameraViewController.isSupported else {
            scannerErrorMessage = "This device does not support document scanning."
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showVotesScanner = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showVotesScanner = true
                    } else {
                        scannerErrorMessage = "Camera access is required to scan guest votes. Enable camera access in Settings."
                    }
                }
            }
        case .denied, .restricted:
            scannerErrorMessage = "Camera access is required to scan guest votes. Enable camera access in Settings."
        @unknown default:
            scannerErrorMessage = "Unable to access the camera right now. Please try again."
        }
#else
        scannerErrorMessage = "Document scanning is not available on this device."
#endif
    }

    // MARK: Logic helpers
    private var hasDuplicateBestPlayers: Bool {
        let ids = Array(bestRanked.prefix(requiredBestPlayersCount)).compactMap { $0 }
        return ids.count != Set(ids).count
    }

    private var hasDuplicateBestPlayersGame2: Bool {
        let ids = Array(bestRankedGame2.prefix(requiredBestPlayersCount)).compactMap { $0 }
        return ids.count != Set(ids).count
    }

    private var hasDuplicateGuestVotes: Bool {
        let ids = Array(guestVotesRanked.prefix(requiredGuestBestPlayersCount)).compactMap { $0 }
        return ids.count != Set(ids).count
    }

    private var hasDuplicateGuestVotesGame2: Bool {
        let ids = Array(guestVotesRankedGame2.prefix(requiredGuestBestPlayersCount)).compactMap { $0 }
        return ids.count != Set(ids).count
    }

    private func setBestPlayer(_ id: UUID, at index: Int, gameNumber: Int) {
        if gameNumber == 2 {
            bestRankedGame2[index] = id
            for i in 0..<requiredBestPlayersCount where i != index {
                if bestRankedGame2[i] == id { bestRankedGame2[i] = nil }
            }
        } else {
            bestRanked[index] = id
            for i in 0..<requiredBestPlayersCount where i != index {
                if bestRanked[i] == id { bestRanked[i] = nil }
            }
        }
    }

    private func setGuestVotePlayer(_ id: UUID, at index: Int, gameNumber: Int) {
        if gameNumber == 2 {
            guestVotesRankedGame2[index] = id
            for i in 0..<requiredGuestBestPlayersCount where i != index {
                if guestVotesRankedGame2[i] == id { guestVotesRankedGame2[i] = nil }
            }
        } else {
            guestVotesRanked[index] = id
            for i in 0..<requiredGuestBestPlayersCount where i != index {
                if guestVotesRanked[i] == id { guestVotesRanked[i] = nil }
            }
        }
    }

    private func createAndSavePlayerFromBestPicker(name: String, number: Int?, gradeIDs: [UUID]) {
        let trimmed = clean(name)
        guard !trimmed.isEmpty else { return }

        let normalized = normalizePlayerName(trimmed)
        guard !players.contains(where: { normalizePlayerName($0.name) == normalized }) else { return }

        let player = Player(name: trimmed, number: number, gradeIDs: gradeIDs)
        dataContext.insert(player)

        do {
            try dataContext.save()
        } catch {
            dataContext.delete(player)
            addPlayerErrorMessage = error.localizedDescription
            showAddPlayerError = true
        }
    }

    private func bestLabel(for idx: Int) -> String {
        let position = idx + 1
        switch position {
        case 1: return "Best"
        case 2: return "2nd"
        case 3: return "3rd"
        default:
            let suffix = (11...13).contains(position % 100) ? "th" : ([1: "st", 2: "nd", 3: "rd"][position % 10] ?? "th")
            return "\(position)\(suffix)"
        }
    }

    private func syncBestPlayersSelectionCount() {
        let targetCount = requiredBestPlayersCount
        if bestRanked.count < targetCount {
            bestRanked.append(contentsOf: Array(repeating: nil, count: targetCount - bestRanked.count))
        } else if bestRanked.count > targetCount {
            bestRanked = Array(bestRanked.prefix(targetCount))
        }
        if bestRankedGame2.count < targetCount {
            bestRankedGame2.append(contentsOf: Array(repeating: nil, count: targetCount - bestRankedGame2.count))
        } else if bestRankedGame2.count > targetCount {
            bestRankedGame2 = Array(bestRankedGame2.prefix(targetCount))
        }
    }

    private func syncGuestVotesSelectionCount() {
        let targetCount = requiredGuestBestPlayersCount
        if guestVotesRanked.count < targetCount {
            guestVotesRanked.append(contentsOf: Array(repeating: nil, count: targetCount - guestVotesRanked.count))
        } else if guestVotesRanked.count > targetCount {
            guestVotesRanked = Array(guestVotesRanked.prefix(targetCount))
        }
        if guestVotesRankedGame2.count < targetCount {
            guestVotesRankedGame2.append(contentsOf: Array(repeating: nil, count: targetCount - guestVotesRankedGame2.count))
        } else if guestVotesRankedGame2.count > targetCount {
            guestVotesRankedGame2 = Array(guestVotesRankedGame2.prefix(targetCount))
        }
    }

    private var totalGoalsKicked: Int { goalKickers.reduce(0) { $0 + $1.goals } }
    private var remainingGoalsToAllocate: Int { ourGoals - totalGoalsKicked }
    private var overAllocatedGoals: Bool { remainingGoalsToAllocate < 0 }

    private var hasDuplicateGoalKickers: Bool {
        let ids = goalKickers.compactMap { $0.playerID }
        return ids.count != Set(ids).count
    }

    private var allGoalKickersSelected: Bool {
        goalKickers.allSatisfy { $0.playerID != nil }
    }

    // MARK: Save
    @discardableResult
    private func saveGame(asDraft: Bool, dismissOnSuccess: Bool, enforceCompletionRequirements: Bool = true) -> Game? {
        guard let gid = gradeID else { return nil }
        guard !finalOpponent.isEmpty else { return nil }
        guard !finalVenue.isEmpty else { return nil }

        let bestPlayersCount = requiredBestPlayersCount
        let guestBestPlayersCount = requiredGuestBestPlayersCount
        let asksGoalKickers = selectedGrade?.asksGoalKickers ?? true
        let asksNotes = selectedGrade?.asksNotes ?? true

        let bestIDs = bestPlayersCount > 0 ? Array(bestRanked.prefix(bestPlayersCount)).compactMap { $0 } : []
        let game2BestIDs = bestPlayersCount > 0 ? Array(bestRankedGame2.prefix(bestPlayersCount)).compactMap { $0 } : []
        let guestVoteIDs = guestBestPlayersCount > 0 ? Array(guestVotesRanked.prefix(guestBestPlayersCount)).compactMap { $0 } : []
        let game2GuestVoteIDs = guestBestPlayersCount > 0 ? Array(guestVotesRankedGame2.prefix(guestBestPlayersCount)).compactMap { $0 } : []
        if enforceCompletionRequirements && bestPlayersCount > 0 {
            guard bestIDs.count == bestPlayersCount, Set(bestIDs).count == bestPlayersCount else { return nil }
            if isTwoGameFlow {
                guard game2BestIDs.count == bestPlayersCount, Set(game2BestIDs).count == bestPlayersCount else { return nil }
            }
        }
        if enforceCompletionRequirements && guestBestPlayersCount > 0 {
            guard guestVoteIDs.count == guestBestPlayersCount, Set(guestVoteIDs).count == guestBestPlayersCount else { return nil }
            if isTwoGameFlow {
                guard game2GuestVoteIDs.count == guestBestPlayersCount, Set(game2GuestVoteIDs).count == guestBestPlayersCount else { return nil }
            }
        }
        let guestVotes = guestVoteIDs.enumerated().map { GameGuestVoteEntry(rank: $0.offset + 1, playerID: $0.element) }
        let game2GuestVotes = game2GuestVoteIDs.enumerated().map { GameGuestVoteEntry(rank: $0.offset + 1, playerID: $0.element) }

        let cleanedNotes = asksNotes ? notes.trimmingCharacters(in: .whitespacesAndNewlines) : ""

        let modelGoalKickers: [GameGoalKickerEntry] = asksGoalKickers ? goalKickers.compactMap { entry in
            guard let pid = entry.playerID, entry.goals > 0 else { return nil }
            return GameGoalKickerEntry(playerID: pid, goals: entry.goals)
        } : []

        let game: Game
        if let existingGame = editingGame {
            existingGame.gradeID = gid
            existingGame.date = date
            existingGame.opponent = finalOpponent
            existingGame.venue = finalVenue
            existingGame.ourGoals = ourGoals
            existingGame.ourBehinds = ourBehinds
            existingGame.theirGoals = theirGoals
            existingGame.theirBehinds = theirBehinds
            existingGame.goalKickers = modelGoalKickers
            existingGame.bestPlayersRanked = bestIDs
            existingGame.guestVotesRanked = guestVotes
            existingGame.headCoachName = finalHeadCoach
            existingGame.assistantCoachName = finalAssCoach
            existingGame.teamManagerName = finalTeamManager
            existingGame.runnerName = finalRunner
            existingGame.goalUmpireName = finalGoalUmpire
            existingGame.fieldUmpireName = finalFieldUmpire
            existingGame.boundaryUmpire1Name = finalBoundary1
            existingGame.boundaryUmpire2Name = finalBoundary2
            existingGame.trainers = selectedTrainerNames
            existingGame.notes = cleanedNotes
            existingGame.guestBestFairestVotesScanPDF = guestBestFairestVotesScanPDF
            existingGame.isDraft = asDraft
            game = existingGame
        } else {
            let newGame = Game(
                id: UUID(),
                gradeID: gid,
                date: date,
                opponent: finalOpponent,
                venue: finalVenue,
                ourGoals: ourGoals,
                ourBehinds: ourBehinds,
                theirGoals: theirGoals,
                theirBehinds: theirBehinds,
                goalKickers: modelGoalKickers,
                bestPlayersRanked: bestIDs,
                guestVotesRanked: guestVotes,
                headCoachName: finalHeadCoach,
                assistantCoachName: finalAssCoach,
                teamManagerName: finalTeamManager,
                runnerName: finalRunner,
                goalUmpireName: finalGoalUmpire,
                fieldUmpireName: finalFieldUmpire,
                boundaryUmpire1Name: finalBoundary1,
                boundaryUmpire2Name: finalBoundary2,
                trainers: selectedTrainerNames,
                notes: cleanedNotes,
                guestBestFairestVotesScanPDF: guestBestFairestVotesScanPDF,
                isDraft: asDraft
            )
            dataContext.insert(newGame)
            game = newGame

            if isTwoGameFlow {
                let game2 = Game(
                    id: UUID(),
                    gradeID: gid,
                    date: date,
                    opponent: finalOpponent,
                    venue: finalVenue,
                    ourGoals: ourGoals,
                    ourBehinds: ourBehinds,
                    theirGoals: theirGoals,
                    theirBehinds: theirBehinds,
                    goalKickers: modelGoalKickers,
                    bestPlayersRanked: game2BestIDs,
                    guestVotesRanked: game2GuestVotes,
                    headCoachName: finalGame2HeadCoach,
                    assistantCoachName: finalGame2AssCoach,
                    teamManagerName: finalGame2TeamManager,
                    runnerName: finalGame2Runner,
                    goalUmpireName: finalGame2GoalUmpire,
                    fieldUmpireName: finalGame2FieldUmpire,
                    boundaryUmpire1Name: finalGame2Boundary1,
                    boundaryUmpire2Name: finalGame2Boundary2,
                    trainers: selectedGame2TrainerNames,
                    notes: cleanedNotes,
                    guestBestFairestVotesScanPDF: guestBestFairestVotesScanPDF,
                    isDraft: asDraft
                )
                dataContext.insert(game2)
            }
        }

        // Persist the last selected staff for this grade so new entries can default to them.
        persistCurrentStaffSelections(for: gid)

        do { try dataContext.save() }
        catch { print("❌ Failed to save game: \(error)"); return nil }

        editingGame = game

        if !asDraft {
            LiveDraftResumeStore.clear(for: game.id)
        }

        if dismissOnSuccess {
            dismiss()
        }

        return game
    }

    private func saveAndSendReport() {
        guard let savedGame = saveGame(asDraft: false, dismissOnSuccess: false),
              let gid = gradeID else { return }

        let gradeName = selectedGradeName
        let playerLookup: (UUID) -> String = { pid in
            players.first(where: { $0.id == pid })?.name ?? "Unknown"
        }

        do {
            reportAttachmentURL = try ExportService.makeGameSummaryPDF(
                game: savedGame,
                gradeName: gradeName,
                playerName: playerLookup
            )
        } catch {
            sendStatusMessage = "Game saved, but failed to build PDF report."
            return
        }

        let recipients = reportRecipients.filter { $0.gradeID == gid }
        let matchedContacts: [(contact: Contact, recipient: ReportRecipient)] = recipients.compactMap { recipient in
            guard let contact = contacts.first(where: { $0.id == recipient.contactID }) else { return nil }
            return (contact, recipient)
        }

        pendingEmailRecipients = matchedContacts
            .filter { $0.recipient.sendEmail }
            .map { $0.contact.email.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        pendingTextRecipients = matchedContacts
            .filter { $0.recipient.sendText }
            .map { $0.contact.mobile.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if pendingEmailRecipients.isEmpty && pendingTextRecipients.isEmpty {
            sendStatusMessage = "Game saved. No report recipients are configured for this grade."
            return
        }

        if !pendingEmailRecipients.isEmpty && MFMailComposeViewController.canSendMail() {
            showMailComposer = true
            return
        }

        beginTextSendIfNeeded()
    }

    private func beginTextSendIfNeeded() {
        if !pendingTextRecipients.isEmpty && MFMessageComposeViewController.canSendText() {
            showMessageComposer = true
            return
        }

        if !pendingEmailRecipients.isEmpty && !MFMailComposeViewController.canSendMail() {
            sendStatusMessage = "Game saved. Mail is not configured on this device, so email recipients were skipped."
            return
        }

        if !pendingTextRecipients.isEmpty && !MFMessageComposeViewController.canSendText() {
            sendStatusMessage = "Game saved. Text messaging is not available on this device, so text recipients were skipped."
            return
        }

        dismiss()
    }

    private struct ScoreEvent {
        var x: Double
        var margin: Int
    }

    private struct LiveGameSessionState {
        var periodMinutes: Int = 20
        var secondsRemaining: Int = 20 * 60
        var pointScorers: [UUID: Int] = [:]
        var rushedPoints: Int = 0
        var periodSnapshots: [PeriodSnapshot] = []
        var scoreEvents: [ScoreEvent] = []
        var isInitialized = false
        var shouldAutoResumeTimer = false

        mutating func configureIfNeeded(initialPeriodMinutes: Int) {
            guard !isInitialized else { return }
            let bounded = min(max(initialPeriodMinutes, 1), 30)
            periodMinutes = bounded
            secondsRemaining = bounded * 60
            pointScorers = [:]
            rushedPoints = 0
            periodSnapshots = []
            scoreEvents = []
            isInitialized = true
        }
    }

    // MARK: - AFL-ish card container
    private struct LiveGameView: View {
        @Binding var date: Date
        @Binding var ourGoals: Int
        @Binding var ourBehinds: Int
        @Binding var theirGoals: Int
        @Binding var theirBehinds: Int
        @Binding var goalKickers: [WizardGoalKickerEntry]
        @Binding var bestRanked: [UUID?]
        @Binding var liveSession: LiveGameSessionState

        let initialPeriodMinutes: Int
        let requiredBestPlayersCount: Int
        let ourTeamName: String
        let oppTeamName: String
        let ourStyle: ClubStyle.Style
        let oppStyle: ClubStyle.Style
        let eligiblePlayers: [Player]
        let playerName: (UUID) -> String
        let onSaveAndContinue: () -> Void
        let onBackToHome: () -> Void
        let onCancelAndDiscard: () -> Void
        let onCollapse: () -> Void

        @State private var timerRunning = false
        @State private var timerTask: Task<Void, Never>?
        @State private var showPlayerPicker = false
        @State private var showPointPicker = false
        @State private var showTimerAdjuster = false
        @State private var showGoalKickerEditor = false
        @State private var showEndOfPeriodPrompt = false
        @State private var showManualSavePrompt = false
        @State private var showCancelConfirmation = false

        init(
            date: Binding<Date>,
            ourGoals: Binding<Int>,
            ourBehinds: Binding<Int>,
            theirGoals: Binding<Int>,
            theirBehinds: Binding<Int>,
            goalKickers: Binding<[WizardGoalKickerEntry]>,
            bestRanked: Binding<[UUID?]>,
            liveSession: Binding<LiveGameSessionState>,
            initialPeriodMinutes: Int,
            requiredBestPlayersCount: Int,
            ourTeamName: String,
            oppTeamName: String,
            ourStyle: ClubStyle.Style,
            oppStyle: ClubStyle.Style,
            eligiblePlayers: [Player],
            playerName: @escaping (UUID) -> String,
            onSaveAndContinue: @escaping () -> Void,
            onBackToHome: @escaping () -> Void,
            onCancelAndDiscard: @escaping () -> Void,
            onCollapse: @escaping () -> Void
        ) {
            _date = date
            _ourGoals = ourGoals
            _ourBehinds = ourBehinds
            _theirGoals = theirGoals
            _theirBehinds = theirBehinds
            _goalKickers = goalKickers
            _bestRanked = bestRanked
            _liveSession = liveSession

            let boundedPeriodMinutes = min(max(initialPeriodMinutes, 1), 30)
            self.initialPeriodMinutes = boundedPeriodMinutes

            self.requiredBestPlayersCount = requiredBestPlayersCount
            self.ourTeamName = ourTeamName
            self.oppTeamName = oppTeamName
            self.ourStyle = ourStyle
            self.oppStyle = oppStyle
            self.eligiblePlayers = eligiblePlayers
            self.playerName = playerName
            self.onSaveAndContinue = onSaveAndContinue
            self.onBackToHome = onBackToHome
            self.onCancelAndDiscard = onCancelAndDiscard
            self.onCollapse = onCollapse
        }

        private var ourScore: Int { ourGoals * 6 + ourBehinds }
        private var theirScore: Int { theirGoals * 6 + theirBehinds }
        private var isDangerTime: Bool { liveSession.secondsRemaining <= 120 }
        private var canSaveAndContinue: Bool { liveSession.periodSnapshots.count == 4 }
        private var nextPeriodLabel: String? {
            switch liveSession.periodSnapshots.count {
            case 0: return "Quarter Time"
            case 1: return "Half Time"
            case 2: return "3 Quarter Time"
            case 3: return "Full Time"
            default: return nil
            }
        }

        private var scorerTally: [(id: UUID, goals: Int, points: Int)] {
            var goalCounts: [UUID: Int] = [:]
            for entry in goalKickers {
                guard let id = entry.playerID, entry.goals > 0 else { continue }
                goalCounts[id, default: 0] += entry.goals
            }

            let ids = Set(goalCounts.keys).union(liveSession.pointScorers.keys)
            return ids
                .map { id in
                    (id: id, goals: goalCounts[id, default: 0], points: liveSession.pointScorers[id, default: 0])
                }
                .filter { $0.goals > 0 || $0.points > 0 }
                .sorted { lhs, rhs in
                    let lhsTotal = lhs.goals * 6 + lhs.points
                    let rhsTotal = rhs.goals * 6 + rhs.points
                    if lhsTotal != rhsTotal { return lhsTotal > rhsTotal }
                    return playerName(lhs.id) < playerName(rhs.id)
                }
        }

        private struct GoalKickerEditorState: Equatable {
            struct Row: Identifiable, Equatable {
                let id: UUID
                var goals: Int
                var points: Int
            }

            var rows: [Row]
            var rushedPoints: Int
        }

        private func makeGoalKickerEditorState() -> GoalKickerEditorState {
            GoalKickerEditorState(
                rows: scorerTally.map { scorer in
                    GoalKickerEditorState.Row(id: scorer.id, goals: scorer.goals, points: scorer.points)
                },
                rushedPoints: liveSession.rushedPoints
            )
        }

        private func applyGoalKickerEditorState(_ state: GoalKickerEditorState) {
            let normalizedRows = state.rows
                .map { row in
                    GoalKickerEditorState.Row(
                        id: row.id,
                        goals: max(0, row.goals),
                        points: max(0, row.points)
                    )
                }
                .filter { $0.goals > 0 || $0.points > 0 }

            goalKickers = normalizedRows
                .filter { $0.goals > 0 }
                .map { WizardGoalKickerEntry(playerID: $0.id, goals: $0.goals) }

            liveSession.pointScorers = Dictionary(uniqueKeysWithValues: normalizedRows.compactMap { row in
                guard row.points > 0 else { return nil }
                return (row.id, row.points)
            })

            liveSession.rushedPoints = max(0, state.rushedPoints)
            ourGoals = goalKickers.reduce(0) { $0 + $1.goals }
            ourBehinds = liveSession.pointScorers.values.reduce(0, +) + liveSession.rushedPoints
        }

        var body: some View {
            VStack(spacing: 0) {
                pullDownHandle
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                HStack {
                    Spacer()
                    Button("Save Game") {
                        pauseTimer()
                        onSaveAndContinue()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(canSaveAndContinue ? .blue : .gray)
                    .disabled(!canSaveAndContinue)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

                GeometryReader { proxy in
                        let compact = proxy.size.width < 980
                        let cardSpacing: CGFloat = compact ? 14 : 18
                        let teamCardWidth = max(300, proxy.size.width * 0.35)
                        let timerWidth = max(280, proxy.size.width * 0.22)
                        let sharedCardHeight = max(368, proxy.size.height * 0.46)
                        let centerCardTopOffset: CGFloat = 16
                        let sideCardTopOffset: CGFloat = 8
                        let centerTimerHeight = max(300, sharedCardHeight + sideCardTopOffset - centerCardTopOffset)

                        ScrollView {
                            VStack(spacing: cardSpacing) {
                                if compact {
                                    teamScoreCard(
                                        title: ourTeamName,
                                        style: ourStyle,
                                        goals: $ourGoals,
                                        behinds: $ourBehinds,
                                        score: ourScore,
                                        goalAction: { showPlayerPicker = true },
                                        pointAction: { showPointPicker = true },
                                        minHeight: sharedCardHeight
                                    )
                                    goalKickerSummaryCard(width: proxy.size.width)
                                    timerCard(minHeight: max(280, sharedCardHeight * 0.66), width: proxy.size.width)
                                    teamScoreCard(
                                        title: oppTeamName,
                                        style: oppStyle,
                                        goals: $theirGoals,
                                        behinds: $theirBehinds,
                                        score: theirScore,
                                        goalAction: { recordOpponentGoal() },
                                        pointAction: { recordOpponentPoint() },
                                        minHeight: sharedCardHeight
                                    )
                                    scoreWormCard(width: proxy.size.width)
                                } else {
                                    VStack(spacing: 0) {
                                        HStack(alignment: .top, spacing: cardSpacing) {
                                            VStack(spacing: cardSpacing) {
                                                teamScoreCard(
                                                    title: ourTeamName,
                                                    style: ourStyle,
                                                    goals: $ourGoals,
                                                    behinds: $ourBehinds,
                                                    score: ourScore,
                                                    goalAction: { showPlayerPicker = true },
                                                    pointAction: { showPointPicker = true },
                                                    minHeight: sharedCardHeight
                                                )
                                                goalKickerSummaryCard(width: teamCardWidth)
                                            }
                                            .frame(width: teamCardWidth, alignment: .topLeading)
                                            .padding(.top, sideCardTopOffset)

                                            VStack(spacing: cardSpacing) {
                                                timerCard(minHeight: centerTimerHeight, width: timerWidth)
                                            }
                                            .frame(width: timerWidth, alignment: .top)
                                            .padding(.top, centerCardTopOffset)

                                            VStack(spacing: cardSpacing) {
                                                teamScoreCard(
                                                    title: oppTeamName,
                                                    style: oppStyle,
                                                    goals: $theirGoals,
                                                    behinds: $theirBehinds,
                                                    score: theirScore,
                                                    goalAction: { recordOpponentGoal() },
                                                    pointAction: { recordOpponentPoint() },
                                                    minHeight: sharedCardHeight
                                                )
                                                scoreWormCard(width: teamCardWidth)
                                            }
                                            .frame(width: teamCardWidth, alignment: .topTrailing)
                                            .padding(.top, sideCardTopOffset)
                                        }
                                    }
                                }
                            }
                        }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 22)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        pauseTimer()
                        showCancelConfirmation = true
                    }
                }
            }
            .alert("If you proceed, all current data for this game will be lost", isPresented: $showCancelConfirmation) {
                Button("Continue", role: .destructive) {
                    onCancelAndDiscard()
                }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: liveSession.periodMinutes) { _, newValue in
                if !timerRunning {
                    liveSession.secondsRemaining = max(1, newValue) * 60
                }
            }
            .onChange(of: ourScore) { oldValue, newValue in
                trackScoreChange(oldScore: oldValue, newScore: newValue, isOurTeam: true)
            }
            .onChange(of: theirScore) { oldValue, newValue in
                trackScoreChange(oldScore: oldValue, newScore: newValue, isOurTeam: false)
            }
            .onAppear {
                applyConfiguredInitialPeriod()
                if liveSession.shouldAutoResumeTimer {
                    liveSession.shouldAutoResumeTimer = false
                    startTimer()
                }
            }
            .onChange(of: initialPeriodMinutes) { _, _ in
                applyConfiguredInitialPeriod()
            }
            .sheet(isPresented: $showPlayerPicker) {
                NavigationStack {
                    List(eligiblePlayers) { player in
                        Button(player.name) {
                            recordGoal(for: player.id)
                            showPlayerPicker = false
                        }
                    }
                    .navigationTitle("Who kicked the goal?")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showPlayerPicker = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $showPointPicker) {
                NavigationStack {
                    List {
                        Section {
                            Button("Rushed") {
                                recordPoint(for: nil)
                                showPointPicker = false
                            }
                            .font(.headline)
                        }

                        Section("Players") {
                            ForEach(eligiblePlayers) { player in
                                Button(player.name) {
                                    recordPoint(for: player.id)
                                    showPointPicker = false
                                }
                            }
                        }
                    }
                    .navigationTitle("Who scored the point?")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showPointPicker = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $showGoalKickerEditor) {
                GoalKickerEditorSheet(
                    eligiblePlayers: eligiblePlayers,
                    playerName: playerName,
                    initialState: makeGoalKickerEditorState()
                ) { updatedState in
                    applyGoalKickerEditorState(updatedState)
                }
            }
            .onDisappear {
                pauseTimer()
            }
            .alert("Period complete", isPresented: $showEndOfPeriodPrompt) {
                Button("No, keep editing", role: .cancel) {
                    showManualSavePrompt = false
                }
                Button("Yes, save score") {
                    saveCurrentPeriodSnapshot()
                }
            } message: {
                Text("Are the current scores correct for \(nextPeriodLabel ?? "this period")?")
            }
            .alert("Save updated score?", isPresented: $showManualSavePrompt) {
                Button("Cancel", role: .cancel) {}
                Button("Save score") {
                    saveCurrentPeriodSnapshot()
                }
            } message: {
                Text("Save \(nextPeriodLabel ?? "period") using the updated live scores?")
            }
        }

        private var pullDownHandle: some View {
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 52, height: 6)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            guard value.translation.height > 70 else { return }
                            pauseTimer()
                            onCollapse()
                        }
                )
                .accessibilityLabel("Swipe down to hide live game view")
        }

        private func timerCard(minHeight: CGFloat, width: CGFloat) -> some View {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Timer")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(liveSession.periodMinutes) min")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                    Button {
                        showTimerAdjuster = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Adjust timer")
                    .popover(isPresented: $showTimerAdjuster, attachmentAnchor: .point(.bottomTrailing), arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Period length")
                                .font(.headline)
                            Picker("Minutes", selection: $liveSession.periodMinutes) {
                                ForEach(1...30, id: \.self) { minute in
                                    Text("\(minute) min").tag(minute)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 200, height: 140)
                        }
                        .padding()
                    }
                }

                Text(timeText(liveSession.secondsRemaining))
                    .font(.system(size: 78, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isDangerTime ? .red : .primary)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 10) {
                    Button {
                        startTimer()
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .accessibilityLabel("Start")
                    .buttonStyle(.borderedProminent)
                    .disabled(timerRunning || liveSession.secondsRemaining == 0)

                    Button {
                        pauseTimer()
                    } label: {
                        Image(systemName: "pause.fill")
                    }
                    .accessibilityLabel("Pause")
                    .buttonStyle(.bordered)
                    .disabled(!timerRunning)

                    Button {
                        resetTimer()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .accessibilityLabel("Reset")
                    .buttonStyle(.bordered)
                }
                .font(.title3.weight(.semibold))
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .center)

                Divider()

                periodScoresSection
            }
            .padding(18)
            .frame(maxWidth: width, minHeight: minHeight, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }

        private var periodScoresSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Period scores")
                    .font(.headline)

                if liveSession.periodSnapshots.isEmpty {
                    Text("No period scores saved yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(liveSession.periodSnapshots) { snapshot in
                        HStack {
                            Text(snapshot.label)
                            Spacer()
                            Text("\(snapshot.ourGoals).\(snapshot.ourBehinds) (\(snapshot.ourScore))")
                                .monospacedDigit()
                            Text("–")
                                .foregroundStyle(.secondary)
                            Text("\(snapshot.theirGoals).\(snapshot.theirBehinds) (\(snapshot.theirScore))")
                                .monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }

                if nextPeriodLabel != nil {
                    Button("Save \(nextPeriodLabel ?? "period") score") {
                        showManualSavePrompt = true
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }

        private func goalKickerSummaryCard(width: CGFloat) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ScorePill("Goal Kickers", style: ourStyle)
                    Spacer()
                    Button {
                        showGoalKickerEditor = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit goal kickers")
                }
                if scorerTally.isEmpty, liveSession.rushedPoints == 0 {
                    Text("No scorers yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scorerTally, id: \.id) { scorer in
                        HStack {
                            Text(playerName(scorer.id))
                            Spacer()
                            Text(playerContribution(goals: scorer.goals, points: scorer.points))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    if liveSession.rushedPoints > 0 {
                        HStack {
                            Text("Rushed")
                            Spacer()
                            Text(playerContribution(goals: 0, points: liveSession.rushedPoints))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: width, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }

        private struct StepAdjuster: View {
            let value: Int
            let onDecrement: () -> Void
            let onIncrement: () -> Void

            var body: some View {
                HStack(spacing: 10) {
                    Button(action: onDecrement) {
                        Image(systemName: "minus")
                            .font(.headline.weight(.bold))
                            .frame(width: 42, height: 42)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(value == 0)

                    Text("\(value)")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .frame(minWidth: 34)

                    Button(action: onIncrement) {
                        Image(systemName: "plus")
                            .font(.headline.weight(.bold))
                            .frame(width: 42, height: 42)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        private struct GoalKickerEditorSheet: View {
            @Environment(\.dismiss) private var dismiss

            let eligiblePlayers: [Player]
            let playerName: (UUID) -> String
            let initialState: GoalKickerEditorState
            let onSave: (GoalKickerEditorState) -> Void

            @State private var draftState: GoalKickerEditorState
            @State private var selectedPlayerID: UUID?

            init(
                eligiblePlayers: [Player],
                playerName: @escaping (UUID) -> String,
                initialState: GoalKickerEditorState,
                onSave: @escaping (GoalKickerEditorState) -> Void
            ) {
                self.eligiblePlayers = eligiblePlayers
                self.playerName = playerName
                self.initialState = initialState
                self.onSave = onSave
                _draftState = State(initialValue: initialState)
            }

            private var hasChanges: Bool { draftState != initialState }

            private var addablePlayers: [Player] {
                let existing = Set(draftState.rows.map(\.id))
                return eligiblePlayers.filter { !existing.contains($0.id) }
            }

            var body: some View {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(spacing: 12) {
                                Picker("Add goal kicker", selection: $selectedPlayerID) {
                                    Text("Select player").tag(nil as UUID?)
                                    ForEach(addablePlayers) { player in
                                        Text(player.name).tag(Optional(player.id))
                                    }
                                }
                                .pickerStyle(.menu)

                                Button("Add") {
                                    guard let playerID = selectedPlayerID else { return }
                                    draftState.rows.append(.init(id: playerID, goals: 0, points: 0))
                                    selectedPlayerID = nil
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(selectedPlayerID == nil)
                            }

                            if draftState.rows.isEmpty {
                                Text("No goal kickers added yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 14) {
                                    ForEach(Array(draftState.rows.enumerated()), id: \.element.id) { index, row in
                                        VStack(alignment: .leading, spacing: 10) {
                                            HStack {
                                                Text(playerName(row.id))
                                                    .font(.headline)
                                                Spacer()
                                                Button {
                                                    draftState.rows.remove(at: index)
                                                } label: {
                                                    Image(systemName: "trash")
                                                }
                                                .buttonStyle(.plain)
                                                .foregroundStyle(.red)
                                                .accessibilityLabel("Remove \(playerName(row.id))")
                                            }

                                            HStack {
                                                Text("Goals")
                                                Spacer()
                                                StepAdjuster(
                                                    value: row.goals,
                                                    onDecrement: { draftState.rows[index].goals = max(0, row.goals - 1) },
                                                    onIncrement: { draftState.rows[index].goals = row.goals + 1 }
                                                )
                                            }

                                            HStack {
                                                Text("Points")
                                                Spacer()
                                                StepAdjuster(
                                                    value: row.points,
                                                    onDecrement: { draftState.rows[index].points = max(0, row.points - 1) },
                                                    onIncrement: { draftState.rows[index].points = row.points + 1 }
                                                )
                                            }
                                        }
                                        .padding(16)
                                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Rushed points")
                                    .font(.headline)
                                HStack {
                                    Text("Rushed")
                                    Spacer()
                                    StepAdjuster(
                                        value: draftState.rushedPoints,
                                        onDecrement: { draftState.rushedPoints = max(0, draftState.rushedPoints - 1) },
                                        onIncrement: { draftState.rushedPoints += 1 }
                                    )
                                }
                                .padding(16)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        .padding(20)
                    }
                    .navigationTitle("Edit Goal Kickers")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { dismiss() }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Save") {
                                onSave(draftState)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(hasChanges ? .blue : .gray)
                            .disabled(!hasChanges)
                        }
                    }
                }
                .presentationSizing(.page)
            }
        }

        private var currentTimelineX: Double {
            let completedPeriods = min(liveSession.periodSnapshots.count, 4)
            let base = Double(completedPeriods)
            let duration = max(1, liveSession.periodMinutes * 60)
            let progress = liveSession.periodMinutes > 0 ? 1 - (Double(liveSession.secondsRemaining) / Double(duration)) : 0
            return min(4, base + max(0, min(1, progress)))
        }

        private var scoreWormPoints: [CGPoint] {
            var points: [CGPoint] = [.init(x: 0, y: 0)]
            var lastX: Double = 0
            var lastMargin: Int = 0

            for event in liveSession.scoreEvents {
                let clampedX = max(0, min(4, event.x))
                if clampedX > lastX {
                    points.append(.init(x: clampedX, y: CGFloat(lastMargin)))
                }
                points.append(.init(x: clampedX, y: CGFloat(event.margin)))
                lastX = clampedX
                lastMargin = event.margin
            }

            let nowX = max(lastX, currentTimelineX)
            points.append(.init(x: nowX, y: CGFloat(ourScore - theirScore)))
            return points
        }

        private func scoreWormCard(width: CGFloat) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ScorePill("Score Worm", style: ourStyle)
                    Spacer()
                    Text("Margin: \(ourScore - theirScore > 0 ? "+" : "")\(ourScore - theirScore)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geo in
                    let points = scoreWormPoints
                    let maxAbs = max(6, points.map { abs($0.y) }.max() ?? 0)
                    let chartHeight = geo.size.height
                    let chartWidth = geo.size.width
                    let zeroY = chartHeight / 2

                    ZStack {
                        ForEach(0...4, id: \.self) { quarter in
                            let x = (CGFloat(quarter) / 4) * chartWidth
                            Path { path in
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: chartHeight))
                            }
                            .stroke(.secondary.opacity(0.2), style: .init(lineWidth: quarter == 0 || quarter == 4 ? 1.2 : 0.8))
                        }

                        Path { path in
                            path.move(to: CGPoint(x: 0, y: zeroY))
                            path.addLine(to: CGPoint(x: chartWidth, y: zeroY))
                        }
                        .stroke(.secondary.opacity(0.35), style: .init(lineWidth: 1, dash: [6, 6]))

                        Path { path in
                            guard let first = points.first else { return }
                            let startX = (first.x / 4) * chartWidth
                            let startY = zeroY - (first.y / maxAbs) * (chartHeight * 0.45)
                            path.move(to: CGPoint(x: startX, y: startY))
                            for point in points.dropFirst() {
                                let x = (point.x / 4) * chartWidth
                                let y = zeroY - (point.y / maxAbs) * (chartHeight * 0.45)
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        .stroke(Color.white, style: .init(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    }
                }
                .frame(height: 170)

                HStack {
                    Text("Q1")
                    Spacer()
                    Text("Q2")
                    Spacer()
                    Text("Q3")
                    Spacer()
                    Text("Q4")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: width, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }

        private func playerContribution(goals: Int, points: Int) -> String {
            "\(goals).\(points)"
        }

        private func teamScoreCard(
            title: String,
            style: ClubStyle.Style,
            goals: Binding<Int>,
            behinds: Binding<Int>,
            score: Int,
            goalAction: @escaping () -> Void,
            pointAction: @escaping () -> Void,
            minHeight: CGFloat
        ) -> some View {
            VStack(alignment: .leading, spacing: 18) {
                scoreColumn(title: title, style: style, goals: goals, behinds: behinds, score: score)
                teamActionSection(style: style, goalAction: goalAction, pointAction: pointAction)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }

        @ViewBuilder
        private func scoreColumn(title: String, style: ClubStyle.Style, goals: Binding<Int>, behinds: Binding<Int>, score: Int) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                ScorePill(title, style: style, fixedWidth: 170)

                Text("\(goals.wrappedValue).\(behinds.wrappedValue)")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("\(score)")
                    .font(.system(size: 88, weight: .black, design: .rounded))
                    .monospacedDigit()

                HStack(spacing: 12) {
                    Stepper("Goals: \(goals.wrappedValue)", value: goals, in: 0...200)
                    Stepper("Points: \(behinds.wrappedValue)", value: behinds, in: 0...200)
                }
                .labelsHidden()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func teamActionSection(
            style: ClubStyle.Style,
            goalAction: @escaping () -> Void,
            pointAction: @escaping () -> Void
        ) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    prominentActionButton(title: "Goal", background: style.background, textColor: style.text, action: goalAction)
                    prominentActionButton(title: "Point", background: style.background, textColor: style.text, action: pointAction)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func prominentActionButton(title: String, background: Color, textColor: Color, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(background.opacity(0.95))
            )
            .foregroundStyle(textColor)
        }

        private func trackScoreChange(oldScore: Int, newScore: Int, isOurTeam: Bool) {
            guard newScore != oldScore else { return }
            let oldMargin = isOurTeam ? oldScore - theirScore : ourScore - oldScore
            let delta = abs(newScore - oldScore)
            var runningMargin = oldMargin
            for _ in 0..<delta {
                runningMargin += isOurTeam ? 1 : -1
                liveSession.scoreEvents.append(ScoreEvent(x: currentTimelineX, margin: runningMargin))
            }
        }

        private func recordGoal(for playerID: UUID) {
            ourGoals += 1
            if let index = goalKickers.firstIndex(where: { $0.playerID == playerID }) {
                goalKickers[index].goals += 1
            } else {
                goalKickers.append(WizardGoalKickerEntry(playerID: playerID, goals: 1))
            }
        }

        private func recordPoint(for playerID: UUID?) {
            ourBehinds += 1
            guard let playerID else {
                liveSession.rushedPoints += 1
                return
            }
            liveSession.pointScorers[playerID, default: 0] += 1
        }

        private func recordOpponentGoal() {
            theirGoals += 1
        }

        private func recordOpponentPoint() {
            theirBehinds += 1
        }

        private func startTimer() {
            guard !timerRunning else { return }
            timerRunning = true
            timerTask?.cancel()
            timerTask = Task {
                while !Task.isCancelled && timerRunning && liveSession.secondsRemaining > 0 {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard timerRunning else { return }
                        liveSession.secondsRemaining = max(0, liveSession.secondsRemaining - 1)
                        if liveSession.secondsRemaining == 0 {
                            timerRunning = false
                            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            showEndOfPeriodPrompt = true
                        }
                    }
                }
            }
        }

        private func pauseTimer() {
            timerRunning = false
            timerTask?.cancel()
            timerTask = nil
        }

        private func resetTimer() {
            pauseTimer()
            liveSession.secondsRemaining = liveSession.periodMinutes * 60
        }

        private func timeText(_ seconds: Int) -> String {
            let mins = seconds / 60
            let secs = seconds % 60
            return String(format: "%02d:%02d", mins, secs)
        }

        private func saveCurrentPeriodSnapshot() {
            guard let label = nextPeriodLabel else { return }
            liveSession.periodSnapshots.append(
                PeriodSnapshot(
                    label: label,
                    ourGoals: ourGoals,
                    ourBehinds: ourBehinds,
                    theirGoals: theirGoals,
                    theirBehinds: theirBehinds
                )
            )
        }

        private func applyConfiguredInitialPeriod() {
            guard !timerRunning, !liveSession.isInitialized, liveSession.periodSnapshots.isEmpty else { return }
            liveSession.periodMinutes = initialPeriodMinutes
            liveSession.secondsRemaining = initialPeriodMinutes * 60
        }
    }

    private struct PeriodSnapshot: Identifiable {
        let id = UUID()
        let label: String
        let ourGoals: Int
        let ourBehinds: Int
        let theirGoals: Int
        let theirBehinds: Int

        var ourScore: Int { ourGoals * 6 + ourBehinds }
        var theirScore: Int { theirGoals * 6 + theirBehinds }
    }

    private struct MailComposeView: UIViewControllerRepresentable {
        let recipients: [String]
        let subject: String
        let body: String
        let attachmentURL: URL
        let onFinish: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(onFinish: onFinish)
        }

        func makeUIViewController(context: Context) -> MFMailComposeViewController {
            let controller = MFMailComposeViewController()
            controller.mailComposeDelegate = context.coordinator
            controller.setToRecipients(recipients)
            controller.setSubject(subject)
            controller.setMessageBody(body, isHTML: false)
            if let data = try? Data(contentsOf: attachmentURL) {
                controller.addAttachmentData(data, mimeType: "application/pdf", fileName: attachmentURL.lastPathComponent)
            }
            return controller
        }

        func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

        final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
            let onFinish: () -> Void

            init(onFinish: @escaping () -> Void) {
                self.onFinish = onFinish
            }

            func mailComposeController(
                _ controller: MFMailComposeViewController,
                didFinishWith result: MFMailComposeResult,
                error: Error?
            ) {
                controller.dismiss(animated: true)
                onFinish()
            }
        }
    }

    private struct MessageComposeView: UIViewControllerRepresentable {
        let recipients: [String]
        let body: String
        let attachmentURL: URL
        let onFinish: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(onFinish: onFinish)
        }

        func makeUIViewController(context: Context) -> MFMessageComposeViewController {
            let controller = MFMessageComposeViewController()
            controller.messageComposeDelegate = context.coordinator
            controller.recipients = recipients
            controller.body = body
            controller.addAttachmentURL(attachmentURL, withAlternateFilename: attachmentURL.lastPathComponent)
            return controller
        }

        func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

        final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
            let onFinish: () -> Void

            init(onFinish: @escaping () -> Void) {
                self.onFinish = onFinish
            }

            func messageComposeViewController(
                _ controller: MFMessageComposeViewController,
                didFinishWith result: MessageComposeResult
            ) {
                controller.dismiss(animated: true)
                onFinish()
            }
        }
    }

    private struct StaffCard<Content: View>: View {
        let title: String
        let systemImage: String
        @ViewBuilder var content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                    Text(title.uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .tracking(0.9)
                    Spacer()
                }
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
                )
            }
        }
    }
}
