import SwiftUI
import SwiftData

struct TotalsView: View {
    @Query private var grades: [Grade]
    @Query(sort: \Player.name) private var players: [Player]
    @Query(sort: \Game.date) private var games: [Game]

    // nil = All Grades
    @State private var selectedGradeID: UUID?

    private var orderedGrades: [Grade] {
        orderedGradesForDisplay(grades)
    }

    private var defaultGradeID: UUID? {
        if let a = orderedGrades.first(where: { $0.name == "A Grade" }) { return a.id }
        return orderedGrades.first?.id
    }

    private var filteredGames: [Game] {
        guard let gid = selectedGradeID else { return games } // All
        return games.filter { $0.gradeID == gid }
    }

    // ✅ Leaderboards pill text includes selected grade
    private var leaderboardTitle: String {
        if let gid = selectedGradeID,
           let grade = orderedGrades.first(where: { $0.id == gid }) {
            return "\(grade.name) Leaderboards"
        } else {
            return "Leaderboards"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // ✅ Leaderboards header (club colours + centred + includes grade)
                HStack {
                    Spacer()
                    ClubPill(text: leaderboardTitle, bg: ClubTheme.navy, fg: ClubTheme.yellow)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                // Best Player (glass card)
                leaderboardCard(title: "Best Player", rows: topBestPlayers())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                // Guest Votes (glass card)
                leaderboardCard(title: "Guest Votes", rows: topGuestVotes())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                // Goal Kickers (glass card)
                leaderboardCard(title: "Goal Kickers", rows: topGoalKickers())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)

            // ✅ custom title row (Totals + grade pill)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.large)

            .toolbar {
                // ✅ TRUE left-aligned title + pill (hard left)
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Text("Totals")
                            .font(.largeTitle.weight(.bold))
                            .fixedSize()

                        FilteredGradeTitle(
                            selectedGradeID: selectedGradeID,
                            grades: orderedGrades
                        )
                        .fixedSize()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    // ✅ Top-right filter button
                    GradeFilterButton(
                        grades: orderedGrades,
                        selectedGradeID: $selectedGradeID,
                        includeAll: true,
                        iconOnly: true
                    )
                }
            }
            .onAppear {
                // Default to A Grade (or first active grade) if nothing selected yet
                if selectedGradeID == nil {
                    selectedGradeID = defaultGradeID
                }
            }
        }
    }
}

// MARK: - Club pill (used for the Leaderboards header)

private struct ClubPill: View {
    let text: String
    let bg: Color
    let fg: Color

    var body: some View {
        Text(text)
            .font(.headline.weight(.semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous).fill(bg)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .textCase(nil)
    }
}

// MARK: - Helper UI + Calculations

private extension TotalsView {

    struct LeaderRow: Identifiable {
        let id = UUID()
        let rank: Int
        let name: String
        let valueText: String
    }

    // Large header pill used INSIDE each leaderboard card (club colours)
    func bigPillHeader(_ text: String) -> some View {
        Text(text)
            .font(.headline.weight(.semibold))
            .foregroundStyle(ClubTheme.yellow)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(ClubTheme.navy)
            )
            .textCase(nil)
    }

    func medal(for rank: Int) -> String {
        switch rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return "\(rank)"
        }
    }

    @ViewBuilder
    func leaderboardCard(title: String, rows: [LeaderRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {

            bigPillHeader(title)

            if rows.isEmpty {
                Text("No data yet.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                let top = Array(rows.prefix(3))
                ForEach(top) { row in
                    HStack(spacing: 10) {
                        Text(medal(for: row.rank))
                            .frame(width: 28, alignment: .leading)

                        Text(row.name)
                            .lineLimit(1)

                        Spacer()

                        Text(row.valueText)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)

                    if row.id != top.last?.id {
                        Divider().opacity(0.25)
                    }
                }
            }
        }
        .premiumGlassCard()      // ✅ premium glass everywhere
        .padding(.vertical, 2)   // spacing between cards
    }

    func playerName(for id: UUID) -> String {
        players.first(where: { $0.id == id })?.name ?? "Unknown"
    }

    // Best Player leaderboard:
    // 1st=3 pts, 2nd=2 pts, 3rd=1 pt per game
    func topBestPlayers() -> [LeaderRow] {
        var points: [UUID: Int] = [:]

        for g in filteredGames {
            let ranked = Array(g.bestPlayersRanked.prefix(3))
            for (idx, pid) in ranked.enumerated() {
                let add: Int
                switch idx {
                case 0: add = 3
                case 1: add = 2
                case 2: add = 1
                default: add = 0
                }
                points[pid, default: 0] += add
            }
        }

        let sorted = points
            .sorted { a, b in
                if a.value != b.value { return a.value > b.value }
                return playerName(for: a.key)
                    .localizedCaseInsensitiveCompare(playerName(for: b.key)) == .orderedAscending
            }
            .prefix(3)

        return sorted.enumerated().map { i, item in
            LeaderRow(rank: i + 1, name: playerName(for: item.key), valueText: "\(item.value) pts")
        }
    }

    // Goal Kickers leaderboard: sum goals across games
    func topGoalKickers() -> [LeaderRow] {
        var totals: [UUID: Int] = [:]

        for g in filteredGames {
            for entry in g.goalKickers {
                if let pid = entry.playerID {
                    totals[pid, default: 0] += entry.goals
                }
            }
        }

        let sorted = totals
            .sorted { a, b in
                if a.value != b.value { return a.value > b.value }
                return playerName(for: a.key)
                    .localizedCaseInsensitiveCompare(playerName(for: b.key)) == .orderedAscending
            }
            .prefix(3)

        return sorted.enumerated().map { i, item in
            LeaderRow(rank: i + 1, name: playerName(for: item.key), valueText: "\(item.value)")
        }
    }

    // Guest Votes leaderboard:
    // 1st=3 pts, 2nd=2 pts, 3rd=1 pt per game
    func topGuestVotes() -> [LeaderRow] {
        var points: [UUID: Int] = [:]

        for game in filteredGames {
            for vote in game.guestVotesRanked {
                let add: Int
                switch vote.rank {
                case 1: add = 3
                case 2: add = 2
                case 3: add = 1
                default: add = 0
                }
                points[vote.playerID, default: 0] += add
            }
        }

        let sorted = points
            .sorted { a, b in
                if a.value != b.value { return a.value > b.value }
                return playerName(for: a.key)
                    .localizedCaseInsensitiveCompare(playerName(for: b.key)) == .orderedAscending
            }
            .prefix(3)

        return sorted.enumerated().map { i, item in
            LeaderRow(rank: i + 1, name: playerName(for: item.key), valueText: "\(item.value) pts")
        }
    }
}
