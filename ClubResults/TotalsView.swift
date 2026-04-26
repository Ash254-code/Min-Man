import SwiftUI
import SwiftData

struct TotalsView: View {
    @Query private var grades: [Grade]
    @Query(sort: \Player.name) private var players: [Player]
    @Query(sort: \Game.date) private var games: [Game]

    @State private var selectedGradeIDs: Set<UUID> = []
    @State private var includeAllGrades = false
    @State private var showFilterSheet = false
    @State private var topCount: TopCountOption = .top3
    @State private var combineAllGrades = false

    private enum TopCountOption: String, CaseIterable, Identifiable {
        case top3 = "Top 3"
        case top5 = "Top 5"
        case top10 = "Top 10"
        case all = "All"

        var id: String { rawValue }
        var limit: Int? {
            switch self {
            case .top3: return 3
            case .top5: return 5
            case .top10: return 10
            case .all: return nil
            }
        }
    }

    private var orderedGrades: [Grade] {
        orderedGradesForDisplay(grades)
    }

    private var defaultGradeID: UUID? {
        if let a = orderedGrades.first(where: { $0.name == "A Grade" }) { return a.id }
        return orderedGrades.first?.id
    }

    private var effectiveGradeIDs: Set<UUID> {
        if includeAllGrades || selectedGradeIDs.isEmpty {
            return Set(orderedGrades.map(\.id))
        }
        return selectedGradeIDs
    }

    private var shouldShowCombineToggle: Bool {
        effectiveGradeIDs.count > 1
    }

    private var displayGroups: [LeaderboardGroup] {
        let allSections = ["Best Player", "Guest Votes", "Best & Fairest", "Goal Kickers"]

        if combineAllGrades || effectiveGradeIDs.count <= 1 {
            let selectedName: String
            if includeAllGrades || effectiveGradeIDs.count > 1 {
                selectedName = "Leaderboards"
            } else if let first = effectiveGradeIDs.first,
                      let grade = orderedGrades.first(where: { $0.id == first }) {
                selectedName = "\(grade.name) Leaderboards"
            } else {
                selectedName = "Leaderboards"
            }

            let sections = allSections.map { section in
                (title: section, rows: rows(for: section, gradeIDs: effectiveGradeIDs))
            }
            return [LeaderboardGroup(title: selectedName, sections: sections)]
        }

        return orderedGrades
            .filter { effectiveGradeIDs.contains($0.id) }
            .map { grade in
                let gradeIDs: Set<UUID> = [grade.id]
                let sections = allSections.map { section in
                    (title: section, rows: rows(for: section, gradeIDs: gradeIDs))
                }
                return LeaderboardGroup(title: "\(grade.name) Leaderboards", sections: sections)
            }
    }

    private struct LeaderboardGroup: Identifiable {
        let id = UUID()
        let title: String
        let sections: [(title: String, rows: [LeaderRow])]
    }

    private func rows(for section: String, gradeIDs: Set<UUID>) -> [LeaderRow] {
        switch section {
        case "Best Player": return topBestPlayers(in: gradeIDs)
        case "Guest Votes": return topGuestVotes(in: gradeIDs)
        case "Best & Fairest": return topBestAndFairest(in: gradeIDs)
        case "Goal Kickers": return topGoalKickers(in: gradeIDs)
        default: return []
        }
    }

    private func filteredGames(in gradeIDs: Set<UUID>) -> [Game] {
        guard !gradeIDs.isEmpty else { return games }
        return games.filter { gradeIDs.contains($0.gradeID) }
    }

    private func constrained(_ rows: [LeaderRow], sectionTitle: String) -> [LeaderRow] {
        if sectionTitle == "Goal Kickers" {
            return Array(rows.prefix(5))
        }
        guard let limit = topCount.limit else { return rows }
        return Array(rows.prefix(limit))
    }

