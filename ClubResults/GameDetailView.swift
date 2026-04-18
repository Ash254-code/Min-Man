import SwiftUI
import SwiftData

struct GameDetailView: View {
    let game: Game
    let grades: [Grade]
    let players: [Player]
    @Query private var games: [Game]

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

    private var grade: Grade? {
        grades.first(where: { $0.id == game.gradeID })
    }

    private var isTwoGameGrade: Bool {
        let normalized = gradeName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "under 9's" || normalized == "under 12's"
    }

    private var shouldShowScore: Bool {
        guard isTwoGameGrade else { return true }
        return grade?.asksScore ?? true
    }

    private var shouldShowScoreInSummary: Bool {
        shouldShowScore
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

    private var partnerGame: Game? {
        guard isTwoGameGrade else { return nil }
        return games.first { candidate in
            candidate.id != game.id && arePairedTwoGames(game, candidate)
        }
    }

    private func normalizedGoalKickerSignature(_ candidateGame: Game) -> [(UUID?, Int)] {
        candidateGame.goalKickers
            .map { ($0.playerID, $0.goals) }
            .sorted { lhs, rhs in
                let leftID = lhs.0?.uuidString ?? ""
                let rightID = rhs.0?.uuidString ?? ""
                if leftID == rightID { return lhs.1 < rhs.1 }
                return leftID < rightID
            }
    }

    private func arePairedTwoGames(_ first: Game, _ second: Game) -> Bool {
        guard first.gradeID == second.gradeID else { return false }
        guard abs(first.date.timeIntervalSince(second.date)) < 1 else { return false }
        guard first.opponent == second.opponent else { return false }
        guard first.venue == second.venue else { return false }
        guard first.isDraft == second.isDraft else { return false }
        guard first.ourGoals == second.ourGoals,
              first.ourBehinds == second.ourBehinds,
              first.theirGoals == second.theirGoals,
              first.theirBehinds == second.theirBehinds else { return false }
        guard first.notes == second.notes else { return false }
        return normalizedGoalKickerSignature(first) == normalizedGoalKickerSignature(second)
    }

    var body: some View {
        List {
            if game.isDraft {
                Section {
                    Text("Draft game")
                        .font(.headline)
                        .foregroundStyle(.orange)
                }
            }

            if let partnerGame {
                Section(header: Text("Match Info")) {
                    row("Grade", gradeName)
                    row("Opponent", game.opponent)
                    row("Date", game.date.formatted(date: .abbreviated, time: .shortened))
                    row("Venue", game.venue)
                    row("Games", "Two games recorded")
                }

                Section(header: Text("Two Game Details")) {
                    HStack(alignment: .top, spacing: 12) {
                        twoGameColumn(title: "Game 1", game: game)
                        twoGameColumn(title: "Game 2", game: partnerGame)
                    }
                }
            } else {
                Section(header: Text("Match Info")) {
                    row("Grade", gradeName)
                    row("Opponent", game.opponent)
                    row("Date", game.date.formatted(date: .abbreviated, time: .shortened))
                    row("Venue", game.venue)
                }

                if shouldShowScore {
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
        }
        .navigationTitle(game.opponent)
        .overlay {
            if game.isDraft {
                Text("DRAFT")
                    .font(.system(size: 80, weight: .black))
                    .foregroundStyle(Color.red.opacity(0.15))
                    .rotationEffect(.degrees(-28))
                    .allowsHitTesting(false)
            }
        }
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

    @ViewBuilder
    private func twoGameColumn(title: String, game: Game) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            if shouldShowScore {
                Text("Score")
                    .font(.subheadline.weight(.semibold))
                Text("\(game.ourGoals).\(game.ourBehinds) (\(game.ourScore))")
                Text("\(game.theirGoals).\(game.theirBehinds) (\(game.theirScore))")
                    .foregroundStyle(.secondary)
            }
            if !game.goalKickers.isEmpty {
                Text("Goal Kickers")
                    .font(.subheadline.weight(.semibold))
                ForEach(game.goalKickers.sorted { $0.goals > $1.goals }) { entry in
                    Text("• \(playerName(for: entry.playerID)) \(entry.goals)")
                        .font(.subheadline)
                }
            }
            if !game.bestPlayersRanked.isEmpty {
                Text("Best Players")
                    .font(.subheadline.weight(.semibold))
                ForEach(Array(game.bestPlayersRanked.enumerated()), id: \.offset) { idx, pid in
                    Text("\(placeLabel(idx)) \(playerName(for: pid))")
                        .font(.subheadline)
                }
            }
            if !game.headCoachName.isEmpty || !game.assistantCoachName.isEmpty || !game.teamManagerName.isEmpty || !game.runnerName.isEmpty {
                Text("Coaching")
                    .font(.subheadline.weight(.semibold))
                if !game.headCoachName.isEmpty { Text("Head Coach: \(game.headCoachName)").font(.subheadline) }
                if !game.assistantCoachName.isEmpty { Text("Assistant: \(game.assistantCoachName)").font(.subheadline) }
                if !game.teamManagerName.isEmpty { Text("Team Manager: \(game.teamManagerName)").font(.subheadline) }
                if !game.runnerName.isEmpty { Text("Runner: \(game.runnerName)").font(.subheadline) }
            }
            if !game.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Notes")
                    .font(.subheadline.weight(.semibold))
                Text(game.notes)
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func prepareShareReport() {
        let gradeName = grades.first(where: { $0.id == game.gradeID })?.name ?? "Unknown Grade"
        let playerLookup: (UUID) -> String = { pid in
            players.first(where: { $0.id == pid })?.name ?? "Unknown"
        }

        do {
            var items: [Any] = []
            items.append(try ExportService.makeGameSummaryTextFile(game: game, gradeName: gradeName, includeScore: shouldShowScoreInSummary, playerName: playerLookup))
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
            shareItems = [ExportService.gameSummaryText(game: game, gradeName: gradeName, includeScore: shouldShowScoreInSummary, playerName: playerLookup)]
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
