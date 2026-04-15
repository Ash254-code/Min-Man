import SwiftUI
import SwiftData
import UIKit

struct GamesView: View {
    @Query(sort: [SortDescriptor(\Game.date, order: .reverse)]) private var games: [Game]
    @Query(sort: [SortDescriptor(\Grade.name)]) private var grades: [Grade]
    @Query(sort: \Player.name) private var players: [Player]

    @State private var selectedGradeID: UUID? = nil
    @State private var showNewGameWizard = false
    @State private var newGameGradeID: UUID? = nil

    // MARK: - Ordered grades (your seeded order + remaining A→Z)
    private var orderedGrades: [Grade] {
        orderedGradesForDisplay(resolvedConfiguredGrades(from: grades))
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

    // ✅ Widest opponent pill (based on currently shown games)
    private var maxOpponentPillWidth: CGFloat {
        let font = UIFont.preferredFont(forTextStyle: .subheadline)

        let maxTextWidth = filteredGames
            .map { ($0.opponent as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0

        // + horizontal padding used inside OpponentBadge (10 + 10)
        return maxTextWidth + 20
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
                            minHeight: geometry.size.height * 0.33,
                            onStartNewGame: { gradeID in
                                newGameGradeID = gradeID
                                showNewGameWizard = true
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
                                                opponentWidth: maxOpponentPillWidth
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
                    FilterAddCapsule(
                        grades: orderedGrades,
                        selectedGradeID: $selectedGradeID,
                        onAdd: {
                            newGameGradeID = nil
                            showNewGameWizard = true
                        }
                    )
                }
            }
            .sheet(isPresented: $showNewGameWizard) {
                NewGameWizardView(initialGradeID: newGameGradeID)
            }
        }
    }
}

private struct NewGameQuickStartSection: View {
    let grades: [Grade]
    let minHeight: CGFloat
    let onStartNewGame: (UUID) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start New Game")
                .font(.system(size: 34, weight: .bold))

            if grades.isEmpty {
                ContentUnavailableView("No active grades", systemImage: "list.bullet.clipboard")
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(grades) { grade in
                        Button {
                            onStartNewGame(grade.id)
                        } label: {
                            VStack(spacing: 10) {
                                Text(grade.name)
                                    .font(.system(size: 34, weight: .bold))
                                    .multilineTextAlignment(.center)
                                    .minimumScaleFactor(0.7)
                                Text("New Game")
                                    .font(.system(size: 30, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 184)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.regularMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
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

// MARK: - Top-right capsule (Filter + Plus) — matches your screenshot
private struct FilterAddCapsule: View {
    let grades: [Grade]
    @Binding var selectedGradeID: UUID?
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {

            // Filter menu
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

            // Divider inside capsule
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1, height: 18)

            // Plus button
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 36)
            }
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

    private var didWin: Bool { game.ourScore >= game.theirScore }

    var body: some View {
        VStack(spacing: 8) {
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
