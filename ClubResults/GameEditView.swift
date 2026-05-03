import SwiftUI
import SwiftData

private struct GameEditDraft: Equatable {
    var gradeID: UUID
    var date: Date
    var opponent: String
    var venue: String

    var ourGoals: Int
    var ourBehinds: Int
    var theirGoals: Int
    var theirBehinds: Int

    var goalKickers: [GameGoalKickerEntry]
    var bestPlayersRanked: [UUID]
    var guestVotesRanked: [GameGuestVoteEntry]

    var headCoachName: String
    var assistantCoachName: String
    var teamManagerName: String
    var runnerName: String
    var goalUmpireName: String
    var timeKeeperName: String
    var fieldUmpireName: String
    var boundaryUmpire1Name: String
    var boundaryUmpire2Name: String
    var waterBoy1Name: String
    var waterBoy2Name: String
    var waterBoy3Name: String
    var waterBoy4Name: String
    var trainer1Name: String
    var trainer2Name: String
    var trainer3Name: String
    var trainer4Name: String

    var notes: String

    init(game: Game) {
        gradeID = game.gradeID
        date = game.date
        opponent = game.opponent
        venue = game.venue
        ourGoals = game.ourGoals
        ourBehinds = game.ourBehinds
        theirGoals = game.theirGoals
        theirBehinds = game.theirBehinds
        goalKickers = game.goalKickers
        bestPlayersRanked = game.bestPlayersRanked
        guestVotesRanked = game.guestVotesRanked.sorted(by: { $0.rank < $1.rank })
        headCoachName = game.headCoachName
        assistantCoachName = game.assistantCoachName
        teamManagerName = game.teamManagerName
        runnerName = game.runnerName
        goalUmpireName = game.goalUmpireName
        timeKeeperName = game.timeKeeperName
        fieldUmpireName = game.fieldUmpireName
        boundaryUmpire1Name = game.boundaryUmpire1Name
        boundaryUmpire2Name = game.boundaryUmpire2Name
        waterBoy1Name = game.waterBoy1Name
        waterBoy2Name = game.waterBoy2Name
        waterBoy3Name = game.waterBoy3Name
        waterBoy4Name = game.waterBoy4Name
        trainer1Name = game.trainers.indices.contains(0) ? game.trainers[0] : ""
        trainer2Name = game.trainers.indices.contains(1) ? game.trainers[1] : ""
        trainer3Name = game.trainers.indices.contains(2) ? game.trainers[2] : ""
        trainer4Name = game.trainers.indices.contains(3) ? game.trainers[3] : ""
        notes = game.notes
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var selectedTrainerNames: [String] {
        [trainer1Name, trainer2Name, trainer3Name, trainer4Name]
            .map(clean)
            .filter { !$0.isEmpty }
    }

    var hasRequiredMatchInfo: Bool {
        !clean(opponent).isEmpty && !clean(venue).isEmpty
    }

    func apply(to game: Game) {
        game.gradeID = gradeID
        game.date = date
        game.opponent = clean(opponent)
        game.venue = clean(venue)
        game.ourGoals = ourGoals
        game.ourBehinds = ourBehinds
        game.theirGoals = theirGoals
        game.theirBehinds = theirBehinds
        game.goalKickers = goalKickers
        game.bestPlayersRanked = bestPlayersRanked
        game.guestVotesRanked = guestVotesRanked.enumerated().map { index, entry in
            GameGuestVoteEntry(id: entry.id, rank: index + 1, playerID: entry.playerID)
        }
        game.headCoachName = clean(headCoachName)
        game.assistantCoachName = clean(assistantCoachName)
        game.teamManagerName = clean(teamManagerName)
        game.runnerName = clean(runnerName)
        game.goalUmpireName = clean(goalUmpireName)
        game.timeKeeperName = clean(timeKeeperName)
        game.fieldUmpireName = clean(fieldUmpireName)
        game.boundaryUmpire1Name = clean(boundaryUmpire1Name)
        game.boundaryUmpire2Name = clean(boundaryUmpire2Name)
        game.waterBoy1Name = clean(waterBoy1Name)
        game.waterBoy2Name = clean(waterBoy2Name)
        game.waterBoy3Name = clean(waterBoy3Name)
        game.waterBoy4Name = clean(waterBoy4Name)
        game.trainers = selectedTrainerNames
        game.notes = notes
    }
}

struct GameEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Bindable var game: Game
    let secondaryGame: Game?
    let grades: [Grade]

