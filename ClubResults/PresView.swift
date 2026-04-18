import SwiftUI
import SwiftData

struct PresView: View {
    private struct PresListItem: Identifiable {
        let primary: Game
        let secondary: Game?
        let showsScore: Bool

        var id: UUID { primary.id }
        var hasTwoGames: Bool { secondary != nil }
    }

    @Query(sort: [SortDescriptor(\Game.date, order: .reverse)]) private var games: [Game]
    @Query(sort: [SortDescriptor(\Grade.name)]) private var grades: [Grade]
    @Query(sort: \Player.name) private var players: [Player]   // ✅ ADD

    @State private var selectedGame: Game?

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

    private var displayItems: [PresListItem] {
        var result: [PresListItem] = []
        var used = Set<UUID>()

        for game in sortedGames {
            guard !used.contains(game.id) else { continue }
            if isTwoGameGrade(game.gradeID),
               let partner = sortedGames.first(where: { candidate in
                   candidate.id != game.id &&
                   !used.contains(candidate.id) &&
                   arePairedTwoGames(game, candidate)
               }) {
                let ordered = [game, partner].sorted { $0.id.uuidString < $1.id.uuidString }
                result.append(PresListItem(primary: ordered[0], secondary: ordered[1], showsScore: shouldShowScore(for: game.gradeID)))
                used.insert(game.id)
                used.insert(partner.id)
            } else {
                result.append(PresListItem(primary: game, secondary: nil, showsScore: shouldShowScore(for: game.gradeID)))
                used.insert(game.id)
            }
        }
        return result
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

    private func normalizedGoalKickerSignature(_ game: Game) -> [String] {
        game.goalKickers
            .map { "\($0.playerID?.uuidString ?? "nil"):\($0.goals)" }
            .sorted()
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
                        ForEach(displayItems) { item in
                            let game = item.primary
                            Button {
                                selectedGame = game
                            } label: {
                                PresGameRow(
                                    gradeName: gradeNameByID[game.gradeID] ?? "Unknown",
                                    opponent: game.opponent,
                                    date: game.date,
                                    ourScore: "\(game.ourGoals).\(game.ourBehinds) (\(game.ourScore))",
                                    theirScore: "\(game.theirGoals).\(game.theirBehinds) (\(game.theirScore))",
                                    showScore: item.showsScore,
                                    hasTwoGames: item.hasTwoGames
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Pres")
            .sheet(item: $selectedGame) { game in
                // ✅ FIX: pass grades + players
                GameDetailView(game: game, grades: orderedGrades, players: players)
                    .appPopupStyle()
            }
        }
    }
}

// MARK: - Row (GRADE IS MOST PROMINENT)
private struct PresGameRow: View {
    let gradeName: String
    let opponent: String
    let date: Date
    let ourScore: String
    let theirScore: String
    let showScore: Bool
    let hasTwoGames: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // ⭐ MAIN TITLE = GRADE
            Text(gradeName)
                .font(.system(size: 20, weight: .bold))

            // opponent + date
            HStack {
                Text(opponent)
                    .font(.system(size: 16, weight: .semibold))
                if hasTwoGames {
                    Text("• Two games")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if showScore {
                HStack {
                    Text("Us: \(ourScore)")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("Them: \(theirScore)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 10)
    }
}
