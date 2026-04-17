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

struct NewGameWizardView: View {
    let initialGradeID: UUID?

    init(initialGradeID: UUID? = nil) {
        self.initialGradeID = initialGradeID
    }

    // MARK: - Club Colours
    private let clubNavy = Color(red: 0.05, green: 0.15, blue: 0.35)
    private let clubYellow = Color(red: 1.0, green: 0.82, blue: 0.0)

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss   // ✅ allow Cancel / dismiss sheet
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Query private var grades: [Grade]
    @Query(sort: \Player.name) private var players: [Player]
    @Query(sort: [SortDescriptor(\Contact.name)]) private var contacts: [Contact]
    @Query private var reportRecipients: [ReportRecipient]

    // ✅ stored defaults per grade + role
    @Query private var staffDefaults: [StaffDefault]

    // ✅ UPDATED: first screen is Setup (grade + date + opponent + venue)
    enum Step: Int { case setup, staff, medical, score, goals, best, votes, review }
    private enum EntryMode {
        case postGame
        case live
    }
    @State private var step: Step = .setup
    @State private var entryMode: EntryMode?
    @State private var showEntryModePrompt = false
    @State private var showLiveGameView = false
    @State private var liveGameSessionSaved = false
    @State private var editingGame: Game?

    // MARK: Setup
    @State private var gradeID: UUID?
    @State private var date = Date()

    @State private var clubConfiguration: ClubConfiguration = ClubConfigurationStore.load()

    // MARK: Selections (dropdowns)
    @State private var opponentName: String = ""
    @State private var venueName: String = ""
    @State private var setupPickerPrompt: SetupPickerPrompt?
    @State private var setupPickerDetent: PresentationDetent = .large

    // MARK: Staff
    @State private var headCoachName: String = ""
    @State private var assCoachName: String = ""
    @State private var teamManagerName: String = ""
    @State private var runnerName: String = ""

    @State private var goalUmpireName: String = ""

    // Boundary umpires are chosen from a configured grade's players, or entered manually.
    @State private var boundaryUmpire1ID: UUID?
    @State private var boundaryUmpire2ID: UUID?
    @State private var boundaryUmpire1CustomName: String = ""
    @State private var boundaryUmpire2CustomName: String = ""
    @State private var boundaryUmpirePickerPrompt: BoundaryUmpireSlot?
    @State private var boundaryUmpirePickerDetent: PresentationDetent = .large
    @State private var boundaryUmpireNamePrompt: BoundaryUmpireSlot?
    @State private var boundaryUmpireNameDraft: String = ""

    @State private var trainer1Name: String = ""
    @State private var trainer2Name: String = ""
    @State private var trainer3Name: String = ""
    @State private var trainer4Name: String = ""

    @State private var notes = ""

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
    @State private var bestPlayerPickerPrompt: Int?
    @State private var bestPlayerPickerDetent: PresentationDetent = .large
    @State private var guestBestFairestVotesScanPDF: Data?
    @State private var showVotesScanner = false
    @State private var scannerErrorMessage: String?
    @State private var hasAppliedInitialGrade = false
    @State private var reportAttachmentURL: URL?
    @State private var pendingEmailRecipients: [String] = []
    @State private var pendingTextRecipients: [String] = []
    @State private var showMailComposer = false
    @State private var showMessageComposer = false
    @State private var sendStatusMessage: String?

    // MARK: Helpers
    private func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var finalOpponent: String { clean(opponentName) }
    private var finalVenue: String { clean(venueName) }

    private var finalHeadCoach: String { clean(headCoachName) }
    private var finalAssCoach: String { clean(assCoachName) }
    private var finalTeamManager: String { clean(teamManagerName) }
    private var finalRunner: String { clean(runnerName) }

    private var finalGoalUmpire: String { clean(goalUmpireName) }

