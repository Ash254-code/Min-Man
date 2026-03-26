import SwiftUI
import SwiftData

struct PresView: View {
    @Query(sort: [SortDescriptor(\Game.date, order: .reverse)]) private var games: [Game]
    @Query(sort: [SortDescriptor(\Grade.name)]) private var grades: [Grade]
    @Query(sort: \Player.name) private var players: [Player]   // ✅ ADD

    @State private var selectedGame: Game?

    // MARK: - Ordered grades (U9 → A Grade)
    private var orderedGrades: [Grade] {
        let active = grades.filter { $0.isActive }
        let nameToGrade = Dictionary(uniqueKeysWithValues: active.map { ($0.name, $0) })

        var result: [Grade] = LockedGradeSeed.orderedGradeNames.compactMap { nameToGrade[$0] }

        let remaining = active
            .filter { !LockedGradeSeed.orderedGradeNames.contains($0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        result.append(contentsOf: remaining)
        return result
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
                        ForEach(sortedGames) { game in
                            Button {
                                selectedGame = game
                            } label: {
                                PresGameRow(
                                    gradeName: gradeNameByID[game.gradeID] ?? "Unknown",
                                    opponent: game.opponent,
                                    date: game.date,
                                    ourScore: "\(game.ourGoals).\(game.ourBehinds) (\(game.ourScore))",
                                    theirScore: "\(game.theirGoals).\(game.theirBehinds) (\(game.theirScore))"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // ⭐ MAIN TITLE = GRADE
            Text(gradeName)
                .font(.system(size: 20, weight: .bold))

            // opponent + date
            HStack {
                Text(opponent)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // scores
            HStack {
                Text("Us: \(ourScore)")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("Them: \(theirScore)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}
