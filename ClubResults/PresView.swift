import SwiftUI
import SwiftData

struct PresView: View {
    fileprivate struct GoalKickerPresentationItem: Identifiable {
        let id = UUID()
        let name: String
        let goals: Int
    }

    fileprivate struct GradePresentationSection: Identifiable {
        let grade: Grade
        let games: [Game]

        var id: UUID { grade.id }
    }

    @Query(sort: [SortDescriptor(\Game.date, order: .reverse)]) private var games: [Game]
    @Query(sort: [SortDescriptor(\Grade.name)]) private var grades: [Grade]
    @Query(sort: \Player.name) private var players: [Player]

    @State private var selectedPresentationGrade: GradePresentationSection?
    @StateObject private var aiNarrator = AIMCNarrator()
    @State private var aiNarrationPreview = ""
    @State private var aiHasApprovedNarration = false
    @State private var isPreviewSheetPresented = false

    @AppStorage(AIMCStorageKeys.selectedAppleVoiceID) private var selectedAppleVoiceID = ""
    @AppStorage(AIMCStorageKeys.includeWeather) private var includeWeather = true
    @AppStorage(AIMCStorageKeys.includeKeyPoints) private var includeKeyPoints = true
    @AppStorage(AIMCStorageKeys.includeAnnouncements) private var includeAnnouncements = true
    @AppStorage(AIMCStorageKeys.includeDates) private var includeDates = false
    @AppStorage(AIMCStorageKeys.includeSectionHeaders) private var includeSectionHeaders = false
    @AppStorage(AIMCStorageKeys.keyPoints) private var keyPointsInput = ""
    @AppStorage(AIMCStorageKeys.announcementGradeID) private var announcementGradeID = ""

