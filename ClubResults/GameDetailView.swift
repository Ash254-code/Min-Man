import SwiftUI
import SwiftData

struct GameDetailView: View {
    let game: Game
    let grades: [Grade]
    let players: [Player]

    // ✅ Code gate
    @State private var showEditPrompt = false
    @State private var editCode = ""
    @State private var showWrongEditCode = false

    // ✅ Edit sheet
    @State private var showEditSheet = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    // 🔐 Change this
    private let requiredEditCode = "1234"

    private var gradeName: String {
        grades.first(where: { $0.id == game.gradeID })?.name ?? "Unknown"
    }

    private func playerName(for id: UUID?) -> String {
        guard let id else { return "Unknown" }
        return players.first(where: { $0.id == id })?.name ?? "Unknown"
    }

    private func playerName(for id: UUID) -> String {
        players.first(where: { $0.id == id })?.name ?? "Unknown"
    }

    private var sortedGoalKickers: [GameGoalKickerEntry] {
        game.goalKickers.sorted { $0.goals > $1.goals }
    }

    var body: some View {
        List {
            Section(header: Text("Match Info")) {
                row("Grade", gradeName)
                row("Opponent", game.opponent)
                row("Date", game.date.formatted(date: .abbreviated, time: .shortened))
                row("Venue", game.venue)
            }

            Section(header: Text("Score")) {
                HStack {
                    Text("Our Score")
                    Spacer()
                    Text("\(game.ourGoals).\(game.ourBehinds)  (\(game.ourScore))")
                }
                HStack {
                    Text("Their Score")
                    Spacer()
                    Text("\(game.theirGoals).\(game.theirBehinds)  (\(game.theirScore))")
                }
            }

            if !game.goalKickers.isEmpty {
                Section(header: Text("Goal Kickers")) {
                    ForEach(sortedGoalKickers) { entry in
                        HStack {
                            Text(playerName(for: entry.playerID))
                            Spacer()
                            Text(entry.goals == 1 ? "1 goal" : "\(entry.goals) goals")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !game.bestPlayersRanked.isEmpty {
                Section(header: Text("Best Players")) {
                    ForEach(Array(game.bestPlayersRanked.enumerated()), id: \.offset) { idx, pid in
                        HStack {
                            Text(placeLabel(idx))
                                .frame(width: 28, alignment: .leading)
                                .foregroundStyle(.secondary)
                            Text(playerName(for: pid))
                        }
                    }
                }
            }

            if !game.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section(header: Text("Notes")) {
                    Text(game.notes)
                }
            }

            if game.guestBestFairestVotesScanPDF != nil {
                Section(header: Text("Guest Best & Fairest Votes")) {
                    Label("Votes scan attached", systemImage: "doc.richtext")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(game.opponent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    prepareShareReport()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    editCode = ""
                    showEditPrompt = true
                }
            }
        }
        // ✅ Prompt for code when Edit tapped
        .alert("Enter edit code", isPresented: $showEditPrompt) {
            SecureField("Code", text: $editCode)

            Button("Cancel", role: .cancel) { }

            Button("Continue") {
                let trimmed = editCode.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed == requiredEditCode else {
                    showWrongEditCode = true
                    return
                }
                showEditSheet = true
            }
        } message: {
            Text("Editing previous games is protected.")
        }
        .alert("Wrong code", isPresented: $showWrongEditCode) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("That code is incorrect.")
        }
        // ✅ Only opens after correct code
        .sheet(isPresented: $showEditSheet) {
            GameEditView(game: game, grades: grades)
                .appPopupStyle()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
    }

    @ViewBuilder
    private func row(_ left: String, _ right: String) -> some View {
        HStack {
            Text(left)
            Spacer()
            Text(right).foregroundStyle(.secondary)
        }
    }

    private func placeLabel(_ idx: Int) -> String {
        switch idx {
        case 0: return "🥇"
        case 1: return "🥈"
        case 2: return "🥉"
        default: return "\(idx + 1)."
        }
    }

    private func prepareShareReport() {
        let gradeName = grades.first(where: { $0.id == game.gradeID })?.name ?? "Unknown Grade"
        let playerLookup: (UUID) -> String = { pid in
            players.first(where: { $0.id == pid })?.name ?? "Unknown"
        }

        do {
            var items: [Any] = []
            items.append(try ExportService.makeGameSummaryTextFile(game: game, gradeName: gradeName, playerName: playerLookup))
            items.append(try ExportService.makeGameCSV(game: game, gradeName: gradeName, playerName: playerLookup))

            if let scanData = game.guestBestFairestVotesScanPDF {
                let pdfName = "GuestVotes_\(gradeName)_\(game.date.formatted(date: .numeric, time: .omitted)).pdf"
                let pdfURL = FileManager.default.temporaryDirectory.appendingPathComponent(pdfName.replacingOccurrences(of: "/", with: "-"))
                try scanData.write(to: pdfURL, options: .atomic)
                items.append(pdfURL)
            }

            shareItems = items
            showShareSheet = true
        } catch {
            shareItems = [ExportService.gameSummaryText(game: game, gradeName: gradeName, playerName: playerLookup)]
            showShareSheet = true
        }
    }
}

#Preview {
    let dummyPlayer = Player(name: "Test Player")

    let dummyGame = Game(
        gradeID: UUID(),
        date: .now,
        opponent: "BSR",
        venue: "Home Ground",
        ourGoals: 10,
        ourBehinds: 8,
        theirGoals: 7,
        theirBehinds: 5,
        goalKickers: [],
        bestPlayersRanked: [],
        notes: "Preview note"
    )

    NavigationStack {
        GameDetailView(
            game: dummyGame,
            grades: [],
            players: [dummyPlayer]
        )
    }
}
