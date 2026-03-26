import SwiftUI
import SwiftData

struct GameEditView: View {
    @Environment(\.dismiss) private var dismiss

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

                        game.notes = notes
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
