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

    private struct NarrationApprovalInputs: Equatable {
        let includeWeather: Bool
        let includeDates: Bool
        let includeSectionHeaders: Bool
        let includeVenue: Bool
        let includeBestPlayers: Bool
        let includeGoalKickers: Bool
        let includeGameNotes: Bool
        let welcomeMessage: String
        let gradeAnnouncements: [UUID: String]
    }

    @Query(sort: [SortDescriptor(\Game.date, order: .reverse)]) private var games: [Game]
    @Query(sort: [SortDescriptor(\Grade.name)]) private var grades: [Grade]
    @Query(sort: \Player.name) private var players: [Player]

    @State private var selectedPresentationGrade: GradePresentationSection?
    @StateObject private var aiNarrator = AIMCNarrator()
    @State private var aiNarrationPreview = ""
    @State private var aiHasApprovedNarration = false
    @State private var isPreviewSheetPresented = false
    @State private var isMissingAPIKeyAlertPresented = false
    @State private var playbackErrorMessage: String?
    @State private var isGeneratingAINarrationAudio = false
    @State private var welcomeMessage = ""
    @State private var openingAnnouncement = ""
    @State private var closingAnnouncement = ""
    @State private var gradeAnnouncements: [UUID: String] = [:]

    @AppStorage(AIMCStorageKeys.elevenLabsVoiceID) private var elevenLabsVoiceID = ""
    @AppStorage(AIMCStorageKeys.includeWeather) private var includeWeather = true
    @AppStorage(AIMCStorageKeys.includeDates) private var includeDates = false
    @AppStorage(AIMCStorageKeys.includeSectionHeaders) private var includeSectionHeaders = false
    @AppStorage(AIMCStorageKeys.includeVenue) private var includeVenue = true
    @AppStorage(AIMCStorageKeys.includeBestPlayers) private var includeBestPlayers = true
    @AppStorage(AIMCStorageKeys.includeGoalKickers) private var includeGoalKickers = true
    @AppStorage(AIMCStorageKeys.includeGameNotes) private var includeGameNotes = false

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

    private var isPlaybackErrorAlertPresented: Binding<Bool> {
        Binding(
            get: { playbackErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    playbackErrorMessage = nil
                }
            }
        )
    }

    private var narrationApprovalInputs: NarrationApprovalInputs {
        NarrationApprovalInputs(
            includeWeather: includeWeather,
            includeDates: includeDates,
            includeSectionHeaders: includeSectionHeaders,
            includeVenue: includeVenue,
            includeBestPlayers: includeBestPlayers,
            includeGoalKickers: includeGoalKickers,
            includeGameNotes: includeGameNotes,
            welcomeMessage: welcomeMessage,
            gradeAnnouncements: gradeAnnouncements
        )
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

    @ViewBuilder
    private var presentationList: some View {
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
                Toggle("Include venue", isOn: $includeVenue)
                Toggle("Include best players", isOn: $includeBestPlayers)
                Toggle("Include goal kickers", isOn: $includeGoalKickers)
                Toggle("Include game notes", isOn: $includeGameNotes)

                TextField("Welcome message", text: $welcomeMessage, axis: .vertical)
                    .lineLimit(2...4)

                ForEach(gradeSections) { section in
                    TextField("\(section.grade.name) announcement", text: gradeAnnouncementBinding(for: section.grade.id), axis: .vertical)
                        .lineLimit(2...4)
                }
            }
        }
    }

    @ViewBuilder
    private var aiControls: some View {
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
            .disabled(gradeSections.isEmpty || isGeneratingAINarrationAudio)
            .opacity((gradeSections.isEmpty || isGeneratingAINarrationAudio) ? 0.45 : 1.0)

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
    }

    private var startPresentationsButton: some View {
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

    private var contentStack: some View {
        VStack(spacing: 20) {
            presentationList
            aiControls
            startPresentationsButton
        }
    }

    private var aiPreviewSheet: some View {
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

    private func setGradeAnnouncement(_ message: String, for gradeID: UUID) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            gradeAnnouncements.removeValue(forKey: gradeID)
        } else {
            gradeAnnouncements[gradeID] = message
        }
    }

    private func gradeAnnouncementBinding(for gradeID: UUID) -> Binding<String> {
        Binding(
            get: { gradeAnnouncements[gradeID] ?? "" },
            set: { setGradeAnnouncement($0, for: gradeID) }
        )
    }

    private func announcementLine(_ message: String, fallback: String? = nil) -> String? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return fallback
    }

    private func scoreReadLine(for game: Game, teamName: String) -> String {
        let ourLine = "\(teamName) - \(game.ourGoals) goal \(game.ourBehinds) \(game.ourScore)"
        let theirLine = "\(game.opponent) \(game.theirGoals) goal \(game.theirBehinds) \(game.theirScore)"

        if game.ourScore > game.theirScore {
            return "\(ourLine) defeated \(theirLine)."
        } else if game.ourScore < game.theirScore {
            return "\(ourLine) lost to \(theirLine)."
        }
        return "\(ourLine) drew with \(theirLine)."
    }

    private func generateAINarrationPreview() {
        let teamName = clubConfiguration.clubTeam.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "Our Team"
        : clubConfiguration.clubTeam.name

        var lines: [String] = []
        if let openingLine = announcementLine(welcomeMessage, fallback: "Welcome everyone.") {
            lines.append(openingLine)
            lines.append(fourSecondPauseText)
        }

        if includeWeather {
            lines.append("Weather update: conditions look good for presentations.")
            lines.append(fourSecondPauseText)
        }

        for section in gradeSections {
            if includeSectionHeaders {
                lines.append("\(section.grade.name).")
            } else {
                lines.append("Now to \(section.grade.name).")
            }

            if let gradeLine = announcementLine(gradeAnnouncements[section.grade.id] ?? "") {
                lines.append(gradeLine)
            }

            if section.games.count > 1 {
                lines.append("We played \(section.games.count) games today.")
            }

            for (index, game) in section.games.enumerated() {
                var gameLineParts: [String] = []
                if section.games.count > 1 {
                    gameLineParts.append("In game \(index + 1),")
                }

                if shouldShowScore(for: section.grade.id) {
                    gameLineParts.append(scoreReadLine(for: game, teamName: teamName))
                }

                if includeDates {
                    gameLineParts.append("Date: \(game.date.formatted(date: .abbreviated, time: .omitted)).")
                }

                if includeVenue {
                    let cleanedVenue = game.venue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanedVenue.isEmpty {
                        gameLineParts.append("Venue: \(cleanedVenue).")
                    }
                }

                if includeBestPlayers {
                    let players = bestPlayerItems(for: game)
                    if !players.isEmpty, players.first != "None recorded" {
                        gameLineParts.append(bestPlayersNarration(for: players))
                    }
                }

                if includeGoalKickers {
                    let kickers = Array(goalKickerItems(for: game)
                        .filter { $0.goals > 0 }
                        .sorted { lhs, rhs in
                            if lhs.goals == rhs.goals {
                                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                            }
                            return lhs.goals < rhs.goals
                        })
                    if !kickers.isEmpty {
                        gameLineParts.append(goalKickersNarration(for: kickers))
                    }
                }

                if includeGameNotes {
                    let note = game.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !note.isEmpty {
                        gameLineParts.append("Coach note: \(note).")
                    }
                }

                lines.append(gameLineParts.joined(separator: " "))
            }
            lines.append(fourSecondPauseText)
        }
        aiNarrationPreview = lines.joined(separator: "\n\n")
        aiHasApprovedNarration = false
    }

    private func ordinalSuffix(for number: Int) -> String {
        let tens = (number / 10) % 10
        let ones = number % 10
        if tens == 1 { return "th" }
        switch ones {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    private func bestPlayersNarration(for players: [String]) -> String {
        let rankedLines = players
            .enumerated()
            .reversed()
            .map { index, name -> String in
                let rank = index + 1
                if rank == 1 {
                    let firstName = firstName(from: name)
                    return "And the Best Player today goes to...... \(name)......... Congratulations \(firstName). \(fourSecondPauseText)"
                }
                return "\(rank)\(ordinalSuffix(for: rank)) Best: \(name)."
            }
            .joined(separator: " ")

        return rankedLines
    }

    private func goalKickersNarration(for kickers: [GoalKickerPresentationItem]) -> String {
        let introLine = "Now to Goal Kickers....."

        let regularLines = kickers
            .map { "\($0.name), \(goalCountText($0.goals))." }
            .joined(separator: " ")

        let leadingGoalCount = kickers.map(\.goals).max() ?? 0
        let leadingKickers = kickers
            .filter { $0.goals == leadingGoalCount }
            .map(\.name)

        let leadingLine: String
        if leadingKickers.count > 1 {
            let names = ListFormatter.localizedString(byJoining: leadingKickers)
            let firstNames = ListFormatter.localizedString(byJoining: leadingKickers.map(firstName(from:)))
            leadingLine = "And the Leading Goal Kickers today were...... \(names), \(goalCountText(leadingGoalCount)). ......... Congratulations \(firstNames). \(fourSecondPauseText)"
        } else if let name = leadingKickers.first {
            let firstName = firstName(from: name)
            leadingLine = "And the Leading Goal Kicker today was...... \(name), \(goalCountText(leadingGoalCount)). ......... Congratulations \(firstName). \(fourSecondPauseText)"
        } else {
            leadingLine = ""
        }

        return [introLine, regularLines, leadingLine].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private var fourSecondPauseText: String {
        "........ ........"
    }

    private func goalCountText(_ goals: Int) -> String {
        goals == 1 ? "1 Goal" : "\(goals) Goals"
    }

    private func firstName(from fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fullName }
        return trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? trimmed
    }

    private func handleAIButtonTapped() {
        if aiNarrator.isSpeaking, aiNarrator.isPaused {
            aiNarrator.resume()
        } else if aiHasApprovedNarration {
            let apiKey = AIMCKeychainStore.loadSecret(for: AIMCSecrets.elevenLabsAPIKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let voiceID = elevenLabsVoiceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                isMissingAPIKeyAlertPresented = true
                return
            }
            guard !voiceID.isEmpty else {
                playbackErrorMessage = "Please set an ElevenLabs Voice ID in Settings → AI Master of Ceremonies."
                return
            }
            isGeneratingAINarrationAudio = true
            Task {
                defer { isGeneratingAINarrationAudio = false }
                do {
                    try await aiNarrator.speakApprovedReport(
                        text: aiNarrationPreview,
                        apiKey: apiKey,
                        voiceID: voiceID
                    )
                } catch {
                    playbackErrorMessage = error.localizedDescription
                }
            }
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
            contentStack
            .navigationTitle("Pres")
            .sheet(isPresented: $isPreviewSheetPresented) {
                aiPreviewSheet
            }
            .onChange(of: narrationApprovalInputs) { _, _ in
                aiHasApprovedNarration = false
            }
            .alert("ElevenLabs API Key Required", isPresented: $isMissingAPIKeyAlertPresented) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Please add your ElevenLabs API key in Settings → AI Master of Ceremonies before playback.")
            }
            .alert("Unable to Play Audio", isPresented: isPlaybackErrorAlertPresented) {
                Button("OK", role: .cancel) {
                    playbackErrorMessage = nil
                }
            } message: {
                Text(playbackErrorMessage ?? "Something went wrong while generating narration.")
            }
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
            .overlay {
                if isGeneratingAINarrationAudio {
                    GeneratingNarrationOverlayView()
                }
            }
        }
    }
}

