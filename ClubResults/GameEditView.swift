import SwiftUI
import SwiftData

struct GameEditView: View {
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
    @State private var boundaryUmpire1Name: String
    @State private var boundaryUmpire2Name: String
    @State private var trainer1Name: String
    @State private var trainer2Name: String
    @State private var trainer3Name: String
    @State private var trainer4Name: String

    @State private var notes: String

    init(game: Game, grades: [Grade]) {
        self.game = game
        self.grades = grades

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
        _boundaryUmpire1Name = State(initialValue: game.boundaryUmpire1Name)
        _boundaryUmpire2Name = State(initialValue: game.boundaryUmpire2Name)
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
                    TextField("Opponent", text: $opponent)
                    TextField("Venue", text: $venue)
                }

                Section("Score") {
                    Stepper("Our Goals: \(ourGoals)", value: $ourGoals, in: 0...99)
                    Stepper("Our Behinds: \(ourBehinds)", value: $ourBehinds, in: 0...99)
                    Stepper("Their Goals: \(theirGoals)", value: $theirGoals, in: 0...99)
                    Stepper("Their Behinds: \(theirBehinds)", value: $theirBehinds, in: 0...99)
                }

                Section("Staff & Officials") {
                    TextField("Head Coach", text: $headCoachName)
                    TextField("Assistant Coach", text: $assistantCoachName)
                    TextField("Team Manager", text: $teamManagerName)
                    TextField("Runner", text: $runnerName)
                    TextField("Goal Umpire", text: $goalUmpireName)
                    TextField("Boundary Umpire 1", text: $boundaryUmpire1Name)
                    TextField("Boundary Umpire 2", text: $boundaryUmpire2Name)
                }

                Section("Trainers") {
                    TextField("Trainer 1", text: $trainer1Name)
                    TextField("Trainer 2", text: $trainer2Name)
                    TextField("Trainer 3", text: $trainer3Name)
                    TextField("Trainer 4", text: $trainer4Name)
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
                        ForEach(players) { p in
                            Button {
                                toggleBestPlayer(p.id)
                            } label: {
                                HStack {
                                    Text(p.name)
                                    Spacer()
                                    if let idx = bestPlayersRanked.firstIndex(of: p.id) {
                                        Text("#\(idx + 1)")
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "checkmark.circle.fill")
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
                        game.boundaryUmpire1Name = boundaryUmpire1Name
                        game.boundaryUmpire2Name = boundaryUmpire2Name
                        game.trainers = [
                            trainer1Name.trimmingCharacters(in: .whitespacesAndNewlines),
                            trainer2Name.trimmingCharacters(in: .whitespacesAndNewlines),
                            trainer3Name.trimmingCharacters(in: .whitespacesAndNewlines),
                            trainer4Name.trimmingCharacters(in: .whitespacesAndNewlines)
                        ].filter { !$0.isEmpty }

                        game.notes = notes
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func toggleBestPlayer(_ id: UUID) {
        if let idx = bestPlayersRanked.firstIndex(of: id) {
            bestPlayersRanked.remove(at: idx)
        } else {
            bestPlayersRanked.append(id)
        }
    }
}
