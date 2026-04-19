import SwiftUI
import SwiftData

struct GamesView: View {
    @Environment(\.modelContext) private var modelContext

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
    @State private var selectedGameForEdit: Game?
    @State private var selectedRoundID: String?
    @State private var gamePendingDelete: Game?
    @State private var codePromptGame: Game?
    @State private var codePromptValue = ""
    @State private var showCodePrompt = false
    @State private var showWrongCodeAlert = false
    @State private var showDeleteConfirmAlert = false
    @State private var pendingProtectedAction: ProtectedGameAction?

    private enum ProtectedGameAction {
        case edit
        case delete
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
        let base = games.sorted { $0.date > $1.date }
        guard let gid = selectedGradeID else { return base }
        return base.filter { $0.gradeID == gid }
    }

    private var gradeByID: [UUID: Grade] {
        Dictionary(uniqueKeysWithValues: grades.map { ($0.id, $0) })
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

    private func shouldShowScore(for gradeID: UUID) -> Bool {
        guard isTwoGameGrade(for: gradeID) else { return true }
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
                hasTwoGames: item.hasTwoGames
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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
                        Text(grouped.grade.name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.secondary)
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
                            outcomePills: roundOutcomePills(for: round)
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

                    // Header like your screenshot: "Games" + small "All" pill
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Games")
                            .font(.system(size: 44, weight: .bold))

                        Text(selectedGradeName)
                            .font(.system(size: 16, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 6)

                    NewGameQuickStartSection(
                        grades: orderedGrades,
                        minHeight: geometry.size.height * 0.33,
                        statusForGrade: gradeStatus(for:),
                        onStartNewGame: startNewGame(for:)
                    )
                    .padding(.horizontal)

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
            .fullScreenCover(item: $newGameWizardPresentation) { presentation in
                NewGameWizardView(
                    initialGradeID: presentation.initialGradeID,
                    draftGameID: presentation.draftGameID,
                    reopenLiveViewOnAppear: presentation.reopenLiveView,
                    onBackToHomeFromLive: { gradeID in
                        DraftResumeStore.setShouldOpenLive(true, for: gradeID)
                    }
                )
            }
            .navigationDestination(item: $selectedGameForSummary) { game in
                GameDetailView(game: game, grades: orderedGrades, players: players)
            }
            .sheet(item: $selectedGameForEdit) { game in
                GameEditView(game: game, grades: orderedGrades)
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
            newGameWizardPresentation = NewGameWizardPresentation(
                initialGradeID: gradeID,
                draftGameID: draft.id,
                reopenLiveView: reopenLive
            )
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
            selectedGameForEdit = game
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
}

private struct NewGameQuickStartSection: View {
    typealias GradeStatus = GamesView.QuickStartGradeStatus

    let grades: [Grade]
    let minHeight: CGFloat
    let statusForGrade: (UUID) -> GradeStatus
    let onStartNewGame: (UUID) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 14), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text("Start New Game")
                    .font(.system(size: 34, weight: .bold))

                Spacer(minLength: 8)

                statusLegend
            }

            if grades.isEmpty {
                ContentUnavailableView("No grades configured", systemImage: "list.bullet.clipboard")
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(grades) { grade in
                        Button {
                            onStartNewGame(grade.id)
                        } label: {
                            VStack(spacing: 10) {
                                Text(grade.name)
                                    .font(.system(size: horizontalSizeClass == .compact ? 20 : 34, weight: .bold))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(horizontalSizeClass == .compact ? 1 : nil)
                                    .minimumScaleFactor(horizontalSizeClass == .compact ? 0.8 : 0.7)
                                if horizontalSizeClass != .compact {
                                    Text("🏉 New Game")
                                        .font(.system(size: 22, weight: .semibold))
                                }
                                if statusForGrade(grade.id) == .liveInProgress {
                                    Text("Game in progress - Tap to Continue")
                                        .font(.system(size: horizontalSizeClass == .compact ? 11 : 14, weight: .semibold))
                                        .foregroundStyle(.orange)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: horizontalSizeClass == .compact ? 84 : 184)
                            .padding(.horizontal, horizontalSizeClass == .compact ? 12 : 16)
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

    private var statusLegend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                legendItem(status: .noGameSaved, text: "No Game Saved")
                legendItem(status: .liveInProgress, text: "Game in Progress")
                legendItem(status: .gameSaved, text: "Game Saved")
            }
        }
        .font(.system(size: horizontalSizeClass == .compact ? 11 : 13, weight: .semibold))
        .foregroundStyle(.secondary)
    }

    private func legendItem(status: GradeStatus, text: String) -> some View {
        HStack(spacing: 6) {
            statusDot(status, size: 12)
            Text(text)
                .lineLimit(1)
        }
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

    init(minHeight: CGFloat, outcomeGradeHeaders: [String], @ViewBuilder content: () -> Content) {
        self.minHeight = minHeight
        self.outcomeGradeHeaders = outcomeGradeHeaders
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                Text("Games")
                    .font(.system(size: 34, weight: .bold))

                Spacer(minLength: 10)

                if !outcomeGradeHeaders.isEmpty {
                    RoundOutcomeColumnHeaders(gradeNames: outcomeGradeHeaders)
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
    let hasTwoGames: Bool

    private var didWin: Bool { game.ourScore >= game.theirScore }

    var body: some View {
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
            ResultPill(win: didWin)
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


private enum RoundOutcomeLayout {
    static let columnWidth: CGFloat = 94
    static let columnSpacing: CGFloat = 20
    static let chevronReserveWidth: CGFloat = 34

    static func contentWidth(for columnCount: Int) -> CGFloat {
        guard columnCount > 0 else { return 0 }
        return (CGFloat(columnCount) * columnWidth) + (CGFloat(columnCount - 1) * columnSpacing)
    }
}

private struct RoundOutcomeColumnHeaders: View {
    let gradeNames: [String]

    var body: some View {
        HStack(spacing: RoundOutcomeLayout.columnSpacing) {
            ForEach(gradeNames, id: \.self) { gradeName in
                Text(gradeName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: RoundOutcomeLayout.columnWidth, alignment: .center)
            }
        }
        .frame(width: RoundOutcomeLayout.contentWidth(for: gradeNames.count), alignment: .center)
        .padding(.trailing, RoundOutcomeLayout.chevronReserveWidth)
    }
}

private struct RoundTitleLine: View {
    let roundNumber: Int
    let dateLabel: String
    let opponent: String
    let outcomePills: [GamesView.RoundOutcomePillItem]
    var showsChevron: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var roundDateColumnWidth: CGFloat {
        horizontalSizeClass == .compact ? 210 : 320
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("ROUND \(roundNumber) - \(dateLabel)")
                .font(.system(size: 22, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: roundDateColumnWidth, alignment: .leading)
                .layoutPriority(3)

            Text("V")
                .font(.system(size: 22, weight: .semibold))
                .lineLimit(1)

            OpponentBadge(opponent: opponent)
                .layoutPriority(1)

            Spacer(minLength: 16)

            HStack(spacing: RoundOutcomeLayout.columnSpacing) {
                ForEach(outcomePills) { item in
                    CompactRoundOutcomePill(item: item)
                        .frame(width: RoundOutcomeLayout.columnWidth)
                }
            }
            .frame(width: RoundOutcomeLayout.contentWidth(for: outcomePills.count), alignment: .center)
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

private struct RoundCardRow: View {
    let roundNumber: Int
    let dateLabel: String
    let opponent: String
    let outcomePills: [GamesView.RoundOutcomePillItem]

    var body: some View {
        RoundTitleLine(
            roundNumber: roundNumber,
            dateLabel: dateLabel,
            opponent: opponent,
            outcomePills: outcomePills,
            showsChevron: true
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    var body: some View {
        RoundTitleLine(
            roundNumber: roundNumber,
            dateLabel: dateLabel,
            opponent: opponent,
            outcomePills: outcomePills,
            showsChevron: false
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct CompactRoundOutcomePill: View {
    let item: GamesView.RoundOutcomePillItem
    private let pillSize: CGFloat = 44

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
            .font(.system(size: 16, weight: .bold))
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