private struct GeneratingNarrationOverlayView: View {
    @State private var isSpinning = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "football.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.orange)
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: isSpinning)

                ProgressView("AI is building voice…")
                    .font(.headline)
                    .tint(.white)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .onAppear {
            isSpinning = true
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
    @State private var openingEventAnnouncement = ""
    @State private var closingEventAnnouncement = ""
    @State private var gradeAnnouncementSlots: [UUID: String] = [:]
    @State private var gameAnnouncementSlots: [UUID: String] = [:]

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

    private func gradeAnnouncementBinding(for gradeID: UUID) -> Binding<String> {
        Binding(
            get: { gradeAnnouncementSlots[gradeID] ?? "" },
            set: { gradeAnnouncementSlots[gradeID] = $0 }
        )
    }

    private func gameAnnouncementBinding(for gameID: UUID) -> Binding<String> {
        Binding(
            get: { gameAnnouncementSlots[gameID] ?? "" },
            set: { gameAnnouncementSlots[gameID] = $0 }
        )
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
                                    announcementEntryCard(
                                        title: "General opening announcement",
                                        placeholder: "Add opening event or announcement",
                                        text: $openingEventAnnouncement,
                                        width: proxy.size.width
                                    )

                                    announcementEntryCard(
                                        title: "\(section.grade.name) announcement",
                                        placeholder: "Add announcement above this grade",
                                        text: gradeAnnouncementBinding(for: section.grade.id),
                                        width: proxy.size.width
                                    )

                                    ForEach(Array(section.games.enumerated()), id: \.element.id) { gameIndex, game in
                                        presentationGameCard(
                                            game: game,
                                            shouldShowScore: shouldShowScore(section.id),
                                            width: proxy.size.width
                                        )

                                        if gameIndex < section.games.count - 1 {
                                            announcementEntryCard(
                                                title: "Milestone announcement slot",
                                                placeholder: "Add milestone between games",
                                                text: gameAnnouncementBinding(for: game.id),
                                                width: proxy.size.width
                                            )
                                        }
                                    }

                                    announcementEntryCard(
                                        title: "General closing announcement",
                                        placeholder: "Add final event or thank-you",
                                        text: $closingEventAnnouncement,
                                        width: proxy.size.width
                                    )
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
    private func announcementEntryCard(title: String, placeholder: String, text: Binding<String>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: width > 1000 ? 28 : 22, weight: .heavy))
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
        }
        .padding(20)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