    private func playerName(for id: UUID?) -> String {
        guard let id else { return "" }
        return players.first(where: { $0.id == id })?.name ?? ""
    }
    private var finalBoundary1: String {
        let custom = clean(boundaryUmpire1CustomName)
        return custom.isEmpty ? playerName(for: boundaryUmpire1ID) : custom
    }
    private var finalBoundary2: String {
        let custom = clean(boundaryUmpire2CustomName)
        return custom.isEmpty ? playerName(for: boundaryUmpire2ID) : custom
    }
    private var selectedTrainerNames: [String] {
        [trainer1Name, trainer2Name, trainer3Name, trainer4Name]
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

    // MARK: Setup picker sizing
    private var setupPickerOptionsCount: Int {
        switch setupPickerPrompt {
        case .opponent:
            return opponentNames.count + 1 // "Select…" option
        case .venue:
            return venuesForSelection.count + 1 // "Select…" option
        case .none:
            return 0
        }
    }

    private var setupPickerRowHeight: CGFloat { isCompactLayout ? 56 : 72 }

    private var setupPickerHeaderAndPaddingHeight: CGFloat { isCompactLayout ? 112 : 132 }

    private var setupPickerHeight: CGFloat {
        PickerSheetPresentation.preferredHeight(
            optionCount: setupPickerOptionsCount,
            rowHeight: setupPickerRowHeight,
            chromeHeight: setupPickerHeaderAndPaddingHeight,
            minVisibleRows: 2,
            isCompactLayout: isCompactLayout
        )
    }

    private var boundaryPickerRowHeight: CGFloat { isCompactLayout ? 56 : 72 }

    private var boundaryPickerHeaderAndPaddingHeight: CGFloat { isCompactLayout ? 128 : 148 }

    private var boundaryPickerOptionsCount: Int {
        let availablePlayers: [Player]

        switch boundaryUmpirePickerPrompt {
        case .one:
            availablePlayers = boundaryUmpirePlayers.filter { $0.id != boundaryUmpire2ID }
        case .two:
            availablePlayers = boundaryUmpirePlayers.filter { $0.id != boundaryUmpire1ID }
        case .none:
            availablePlayers = []
        }

        // "Select…" + available players + "Enter Different Name"
        return availablePlayers.count + 2
    }

    private var boundaryPickerHeight: CGFloat {
        PickerSheetPresentation.preferredHeight(
            optionCount: boundaryPickerOptionsCount,
            rowHeight: boundaryPickerRowHeight,
            chromeHeight: boundaryPickerHeaderAndPaddingHeight,
            minVisibleRows: 3,
            isCompactLayout: isCompactLayout
        )
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
        assignDefault(for: .trainer1, role: .trainer, gradeID: gradeID) { trainer1Name = $0 }
        assignDefault(for: .trainer2, role: .trainer, gradeID: gradeID) { trainer2Name = $0 }
        assignDefault(for: .trainer3, role: .trainer, gradeID: gradeID) { trainer3Name = $0 }
        assignDefault(for: .trainer4, role: .trainer, gradeID: gradeID) { trainer4Name = $0 }
    }

    private func persistCurrentStaffSelections(for gradeID: UUID?) {
        saveLastSelection(headCoachName, for: .headCoach, gradeID: gradeID)
        saveLastSelection(assCoachName, for: .assistantCoach, gradeID: gradeID)
        saveLastSelection(teamManagerName, for: .teamManager, gradeID: gradeID)
        saveLastSelection(runnerName, for: .runner, gradeID: gradeID)
        saveLastSelection(goalUmpireName, for: .goalUmpire, gradeID: gradeID)
        saveLastSelection(trainer1Name, for: .trainer1, gradeID: gradeID)
        saveLastSelection(trainer2Name, for: .trainer2, gradeID: gradeID)
        saveLastSelection(trainer3Name, for: .trainer3, gradeID: gradeID)
        saveLastSelection(trainer4Name, for: .trainer4, gradeID: gradeID)
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
        guard let gid = gradeID else { return [] }
        return players.filter { $0.isActive && $0.gradeIDs.contains(gid) }
    }

    private var boundaryUmpireSourceGradeIDs: [UUID] {
        guard let gid = gradeID else { return [] }
        let configured = SettingsBackupStore.loadBoundaryUmpireGradeMappings()[gid] ?? [gid]
        return configured.isEmpty ? [gid] : configured
    }

    private var boundaryUmpirePlayers: [Player] {
        let sourceGradeIDs = Set(boundaryUmpireSourceGradeIDs)
        guard !sourceGradeIDs.isEmpty else { return [] }
        return players.filter { player in
            player.isActive && !sourceGradeIDs.isDisjoint(with: Set(player.gradeIDs))
        }
    }

    private enum BoundaryUmpireSlot {
        case one
        case two
    }

    private enum SetupPickerPrompt {
        case opponent
        case venue
    }

    private var isCompactLayout: Bool { horizontalSizeClass == .compact }

    private var wizardPrimaryTitleFont: Font {
        .system(size: isCompactLayout ? 40 : 52, weight: .bold)
    }

    private var wizardSecondaryTitleFont: Font {
        .system(size: isCompactLayout ? 22 : 30, weight: .semibold)
    }

    private var wizardBodyFont: Font {
        .system(size: isCompactLayout ? 20 : 24, weight: .regular)
    }

    private var selectedGrade: Grade? {
        guard let gid = gradeID else { return nil }
        return resolvedGrades.first(where: { $0.id == gid })
    }

    private var requiredBestPlayersCount: Int {
        min(max(selectedGrade?.bestPlayersCount ?? 6, 0), 10)
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
            grade.asksBoundaryUmpire1 ||
            grade.asksBoundaryUmpire2 ||
            grade.asksTrainers ||
            grade.asksNotes {
            steps.append(.medical)
        }
        if entryMode != .live {
            steps.append(.score)
            if grade.asksGoalKickers { steps.append(.goals) }
        }
        if grade.bestPlayersCount > 0 { steps.append(.best) }
        if grade.asksGuestBestFairestVotesScan { steps.append(.votes) }
        steps.append(.review)
        return steps
    }

    private var entryModeTriggerStep: Step {
        if activeSteps.contains(.medical) { return .medical }
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
    private func formSelectorRow(
        title: String,
        value: String,
        placeholder: String = "Select…",
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(wizardBodyFont)
                    .foregroundStyle(disabled ? .secondary : .primary)
                Spacer()
                Text(value.isEmpty ? placeholder : value)
                    .font(wizardBodyFont)
                    .foregroundStyle(value.isEmpty || disabled ? .secondary : .primary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: isCompactLayout ? 14 : 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, isCompactLayout ? 6 : 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.65 : 1)
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
        return bestRanked[rankIndex]
    }

    private func clearBestPlayer(at rankIndex: Int?) {
        guard let rankIndex, bestRanked.indices.contains(rankIndex) else { return }
        bestRanked[rankIndex] = nil
    }

    // MARK: Validation
    private var canProceed: Bool {
        switch step {

        case .setup:
            return gradeID != nil &&
                   !finalOpponent.isEmpty &&
                   !finalVenue.isEmpty

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

            return coachingOK

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
            return ids.count == requiredBestPlayersCount && Set(ids).count == requiredBestPlayersCount

        case .votes:
            return guestBestFairestVotesScanPDF != nil

        case .review:
            return true
        }
    }

    private var canProceedOnCurrentStep: Bool {
        step == .medical ? true : canProceed
    }

    // MARK: Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                ProgressView(
                    value: Double(activeSteps.firstIndex(of: step) ?? 0),
                    total: Double(max(activeSteps.count - 1, 1))
                )
                .padding(.horizontal)
                .padding(.top, 14)
                .padding(.bottom, 10)

                ZStack {
                    switch step {
                    case .setup: setupStep
                    case .staff: staffStep
                    case .medical: medicalStepView
                    case .score: scoreStep
                    case .goals: goalsStep
                    case .best: bestStep
                    case .votes: votesStep
                    case .review: reviewStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack {
                    // ✅ hide Back entirely on the first step
                    if step != .setup {
                        Button("Back") { back() }
                    }

                    Spacer()

                    if step == .review {
                        Button("Save Draft") {
                            _ = saveGame(asDraft: true, dismissOnSuccess: true)
                        }
                        .disabled(!canProceedOnCurrentStep)
                        .buttonStyle(.bordered)

                        Button("Save and Send") {
                            saveAndSendReport()
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
            .navigationTitle(step == .setup ? "" : "New Game")
            .navigationBarTitleDisplayMode(step == .setup ? .inline : .large)

            // ✅ Cancel in top-left ONLY on first step
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if step == .setup {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        // ✅ Seed staff + defaults once
        .onAppear {
            StaffSeeder.seedIfNeeded(modelContext: modelContext, grades: grades)
            clubConfiguration = ClubConfigurationStore.load()
            if !opponentName.isEmpty && !opponentNames.contains(opponentName) {
                opponentName = ""
                venueName = ""
            }
            applyDefaults(for: gradeID)
        }
        // ✅ When user changes grade, auto-fill defaults from last selected values (or seeded defaults)
        .onChange(of: gradeID) { _, newGrade in
            applyDefaults(for: newGrade)
            syncBestPlayersSelectionCount()
            step = .setup
            entryMode = nil
            liveGameSessionSaved = false
            editingGame = nil
        }
        .onAppear {
            guard !hasAppliedInitialGrade else { return }
            hasAppliedInitialGrade = true
            if let initialGradeID {
                gradeID = initialGradeID
                applyDefaults(for: initialGradeID)
                syncBestPlayersSelectionCount()
            }
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
        .confirmationDialog("Live entry or Post-Game entry?", isPresented: $showEntryModePrompt, titleVisibility: .visible) {
            Button("Post-Game entry") {
                entryMode = .postGame
                liveGameSessionSaved = false
                proceedAfterEntryModeSelection()
            }
            Button("Live entry") {
                entryMode = .live
                liveGameSessionSaved = false
                showLiveGameView = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showLiveGameView) {
            LiveGameView(
                date: $date,
                ourGoals: $ourGoals,
                ourBehinds: $ourBehinds,
                theirGoals: $theirGoals,
                theirBehinds: $theirBehinds,
                goalKickers: $goalKickers,
                eligiblePlayers: eligiblePlayers,
                playerName: { playerID in
                    players.first(where: { $0.id == playerID })?.name ?? "Unknown"
                },
                onSaveAndContinue: {
                    let saved = saveGame(asDraft: true, dismissOnSuccess: false, enforceCompletionRequirements: false)
                    if saved != nil {
                        liveGameSessionSaved = true
                        showLiveGameView = false
                        proceedAfterLiveSave()
                    }
                },
                onCancel: {
                    showLiveGameView = false
                    if entryMode == .live && !liveGameSessionSaved {
                        entryMode = nil
                    }
                }
            )
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

    private func next() {
        if step == entryModeTriggerStep && entryMode == nil {
            showEntryModePrompt = true
            return
        }

        if step == entryModeTriggerStep && entryMode == .live && !liveGameSessionSaved {
            showLiveGameView = true
            return
        }

        guard let currentIndex = activeSteps.firstIndex(of: step) else { return }
        let nextIndex = currentIndex + 1
        guard activeSteps.indices.contains(nextIndex) else { return }
        step = activeSteps[nextIndex]
    }

    private func back() {
        guard let currentIndex = activeSteps.firstIndex(of: step), currentIndex > 0 else { return }
        step = activeSteps[currentIndex - 1]
    }

    private func proceedAfterEntryModeSelection() {
        guard step == entryModeTriggerStep else { return }
        if entryMode == .live {
            showLiveGameView = true
            return
        }
        guard let currentIndex = activeSteps.firstIndex(of: step) else { return }
        let nextIndex = currentIndex + 1
        guard activeSteps.indices.contains(nextIndex) else { return }
        step = activeSteps[nextIndex]
    }

    private func proceedAfterLiveSave() {
        if activeSteps.contains(.best) {
            step = .best
        } else if activeSteps.contains(.votes) {
            step = .votes
        } else {
            step = .review
        }
    }

    // MARK: Steps

    // ✅ NEW: Setup step (Grade + Date + Opponent + Venue)
    // Uses the SAME Form styling you had on the Grade screen.
    private var setupStep: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("New Game")
                    .font(wizardPrimaryTitleFont)
                Spacer()
                Text(selectedGradeName)
                    .font(wizardSecondaryTitleFont)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, isCompactLayout ? 20 : 28)
            .padding(.top, isCompactLayout ? 8 : 14)
            .padding(.bottom, isCompactLayout ? 12 : 16)

            Form {
                if let _ = gradeID, eligiblePlayers.isEmpty {
                    Section {
                        Text("No active players assigned to this grade yet. Add players first.")
                            .foregroundStyle(.secondary)
                    }
                } else if gradeID != nil {
                    Section {
                        Text("\(eligiblePlayers.count) eligible players")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Game details") {
                    DatePicker("Date & time", selection: $date, displayedComponents: [.date, .hourAndMinute])

                    formSelectorRow(title: "Opponent", value: opponentName) {
                        setupPickerPrompt = .opponent
                    }

                    formSelectorRow(
                        title: "Venue",
                        value: venueName,
                        disabled: venuesForSelection.isEmpty
                    ) {
                        setupPickerPrompt = .venue
                    }
                }
            }
            .font(wizardBodyFont)
            .environment(\.defaultMinListRowHeight, isCompactLayout ? 56 : 72)
        }
        .dynamicTypeSize(.large ... .accessibility2)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .sheet(
            isPresented: Binding(
                get: { setupPickerPrompt != nil },
                set: { if !$0 { setupPickerPrompt = nil } }
            )
        ) {
            NavigationStack {
                List {
                    switch setupPickerPrompt {
                    case .opponent:
                        Button {
                            opponentName = ""
                            venueName = ""
                            setupPickerPrompt = nil
                        } label: {
                            selectorListRow(title: "Select…", selected: opponentName.isEmpty)
                        }
                        .buttonStyle(.plain)

                        ForEach(opponentNames, id: \.self) { opposition in
                            Button {
                                opponentName = opposition
                                if !venuesForSelection.contains(venueName) {
                                    venueName = ""
                                }
                                setupPickerPrompt = nil
                            } label: {
                                selectorListRow(title: opposition, selected: opponentName == opposition)
                            }
                            .buttonStyle(.plain)
                        }

                    case .venue:
                        Button {
                            venueName = ""
                            setupPickerPrompt = nil
                        } label: {
                            selectorListRow(title: "Select…", selected: venueName.isEmpty)
                        }
                        .buttonStyle(.plain)

                        ForEach(venuesForSelection, id: \.self) { venue in
                            Button {
                                venueName = venue
                                setupPickerPrompt = nil
                            } label: {
                                selectorListRow(title: venue, selected: venueName == venue)
                            }
                            .buttonStyle(.plain)
                        }

                    case .none:
                        EmptyView()
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(setupPickerPrompt == .venue ? "Select Venue" : "Select Opponent")
                .navigationBarTitleDisplayMode(.inline)
                .environment(\.defaultMinListRowHeight, isCompactLayout ? 56 : 72)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { setupPickerPrompt = nil }
                    }
                }
            }
            .presentationDetents([.height(setupPickerHeight), setupPickerExpandedDetent], selection: $setupPickerDetent)
            .presentationDragIndicator(.visible)
            .onAppear {
                setupPickerDetent = setupPickerExpandedDetent
            }
            .onChange(of: setupPickerPrompt) { _, _ in
                setupPickerDetent = setupPickerExpandedDetent
            }
        }
    }

    // Staff step (coaching only)
    private var staffStep: some View {
        ScrollView {
            VStack(spacing: 14) {

                StaffCard(title: "Coaching", systemImage: "person.2.fill") {
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
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var medicalStep: some View {
        ScrollView {
            VStack(spacing: 14) {
                StaffCard(title: "Officials", systemImage: "flag.fill") {
                    if selectedGrade?.asksGoalUmpire ?? true {
                        StaffPickerField(title: "Goal Umpire", role: .goalUmpire, gradeID: gradeID, value: $goalUmpireName)
                    }

                    let asksBoundaryUmpire1 = selectedGrade?.asksBoundaryUmpire1 ?? true
                    let asksBoundaryUmpire2 = selectedGrade?.asksBoundaryUmpire2 ?? true

                    if asksBoundaryUmpire1 {
                        HStack(spacing: 12) {
                            rowLabel("Boundary Umpire 1")
                            Spacer()
                            Button {
                                boundaryUmpirePickerPrompt = .one
                            } label: {
                                HStack(spacing: 6) {
                                    rowValue(finalBoundary1)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: isCompactLayout ? 14 : 18, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }

                    if asksBoundaryUmpire2 {
                        HStack(spacing: 12) {
                            rowLabel("Boundary Umpire 2")
                            Spacer()
                            Button {
                                boundaryUmpirePickerPrompt = .two
                            } label: {
                                HStack(spacing: 6) {
                                    rowValue(finalBoundary2)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: isCompactLayout ? 14 : 18, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }

                    if asksBoundaryUmpire1, asksBoundaryUmpire2, boundaryUmpire1ID != nil, boundaryUmpire1ID == boundaryUmpire2ID {
                        Text("Boundary Umpire 1 and 2 can’t be the same.")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.top, 6)
                    }
                }

                StaffCard(title: "Medical & Trainers", systemImage: "cross.case.fill") {
                    if selectedGrade?.asksTrainers ?? true {
                        StaffPickerField(title: "Trainer 1", role: .trainer, gradeID: gradeID, value: $trainer1Name)
                        StaffPickerField(title: "Trainer 2", role: .trainer, gradeID: gradeID, value: $trainer2Name)
                        StaffPickerField(title: "Trainer 3", role: .trainer, gradeID: gradeID, value: $trainer3Name)
                        StaffPickerField(title: "Trainer 4", role: .trainer, gradeID: gradeID, value: $trainer4Name)
                    } else {
                        Text("Trainer fields are disabled for this grade.")
                            .foregroundStyle(.secondary)
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
        .sheet(
            isPresented: Binding(
                get: { boundaryUmpirePickerPrompt != nil },
                set: { if !$0 { boundaryUmpirePickerPrompt = nil } }
            )
        ) {
            NavigationStack {
                List {
                    Button {
                        if boundaryUmpirePickerPrompt == .one {
                            boundaryUmpire1ID = nil
                            boundaryUmpire1CustomName = ""
                        } else if boundaryUmpirePickerPrompt == .two {
                            boundaryUmpire2ID = nil
                            boundaryUmpire2CustomName = ""
                        }
                        boundaryUmpirePickerPrompt = nil
                    } label: {
                        selectorListRow(
                            title: "Select…",
                            selected: boundaryUmpirePickerPrompt == .one ? finalBoundary1.isEmpty : finalBoundary2.isEmpty
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(boundaryUmpirePlayers) { person in
                        if (boundaryUmpirePickerPrompt == .one && person.id != boundaryUmpire2ID) ||
                            (boundaryUmpirePickerPrompt == .two && person.id != boundaryUmpire1ID) {
                            Button {
                                if boundaryUmpirePickerPrompt == .one {
                                    boundaryUmpire1ID = person.id
                                    boundaryUmpire1CustomName = ""
                                } else if boundaryUmpirePickerPrompt == .two {
                                    boundaryUmpire2ID = person.id
                                    boundaryUmpire2CustomName = ""
                                }
                                boundaryUmpirePickerPrompt = nil
                            } label: {
                                selectorListRow(
                                    title: person.name,
                                    selected: boundaryUmpirePickerPrompt == .one ? boundaryUmpire1ID == person.id : boundaryUmpire2ID == person.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Section {
                        Button {
                            if boundaryUmpirePickerPrompt == .one {
                                boundaryUmpireNameDraft = boundaryUmpire1CustomName
                                boundaryUmpireNamePrompt = .one
                            } else if boundaryUmpirePickerPrompt == .two {
                                boundaryUmpireNameDraft = boundaryUmpire2CustomName
                                boundaryUmpireNamePrompt = .two
                            }
                            boundaryUmpirePickerPrompt = nil
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: isCompactLayout ? 22 : 26, weight: .semibold))
                                    .foregroundStyle(.tint)
                                Text("Enter Different Name")
                                    .font(selectorListFont)
                                    .foregroundStyle(.primary)
                            }
                            .padding(.vertical, isCompactLayout ? 8 : 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(boundaryUmpirePickerPrompt == .two ? "Boundary Umpire 2" : "Boundary Umpire 1")
                .navigationBarTitleDisplayMode(.inline)
                .environment(\.defaultMinListRowHeight, isCompactLayout ? 56 : 72)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { boundaryUmpirePickerPrompt = nil }
                    }
                }
            }
            .presentationDetents([.height(boundaryPickerHeight), setupPickerExpandedDetent], selection: $boundaryUmpirePickerDetent)
            .presentationDragIndicator(.visible)
            .onAppear {
                boundaryUmpirePickerDetent = setupPickerExpandedDetent
            }
            .onChange(of: boundaryUmpirePickerPrompt) { _, _ in
                boundaryUmpirePickerDetent = setupPickerExpandedDetent
            }
        }
        .alert(
            boundaryUmpireNamePrompt == .one ? "Boundary Umpire 1" : "Boundary Umpire 2",
            isPresented: Binding(
                get: { boundaryUmpireNamePrompt != nil },
                set: { if !$0 { boundaryUmpireNamePrompt = nil } }
            )
        ) {
            TextField("Name", text: $boundaryUmpireNameDraft)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {
                boundaryUmpireNamePrompt = nil
            }
            Button("Save") {
                let enteredName = clean(boundaryUmpireNameDraft)
                if boundaryUmpireNamePrompt == .one {
                    boundaryUmpire1CustomName = enteredName
                    boundaryUmpire1ID = nil
                } else if boundaryUmpireNamePrompt == .two {
                    boundaryUmpire2CustomName = enteredName
                    boundaryUmpire2ID = nil
                }
                boundaryUmpireNamePrompt = nil
            }
        } message: {
            Text("Enter a name if no listed player was the boundary umpire.")
        }
    }

    private var medicalStepView: some View {
        ScrollView {
            VStack(spacing: 14) {
                StaffCard(title: "Medical & Trainers", systemImage: "cross.case.fill") {
                    if selectedGrade?.asksTrainers ?? true {
                        StaffPickerField(title: "Trainer 1", role: .trainer, gradeID: gradeID, value: $trainer1Name)
                        StaffPickerField(title: "Trainer 2", role: .trainer, gradeID: gradeID, value: $trainer2Name)
                        StaffPickerField(title: "Trainer 3", role: .trainer, gradeID: gradeID, value: $trainer3Name)
                        StaffPickerField(title: "Trainer 4", role: .trainer, gradeID: gradeID, value: $trainer4Name)
                    } else {
                        Text("Trainer fields are disabled for this grade.")
                            .foregroundStyle(.secondary)
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

    private var scoreStep: some View {
        GeometryReader { proxy in
            ScrollView {
                let cardSpacing: CGFloat = isCompactLayout ? 14 : 18
                let timerHeight = max(190, proxy.size.height * 0.25)
                let timerWidth = max(280, proxy.size.width * 0.33)
                let scoreboardHeight = max(300, proxy.size.height * 0.5)

                VStack(spacing: cardSpacing) {
                    if isCompactLayout {
                        scoreboardCard(minHeight: scoreboardHeight)
                        timerCard(width: proxy.size.width, minHeight: timerHeight)
                    } else {
                        HStack(alignment: .top, spacing: cardSpacing) {
                            scoreboardCard(minHeight: scoreboardHeight)
                                .frame(maxWidth: .infinity, alignment: .topLeading)

                            timerCard(width: timerWidth, minHeight: timerHeight)
                                .frame(width: timerWidth, alignment: .topTrailing)
                        }
                    }
                }
                .padding(.horizontal, isCompactLayout ? 14 : 24)
                .padding(.top, isCompactLayout ? 14 : 20)
                .padding(.bottom, 26)
            }
        }
        .onChange(of: periodMinutes) { _, newValue in
            periodMinutes = max(1, newValue)
            if !isTimerRunning {
                remainingSeconds = periodMinutes * 60
            }
        }
        .onReceive(timerTick.autoconnect()) { _ in
            guard isTimerRunning else { return }
            if remainingSeconds > 0 {
                remainingSeconds -= 1
            } else {
                isTimerRunning = false
            }
        }
    }

    private var timerTick: Timer.TimerPublisher {
        Timer.publish(every: 1, on: .main, in: .common)
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
                    Text("Minutes")
                        .foregroundStyle(.secondary)
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
            Section("Best players (ranked 1–\(requiredBestPlayersCount))") {
                if eligiblePlayers.isEmpty {
                    Text("Add players to this grade first.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(0..<requiredBestPlayersCount, id: \.self) { idx in
                        Button {
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
                                setBestPlayer(player.id, at: rank)
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
                .navigationTitle("Select Best Player")
                .navigationBarTitleDisplayMode(.inline)
                .environment(\.defaultMinListRowHeight, isCompactLayout ? 56 : 72)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { bestPlayerPickerPrompt = nil }
                    }
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
            Section("Guest Best & Fairest votes") {
                if guestBestFairestVotesScanPDF == nil {
                    Text("Scan the paper votes before saving.")
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
        .sheet(isPresented: $showVotesScanner) {
            VotesScannerSheet { data in
                guestBestFairestVotesScanPDF = data
                showVotesScanner = false
            } onCancel: {
                showVotesScanner = false
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
            }
        } message: {
            Text(scannerErrorMessage ?? "")
        }
        .scrollContentBackground(.hidden)
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

    private func setBestPlayer(_ id: UUID, at index: Int) {
        bestRanked[index] = id
        for i in 0..<requiredBestPlayersCount where i != index {
            if bestRanked[i] == id { bestRanked[i] = nil }
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
        let asksGoalKickers = selectedGrade?.asksGoalKickers ?? true
        let asksNotes = selectedGrade?.asksNotes ?? true
        let asksVotesScan = selectedGrade?.asksGuestBestFairestVotesScan ?? false

        let bestIDs = bestPlayersCount > 0 ? Array(bestRanked.prefix(bestPlayersCount)).compactMap { $0 } : []
        if enforceCompletionRequirements && bestPlayersCount > 0 {
            guard bestIDs.count == bestPlayersCount, Set(bestIDs).count == bestPlayersCount else { return nil }
        }
        if enforceCompletionRequirements && asksVotesScan {
            guard guestBestFairestVotesScanPDF != nil else { return nil }
        }

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
            existingGame.headCoachName = finalHeadCoach
            existingGame.assistantCoachName = finalAssCoach
            existingGame.teamManagerName = finalTeamManager
            existingGame.runnerName = finalRunner
            existingGame.goalUmpireName = finalGoalUmpire
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
                headCoachName: finalHeadCoach,
                assistantCoachName: finalAssCoach,
                teamManagerName: finalTeamManager,
                runnerName: finalRunner,
                goalUmpireName: finalGoalUmpire,
                boundaryUmpire1Name: finalBoundary1,
                boundaryUmpire2Name: finalBoundary2,
                trainers: selectedTrainerNames,
                notes: cleanedNotes,
                guestBestFairestVotesScanPDF: guestBestFairestVotesScanPDF,
                isDraft: asDraft
            )
            modelContext.insert(newGame)
            game = newGame
        }

        // Persist the last selected staff for this grade so new entries can default to them.
        persistCurrentStaffSelections(for: gid)

        do { try modelContext.save() }
        catch { print("❌ Failed to save game: \(error)"); return nil }

        editingGame = game

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

    // MARK: - AFL-ish card container
    private struct LiveGameView: View {
        @Binding var date: Date
        @Binding var ourGoals: Int
        @Binding var ourBehinds: Int
        @Binding var theirGoals: Int
        @Binding var theirBehinds: Int
        @Binding var goalKickers: [WizardGoalKickerEntry]

        let eligiblePlayers: [Player]
        let playerName: (UUID) -> String
        let onSaveAndContinue: () -> Void
        let onCancel: () -> Void

        @State private var periodMinutes: Int = 20
        @State private var secondsRemaining: Int = 20 * 60
        @State private var timerRunning = false
        @State private var timerTask: Task<Void, Never>?
        @State private var showPlayerPicker = false

        private var ourScore: Int { ourGoals * 6 + ourBehinds }
        private var theirScore: Int { theirGoals * 6 + theirBehinds }
        private var isDangerTime: Bool { secondsRemaining <= 120 }

        private var scorerTally: [(id: UUID, goals: Int)] {
            goalKickers
                .compactMap { entry -> (UUID, Int)? in
                    guard let id = entry.playerID, entry.goals > 0 else { return nil }
                    return (id, entry.goals)
                }
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                    return playerName(lhs.0) < playerName(rhs.0)
                }
        }

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 10) {
                            Text("Live Game View")
                                .font(.title.bold())
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 12) {
                            Text(timeText(secondsRemaining))
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(isDangerTime ? .red : .primary)

                            Stepper("Period minutes: \(periodMinutes)", value: $periodMinutes, in: 10...30)
                                .onChange(of: periodMinutes) { _, newValue in
                                    if !timerRunning {
                                        secondsRemaining = newValue * 60
                                    }
                                }

                            HStack {
                                Button("Start") { startTimer() }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(timerRunning || secondsRemaining == 0)
                                Button("Pause") { pauseTimer() }
                                    .buttonStyle(.bordered)
                                    .disabled(!timerRunning)
                                Button("Reset") { resetTimer() }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                        VStack(spacing: 12) {
                            Text("Scoreboard")
                                .font(.headline)
                            HStack {
                                scoreColumn(title: "Us", goals: $ourGoals, behinds: $ourBehinds, score: ourScore)
                                scoreColumn(title: "Opp", goals: $theirGoals, behinds: $theirBehinds, score: theirScore)
                            }

                            HStack {
                                Button("Our Goal") { showPlayerPicker = true }
                                    .buttonStyle(.borderedProminent)
                                Button("Our Point") { ourBehinds += 1 }
                                    .buttonStyle(.bordered)
                                Button("Opp Goal") { theirGoals += 1 }
                                    .buttonStyle(.bordered)
                                Button("Opp Point") { theirBehinds += 1 }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Goal scorers")
                                .font(.headline)
                            if scorerTally.isEmpty {
                                Text("No goal scorers yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(scorerTally, id: \.id) { scorer in
                                    HStack {
                                        Text(playerName(scorer.id))
                                        Spacer()
                                        Text("\(scorer.goals)")
                                            .font(.headline)
                                            .monospacedDigit()
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                        Button("Save and Continue") {
                            pauseTimer()
                            onSaveAndContinue()
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.headline)
                        .padding(.top, 8)
                    }
                    .padding()
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") {
                            pauseTimer()
                            onCancel()
                        }
                    }
                }
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
            .onDisappear {
                pauseTimer()
            }
        }

        @ViewBuilder
        private func scoreColumn(title: String, goals: Binding<Int>, behinds: Binding<Int>, score: Int) -> some View {
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                Stepper("Goals \(goals.wrappedValue)", value: goals, in: 0...200)
                Stepper("Points \(behinds.wrappedValue)", value: behinds, in: 0...200)
                Text("Total \(score)")
                    .font(.title3.bold())
            }
            .frame(maxWidth: .infinity)
        }

        private func recordGoal(for playerID: UUID) {
            ourGoals += 1
            if let index = goalKickers.firstIndex(where: { $0.playerID == playerID }) {
                goalKickers[index].goals += 1
            } else {
                goalKickers.append(WizardGoalKickerEntry(playerID: playerID, goals: 1))
            }
        }

        private func startTimer() {
            guard !timerRunning else { return }
            timerRunning = true
            timerTask?.cancel()
            timerTask = Task {
                while !Task.isCancelled && timerRunning && secondsRemaining > 0 {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard timerRunning else { return }
                        secondsRemaining = max(0, secondsRemaining - 1)
                        if secondsRemaining == 0 {
                            timerRunning = false
                            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
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
            secondsRemaining = periodMinutes * 60
        }

        private func timeText(_ seconds: Int) -> String {
            let mins = seconds / 60
            let secs = seconds % 60
            return String(format: "%02d:%02d", mins, secs)
        }
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