    @State private var primaryDraft: GameEditDraft
    @State private var secondaryDraft: GameEditDraft?
    @State private var selectedGameTab = 0

    init(game: Game, secondaryGame: Game? = nil, grades: [Grade]) {
        self.game = game
        self.secondaryGame = secondaryGame
        self.grades = grades
        _primaryDraft = State(initialValue: GameEditDraft(game: game))
        _secondaryDraft = State(initialValue: secondaryGame.map(GameEditDraft.init(game:)))
    }

    private var canSave: Bool {
        primaryDraft.hasRequiredMatchInfo && (secondaryDraft?.hasRequiredMatchInfo ?? true)
    }

    private var hasChanges: Bool {
        primaryDraft != GameEditDraft(game: game)
            || secondaryHasChanges
    }

    private var secondaryHasChanges: Bool {
        guard let secondaryGame, let secondaryDraft else { return false }
        return secondaryDraft != GameEditDraft(game: secondaryGame)
    }

    private var showsTwoGameEditor: Bool {
        secondaryDraft != nil && secondaryGame != nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if showsTwoGameEditor {
                    if horizontalSizeClass == .compact {
                        compactTwoGameEditor
                    } else {
                        regularTwoGameEditor
                    }
                } else {
                    SingleGameEditForm(
                        title: nil,
                        draft: $primaryDraft,
                        grades: grades
                    )
                }
            }
            .navigationTitle(showsTwoGameEditor ? "Edit Games" : "Edit Game")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveGames()
                        dismiss()
                    }
                    .saveButtonBehavior(isEnabled: canSave && hasChanges)
                }
            }
        }
    }

    private var compactTwoGameEditor: some View {
        VStack(spacing: 0) {
            Picker("Game", selection: $selectedGameTab) {
                Text("Game 1").tag(0)
                Text("Game 2").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)

            if selectedGameTab == 0 {
                SingleGameEditForm(
                    title: "Game 1",
                    draft: $primaryDraft,
                    grades: grades
                )
            } else if let secondaryDraftBinding = secondaryDraftBinding {
                SingleGameEditForm(
                    title: "Game 2",
                    draft: secondaryDraftBinding,
                    grades: grades
                )
            }
        }
    }

    private var regularTwoGameEditor: some View {
        HStack(spacing: 0) {
            SingleGameEditForm(
                title: "Game 1",
                draft: $primaryDraft,
                grades: grades
            )

            Divider()

            if let secondaryDraftBinding = secondaryDraftBinding {
                SingleGameEditForm(
                    title: "Game 2",
                    draft: secondaryDraftBinding,
                    grades: grades
                )
            }
        }
    }

    private var secondaryDraftBinding: Binding<GameEditDraft>? {
        guard secondaryDraft != nil else { return nil }
        return Binding(
            get: { secondaryDraft ?? primaryDraft },
            set: { secondaryDraft = $0 }
        )
    }

    private func saveGames() {
        primaryDraft.apply(to: game)
        if let secondaryGame, let secondaryDraft {
            secondaryDraft.apply(to: secondaryGame)
        }
    }
}

private struct SingleGameEditForm: View {
    private enum SetupPickerPrompt {
        case opponent
        case venue
    }

