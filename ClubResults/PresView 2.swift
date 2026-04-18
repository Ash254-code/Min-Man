import SwiftUI
import SwiftData

struct PresView: View {
    private struct GradePresentationSection: Identifiable {
        let grade: Grade
        let games: [Game]

        var id: UUID { grade.id }
    }

    @Query(sort: [SortDescriptor(\Game.date, order: .reverse)]) private var games: [Game]
    @Query(sort: [SortDescriptor(\Grade.name)]) private var grades: [Grade]
    @Query(sort: \Player.name) private var players: [Player]   // ✅ ADD

    @State private var selectedPresentationGame: Game?
    @State private var expandedGradeIDs: Set<UUID> = []

    // MARK: - Ordered grades (U9 → A Grade)
    private var orderedGrades: [Grade] {
        orderedGradesForDisplay(grades)
    }

    // Grade lookup helpers
    private var gradeNameByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: orderedGrades.map { ($0.id, $0.name) })
    }

    private var gradeOrderIndex: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: orderedGrades.enumerated().map { ($1.id, $0) })
    }

    // MARK: - Last 5 days filter
    private var lastFiveDaysGames: [Game] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -4, to: cal.startOfDay(for: Date())) ?? Date()
        return games.filter { $0.date >= start }
    }

    // MARK: - Sorted by grade order (U9 first → A Grade last)
    private var sortedGames: [Game] {
        lastFiveDaysGames.sorted {
            let g1 = gradeOrderIndex[$0.gradeID] ?? 999
            let g2 = gradeOrderIndex[$1.gradeID] ?? 999

            if g1 != g2 { return g1 < g2 }      // grade order first
            return $0.date > $1.date            // newest first within grade
        }
    }

    private var gradeByID: [UUID: Grade] {
        Dictionary(uniqueKeysWithValues: grades.map { ($0.id, $0) })
    }

    private var playerNameByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.name) })
    }

    private var clubConfiguration: ClubConfiguration {
        ClubConfigurationStore.load()
    }

    private var gradeSections: [GradePresentationSection] {
        orderedGrades.compactMap { grade in
            let gradeGames = sortedGames
                .filter { $0.gradeID == grade.id }
                .sorted { $0.date > $1.date }
            guard !gradeGames.isEmpty else { return nil }
            return GradePresentationSection(grade: grade, games: gradeGames)
        }
    }

    private func playerName(for id: UUID?) -> String {
        guard let id else { return "Unknown" }
        return playerNameByID[id] ?? "Unknown"
    }

    private func goalKickerSummary(for game: Game) -> String {
        goalKickerItems(for: game).joined(separator: ", ")
    }

    private func goalKickerItems(for game: Game) -> [String] {
        guard !game.goalKickers.isEmpty else { return ["None recorded"] }
        return game.goalKickers
            .sorted { $0.goals > $1.goals }
            .map { "\(playerName(for: $0.playerID)) \($0.goals)" }
    }

    private func bestPlayersSummary(for game: Game) -> String {
        bestPlayerItems(for: game).joined(separator: " • ")
    }

    private func bestPlayerItems(for game: Game) -> [String] {
        guard !game.bestPlayersRanked.isEmpty else { return ["None recorded"] }
        return game.bestPlayersRanked
            .enumerated()
            .map { index, playerID in "\(index + 1). \(playerNameByID[playerID] ?? "Unknown")" }
    }

    private func normalizedGradeName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isTwoGameGrade(_ gradeID: UUID) -> Bool {
        guard let grade = gradeByID[gradeID] else { return false }
        let normalized = normalizedGradeName(grade.name)
        return normalized == "under 9's" || normalized == "under 12's"
    }

    private func shouldShowScore(for gradeID: UUID) -> Bool {
        guard isTwoGameGrade(gradeID) else { return true }
        return gradeByID[gradeID]?.asksScore ?? true
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Last 5 Days") {
                    if sortedGames.isEmpty {
                        ContentUnavailableView(
                            "No games in the last 5 days",
                            systemImage: "calendar",
                            description: Text("Recent games will appear here.")
                        )
                    } else {
                        ForEach(gradeSections) { section in
                            Button {
                                if expandedGradeIDs.contains(section.id) {
                                    expandedGradeIDs.remove(section.id)
                                } else {
                                    expandedGradeIDs.insert(section.id)
                                }
                            } label: {
                                PresGradeRow(
                                    gradeName: section.grade.name,
                                    gameCount: section.games.count,
                                    isExpanded: expandedGradeIDs.contains(section.id)
                                )
                            }
                            .buttonStyle(.plain)

                            if expandedGradeIDs.contains(section.id) {
                                ForEach(section.games) { game in
                                    Button {
                                        selectedPresentationGame = game
                                    } label: {
                                        PresentationExpandableGameCard(
                                            game: game,
                                            showScore: shouldShowScore(for: section.id),
                                            goalKickers: goalKickerSummary(for: game),
                                            bestPlayers: bestPlayersSummary(for: game)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pres")
            .fullScreenCover(item: $selectedPresentationGame) { game in
                PresentationGameFullScreenView(
                    game: game,
                    gradeName: gradeNameByID[game.gradeID] ?? "Unknown",
                    showScore: shouldShowScore(for: game.gradeID),
                    ourTeamName: clubConfiguration.clubTeam.name,
                    goalKickers: goalKickerItems(for: game),
                    bestPlayers: bestPlayerItems(for: game),
                    clubConfiguration: clubConfiguration
                )
            }
        }
    }
}

private struct PresGradeRow: View {
    let gradeName: String
    let gameCount: Int
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(gradeName)
                .font(.system(size: 20, weight: .bold))
            Spacer()
            Text("\(gameCount) game\(gameCount == 1 ? "" : "s")")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }
}

private struct PresentationExpandableGameCard: View {
    let game: Game
    let showScore: Bool
    let goalKickers: String
    let bestPlayers: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("vs \(game.opponent)")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Text(game.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if showScore {
                Text("Score: \(game.ourGoals).\(game.ourBehinds) (\(game.ourScore)) — \(game.theirGoals).\(game.theirBehinds) (\(game.theirScore))")
                    .font(.system(size: 16, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Goal Kickers")
                    .font(.system(size: 14, weight: .bold))
                Text(goalKickers)
                    .font(.system(size: 14))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Best Players")
                    .font(.system(size: 14, weight: .bold))
                Text(bestPlayers)
                    .font(.system(size: 14))
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PresentationGameFullScreenView: View {
    @Environment(\.dismiss) private var dismiss

    let game: Game
    let gradeName: String
    let showScore: Bool
    let ourTeamName: String
    let goalKickers: [String]
    let bestPlayers: [String]
    let clubConfiguration: ClubConfiguration

    private var ourTeamLabel: String {
        let cleaned = ourTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Our Team" : cleaned
    }

    private var ourScoreline: String {
        "\(game.ourGoals).\(game.ourBehinds) (\(game.ourScore))"
    }

    private var theirScoreline: String {
        "\(game.theirGoals).\(game.theirBehinds) (\(game.theirScore))"
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(gradeName)
                            .font(.system(size: 52, weight: .black))
                            .minimumScaleFactor(0.8)
                        Text("vs \(game.opponent)")
                            .font(.system(size: 36, weight: .bold))
                            .minimumScaleFactor(0.8)
                        Text(game.date.formatted(date: .complete, time: .omitted))
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .center, spacing: 20) {
                        ScorePill(
                            ourTeamLabel,
                            style: ClubStyle.style(for: ourTeamLabel, configuration: clubConfiguration)
                        )
                        .scaleEffect(1.6)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if showScore {
                            HStack(spacing: 18) {
                                Text(ourScoreline)
                                    .font(.system(size: proxy.size.width > 900 ? 72 : 54, weight: .black))
                                    .minimumScaleFactor(0.7)
                                Text("—")
                                    .font(.system(size: proxy.size.width > 900 ? 56 : 42, weight: .heavy))
                                    .foregroundStyle(.secondary)
                                Text(theirScoreline)
                                    .font(.system(size: proxy.size.width > 900 ? 72 : 54, weight: .black))
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        ScorePill(
                            game.opponent,
                            style: ClubStyle.style(for: game.opponent, configuration: clubConfiguration)
                        )
                        .scaleEffect(1.6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.vertical, 8)

                    Divider()

                    HStack(alignment: .top, spacing: 32) {
                        presentationListColumn(title: "Goal Kickers", items: goalKickers)
                        presentationListColumn(title: "Best Players", items: bestPlayers)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(32)
            }
            .background(Color(.systemBackground))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .font(.system(size: 26, weight: .bold))
                }
            }
        }
    }

    @ViewBuilder
    private func presentationListColumn(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 36, weight: .heavy))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        Text(item)
                            .font(.system(size: 32, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