    // MARK: - Ordered grades (U9 → A Grade)
    private var orderedGrades: [Grade] {
        orderedGradesForDisplay(grades)
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

    private func goalKickerItems(for game: Game) -> [GoalKickerPresentationItem] {
        guard !game.goalKickers.isEmpty else {
            return [GoalKickerPresentationItem(name: "None recorded", goals: 0)]
        }

        return game.goalKickers
            .sorted { $0.goals > $1.goals }
            .map { GoalKickerPresentationItem(name: playerName(for: $0.playerID), goals: $0.goals) }
    }

    private func bestPlayerItems(for game: Game) -> [String] {
        guard !game.bestPlayersRanked.isEmpty else { return ["None recorded"] }
        return game.bestPlayersRanked
            .enumerated()
            .map { _, playerID in playerNameByID[playerID] ?? "Unknown" }
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

    private var announcementGradeName: String {
        guard let grade = orderedGrades.first(where: { $0.id.uuidString == announcementGradeID }) else {
            return "each grade section"
        }
        return grade.name
    }

    private func generateAINarrationPreview() {
        let reportDate = Date().formatted(date: .complete, time: .omitted)
        var lines: [String] = [
            "Good evening everyone, here is the club report for \(reportDate)."
        ]

        if includeWeather {
            lines.append("Weather update: conditions look good for presentations.")
        }

        if includeKeyPoints {
            let trimmedKeyPoints = keyPointsInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedKeyPoints.isEmpty {
                lines.append("Key point: celebrate effort, teamwork, and sportsmanship across all grades.")
            } else {
                lines.append("Key points: \(trimmedKeyPoints).")
            }
        }

        for section in gradeSections {
            if includeAnnouncements,
               (announcementGradeID.isEmpty || section.grade.id.uuidString == announcementGradeID) {
                if includeSectionHeaders {
                    lines.append("Announcements.")
                }
                lines.append("A quick announcement from the committee.")
            }

            if includeSectionHeaders {
                lines.append("\(section.grade.name).")
            }
            lines.append("\(section.games.count) game\(section.games.count == 1 ? "" : "s") to report.")
            for game in section.games {
                let teamName = clubConfiguration.clubTeam.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Our Team"
                : clubConfiguration.clubTeam.name
                let resultLine = shouldShowScore(for: section.grade.id)
                ? "\(teamName) \(game.ourScore), \(game.opponent) \(game.theirScore)."
                : "score summary disabled for this grade."
                if includeDates {
                    lines.append("Played against \(game.opponent) on \(game.date.formatted(date: .abbreviated, time: .omitted)); \(resultLine)")
                } else {
                    lines.append("Played against \(game.opponent); \(resultLine)")
                }

                let bestPlayers = bestPlayerItems(for: game).prefix(3).joined(separator: ", ")
                if !bestPlayers.isEmpty, bestPlayers != "None recorded" {
                    lines.append("Best players included \(bestPlayers).")
                }

                let kickers = goalKickerItems(for: game)
                    .filter { $0.goals > 0 }
                    .prefix(3)
                    .map { "\($0.name) \($0.goals)" }
                    .joined(separator: ", ")
                if !kickers.isEmpty {
                    lines.append("Goal kickers: \(kickers).")
                }
            }
        }

        lines.append("That concludes the AI Master of Ceremonies report.")
        aiNarrationPreview = lines.joined(separator: "\n\n")
        aiHasApprovedNarration = false
    }

    private func handleAIButtonTapped() {
        if aiNarrator.isSpeaking, aiNarrator.isPaused {
            aiNarrator.resume()
        } else if aiHasApprovedNarration {
            aiNarrator.speak(text: aiNarrationPreview, appleVoiceID: selectedAppleVoiceID.isEmpty ? nil : selectedAppleVoiceID)
        } else {
            generateAINarrationPreview()
            isPreviewSheetPresented = true
        }
    }

    private func startPresentations() {
        guard let firstGradeSection = gradeSections.first else { return }
        selectedPresentationGrade = firstGradeSection
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
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
                                    selectedPresentationGrade = section
                                } label: {
                                    PresGradeRow(
                                        gradeName: section.grade.name,
                                        gameCount: section.games.count
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Section("AI Intelligence") {
                        Toggle("Include weather", isOn: $includeWeather)
                        Toggle("Read dates", isOn: $includeDates)
                        Toggle("Read section headers", isOn: $includeSectionHeaders)
                        Toggle("Include key points", isOn: $includeKeyPoints)
                        Toggle("Include announcements", isOn: $includeAnnouncements)

                        if includeKeyPoints {
                            TextField("Key points for tonight", text: $keyPointsInput, axis: .vertical)
                                .lineLimit(2...5)
                        }

                        Picker("Announcement placement", selection: $announcementGradeID) {
                            Text("Before each grade").tag("")
                            ForEach(orderedGrades) { grade in
                                Text("Before \(grade.name)").tag(grade.id.uuidString)
                            }
                        }

                        Text("Announcements will run before \(announcementGradeName).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        handleAIButtonTapped()
                    } label: {
                        Label(
                            aiNarrator.isSpeaking && aiNarrator.isPaused
                            ? "Resume AI"
                            : (aiHasApprovedNarration ? "Play AI" : "AI"),
                            systemImage: aiNarrator.isSpeaking && aiNarrator.isPaused
                            ? "play.circle.fill"
                            : (aiHasApprovedNarration ? "play.circle.fill" : "sparkles")
                        )
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.purple, in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(gradeSections.isEmpty)
                    .opacity(gradeSections.isEmpty ? 0.45 : 1.0)

                    if aiNarrator.isSpeaking {
                        Button {
                            if aiNarrator.isPaused {
                                aiNarrator.resume()
                            } else {
                                aiNarrator.pause()
                            }
                        } label: {
                            Label(aiNarrator.isPaused ? "Resume" : "Pause", systemImage: aiNarrator.isPaused ? "play.circle.fill" : "pause.circle.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.orange, in: Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            aiNarrator.stop()
                        } label: {
                            Label("Stop", systemImage: "stop.circle.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.red, in: Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                Button {
                    startPresentations()
                } label: {
                    Text("Start Presentations")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(gradeSections.isEmpty)
                .opacity(gradeSections.isEmpty ? 0.45 : 1.0)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .navigationTitle("Pres")
            .sheet(isPresented: $isPreviewSheetPresented) {
                NavigationStack {
                    ScrollView {
                        Text(aiNarrationPreview)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle("AI Preview")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                isPreviewSheetPresented = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Approve") {
                                aiHasApprovedNarration = true
                                isPreviewSheetPresented = false
                            }
                        }
                    }
                }
            }
            .onChange(of: includeWeather) { _, _ in aiHasApprovedNarration = false }
            .onChange(of: includeDates) { _, _ in aiHasApprovedNarration = false }
            .onChange(of: includeSectionHeaders) { _, _ in aiHasApprovedNarration = false }
            .onChange(of: includeKeyPoints) { _, _ in aiHasApprovedNarration = false }
            .onChange(of: includeAnnouncements) { _, _ in aiHasApprovedNarration = false }
            .onChange(of: keyPointsInput) { _, _ in aiHasApprovedNarration = false }
            .onChange(of: announcementGradeID) { _, _ in aiHasApprovedNarration = false }
            .fullScreenCover(item: $selectedPresentationGrade) { selectedGrade in
                PresentationGradeFullScreenView(
                    sections: gradeSections,
                    initiallySelectedGradeID: selectedGrade.id,
                    shouldShowScore: shouldShowScore(for:),
                    ourTeamName: clubConfiguration.clubTeam.name,
                    goalKickerItems: goalKickerItems(for:),
                    bestPlayerItems: bestPlayerItems(for:),
                    clubConfiguration: clubConfiguration
                )
            }
        }
    }
}

private struct PresGradeRow: View {
    let gradeName: String
    let gameCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(gradeName)
                .font(.system(size: 20, weight: .bold))
            Spacer()
            Text("\(gameCount) game\(gameCount == 1 ? "" : "s")")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }
}

private struct PresentationGradeFullScreenView: View {
    @Environment(\.dismiss) private var dismiss

    let sections: [PresView.GradePresentationSection]
    let initiallySelectedGradeID: UUID
    let shouldShowScore: (UUID) -> Bool
    let ourTeamName: String
    let goalKickerItems: (Game) -> [PresView.GoalKickerPresentationItem]
    let bestPlayerItems: (Game) -> [String]
    let clubConfiguration: ClubConfiguration

    @State private var selectedPageIndex = 0

    private var selectedSection: PresView.GradePresentationSection? {
        guard sections.indices.contains(selectedPageIndex) else { return nil }
        return sections[selectedPageIndex]
    }

    private var ourTeamLabel: String {
        let cleaned = ourTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Our Team" : cleaned
    }

    private var scorePillWidth: CGFloat {
        ClubStyle.standardPillWidth(configuration: clubConfiguration, fontTextStyle: .title2)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    Text(selectedSection?.grade.name ?? "")
                        .font(.system(size: proxy.size.width > 1000 ? 56 : 42, weight: .black))
                        .padding(.top, 8)

                    TabView(selection: $selectedPageIndex) {
                        ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 28) {
                                    ForEach(section.games) { game in
                                        presentationGameCard(
                                            game: game,
                                            shouldShowScore: shouldShowScore(section.id),
                                            width: proxy.size.width
                                        )
                                    }
                                }
                                .padding(.bottom, 10)
                            }
                            .scrollIndicators(.hidden)
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
                .padding(.horizontal, 32)
                .padding(.top, 34)
                .padding(.bottom, 20)
                .onAppear {
                    if let index = sections.firstIndex(where: { $0.id == initiallySelectedGradeID }) {
                        selectedPageIndex = index
                    }
                }

                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 24, weight: .bold))
                }
                .padding(.leading, 18)
                .padding(.top, 10)
            }
        }
    }

    @ViewBuilder
    private func presentationGameCard(game: Game, shouldShowScore: Bool, width: CGFloat) -> some View {
        let ourStyle = ClubStyle.style(for: ourTeamLabel, configuration: clubConfiguration)
        let oppositionStyle = ClubStyle.style(for: game.opponent, configuration: clubConfiguration)

        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    ScorePill(
                        ourTeamLabel,
                        style: ourStyle,
                        fixedWidth: scorePillWidth
                    )
                    if shouldShowScore {
                        Text("\(game.ourGoals).\(game.ourBehinds) (\(game.ourScore))")
                            .font(.system(size: width > 1000 ? 52 : 42, weight: .black))
                            .minimumScaleFactor(0.75)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 10) {
                    ScorePill(
                        game.opponent,
                        style: oppositionStyle,
                        fixedWidth: scorePillWidth
                    )
                    if shouldShowScore {
                        Text("\(game.theirGoals).\(game.theirBehinds) (\(game.theirScore))")
                            .font(.system(size: width > 1000 ? 52 : 42, weight: .black))
                            .minimumScaleFactor(0.75)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Text(game.date.formatted(date: .complete, time: .omitted))
                .font(.system(size: width > 1000 ? 28 : 22, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 28) {
                presentationListColumn(
                    title: "Goal Kickers",
                    items: goalKickerItems(game),
                    style: ourStyle,
                    width: width
                )
                presentationListColumn(
                    title: "Best Players",
                    items: bestPlayerItems(game),
                    style: ourStyle,
                    width: width
                )
            }
        }
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private func presentationListColumn(title: String, items: [PresView.GoalKickerPresentationItem], style: ClubStyle.Style, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: width > 1000 ? 38 : 32, weight: .heavy))
                .foregroundStyle(style.text)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        if item.goals > 0 {
                            Text("\(item.goals) -")
                                .font(.system(size: width > 1000 ? 30 : 26, weight: .black))
                                .foregroundStyle(style.text)
                        }
                        Text(item.name)
                            .font(.system(size: width > 1000 ? 34 : 28, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func presentationListColumn(title: String, items: [String], style: ClubStyle.Style, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: width > 1000 ? 38 : 32, weight: .heavy))
                .foregroundStyle(style.text)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1).")
                            .font(.system(size: width > 1000 ? 30 : 26, weight: .black))
                            .foregroundStyle(style.text)
                        Text(item)
                            .font(.system(size: width > 1000 ? 34 : 28, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