    let title: String?
    @Binding var draft: GameEditDraft
    let grades: [Grade]

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: [SortDescriptor(\Player.name)]) private var players: [Player]

    @State private var setupPickerPrompt: SetupPickerPrompt?
    @State private var setupPickerDetent: PresentationDetent = .large

    private let clubConfiguration = ClubConfigurationStore.load()

    private var selectedGrade: Grade? {
        grades.first(where: { $0.id == draft.gradeID })
    }

    private var selectedOpposition: OppositionTeamProfile? {
        clubConfiguration.sortedOppositions.first {
            $0.name == draft.opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var venuesForSelection: [String] {
        let combined = clubConfiguration.clubTeam.sanitizedVenues + (selectedOpposition?.sanitizedVenues ?? [])
        var seen = Set<String>()
        return combined.filter { seen.insert($0).inserted }
    }

    private var eligiblePlayers: [Player] {
        players.filter { $0.isActive && $0.gradeIDs.contains(draft.gradeID) }
    }

    private var isHomeGame: Bool {
        let selectedVenue = draft.venue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !selectedVenue.isEmpty else { return false }
        return clubConfiguration.clubTeam.sanitizedVenues
            .map { $0.lowercased() }
            .contains(selectedVenue)
    }

    private var shouldShowScore: Bool {
        selectedGrade?.asksScore ?? true
    }

    private var shouldShowStaffSection: Bool {
        (selectedGrade?.asksHeadCoach ?? false)
            || (selectedGrade?.asksAssistantCoach ?? false)
            || (selectedGrade?.asksTeamManager ?? false)
            || (selectedGrade?.asksRunner ?? false)
    }

    private var shouldShowOfficialsSection: Bool {
        (selectedGrade?.asksGoalUmpire ?? false)
            || (selectedGrade?.asksTimeKeeper ?? false)
            || shouldShowFieldUmpire
            || (selectedGrade?.asksBoundaryUmpire1 ?? false)
            || (selectedGrade?.asksBoundaryUmpire2 ?? false)
            || (selectedGrade?.asksWaterBoy1 ?? false)
            || (selectedGrade?.asksWaterBoy2 ?? false)
            || (selectedGrade?.asksWaterBoy3 ?? false)
            || (selectedGrade?.asksWaterBoy4 ?? false)
    }

    private var shouldShowFieldUmpire: Bool {
        (selectedGrade?.asksFieldUmpire ?? false) && isHomeGame
    }

    private var shouldShowTrainersSection: Bool {
        (selectedGrade?.asksTrainer1 ?? false)
            || (selectedGrade?.asksTrainer2 ?? false)
            || (selectedGrade?.asksTrainer3 ?? false)
            || (selectedGrade?.asksTrainer4 ?? false)
    }

    private var shouldShowGoalKickers: Bool {
        selectedGrade?.asksGoalKickers ?? true
    }

    private var shouldShowBestPlayers: Bool {
        (selectedGrade?.bestPlayersCount ?? 0) > 0
    }

    private var shouldShowGuestVotes: Bool {
        (selectedGrade?.asksGuestBestFairestVotesScan ?? false)
            && (selectedGrade?.guestBestPlayersCount ?? 0) > 0
    }

    private var shouldShowNotes: Bool {
        selectedGrade?.asksNotes ?? false
    }

    private var requiredBestPlayersCount: Int {
        min(max(selectedGrade?.bestPlayersCount ?? 0, 0), 10)
    }

    private var requiredGuestVotesCount: Int {
        min(max(selectedGrade?.guestBestPlayersCount ?? 0, 0), 10)
    }

    var body: some View {
        Form {
            if let title {
                Section {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Match Info") {
                Picker("Grade", selection: $draft.gradeID) {
                    ForEach(grades) { grade in
                        Text(grade.name).tag(grade.id)
                    }
                }
                DatePicker("Date", selection: $draft.date)

                Button {
                    setupPickerPrompt = .opponent
                } label: {
                    selectorRow(title: "Opponent", value: draft.opponent)
                }
                .buttonStyle(.plain)

                Button {
                    setupPickerPrompt = .venue
                } label: {
                    selectorRow(title: "Venue", value: draft.venue)
                }
                .buttonStyle(.plain)
                .disabled(venuesForSelection.isEmpty)
            }

            if shouldShowScore {
                Section("Score") {
                    Stepper("Our Goals: \(draft.ourGoals)", value: $draft.ourGoals, in: 0...99)
                    Stepper("Our Behinds: \(draft.ourBehinds)", value: $draft.ourBehinds, in: 0...99)
                    Stepper("Their Goals: \(draft.theirGoals)", value: $draft.theirGoals, in: 0...99)
                    Stepper("Their Behinds: \(draft.theirBehinds)", value: $draft.theirBehinds, in: 0...99)
                }
            }

            if shouldShowStaffSection {
                Section("Coaching Staff") {
                    if selectedGrade?.asksHeadCoach ?? false {
                        StaffPickerField(title: "Head Coach", role: .headCoach, gradeID: draft.gradeID, value: $draft.headCoachName)
                    }
                    if selectedGrade?.asksAssistantCoach ?? false {
                        StaffPickerField(title: "Assistant Coach", role: .assistantCoach, gradeID: draft.gradeID, value: $draft.assistantCoachName)
                    }
                    if selectedGrade?.asksTeamManager ?? false {
                        StaffPickerField(title: "Team Manager", role: .teamManager, gradeID: draft.gradeID, value: $draft.teamManagerName)
                    }
                    if selectedGrade?.asksRunner ?? false {
                        StaffPickerField(title: "Runner", role: .runner, gradeID: draft.gradeID, value: $draft.runnerName)
                    }
                }
            }

            if shouldShowOfficialsSection {
                Section("Officials") {
                    if selectedGrade?.asksGoalUmpire ?? false {
                        StaffPickerField(title: "Goal Umpire", role: .goalUmpire, gradeID: draft.gradeID, value: $draft.goalUmpireName)
                    }
                    if selectedGrade?.asksTimeKeeper ?? false {
                        StaffPickerField(title: "Time Keeper", role: .timeKeeper, gradeID: draft.gradeID, value: $draft.timeKeeperName)
                    }
                    if shouldShowFieldUmpire {
                        StaffPickerField(title: "Field Umpire", role: .fieldUmpire, gradeID: draft.gradeID, value: $draft.fieldUmpireName)
                    }
                    if selectedGrade?.asksBoundaryUmpire1 ?? false {
                        StaffPickerField(title: "Boundary Umpire 1", role: .boundaryUmpire, gradeID: draft.gradeID, value: $draft.boundaryUmpire1Name)
                    }
                    if selectedGrade?.asksBoundaryUmpire2 ?? false {
                        StaffPickerField(title: "Boundary Umpire 2", role: .boundaryUmpire, gradeID: draft.gradeID, value: $draft.boundaryUmpire2Name)
                    }
                    if selectedGrade?.asksWaterBoy1 ?? false {
                        StaffPickerField(title: "Water 1", role: .waterBoy, gradeID: draft.gradeID, value: $draft.waterBoy1Name)
                    }
                    if selectedGrade?.asksWaterBoy2 ?? false {
                        StaffPickerField(title: "Water 2", role: .waterBoy, gradeID: draft.gradeID, value: $draft.waterBoy2Name)
                    }
                    if selectedGrade?.asksWaterBoy3 ?? false {
                        StaffPickerField(title: "Water 3", role: .waterBoy, gradeID: draft.gradeID, value: $draft.waterBoy3Name)
                    }
                    if selectedGrade?.asksWaterBoy4 ?? false {
                        StaffPickerField(title: "Water 4", role: .waterBoy, gradeID: draft.gradeID, value: $draft.waterBoy4Name)
                    }
                }
            }

            if shouldShowTrainersSection {
                Section("Trainers") {
                    if selectedGrade?.asksTrainer1 ?? false {
                        StaffPickerField(title: "Trainer 1", role: .trainer, gradeID: draft.gradeID, value: $draft.trainer1Name)
                    }
                    if selectedGrade?.asksTrainer2 ?? false {
                        StaffPickerField(title: "Trainer 2", role: .trainer, gradeID: draft.gradeID, value: $draft.trainer2Name)
                    }
                    if selectedGrade?.asksTrainer3 ?? false {
                        StaffPickerField(title: "Trainer 3", role: .trainer, gradeID: draft.gradeID, value: $draft.trainer3Name)
                    }
                    if selectedGrade?.asksTrainer4 ?? false {
                        StaffPickerField(title: "Trainer 4", role: .trainer, gradeID: draft.gradeID, value: $draft.trainer4Name)
                    }
                }
            }

            if shouldShowGoalKickers {
                Section("Goal Kickers") {
                    if draft.goalKickers.isEmpty {
                        Text("No goal kickers added.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(draft.goalKickers.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Player", selection: $draft.goalKickers[index].playerID) {
                                Text("Select…").tag(UUID?.none)
                                ForEach(eligiblePlayers) { player in
                                    Text(player.name).tag(UUID?.some(player.id))
                                }
                            }
                            Stepper("Goals: \(draft.goalKickers[index].goals)", value: $draft.goalKickers[index].goals, in: 0...20)
                        }
                    }
                    .onDelete { offsets in
                        draft.goalKickers.remove(atOffsets: offsets)
                    }

                    Button {
                        draft.goalKickers.append(GameGoalKickerEntry(playerID: nil, goals: 1))
                    } label: {
                        Label("Add goal kicker", systemImage: "plus")
                    }
                }
            }

            if shouldShowBestPlayers {
                Section("Best Players") {
                    if eligiblePlayers.isEmpty {
                        Text("No players yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(0..<requiredBestPlayersCount, id: \.self) { index in
                            Picker(bestPlayerLabel(for: index), selection: bestPlayerBinding(for: index)) {
                                Text("Select…").tag(UUID?.none)
                                ForEach(eligiblePlayers) { player in
                                    Text(player.name).tag(UUID?.some(player.id))
                                }
                            }
                        }
                    }
                }
            }

            if shouldShowGuestVotes {
                Section("Guest Votes") {
                    if eligiblePlayers.isEmpty {
                        Text("No players yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(0..<requiredGuestVotesCount, id: \.self) { index in
                            Picker(guestVoteLabel(for: index), selection: guestVoteBinding(for: index)) {
                                Text("Select…").tag(UUID?.none)
                                ForEach(eligiblePlayers) { player in
                                    Text(player.name).tag(UUID?.some(player.id))
                                }
                            }
                        }
                    }
                }
            }

            if shouldShowNotes {
                Section("Notes") {
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 120)
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { setupPickerPrompt != nil },
                set: { if !$0 { setupPickerPrompt = nil } }
            )
        ) {
            setupPickerSheet
        }
    }

    private func bestPlayerBinding(for index: Int) -> Binding<UUID?> {
        Binding<UUID?>(
            get: {
                guard draft.bestPlayersRanked.indices.contains(index) else { return nil }
                return draft.bestPlayersRanked[index]
            },
            set: { selectedID in
                if let selectedID {
                    if let existingIndex = draft.bestPlayersRanked.firstIndex(of: selectedID), existingIndex != index {
                        draft.bestPlayersRanked.remove(at: existingIndex)
                    }
                    if draft.bestPlayersRanked.indices.contains(index) {
                        draft.bestPlayersRanked[index] = selectedID
                    } else {
                        while draft.bestPlayersRanked.count < index {
                            draft.bestPlayersRanked.append(UUID())
                        }
                        if draft.bestPlayersRanked.count == index {
                            draft.bestPlayersRanked.append(selectedID)
                        } else {
                            draft.bestPlayersRanked[index] = selectedID
                        }
                    }
                } else if draft.bestPlayersRanked.indices.contains(index) {
                    draft.bestPlayersRanked.remove(at: index)
                }
            }
        )
    }

    private func guestVoteBinding(for index: Int) -> Binding<UUID?> {
        Binding<UUID?>(
            get: {
                guard draft.guestVotesRanked.indices.contains(index) else { return nil }
                return draft.guestVotesRanked[index].playerID
            },
            set: { selectedID in
                if let selectedID {
                    if let existingIndex = draft.guestVotesRanked.firstIndex(where: { $0.playerID == selectedID }), existingIndex != index {
                        draft.guestVotesRanked.remove(at: existingIndex)
                    }
                    while draft.guestVotesRanked.count <= index {
                        draft.guestVotesRanked.append(
                            GameGuestVoteEntry(rank: draft.guestVotesRanked.count + 1, playerID: selectedID)
                        )
                    }
                    draft.guestVotesRanked[index].playerID = selectedID
                } else if draft.guestVotesRanked.indices.contains(index) {
                    draft.guestVotesRanked.remove(at: index)
                }

                for rankIndex in draft.guestVotesRanked.indices {
                    draft.guestVotesRanked[rankIndex].rank = rankIndex + 1
                }
            }
        )
    }

    private func bestPlayerLabel(for index: Int) -> String {
        switch index {
        case 0: return "1st Best Player"
        case 1: return "2nd Best Player"
        case 2: return "3rd Best Player"
        default: return "\(index + 1)th Best Player"
        }
    }

    private func guestVoteLabel(for index: Int) -> String {
        switch index {
        case 0: return "1st Guest Vote"
        case 1: return "2nd Guest Vote"
        case 2: return "3rd Guest Vote"
        default: return "\(index + 1)th Guest Vote"
        }
    }

    @ViewBuilder
    private var setupPickerSheet: some View {
        NavigationStack {
            List {
                switch setupPickerPrompt {
                case .opponent:
                    Button {
                        draft.opponent = ""
                        draft.venue = ""
                        setupPickerPrompt = nil
                    } label: {
                        selectorListRow(title: "Select…", selected: draft.opponent.isEmpty)
                    }
                    .buttonStyle(.plain)

                    ForEach(clubConfiguration.sortedOppositions.map(\.name), id: \.self) { option in
                        Button {
                            draft.opponent = option
                            if !venuesForSelection.contains(draft.venue) {
                                draft.venue = ""
                            }
                            setupPickerPrompt = nil
                        } label: {
                            selectorListRow(title: option, selected: draft.opponent == option)
                        }
                        .buttonStyle(.plain)
                    }

                case .venue:
                    Button {
                        draft.venue = ""
                        setupPickerPrompt = nil
                    } label: {
                        selectorListRow(title: "Select…", selected: draft.venue.isEmpty)
                    }
                    .buttonStyle(.plain)

                    ForEach(venuesForSelection, id: \.self) { option in
                        Button {
                            draft.venue = option
                            setupPickerPrompt = nil
                        } label: {
                            selectorListRow(title: option, selected: draft.venue == option)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { setupPickerPrompt = nil }
                }
            }
        }
        .presentationDetents([.height(setupPickerHeight), .large], selection: $setupPickerDetent)
        .presentationDragIndicator(.visible)
        .onAppear {
            setupPickerDetent = .large
        }
    }

    @ViewBuilder
    private func selectorRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.isEmpty ? "Select…" : value)
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func selectorListRow(title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }

    private var setupPickerHeight: CGFloat {
        let count: Int
        switch setupPickerPrompt {
        case .opponent:
            count = clubConfiguration.sortedOppositions.count + 1
        case .venue:
            count = venuesForSelection.count + 1
        case .none:
            count = 2
        }

        return PickerSheetPresentation.preferredHeight(
            optionCount: count,
            rowHeight: 56,
            chromeHeight: 112,
            minVisibleRows: 2,
            isCompactLayout: horizontalSizeClass == .compact
        )
    }
}
