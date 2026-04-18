import SwiftUI
import SwiftData

struct GamesView: View {
    enum QuickStartGradeStatus {
        case noGameSaved
        case draftOnly
        case gameSaved

        // Backward-compatible aliases for previously used naming.
        static let noneRecent: Self = .noGameSaved
        static let inProgressDraft: Self = .draftOnly
        static let finalizedRecent: Self = .gameSaved

        var color: Color {
            switch self {
            case .noGameSaved: return .secondary
            case .draftOnly: return .orange
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

    fileprivate enum GradeRecentStatus {
        case noneRecent
        case inProgressDraft
        case finalizedRecent
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

    private func latestDraft(for gradeID: UUID) -> Game? {
        games
            .filter { $0.gradeID == gradeID && $0.isDraft }
            .sorted { $0.date > $1.date }
            .first
    }

    private func gradeStatus(for gradeID: UUID) -> GradeRecentStatus {
        if latestDraft(for: gradeID) != nil {
            return .inProgressDraft
        }

        let cutoff = Date().addingTimeInterval(-48 * 60 * 60)
        let hasRecentFinalized = games.contains { game in
            game.gradeID == gradeID && !game.isDraft && game.date >= cutoff
        }
        return hasRecentFinalized ? .finalizedRecent : .noneRecent
    }

    private var standardPillWidth: CGFloat {
        ClubStyle.standardPillWidth(configuration: ClubConfigurationStore.load())
    }

    var body: some View {
        NavigationStack {
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
                            games: games,
                            minHeight: geometry.size.height * 0.33,
                            statusForGrade: gradeStatus(for:),
                            onStartNewGame: { gradeID in
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
                        )
                        .padding(.horizontal)

                        GamesListSection(minHeight: geometry.size.height * 0.33) {
                            if filteredGames.isEmpty {
                                ContentUnavailableView("No games yet", systemImage: "sportscourt")
                                    .padding(.vertical, 36)
                            } else {
                                VStack(spacing: 14) {
                                    ForEach(filteredGames) { game in
                                        NavigationLink {
                                            GameDetailView(game: game, grades: orderedGrades, players: players)
                                        } label: {
                                            GameCardRow(
                                                game: game,
                                                gradeName: gradeNameByID[game.gradeID] ?? "Unknown",
                                                opponentWidth: standardPillWidth
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)

                        Spacer(minLength: 20)
                    }
                }
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
            .sheet(item: $newGameWizardPresentation) { presentation in
                NewGameWizardView(
                    initialGradeID: presentation.initialGradeID,
                    draftGameID: presentation.draftGameID,
                    reopenLiveViewOnAppear: presentation.reopenLiveView,
                    onBackToHomeFromLive: { gradeID in
                        DraftResumeStore.setShouldOpenLive(true, for: gradeID)
                    }
                )
                    .appPopupStyle()
            }
        }
    }
}

private struct NewGameQuickStartSection: View {
    typealias GradeStatus = GamesView.QuickStartGradeStatus

    let grades: [Grade]
    let games: [Game]
    let statusProvider: (@Sendable (UUID) -> GradeStatus)? = nil
    let minHeight: CGFloat
    let statusForGrade: (UUID) -> GradeStatus
    let onStartNewGame: (UUID) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 14), count: count)
    }

    private func status(for gradeID: UUID) -> GradeStatus {
        if let statusProvider {
            return statusProvider(gradeID)
        }
        let gradeGames = games.filter { $0.gradeID == gradeID }
        if gradeGames.contains(where: { !$0.isDraft }) {
            return .gameSaved
        }
        if !gradeGames.isEmpty {
            return .draftOnly
        }
        return .noGameSaved
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
                        let status = status(for: grade.id)
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
                legendItem(status: .noneRecent, text: "No Game Saved")
                legendItem(status: .inProgressDraft, text: "Game in Draft")
                legendItem(status: .finalizedRecent, text: "Game Saved")
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
        case .inProgressDraft:
            Circle()
                .fill(Color.orange)
                .frame(width: size, height: size)
        case .finalizedRecent:
            Circle()
                .fill(Color.green)
                .frame(width: size, height: size)
        case .noneRecent:
            Circle()
                .stroke(Color.secondary.opacity(0.75), lineWidth: 2)
                .frame(width: size, height: size)
        }
    }
}

private struct GamesListSection<Content: View>: View {
    let minHeight: CGFloat
    let content: Content

    init(minHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.minHeight = minHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Games")
                .font(.system(size: 34, weight: .bold))

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
    let gradeName: String
    let opponentWidth: CGFloat

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var didWin: Bool { game.ourScore >= game.theirScore }
    private var isCompact: Bool { horizontalSizeClass == .compact }

    var body: some View {
        VStack(spacing: 8) {
            if isCompact {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 10) {
                        OpponentBadge(opponent: game.opponent, fixedWidth: nil)
                        Text(game.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)

                    VStack(alignment: .trailing, spacing: 8) {
                        ResultPill(win: didWin)
                        Text("\(game.ourGoals).\(game.ourBehinds) - \(game.theirGoals).\(game.theirBehinds)")
                            .font(.system(size: 22, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(gradeName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                HStack(spacing: 12) {

                    // ✅ opponent pills all same width
                    OpponentBadge(opponent: game.opponent, fixedWidth: opponentWidth)

                    Spacer(minLength: 10)

                    Text("\(game.ourGoals).\(game.ourBehinds) - \(game.theirGoals).\(game.theirBehinds)")
                        .font(.system(size: 24, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 10)

                    VStack(alignment: .trailing, spacing: 6) {
                        ResultPill(win: didWin)
                        Text(gradeName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text(game.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
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
