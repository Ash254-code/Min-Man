import SwiftUI
import SwiftData

struct GameEditView: View {
    private enum SetupPickerPrompt {
        case opponent
        case venue
    }

    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Player.name)]) private var players: [Player]

    @Bindable var game: Game
    let grades: [Grade]

    // Local working copies (Cancel won’t change the model)
    @State private var gradeID: UUID
    @State private var date: Date
    @State private var opponent: String
    @State private var venue: String

    @State private var ourGoals: Int
    @State private var ourBehinds: Int
    @State private var theirGoals: Int
    @State private var theirBehinds: Int

    @State private var goalKickers: [GameGoalKickerEntry]
    @State private var bestPlayersRanked: [UUID]

    @State private var headCoachName: String
    @State private var assistantCoachName: String
    @State private var teamManagerName: String
    @State private var runnerName: String
    @State private var goalUmpireName: String
    @State private var fieldUmpireName: String
    @State private var boundaryUmpire1Name: String
    @State private var boundaryUmpire2Name: String
    @State private var waterBoy1Name: String
    @State private var waterBoy2Name: String
    @State private var waterBoy3Name: String
    @State private var waterBoy4Name: String
    @State private var trainer1Name: String
    @State private var trainer2Name: String
    @State private var trainer3Name: String
    @State private var trainer4Name: String

    @State private var notes: String

    @State private var setupPickerPrompt: SetupPickerPrompt?
    @State private var setupPickerDetent: PresentationDetent = .large

    private let clubConfiguration: ClubConfiguration

    init(game: Game, grades: [Grade]) {
        self.game = game
        self.grades = grades
        self.clubConfiguration = ClubConfigurationStore.load()

        _gradeID = State(initialValue: game.gradeID)
        _date = State(initialValue: game.date)
        _opponent = State(initialValue: game.opponent)
        _venue = State(initialValue: game.venue)

        _ourGoals = State(initialValue: game.ourGoals)
        _ourBehinds = State(initialValue: game.ourBehinds)
        _theirGoals = State(initialValue: game.theirGoals)
        _theirBehinds = State(initialValue: game.theirBehinds)

        _goalKickers = State(initialValue: game.goalKickers)
        _bestPlayersRanked = State(initialValue: game.bestPlayersRanked)

        _headCoachName = State(initialValue: game.headCoachName)
        _assistantCoachName = State(initialValue: game.assistantCoachName)
        _teamManagerName = State(initialValue: game.teamManagerName)
        _runnerName = State(initialValue: game.runnerName)
        _goalUmpireName = State(initialValue: game.goalUmpireName)
        _fieldUmpireName = State(initialValue: game.fieldUmpireName)
        _boundaryUmpire1Name = State(initialValue: game.boundaryUmpire1Name)
        _boundaryUmpire2Name = State(initialValue: game.boundaryUmpire2Name)
        _waterBoy1Name = State(initialValue: game.waterBoy1Name)
        _waterBoy2Name = State(initialValue: game.waterBoy2Name)
        _waterBoy3Name = State(initialValue: game.waterBoy3Name)
        _waterBoy4Name = State(initialValue: game.waterBoy4Name)
        _trainer1Name = State(initialValue: game.trainers.indices.contains(0) ? game.trainers[0] : "")
        _trainer2Name = State(initialValue: game.trainers.indices.contains(1) ? game.trainers[1] : "")
        _trainer3Name = State(initialValue: game.trainers.indices.contains(2) ? game.trainers[2] : "")
        _trainer4Name = State(initialValue: game.trainers.indices.contains(3) ? game.trainers[3] : "")

        _notes = State(initialValue: game.notes)
    }

    private var canSave: Bool {
        !opponent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !venue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasChanges: Bool {
        guard canSave else { return false }

        return game.gradeID != gradeID ||
        game.date != date ||
        game.opponent != opponent ||
        game.venue != venue ||
        game.ourGoals != ourGoals ||
        game.ourBehinds != ourBehinds ||
        game.theirGoals != theirGoals ||
        game.theirBehinds != theirBehinds ||
        game.goalKickers != goalKickers ||
        game.bestPlayersRanked != bestPlayersRanked ||
        game.headCoachName != headCoachName ||
        game.assistantCoachName != assistantCoachName ||
        game.teamManagerName != teamManagerName ||
        game.runnerName != runnerName ||
        game.goalUmpireName != goalUmpireName ||
        game.fieldUmpireName != fieldUmpireName ||
        game.boundaryUmpire1Name != boundaryUmpire1Name ||
        game.boundaryUmpire2Name != boundaryUmpire2Name ||
        game.waterBoy1Name != waterBoy1Name ||
        game.waterBoy2Name != waterBoy2Name ||
        game.waterBoy3Name != waterBoy3Name ||
        game.waterBoy4Name != waterBoy4Name ||
        game.trainers != selectedTrainerNames ||
        game.notes != notes
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Match Info") {
                    Picker("Grade", selection: $gradeID) {
                        ForEach(grades) { g in
                            Text(g.name).tag(g.id)
                        }
                    }
                    DatePicker("Date", selection: $date)

                    Button {
                        setupPickerPrompt = .opponent
                    } label: {
                        selectorRow(title: "Opponent", value: opponent)
                    }
                    .buttonStyle(.plain)

                    Button {
                        setupPickerPrompt = .venue
                    } label: {
                        selectorRow(title: "Venue", value: venue)
                    }
                    .buttonStyle(.plain)
                    .disabled(venuesForSelection.isEmpty)
                }

                Section("Score") {
                    Stepper("Our Goals: \(ourGoals)", value: $ourGoals, in: 0...99)
                    Stepper("Our Behinds: \(ourBehinds)", value: $ourBehinds, in: 0...99)
                    Stepper("Their Goals: \(theirGoals)", value: $theirGoals, in: 0...99)
                    Stepper("Their Behinds: \(theirBehinds)", value: $theirBehinds, in: 0...99)
                }

                Section("Coaching Staff") {
                    StaffPickerField(title: "Head Coach", role: .headCoach, gradeID: gradeID, value: $headCoachName)
                    StaffPickerField(title: "Assistant Coach", role: .assistantCoach, gradeID: gradeID, value: $assistantCoachName)
                    StaffPickerField(title: "Team Manager", role: .teamManager, gradeID: gradeID, value: $teamManagerName)
                    StaffPickerField(title: "Runner", role: .runner, gradeID: gradeID, value: $runnerName)
                }

                Section("Officials") {
                    StaffPickerField(title: "Goal Umpire", role: .goalUmpire, gradeID: gradeID, value: $goalUmpireName)
                    StaffPickerField(title: "Field Umpire", role: .fieldUmpire, gradeID: gradeID, value: $fieldUmpireName)
                    StaffPickerField(title: "Boundary Umpire 1", role: .boundaryUmpire, gradeID: gradeID, value: $boundaryUmpire1Name)
                    StaffPickerField(title: "Boundary Umpire 2", role: .boundaryUmpire, gradeID: gradeID, value: $boundaryUmpire2Name)
                    StaffPickerField(title: "Water Boy 1", role: .waterBoy, gradeID: gradeID, value: $waterBoy1Name)
                    StaffPickerField(title: "Water Boy 2", role: .waterBoy, gradeID: gradeID, value: $waterBoy2Name)
                    StaffPickerField(title: "Water Boy 3", role: .waterBoy, gradeID: gradeID, value: $waterBoy3Name)
                    StaffPickerField(title: "Water Boy 4", role: .waterBoy, gradeID: gradeID, value: $waterBoy4Name)
                }

                Section("Trainers") {
                    StaffPickerField(title: "Trainer 1", role: .trainer, gradeID: gradeID, value: $trainer1Name)
                    StaffPickerField(title: "Trainer 2", role: .trainer, gradeID: gradeID, value: $trainer2Name)
                    StaffPickerField(title: "Trainer 3", role: .trainer, gradeID: gradeID, value: $trainer3Name)
                    StaffPickerField(title: "Trainer 4", role: .trainer, gradeID: gradeID, value: $trainer4Name)
                }

                Section("Goal Kickers") {
                    if goalKickers.isEmpty {
                        Text("No goal kickers added.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(goalKickers.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Player", selection: $goalKickers[i].playerID) {
                                Text("Select…").tag(UUID?.none)
                                ForEach(players) { p in
                                    Text(p.name).tag(UUID?.some(p.id))
                                }
                            }
                            Stepper("Goals: \(goalKickers[i].goals)", value: $goalKickers[i].goals, in: 0...20)
                        }
                    }
                    .onDelete { offsets in
                        goalKickers.remove(atOffsets: offsets)
                    }

                    Button {
                        goalKickers.append(GameGoalKickerEntry(playerID: nil, goals: 1))
                    } label: {
                        Label("Add goal kicker", systemImage: "plus")
                    }
                }

                Section("Best Players") {
                    if players.isEmpty {
                        Text("No players yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(bestPlayerRanks, id: \.self) { index in
                            Picker(bestPlayerLabel(for: index), selection: bestPlayerBinding(for: index)) {
                                Text("Select…").tag(UUID?.none)
                                ForEach(players) { p in
                                    Text(p.name).tag(UUID?.some(p.id))
                                }
                            }
                        }

                        Button {
                            bestPlayersRanked.append(players.first?.id ?? UUID())
                        } label: {
                            Label("Add best player", systemImage: "plus")
                        }
                        .disabled(bestPlayersRanked.count >= players.count)

                        if !bestPlayersRanked.isEmpty {
                            Button(role: .destructive) {
                                bestPlayersRanked.removeAll()
                            } label: {
                                Text("Clear best players")
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("Edit Game")
            .sheet(
                isPresented: Binding(
                    get: { setupPickerPrompt != nil },
                    set: { if !$0 { setupPickerPrompt = nil } }
                )
            ) {
                setupPickerSheet
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveGame()
                        dismiss()
                    }
                    .saveButtonBehavior(isEnabled: hasChanges)
                }
            }
        }
    }

    private var bestPlayerRanks: [Int] {
        Array(bestPlayersRanked.indices)
    }

    private var opponentNames: [String] {
        clubConfiguration.sortedOppositions.map(\.name)
    }

    private var selectedOpposition: OppositionTeamProfile? {
        clubConfiguration.sortedOppositions.first(where: { $0.name == opponent.trimmingCharacters(in: .whitespacesAndNewlines) })
    }

    private var venuesForSelection: [String] {
        let combined = clubConfiguration.clubTeam.sanitizedVenues + (selectedOpposition?.sanitizedVenues ?? [])
        var seen = Set<String>()
        return combined.filter { seen.insert($0).inserted }
    }

    private var selectedTrainerNames: [String] {
        [trainer1Name, trainer2Name, trainer3Name, trainer4Name]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    @ViewBuilder
    private var setupPickerSheet: some View {
        NavigationStack {
            List {
                switch setupPickerPrompt {
                case .opponent:
                    Button {
                        opponent = ""
                        venue = ""
                        setupPickerPrompt = nil
                    } label: {
                        selectorListRow(title: "Select…", selected: opponent.isEmpty)
                    }
                    .buttonStyle(.plain)

                    ForEach(opponentNames, id: \.self) { option in
                        Button {
                            opponent = option
                            if !venuesForSelection.contains(venue) {
                                venue = ""
                            }
                            setupPickerPrompt = nil
                        } label: {
                            selectorListRow(title: option, selected: opponent == option)
                        }
                        .buttonStyle(.plain)
                    }

                case .venue:
                    Button {
                        venue = ""
                        setupPickerPrompt = nil
                    } label: {
                        selectorListRow(title: "Select…", selected: venue.isEmpty)
                    }
                    .buttonStyle(.plain)

                    ForEach(venuesForSelection, id: \.self) { option in
                        Button {
                            venue = option
                            setupPickerPrompt = nil
                        } label: {
                            selectorListRow(title: option, selected: venue == option)
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
            count = opponentNames.count + 1
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
            isCompactLayout: true
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

    private func bestPlayerBinding(for index: Int) -> Binding<UUID?> {
        Binding<UUID?>(
            get: {
                guard bestPlayersRanked.indices.contains(index) else { return nil }
                return bestPlayersRanked[index]
            },
            set: { selectedID in
                guard bestPlayersRanked.indices.contains(index) else { return }
                if let selectedID {
                    if let existingIndex = bestPlayersRanked.firstIndex(of: selectedID), existingIndex != index {
                        bestPlayersRanked.remove(at: existingIndex)
                        let adjusted = existingIndex < index ? index - 1 : index
                        bestPlayersRanked[adjusted] = selectedID
                    } else {
                        bestPlayersRanked[index] = selectedID
                    }
                } else {
                    bestPlayersRanked.remove(at: index)
                }
            }
        )
    }

    private func saveGame() {
        game.gradeID = gradeID
        game.date = date
        game.opponent = opponent
        game.venue = venue

        game.ourGoals = ourGoals
        game.ourBehinds = ourBehinds
        game.theirGoals = theirGoals
        game.theirBehinds = theirBehinds

        game.goalKickers = goalKickers
        game.bestPlayersRanked = bestPlayersRanked

        game.headCoachName = headCoachName
        game.assistantCoachName = assistantCoachName
        game.teamManagerName = teamManagerName
        game.runnerName = runnerName
        game.goalUmpireName = goalUmpireName
        game.fieldUmpireName = fieldUmpireName
        game.boundaryUmpire1Name = boundaryUmpire1Name
        game.boundaryUmpire2Name = boundaryUmpire2Name
        game.waterBoy1Name = waterBoy1Name
        game.waterBoy2Name = waterBoy2Name
        game.waterBoy3Name = waterBoy3Name
        game.waterBoy4Name = waterBoy4Name
        game.trainers = selectedTrainerNames

        game.notes = notes
    }
}