    private func toggleGradeSelection(_ gradeID: UUID) {
        includeAllGrades = false

        if selectedGradeIDs.contains(gradeID) {
            selectedGradeIDs.remove(gradeID)
        } else {
            selectedGradeIDs.insert(gradeID)
        }

        if selectedGradeIDs.isEmpty {
            includeAllGrades = true
        }
    }

    private func isGradeSelected(_ gradeID: UUID) -> Bool {
        includeAllGrades || selectedGradeIDs.contains(gradeID)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height
                let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: isLandscape ? 2 : 1)

                ScrollView {
                    LazyVStack(spacing: 18) {
                        ForEach(displayGroups) { group in
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Spacer()
                                    ClubPill(text: group.title, bg: ClubTheme.navy, fg: ClubTheme.yellow)
                                    Spacer()
                                }

                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(Array(group.sections.enumerated()), id: \.offset) { _, section in
                                        leaderboardCard(title: section.title, rows: section.rows)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .background(Color.clear)

            .navigationTitle("")
            .navigationBarTitleDisplayMode(.large)

            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Text("Totals")
                            .font(.largeTitle.weight(.bold))
                            .fixedSize()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilterSheet = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Open filters")
                }
            }
            .onAppear {
                if selectedGradeIDs.isEmpty, !includeAllGrades,
                   let defaultGradeID {
                    selectedGradeIDs = [defaultGradeID]
                }
            }
            .overlay {
                if showFilterSheet {
                    filterOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(2)
                }
            }
        }
    }

    private var filterOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { showFilterSheet = false }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Filters")
                        .font(.system(size: 40, weight: .bold))
                    Spacer()
                    Button("Done") { showFilterSheet = false }
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Grades")
                    UniformPillGrid {
                        filterPill(
                            title: "All",
                            isSelected: includeAllGrades,
                            action: {
                                includeAllGrades = true
                                selectedGradeIDs.removeAll()
                            }
                        )

                        ForEach(orderedGrades, id: \.id) { grade in
                            filterPill(
                                title: grade.name,
                                isSelected: isGradeSelected(grade.id),
                                action: { toggleGradeSelection(grade.id) }
                            )
                        }
                    }
                }
                .panelSection()

                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Show")
                    UniformPillGrid {
                        ForEach(TopCountOption.allCases) { option in
                            filterPill(
                                title: option.rawValue,
                                isSelected: topCount == option,
                                action: { topCount = option }
                            )
                        }
                    }
                }
                .panelSection()

                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Layout")
                    Toggle("Combine All Grades", isOn: $combineAllGrades)
                        .toggleStyle(.switch)
                        .font(.headline)
                        .disabled(!shouldShowCombineToggle)
                        .opacity(shouldShowCombineToggle ? 1 : 0.45)
                    if !shouldShowCombineToggle {
                        Text("Select 2 or more grades to enable.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .panelSection()
            }
            .padding(24)
            .frame(maxWidth: 880)
            .frame(height: 560)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
            .padding(24)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.bold))
    }

    @ViewBuilder
    private func filterPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.blue : Color.gray.opacity(0.22))
                )
        }
        .buttonStyle(.plain)
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

            let visibleRows = constrained(rows, sectionTitle: title)

            if visibleRows.isEmpty {
                Text("No data yet.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(visibleRows) { row in
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

                    if row.id != visibleRows.last?.id {
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

    func grade(for id: UUID) -> Grade? {
        grades.first(where: { $0.id == id })
    }

    func bestPlayersPoints(for game: Game, rankIndex: Int) -> Int {
        guard let grade = grade(for: game.gradeID) else {
            return Grade.normalizedVotes(nil, count: 6)[safe: rankIndex] ?? 0
        }
        return grade.bestPlayersVotes[safe: rankIndex] ?? 0
    }

    func guestBestPlayersPoints(for game: Game, rank: Int) -> Int {
        guard let grade = grade(for: game.gradeID) else {
            return Grade.normalizedGuestVotes(nil, count: 3)[safe: rank - 1] ?? 0
        }
        return grade.guestBestPlayersVotes[safe: rank - 1] ?? 0
    }

    // Best Player leaderboard:
    func topBestPlayers(in gradeIDs: Set<UUID>) -> [LeaderRow] {
        var points: [UUID: Int] = [:]

        for g in filteredGames(in: gradeIDs) {
            let ranked = Array(g.bestPlayersRanked.prefix(10))
            for (idx, pid) in ranked.enumerated() {
                points[pid, default: 0] += bestPlayersPoints(for: g, rankIndex: idx)
            }
        }

        let sorted = points
            .sorted { a, b in
                if a.value != b.value { return a.value > b.value }
                return playerName(for: a.key)
                    .localizedCaseInsensitiveCompare(playerName(for: b.key)) == .orderedAscending
            }

        return sorted.enumerated().map { i, item in
            LeaderRow(rank: i + 1, name: playerName(for: item.key), valueText: "\(item.value) votes")
        }
    }

    // Goal Kickers leaderboard: sum goals and points (behinds) across games
    func topGoalKickers(in gradeIDs: Set<UUID>) -> [LeaderRow] {
        var totals: [UUID: (goals: Int, points: Int)] = [:]

        for g in filteredGames(in: gradeIDs) {
            for entry in g.goalKickers {
                if let pid = entry.playerID {
                    totals[pid, default: (goals: 0, points: 0)].goals += entry.goals
                    totals[pid, default: (goals: 0, points: 0)].points += entry.points
                }
            }
        }

        let sorted = totals
            .sorted { a, b in
                if a.value.goals != b.value.goals { return a.value.goals > b.value.goals }
                if a.value.points != b.value.points { return a.value.points > b.value.points }
                return playerName(for: a.key)
                    .localizedCaseInsensitiveCompare(playerName(for: b.key)) == .orderedAscending
            }

        return sorted.enumerated().map { i, item in
            LeaderRow(
                rank: i + 1,
                name: playerName(for: item.key),
                valueText: "\(item.value.goals).\(item.value.points)"
            )
        }
    }

    // Guest Votes leaderboard:
    func topGuestVotes(in gradeIDs: Set<UUID>) -> [LeaderRow] {
        var points: [UUID: Int] = [:]

        for game in filteredGames(in: gradeIDs) {
            for vote in game.guestVotesRanked {
                points[vote.playerID, default: 0] += guestBestPlayersPoints(for: game, rank: vote.rank)
            }
        }

        let sorted = points
            .sorted { a, b in
                if a.value != b.value { return a.value > b.value }
                return playerName(for: a.key)
                    .localizedCaseInsensitiveCompare(playerName(for: b.key)) == .orderedAscending
            }

        return sorted.enumerated().map { i, item in
            LeaderRow(rank: i + 1, name: playerName(for: item.key), valueText: "\(item.value) votes")
        }
    }

    // Best & Fairest leaderboard:
    // Combines Best Player points + Guest Votes points
    func topBestAndFairest(in gradeIDs: Set<UUID>) -> [LeaderRow] {
        var points: [UUID: Int] = [:]

        // Best Player points
        for game in filteredGames(in: gradeIDs) {
            let ranked = Array(game.bestPlayersRanked.prefix(10))
            for (idx, pid) in ranked.enumerated() {
                points[pid, default: 0] += bestPlayersPoints(for: game, rankIndex: idx)
            }
        }

        // Guest Votes points
        for game in filteredGames(in: gradeIDs) {
            for vote in game.guestVotesRanked {
                points[vote.playerID, default: 0] += guestBestPlayersPoints(for: game, rank: vote.rank)
            }
        }

        let sorted = points
            .sorted { a, b in
                if a.value != b.value { return a.value > b.value }
                return playerName(for: a.key)
                    .localizedCaseInsensitiveCompare(playerName(for: b.key)) == .orderedAscending
            }

        return sorted.enumerated().map { i, item in
            LeaderRow(rank: i + 1, name: playerName(for: item.key), valueText: "\(item.value) votes")
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

private struct UniformPillGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 130, maximum: 130), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func panelSection() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}
