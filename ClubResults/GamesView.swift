import SwiftUI
import SwiftData
import UIKit

struct GamesView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigationState: AppNavigationState

    private let clubConfiguration = ClubConfigurationStore.load()

    private struct RoundGroup: Identifiable {
        let id: String
        let roundNumber: Int
        let date: Date
        let opponent: String
        let games: [Game]
    }

    fileprivate enum RoundOutcome {
        case win
        case draw
        case loss

        var label: String {
            switch self {
            case .win: return "W"
            case .draw: return "D"
            case .loss: return "L"
            }
        }
    }

    fileprivate struct RoundOutcomePillItem: Identifiable {
        let gradeID: UUID
        let gradeName: String
        let outcome: RoundOutcome?

        var id: UUID { gradeID }
    }

    private struct GameListItem: Identifiable {
        let primary: Game
        let secondary: Game?

        var id: UUID { primary.id }
        var hasTwoGames: Bool { secondary != nil }
    }

    fileprivate struct CompletionFieldStatus: Identifiable {
        let title: String
        let isComplete: Bool

        var id: String { title }
    }

    fileprivate struct IncompleteGradeStatusDetails: Identifiable {
        let gradeName: String
        let fields: [CompletionFieldStatus]

        var id: String { gradeName }
    }

    enum QuickStartGradeStatus {
        case noGameSaved
        case draftOnly
        case liveInProgress
        case gameSaved

        // Backward-compatible aliases for previously used naming.
        static let noneRecent: Self = .noGameSaved
        static let inProgressDraft: Self = .draftOnly
        static let finalizedRecent: Self = .gameSaved

        var color: Color {
            switch self {
            case .noGameSaved: return .secondary
            case .draftOnly: return .orange
            case .liveInProgress: return .orange
            case .gameSaved: return .green
            @unknown default: return .secondary
            }
        }
    }

    private struct NewGameWizardPresentation: Identifiable {
        let id = UUID()
        let initialGradeID: UUID?
        let draftGameID: UUID?
        let reopenLiveView: Bool
    }

    private struct GameEditPresentation: Identifiable {
        let primary: Game
        let secondary: Game?

        var id: UUID { primary.id }
    }

    private enum DraftResumeStore {
        private static let openLivePrefix = "resume.openLive."

        static func shouldOpenLive(for gradeID: UUID) -> Bool {
            UserDefaults.standard.bool(forKey: openLivePrefix + gradeID.uuidString)
        }

        static func setShouldOpenLive(_ shouldOpen: Bool, for gradeID: UUID) {
            UserDefaults.standard.set(shouldOpen, forKey: openLivePrefix + gradeID.uuidString)
        }
    }

    @Query(sort: [SortDescriptor(\Game.date, order: .reverse)]) private var games: [Game]
    @Query(sort: [SortDescriptor(\Grade.name)]) private var grades: [Grade]
    @Query(sort: \Player.name) private var players: [Player]

    @State private var selectedGradeID: UUID? = nil
    @State private var newGameWizardPresentation: NewGameWizardPresentation?
    @State private var selectedGameForSummary: Game?
    @State private var selectedGameForEdit: GameEditPresentation?
    @State private var selectedIncompleteGradeStatus: IncompleteGradeStatusDetails?
    @State private var selectedRoundID: String?
    @State private var gamePendingDelete: Game?
    @State private var codePromptGame: Game?
    @State private var codePromptValue = ""
    @State private var showCodePrompt = false
    @State private var showWrongCodeAlert = false
    @State private var showDeleteConfirmAlert = false
    @State private var pendingProtectedAction: ProtectedGameAction?
    @State private var showPresentationView = false

    private enum ProtectedGameAction {
        case edit
        case delete
    }

    private var isIPhoneAdminLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && navigationState.currentRole == .admin
    }


    // MARK: - Ordered grades (your seeded order + remaining A→Z)
    private var orderedGrades: [Grade] {
        // Show all configured grades (including ones marked inactive) so rebuilt club
        // grade lists still expose quick-start buttons immediately.
        orderedGradesForDisplay(resolvedConfiguredGrades(from: grades), includeInactive: true)
    }

    private var gradeNameByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: orderedGrades.map { ($0.id, $0.name) })
    }

    private var selectedGradeName: String {
        guard let gid = selectedGradeID else { return "All" }
        return gradeNameByID[gid] ?? "All"
    }

    private var filteredGames: [Game] {
        let base = visibleGames.sorted { $0.date > $1.date }
        guard let gid = selectedGradeID else { return base }
        return base.filter { $0.gradeID == gid }
    }

    private var visibleGames: [Game] {
        if navigationState.currentRole.canEditGames {
            return games
        }

        return games.filter { !$0.isDraft }
    }

    private var gradeByID: [UUID: Grade] {
        Dictionary(uniqueKeysWithValues: grades.map { ($0.id, $0) })
    }

    private var playerIDs: Set<UUID> {
        Set(players.map(\.id))
    }

    private func gameListItems(from sourceGames: [Game]) -> [GameListItem] {
        var result: [GameListItem] = []
        var used = Set<UUID>()

        for game in sourceGames {
            guard !used.contains(game.id) else { continue }

            if isTwoGameGrade(for: game.gradeID),
               let partner = sourceGames.first(where: { candidate in
                   candidate.id != game.id &&
                   !used.contains(candidate.id) &&
                   arePairedTwoGames(game, candidate)
               }) {
                let ordered = [game, partner].sorted { $0.id.uuidString < $1.id.uuidString }
                result.append(GameListItem(primary: ordered[0], secondary: ordered[1]))
                used.insert(game.id)
                used.insert(partner.id)
            } else {
                result.append(GameListItem(primary: game, secondary: nil))
                used.insert(game.id)
            }
        }

        return result
    }

    private var roundGroups: [RoundGroup] {
        let sortedChronological = filteredGames.sorted { $0.date < $1.date }
        guard !sortedChronological.isEmpty else { return [] }

        struct RoundBucket {
            var id: String
            var opponentKey: String
            var opponentLabel: String
            var anchorDate: Date
            var games: [Game]
        }

        var buckets: [RoundBucket] = []
        let matchingWindow: TimeInterval = 60 * 60 * 24 * 3

        for game in sortedChronological {
            let opponentKey = game.opponent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let index = buckets.firstIndex(where: { bucket in
                bucket.opponentKey == opponentKey &&
                abs(bucket.anchorDate.timeIntervalSince(game.date)) <= matchingWindow
            }) {
                buckets[index].games.append(game)
                let sortedDates = buckets[index].games.map(\.date).sorted()
                buckets[index].anchorDate = sortedDates[sortedDates.count / 2]
            } else {
                let dayKey = Calendar.current.startOfDay(for: game.date).timeIntervalSince1970
                buckets.append(
                    RoundBucket(
                        id: "\(opponentKey)|\(Int(dayKey))",
                        opponentKey: opponentKey,
                        opponentLabel: game.opponent,
                        anchorDate: game.date,
                        games: [game]
                    )
                )
            }
        }

        let chronologicalRounds = buckets
            .map { bucket in
                (
                    id: bucket.id,
                    date: bucket.games.map(\.date).max() ?? bucket.anchorDate,
                    opponent: bucket.opponentLabel,
                    games: bucket.games.sorted { $0.date > $1.date }
                )
            }
            .sorted { $0.date < $1.date }

        return chronologicalRounds
            .enumerated()
            .map { idx, round in
                RoundGroup(
                    id: round.id,
                    roundNumber: idx + 1,
                    date: round.date,
                    opponent: round.opponent,
                    games: round.games
                )
            }
            .sorted { $0.date > $1.date }
    }

    private var selectedRound: RoundGroup? {
        roundGroups.first(where: { $0.id == selectedRoundID })
    }

    private func roundGamesByGrade(for round: RoundGroup) -> [(grade: Grade, items: [GameListItem])] {
        orderedGrades.compactMap { grade in
            let gamesInGrade = round.games.filter { $0.gradeID == grade.id }
            guard !gamesInGrade.isEmpty else { return nil }
            return (grade, gameListItems(from: gamesInGrade.sorted { $0.date > $1.date }))
        }
    }

    private func roundDateLabel(for round: RoundGroup) -> String {
        round.date.formatted(date: .abbreviated, time: .omitted)
    }

    private func roundOutcomePills(for round: RoundGroup) -> [RoundOutcomePillItem] {
        orderedGrades.compactMap { grade in
            guard grade.asksScore else { return nil }

            let gamesInGrade = round.games
                .filter { $0.gradeID == grade.id }
                .sorted { $0.date > $1.date }

            guard let game = gamesInGrade.first else {
                return RoundOutcomePillItem(
                    gradeID: grade.id,
                    gradeName: grade.name,
                    outcome: nil
                )
            }

            let ourScore = game.ourGoals * 6 + game.ourBehinds
            let theirScore = game.theirGoals * 6 + game.theirBehinds
            let outcome: RoundOutcome
            if ourScore > theirScore {
                outcome = .win
            } else if ourScore < theirScore {
                outcome = .loss
            } else {
                outcome = .draw
            }

            return RoundOutcomePillItem(
                gradeID: grade.id,
                gradeName: grade.name,
                outcome: outcome
            )
        }
    }

    private func latestDraft(for gradeID: UUID) -> Game? {
        games
            .filter { $0.gradeID == gradeID && $0.isDraft }
            .sorted { $0.date > $1.date }
            .first
    }

    private func gradeStatus(for gradeID: UUID) -> QuickStartGradeStatus {
        if latestDraft(for: gradeID) != nil, DraftResumeStore.shouldOpenLive(for: gradeID) {
            return .liveInProgress
        }

        if latestDraft(for: gradeID) != nil {
            return .draftOnly
        }

        let calendar = Calendar.current
        let now = Date()
        let hasRecentFinalized = games.contains { game in
            game.gradeID == gradeID &&
            !game.isDraft &&
            calendar.isDate(game.date, inSameDayAs: now)
        }
        return hasRecentFinalized ? .gameSaved : .noGameSaved
    }

    private var outcomeGradeHeaders: [String] {
        orderedGrades
            .filter(\.asksScore)
            .map(\.name)
    }

    private var standardPillWidth: CGFloat {
        ClubStyle.standardPillWidth(configuration: ClubConfigurationStore.load())
    }

    private func normalizedGradeName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isTwoGameGrade(for gradeID: UUID) -> Bool {
        guard let grade = gradeByID[gradeID] else { return false }
        let normalized = normalizedGradeName(grade.name)
        return normalized == "under 9's" || normalized == "under 12's"
    }

    private var showsExpandedRoundCompletionIndicator: Bool {
        navigationState.currentRole == .admin || navigationState.currentRole == .restrictedAdmin
    }

    private func requiredBestPlayersCount(for grade: Grade) -> Int {
        min(max(grade.bestPlayersCount, 0), 10)
    }

    private func requiredGuestVotesCount(for grade: Grade) -> Int {
        guard grade.asksGuestBestFairestVotesScan else { return 0 }
        return min(max(grade.guestBestPlayersCount, 0), 10)
    }

    private func hasRequiredBestPlayers(for game: Game, grade: Grade) -> Bool {
        let requiredCount = requiredBestPlayersCount(for: grade)
        guard requiredCount > 0 else { return true }

        let playerIDs = Array(game.bestPlayersRanked.prefix(requiredCount))
        return playerIDs.count == requiredCount
            && Set(playerIDs).count == requiredCount
            && playerIDs.allSatisfy(self.playerIDs.contains)
    }

    private func hasRequiredGuestVotes(for game: Game, grade: Grade) -> Bool {
        let requiredCount = requiredGuestVotesCount(for: grade)
        guard requiredCount > 0 else { return true }

        let votes = Array(game.guestVotesRanked.prefix(requiredCount))
        let playerIDs = votes.map(\.playerID)
        return votes.count == requiredCount
            && Set(playerIDs).count == requiredCount
            && playerIDs.allSatisfy(self.playerIDs.contains)
    }

    private func hasTextValue(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func requiredTrainerCount(for grade: Grade) -> Int {
        [
            grade.asksTrainer1,
            grade.asksTrainer2,
            grade.asksTrainer3,
            grade.asksTrainer4
        ].filter { $0 }.count
    }

    private func isHomeGame(_ game: Game) -> Bool {
        let selectedVenue = game.venue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !selectedVenue.isEmpty else { return false }
        return clubConfiguration.clubTeam.sanitizedVenues
            .map { $0.lowercased() }
            .contains(selectedVenue)
    }

    private func requiresFieldUmpire(for game: Game, grade: Grade) -> Bool {
        grade.asksFieldUmpire && isHomeGame(game)
    }

    private func hasRequiredStaffFields(for game: Game, grade: Grade) -> Bool {
        if grade.asksHeadCoach && !hasTextValue(game.headCoachName) { return false }
        if grade.asksAssistantCoach && !hasTextValue(game.assistantCoachName) { return false }
        if grade.asksTeamManager && !hasTextValue(game.teamManagerName) { return false }
        if grade.asksRunner && !hasTextValue(game.runnerName) { return false }
        if grade.asksGoalUmpire && !hasTextValue(game.goalUmpireName) { return false }
        if grade.asksTimeKeeper && !hasTextValue(game.timeKeeperName) { return false }
        if requiresFieldUmpire(for: game, grade: grade) && !hasTextValue(game.fieldUmpireName) { return false }
        if grade.asksBoundaryUmpire1 && !hasTextValue(game.boundaryUmpire1Name) { return false }
        if grade.asksBoundaryUmpire2 && !hasTextValue(game.boundaryUmpire2Name) { return false }
        if grade.asksWaterBoy1 && !hasTextValue(game.waterBoy1Name) { return false }
        if grade.asksWaterBoy2 && !hasTextValue(game.waterBoy2Name) { return false }
        if grade.asksWaterBoy3 && !hasTextValue(game.waterBoy3Name) { return false }
        if grade.asksWaterBoy4 && !hasTextValue(game.waterBoy4Name) { return false }

        let completedTrainerCount = game.trainers.filter(hasTextValue).count
        return completedTrainerCount >= requiredTrainerCount(for: grade)
    }

    private func hasRequiredNotes(for game: Game, grade: Grade) -> Bool {
        guard grade.asksNotes else { return true }
        return hasTextValue(game.notes)
    }

    private func hasRequiredGoalKickers(for game: Game, grade: Grade) -> Bool {
        guard grade.asksGoalKickers else { return true }
        guard game.ourGoals > 0 else { return true }

        let validEntries = game.goalKickers.filter { entry in
            entry.goals > 0 && entry.playerID.map(playerIDs.contains) == true
        }
        let totalGoals = validEntries.reduce(0) { $0 + $1.goals }
        return totalGoals == game.ourGoals
    }

    private func isGameComplete(_ game: Game, grade: Grade) -> Bool {
        hasRequiredStaffFields(for: game, grade: grade)
            && hasRequiredNotes(for: game, grade: grade)
            && hasRequiredGoalKickers(for: game, grade: grade)
            && hasRequiredBestPlayers(for: game, grade: grade)
            && hasRequiredGuestVotes(for: game, grade: grade)
    }

    private func isExpandedRoundComplete(for grade: Grade, items: [GameListItem]) -> Bool {
        items.allSatisfy { item in
            isGameComplete(item.primary, grade: grade)
                && (item.secondary.map { isGameComplete($0, grade: grade) } ?? true)
        }
    }

    @ViewBuilder
    private func gradeCompletionIcon(isComplete: Bool, grade: Grade, items: [GameListItem]) -> some View {
        if isComplete {
            RoundCompletionIcon(isComplete: true)
                .accessibilityLabel("\(grade.name) complete")
        } else {
            Button {
                selectedIncompleteGradeStatus = IncompleteGradeStatusDetails(
                    gradeName: grade.name,
                    fields: completionFieldStatuses(for: grade, items: items)
                )
            } label: {
                RoundCompletionIcon(isComplete: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(grade.name) incomplete")
        }
    }

    private func completionFieldStatuses(for grade: Grade, items: [GameListItem]) -> [CompletionFieldStatus] {
        var fields: [CompletionFieldStatus] = []

        if grade.asksHeadCoach {
            fields.append(makeCompletionFieldStatus(title: "Head Coach", items: items) { hasTextValue($0.headCoachName) })
        }
        if grade.asksAssistantCoach {
            fields.append(makeCompletionFieldStatus(title: "Assistant Coach", items: items) { hasTextValue($0.assistantCoachName) })
        }
        if grade.asksTeamManager {
            fields.append(makeCompletionFieldStatus(title: "Team Manager", items: items) { hasTextValue($0.teamManagerName) })
        }
        if grade.asksRunner {
            fields.append(makeCompletionFieldStatus(title: "Runner", items: items) { hasTextValue($0.runnerName) })
        }
        if grade.asksGoalUmpire {
            fields.append(makeCompletionFieldStatus(title: "Goal Umpire", items: items) { hasTextValue($0.goalUmpireName) })
        }
        if grade.asksTimeKeeper {
            fields.append(makeCompletionFieldStatus(title: "Time Keeper", items: items) { hasTextValue($0.timeKeeperName) })
        }
        let anyGameRequiresFieldUmpire = items.contains { item in
            requiresFieldUmpire(for: item.primary, grade: grade)
                || item.secondary.map { requiresFieldUmpire(for: $0, grade: grade) } == true
        }
        if anyGameRequiresFieldUmpire {
            fields.append(makeCompletionFieldStatus(title: "Field Umpire", items: items) {
                !requiresFieldUmpire(for: $0, grade: grade) || hasTextValue($0.fieldUmpireName)
            })
        }
        if grade.asksBoundaryUmpire1 {
            fields.append(makeCompletionFieldStatus(title: "Boundary Umpire 1", items: items) { hasTextValue($0.boundaryUmpire1Name) })
        }
        if grade.asksBoundaryUmpire2 {
            fields.append(makeCompletionFieldStatus(title: "Boundary Umpire 2", items: items) { hasTextValue($0.boundaryUmpire2Name) })
        }
        if grade.asksWaterBoy1 {
            fields.append(makeCompletionFieldStatus(title: "Water 1", items: items) { hasTextValue($0.waterBoy1Name) })
        }
        if grade.asksWaterBoy2 {
            fields.append(makeCompletionFieldStatus(title: "Water 2", items: items) { hasTextValue($0.waterBoy2Name) })
        }
        if grade.asksWaterBoy3 {
            fields.append(makeCompletionFieldStatus(title: "Water 3", items: items) { hasTextValue($0.waterBoy3Name) })
        }
        if grade.asksWaterBoy4 {
            fields.append(makeCompletionFieldStatus(title: "Water 4", items: items) { hasTextValue($0.waterBoy4Name) })
        }

        let trainerCount = requiredTrainerCount(for: grade)
        if trainerCount > 0 {
            let title = trainerCount == 1 ? "Trainer" : "Trainers (\(trainerCount) required)"
            fields.append(makeCompletionFieldStatus(title: title, items: items) {
                $0.trainers.filter(hasTextValue).count >= trainerCount
            })
        }

        if grade.asksNotes {
            fields.append(makeCompletionFieldStatus(title: "Notes", items: items) { hasTextValue($0.notes) })
        }
        if grade.asksGoalKickers {
            fields.append(makeCompletionFieldStatus(title: "Goal Kickers", items: items) { hasRequiredGoalKickers(for: $0, grade: grade) })
        }
        if requiredBestPlayersCount(for: grade) > 0 {
            fields.append(makeCompletionFieldStatus(title: "Best Players (\(requiredBestPlayersCount(for: grade)) required)", items: items) {
                hasRequiredBestPlayers(for: $0, grade: grade)
            })
        }
        if requiredGuestVotesCount(for: grade) > 0 {
            fields.append(makeCompletionFieldStatus(title: "Guest Votes (\(requiredGuestVotesCount(for: grade)) required)", items: items) {
                hasRequiredGuestVotes(for: $0, grade: grade)
            })
        }

        return fields
    }

    private func makeCompletionFieldStatus(
        title: String,
        items: [GameListItem],
        check: (Game) -> Bool
    ) -> CompletionFieldStatus {
        let isComplete = items.allSatisfy { item in
            check(item.primary) && (item.secondary.map(check) ?? true)
        }
        return CompletionFieldStatus(title: title, isComplete: isComplete)
    }

    private func isRoundComplete(_ round: RoundGroup) -> Bool {
        let groupedGrades = roundGamesByGrade(for: round)
        guard !groupedGrades.isEmpty else { return false }
        return groupedGrades.allSatisfy { grouped in
            isExpandedRoundComplete(for: grouped.grade, items: grouped.items)
        }
    }

    private func shouldShowScore(for gradeID: UUID) -> Bool {
        guard isTwoGameGrade(for: gradeID) else { return true }
        return gradeByID[gradeID]?.asksScore ?? true
    }

    private func shouldShowOutcome(for gradeID: UUID) -> Bool {
        gradeByID[gradeID]?.asksScore ?? true
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

    @ViewBuilder
    private func gameRow(for item: GameListItem) -> some View {
        let game = item.primary
        NavigationLink {
            GameDetailView(game: game, grades: orderedGrades, players: players)
        } label: {
            GameCardRow(
                game: game,
                opponentWidth: standardPillWidth,
                showScore: shouldShowScore(for: game.gradeID),
                showOutcome: shouldShowOutcome(for: game.gradeID),
                hasTwoGames: item.hasTwoGames
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if navigationState.currentRole.canEditGames {
                Button {
                    requestProtectedAction(.delete, for: game)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)

                Button {
                    requestProtectedAction(.edit, for: game)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.orange)
            }
        }
    }

    @ViewBuilder
    private var gamesListContent: some View {
        if filteredGames.isEmpty {
            ContentUnavailableView("No games yet", systemImage: "sportscourt")
                .padding(.vertical, 36)
        } else if let round = selectedRound {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    selectedRoundID = nil
                } label: {
                    Label("Back to Games", systemImage: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)

                RoundDetailHeaderCard(
                    roundNumber: round.roundNumber,
                    dateLabel: roundDateLabel(for: round),
                    opponent: round.opponent,
                    outcomePills: roundOutcomePills(for: round)
                )

                ForEach(roundGamesByGrade(for: round), id: \.grade.id) { grouped in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(grouped.grade.name)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.secondary)

                            if showsExpandedRoundCompletionIndicator {
                                let isComplete = isExpandedRoundComplete(for: grouped.grade, items: grouped.items)
                                gradeCompletionIcon(
                                    isComplete: isComplete,
                                    grade: grouped.grade,
                                    items: grouped.items
                                )
                            }
                        }
                        ForEach(grouped.items) { item in
                            gameRow(for: item)
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 14) {
                ForEach(roundGroups) { round in
                    Button {
                        selectedRoundID = round.id
                    } label: {
                        RoundCardRow(
                            roundNumber: round.roundNumber,
                            dateLabel: roundDateLabel(for: round),
                            opponent: round.opponent,
                            outcomePills: roundOutcomePills(for: round),
                            completionStatus: showsExpandedRoundCompletionIndicator ? isRoundComplete(round) : nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var gamesHomeContent: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    // Header
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Home")
                            .font(.system(size: 44, weight: .bold))

                        Spacer()

                        if isIPhoneAdminLayout {
                            Button {
                                showPresentationView = true
                            } label: {
                                Image(systemName: "rectangle.stack.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                            .accessibilityLabel("Presentation")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 6)

                    if navigationState.currentRole.canStartGames {
                        NewGameQuickStartSection(
                            grades: orderedGrades,
                            availableWidth: geometry.size.width,
                            minHeight: geometry.size.height * 0.33,
                            statusForGrade: gradeStatus(for:),
                            onStartNewGame: startNewGame(for:)
                        )
                        .padding(.horizontal)
                    }

                    GamesListSection(
                        minHeight: geometry.size.height * 0.33,
                        outcomeGradeHeaders: selectedRoundID == nil ? outcomeGradeHeaders : []
                    ) {
                        gamesListContent
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 20)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            gamesHomeContent
        }
        .navigationBarTitleDisplayMode(.inline)

            // ✅ EXACT "other pages" style: one capsule containing filter + plus
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    FilterCapsule(
                        grades: orderedGrades,
                        selectedGradeID: $selectedGradeID
                    )
                }
            }
            .onChange(of: selectedGradeID) { _, _ in
                selectedRoundID = nil
            }
            .fullScreenCover(isPresented: $showPresentationView) {
                PresView()
            }
            .fullScreenCover(item: $newGameWizardPresentation) { presentation in
                NewGameWizardView(
                    initialGradeID: presentation.initialGradeID,
                    draftGameID: presentation.draftGameID,
                    reopenLiveViewOnAppear: presentation.reopenLiveView,
                    onBackToHomeFromLive: { gradeID in
                        DraftResumeStore.setShouldOpenLive(true, for: gradeID)
                    },
                    handoffLiveGameToDedicatedTab: true
                )
            }
            .navigationDestination(item: $selectedGameForSummary) { game in
                GameDetailView(game: game, grades: orderedGrades, players: players)
            }
            .sheet(item: $selectedGameForEdit) { presentation in
                GameEditView(game: presentation.primary, secondaryGame: presentation.secondary, grades: orderedGrades)
                    .appPopupStyle()
            }
            .sheet(item: $selectedIncompleteGradeStatus) { details in
                GradeCompletionStatusSheet(details: details)
                    .appPopupStyle()
            }
            .alert("Enter code", isPresented: $showCodePrompt) {
                SecureField("Code", text: $codePromptValue)
                Button("Cancel", role: .cancel) {
                    pendingProtectedAction = nil
                    codePromptGame = nil
                }
                Button("Continue") {
                    handleCodeSubmission()
                }
            } message: {
                Text("Editing and deleting previously saved games is protected.")
            }
            .alert("Wrong code", isPresented: $showWrongCodeAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("That code is incorrect.")
            }
            .alert("Delete game?", isPresented: $showDeleteConfirmAlert, presenting: gamePendingDelete) { game in
                Button("Delete", role: .destructive) {
                    delete(game)
                }
                Button("Cancel", role: .cancel) { }
            } message: { game in
                Text("Delete \(game.opponent) permanently? This cannot be undone.")
            }
    }

    private func startNewGame(for gradeID: UUID) {
        if let draft = latestDraft(for: gradeID) {
            let reopenLive = DraftResumeStore.shouldOpenLive(for: gradeID)
            if reopenLive {
                navigationState.openLiveGameTab(draftGameID: draft.id, gradeID: gradeID)
            } else {
                newGameWizardPresentation = NewGameWizardPresentation(
                    initialGradeID: gradeID,
                    draftGameID: draft.id,
                    reopenLiveView: false
                )
            }
            DraftResumeStore.setShouldOpenLive(false, for: gradeID)
        } else {
            newGameWizardPresentation = NewGameWizardPresentation(
                initialGradeID: gradeID,
                draftGameID: nil,
                reopenLiveView: false
            )
        }
    }

    private func requestProtectedAction(_ action: ProtectedGameAction, for game: Game) {
        pendingProtectedAction = action
        codePromptGame = game
        codePromptValue = ""
        showCodePrompt = true
    }

    private func handleCodeSubmission() {
        let trimmed = codePromptValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DeleteCodeStore.verify(trimmed) else {
            showWrongCodeAlert = true
            return
        }

        guard let action = pendingProtectedAction, let game = codePromptGame else { return }
        switch action {
        case .edit:
            selectedGameForEdit = editPresentation(for: game)
        case .delete:
            gamePendingDelete = game
            showDeleteConfirmAlert = true
        }

        pendingProtectedAction = nil
        codePromptGame = nil
    }

    private func delete(_ game: Game) {
        modelContext.delete(game)
        try? modelContext.save()
        gamePendingDelete = nil
    }

    private func editPresentation(for game: Game) -> GameEditPresentation {
        GameEditPresentation(
            primary: game,
            secondary: pairedGame(for: game)
        )
    }

    private func pairedGame(for game: Game) -> Game? {
        guard isTwoGameGrade(for: game.gradeID) else { return nil }
        return games.first { candidate in
            candidate.id != game.id && arePairedTwoGames(game, candidate)
        }
    }
}

struct NewGameQuickStartSection: View {
    typealias GradeStatus = GamesView.QuickStartGradeStatus

    let grades: [Grade]
    let availableWidth: CGFloat
    let minHeight: CGFloat
    let statusForGrade: (UUID) -> GradeStatus
    let onStartNewGame: (UUID) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isNarrowRegularWidth: Bool {
        horizontalSizeClass == .regular && availableWidth < 820
    }

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 3
        let spacing: CGFloat = isNarrowRegularWidth ? 10 : 14
        return Array(repeating: GridItem(.flexible(minimum: 0), spacing: spacing), count: count)
    }

    private var gridSpacing: CGFloat {
        isNarrowRegularWidth ? 10 : 14
    }

    private var gradeFontSize: CGFloat {
        if horizontalSizeClass == .compact { return 20 }
        return isNarrowRegularWidth ? 30 : 34
    }

    private var cardHorizontalPadding: CGFloat {
        if horizontalSizeClass == .compact { return 12 }
        return isNarrowRegularWidth ? 10 : 16
    }

    private var cardMinHeight: CGFloat {
        if horizontalSizeClass == .compact { return 84 }
        return isNarrowRegularWidth ? 170 : 184
    }

    private var newGameFontSize: CGFloat {
        isNarrowRegularWidth ? 20 : 22
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if horizontalSizeClass == .compact {
                Text("Start New Game")
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    Text("Start New Game")
                        .font(.system(size: 34, weight: .bold))

                    Spacer(minLength: 8)
                }
            }

            if grades.isEmpty {
                ContentUnavailableView("No grades configured", systemImage: "list.bullet.clipboard")
            } else {
                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    ForEach(grades) { grade in
                        Button {
                            onStartNewGame(grade.id)
                        } label: {
                            VStack(spacing: 10) {
                                Text(grade.name)
                                    .font(.system(size: gradeFontSize, weight: .bold))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(horizontalSizeClass == .compact ? 1 : nil)
                                    .minimumScaleFactor(horizontalSizeClass == .compact ? 0.8 : 0.7)
                                if horizontalSizeClass != .compact {
                                    Text("🏉 New Game")
                                        .font(.system(size: newGameFontSize, weight: .semibold))
                                }
                                if statusForGrade(grade.id) == .liveInProgress {
                                    Text("Game in progress - Tap to Continue")
                                        .font(.system(size: horizontalSizeClass == .compact ? 11 : 14, weight: .semibold))
                                        .foregroundStyle(.orange)
                                    .multilineTextAlignment(.center)
                                } else if statusForGrade(grade.id) == .draftOnly {
                                    Text("Draft game in progress")
                                        .font(.system(size: horizontalSizeClass == .compact ? 11 : 14, weight: .semibold))
                                        .foregroundStyle(.orange)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: cardMinHeight)
                            .padding(.horizontal, cardHorizontalPadding)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.regularMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                            .overlay(alignment: .topTrailing) {
                                statusDot(statusForGrade(grade.id))
                                    .padding(10)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private func statusDot(_ status: GradeStatus, size: CGFloat = 14) -> some View {
        switch status {
        case .liveInProgress:
            Circle()
                .fill(Color.orange)
                .frame(width: size, height: size)
        case .draftOnly:
            Circle()
                .fill(Color.orange)
                .frame(width: size, height: size)
        case .gameSaved:
            Circle()
                .fill(Color.green)
                .frame(width: size, height: size)
        case .noGameSaved:
            Circle()
                .stroke(Color.secondary.opacity(0.75), lineWidth: 2)
                .frame(width: size, height: size)
        }
    }
}

private struct GamesListSection<Content: View>: View {
    let minHeight: CGFloat
    let outcomeGradeHeaders: [String]
    let content: Content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(minHeight: CGFloat, outcomeGradeHeaders: [String], @ViewBuilder content: () -> Content) {
        self.minHeight = minHeight
        self.outcomeGradeHeaders = outcomeGradeHeaders
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if horizontalSizeClass == .compact {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Previous Games")
                        .font(.system(size: 28, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            } else {
                HStack(alignment: .bottom, spacing: 12) {
                    Text("Previous Games")
                        .font(.system(size: 34, weight: .bold))

                    Spacer(minLength: 10)

                    if !outcomeGradeHeaders.isEmpty {
                        RoundOutcomeColumnHeaders(gradeNames: outcomeGradeHeaders)
                    }
                }
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Top-right capsule (Filter only)
private struct FilterCapsule: View {
    let grades: [Grade]
    @Binding var selectedGradeID: UUID?

    var body: some View {
        Menu {
            Button("All") { selectedGradeID = nil }

            if !grades.isEmpty {
                Divider()
                ForEach(grades) { g in
                    Button(g.name) { selectedGradeID = g.id }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 36)
        }
        .foregroundStyle(.primary)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Card Row (rounded cards + opponent pill + win/loss + grade)
private struct GameCardRow: View {
    let game: Game
    let opponentWidth: CGFloat
    let showScore: Bool
    let showOutcome: Bool
    let hasTwoGames: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var outcome: GamesView.RoundOutcome {
        if game.ourScore > game.theirScore {
            return .win
        } else if game.ourScore < game.theirScore {
            return .loss
        } else {
            return .draw
        }
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                HStack(spacing: 12) {
                    if hasTwoGames {
                        Text("Two games")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    if showScore {
                        Text("\(game.ourGoals).\(game.ourBehinds) - \(game.theirGoals).\(game.theirBehinds)")
                            .font(.system(size: 22, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: 8)
                    if showOutcome {
                        CompactGameOutcomePill(outcome: outcome)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    OpponentBadge(opponent: game.opponent, fixedWidth: opponentWidth)

                    if hasTwoGames {
                        Text("Two games")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 10)

                    if showScore {
                        Text("\(game.ourGoals).\(game.ourBehinds) - \(game.theirGoals).\(game.theirBehinds)")
                            .font(.system(size: 24, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }

                    Spacer(minLength: 10)
                    if showOutcome {
                        ResultPill(win: outcome == .win)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .overlay {
            if game.isDraft {
                Text("DRAFT")
                    .font(.system(size: 56, weight: .black))
                    .foregroundStyle(Color.red.opacity(0.22))
                    .rotationEffect(.degrees(-28))
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct CompactGameOutcomePill: View {
    let outcome: GamesView.RoundOutcome

    private var backgroundColor: Color {
        switch outcome {
        case .win: return Color.green.opacity(0.2)
        case .draw: return Color.orange.opacity(0.2)
        case .loss: return Color.red.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch outcome {
        case .win: return .green
        case .draw: return .orange
        case .loss: return .red
        }
    }

    var body: some View {
        Text(outcome.label)
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor)
            )
            .foregroundStyle(foregroundColor)
    }
}


private enum RoundOutcomeLayout {
    static let defaultColumnWidth: CGFloat = 94
    static let defaultColumnSpacing: CGFloat = 20
    static let compactColumnWidth: CGFloat = 68
    static let compactColumnSpacing: CGFloat = 10
    static let chevronReserveWidth: CGFloat = 34
    static let compactLayoutThreshold: CGFloat = 1100
    static let headerAlignmentNudge: CGFloat = -20

    static func columnWidth(forCompactLayout isCompact: Bool) -> CGFloat {
        isCompact ? compactColumnWidth : defaultColumnWidth
    }

    static func columnSpacing(forCompactLayout isCompact: Bool) -> CGFloat {
        isCompact ? compactColumnSpacing : defaultColumnSpacing
    }

    static func contentWidth(for columnCount: Int, compact: Bool) -> CGFloat {
        guard columnCount > 0 else { return 0 }
        let columnWidth = columnWidth(forCompactLayout: compact)
        let columnSpacing = columnSpacing(forCompactLayout: compact)
        return (CGFloat(columnCount) * columnWidth) + (CGFloat(columnCount - 1) * columnSpacing)
    }

    static func useCompactLayout(for availableWidth: CGFloat) -> Bool {
        availableWidth < compactLayoutThreshold
    }
}

private struct RoundOutcomeColumnHeaders: View {
    let gradeNames: [String]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .compact {
            EmptyView()
        } else {
        GeometryReader { proxy in
            let useCompactLayout = RoundOutcomeLayout.useCompactLayout(for: proxy.size.width)
            let columnWidth = RoundOutcomeLayout.columnWidth(forCompactLayout: useCompactLayout)
            let columnSpacing = RoundOutcomeLayout.columnSpacing(forCompactLayout: useCompactLayout)

            HStack(spacing: columnSpacing) {
                ForEach(gradeNames, id: \.self) { gradeName in
                    Text(gradeName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: columnWidth, alignment: .center)
                }
            }
            .frame(width: RoundOutcomeLayout.contentWidth(for: gradeNames.count, compact: useCompactLayout), alignment: .center)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, RoundOutcomeLayout.chevronReserveWidth)
            .offset(x: RoundOutcomeLayout.headerAlignmentNudge)
        }
        .frame(height: 24)
        }
    }
}

private struct RoundTitleLine: View {
    let roundNumber: Int
    let dateLabel: String
    let opponent: String
    let outcomePills: [GamesView.RoundOutcomePillItem]
    let completionStatus: Bool?
    var showsChevron: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { proxy in
            let useCompactLayout = horizontalSizeClass == .compact || RoundOutcomeLayout.useCompactLayout(for: proxy.size.width)
            let roundDateColumnWidth: CGFloat = useCompactLayout ? 210 : 320
            let columnWidth = RoundOutcomeLayout.columnWidth(forCompactLayout: useCompactLayout)
            let columnSpacing = RoundOutcomeLayout.columnSpacing(forCompactLayout: useCompactLayout)
            let pillSize: CGFloat = useCompactLayout ? 38 : 44

            if horizontalSizeClass == .compact {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("ROUND \(roundNumber) - \(dateLabel)")
                                .font(.system(size: 19, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .layoutPriority(3)

                            if let completionStatus {
                                RoundCompletionIcon(isComplete: completionStatus)
                            }
                        }

                        Spacer(minLength: 4)

                        if showsChevron {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    OpponentBadge(opponent: opponent)
                }
            } else {
                HStack(spacing: useCompactLayout ? 8 : 10) {
                    HStack(spacing: 8) {
                        Text("ROUND \(roundNumber) - \(dateLabel)")
                            .font(.system(size: useCompactLayout ? 19 : 22, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .layoutPriority(3)

                        if let completionStatus {
                            RoundCompletionIcon(isComplete: completionStatus)
                        }
                    }
                    .frame(width: roundDateColumnWidth, alignment: .leading)
                    .layoutPriority(3)

                    Text("V")
                        .font(.system(size: useCompactLayout ? 19 : 22, weight: .semibold))
                        .lineLimit(1)

                    OpponentBadge(opponent: opponent)
                        .layoutPriority(1)

                    Spacer(minLength: useCompactLayout ? 8 : 16)

                    HStack(spacing: columnSpacing) {
                        ForEach(outcomePills) { item in
                            CompactRoundOutcomePill(item: item, pillSize: pillSize)
                                .frame(width: columnWidth)
                        }
                    }
                    .frame(width: RoundOutcomeLayout.contentWidth(for: outcomePills.count, compact: useCompactLayout), alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .layoutPriority(3)

                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: RoundOutcomeLayout.chevronReserveWidth, alignment: .trailing)
                    }
                }
            }
        }
        .frame(height: horizontalSizeClass == .compact ? nil : 52)
    }
}

private struct RoundCardRow: View {
    let roundNumber: Int
    let dateLabel: String
    let opponent: String
    let outcomePills: [GamesView.RoundOutcomePillItem]
    let completionStatus: Bool?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        RoundTitleLine(
            roundNumber: roundNumber,
            dateLabel: dateLabel,
            opponent: opponent,
            outcomePills: outcomePills,
            completionStatus: completionStatus,
            showsChevron: true
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(
            maxWidth: .infinity,
            minHeight: horizontalSizeClass == .compact ? 110 : nil,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct RoundDetailHeaderCard: View {
    let roundNumber: Int
    let dateLabel: String
    let opponent: String
    let outcomePills: [GamesView.RoundOutcomePillItem]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        RoundTitleLine(
            roundNumber: roundNumber,
            dateLabel: dateLabel,
            opponent: opponent,
            outcomePills: outcomePills,
            completionStatus: nil,
            showsChevron: false
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(
            maxWidth: .infinity,
            minHeight: horizontalSizeClass == .compact ? 110 : nil,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct RoundCompletionIcon: View {
    let isComplete: Bool

    var body: some View {
        Image(systemName: isComplete ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isComplete ? Color.green : Color.red)
    }
}

private struct GradeCompletionStatusSheet: View {
    let details: GamesView.IncompleteGradeStatusDetails
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(details.fields) { field in
                        HStack(spacing: 12) {
                            Image(systemName: field.isComplete ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(field.isComplete ? Color.green : Color.red)
                                .font(.system(size: 18, weight: .semibold))
                            Text(field.title)
                                .font(.body.weight(.medium))
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Monitored Fields")
                }
            }
            .navigationTitle(details.gradeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct CompactRoundOutcomePill: View {
    let item: GamesView.RoundOutcomePillItem
    let pillSize: CGFloat

    private var foregroundColor: Color {
        guard let outcome = item.outcome else { return .secondary }
        switch outcome {
        case .win: return .green
        case .draw: return .orange
        case .loss: return .red
        }
    }

    var body: some View {
        Text(item.outcome?.label ?? "-")
            .font(.system(size: pillSize * 0.36, weight: .bold))
            .frame(width: pillSize, height: pillSize)
            .background(
                Circle()
                    .fill(item.outcome == nil ? Color.clear : foregroundColor.opacity(0.22))
            )
            .foregroundStyle(foregroundColor)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(item.outcome == nil ? 0.18 : 0), lineWidth: 1)
            )
            .accessibilityLabel("\(item.gradeName) \(item.outcome?.label ?? "No game")")
    }
}

// MARK: - Win/Loss pill
private struct ResultPill: View {
    let win: Bool

    var body: some View {
        Text(win ? "Win" : "Loss")
            .font(.system(size: 14, weight: .bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(win ? Color.green.opacity(0.20) : Color.red.opacity(0.20))
            )
            .foregroundStyle(win ? Color.green : Color.red)
    }
}
