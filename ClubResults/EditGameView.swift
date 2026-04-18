import SwiftUI
import SwiftData

struct EditGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext: ModelContext

    @Query(sort: [SortDescriptor(\Player.name)]) private var players: [Player]
    @Query(sort: [SortDescriptor(\Grade.name)]) private var grades: [Grade]

    @Bindable var game: Game

    private var gradeName: String {
        grades.first(where: { $0.id == game.gradeID })?.name ?? "Unknown"
    }

    var body: some View {
        Form {
            Section("Game") {
                Text("Grade: \(gradeName)")
                    .foregroundStyle(.secondary)

                DatePicker("Date", selection: $game.date, displayedComponents: .date)
                TextField("Opponent", text: $game.opponent)
                TextField("Venue", text: $game.venue)
            }

            Section("Score") {
                Stepper("Our goals: \(game.ourGoals)", value: $game.ourGoals, in: 0...60)
                Stepper("Our behinds: \(game.ourBehinds)", value: $game.ourBehinds, in: 0...60)
                Text("Our total: \(game.ourScore)")

                Stepper("Their goals: \(game.theirGoals)", value: $game.theirGoals, in: 0...60)
                Stepper("Their behinds: \(game.theirBehinds)", value: $game.theirBehinds, in: 0...60)
                Text("Their total: \(game.theirScore)")
            }

            Section("Goal Kickers") {
                if game.goalKickers.isEmpty {
                    Text("No goal kickers added.")
                        .foregroundStyle(.secondary)
                }

                ForEach(game.goalKickers.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Player", selection: $game.goalKickers[i].playerID) {
                            Text("Select…").tag(UUID?.none)
                            ForEach(players) { p in
                                Text(p.name).tag(UUID?.some(p.id))
                            }
                        }

                        Stepper("Goals: \(game.goalKickers[i].goals)",
                                value: $game.goalKickers[i].goals,
                                in: 0...20)
                    }
                }
                .onDelete { offsets in
                    game.goalKickers.remove(atOffsets: offsets)
                }

                Button {
                    game.goalKickers.append(GameGoalKickerEntry(playerID: nil, goals: 1))
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
                                if let idx = game.bestPlayersRanked.firstIndex(of: p.id) {
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

                    if !game.bestPlayersRanked.isEmpty {
                        Button(role: .destructive) {
                            game.bestPlayersRanked.removeAll()
                        } label: {
                            Text("Clear best players")
                        }
                    }
                }
            }

            Section("Notes") {
                TextEditor(text: $game.notes)
                    .frame(minHeight: 120)
            }
        }
        .navigationTitle("Edit Game")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
    }

    private func toggleBestPlayer(_ id: UUID) {
        if let idx = game.bestPlayersRanked.firstIndex(of: id) {
            game.bestPlayersRanked.remove(at: idx)
        } else {
            game.bestPlayersRanked.append(id)
        }
    }
}
