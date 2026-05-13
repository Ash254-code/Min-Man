import SwiftUI
import SwiftData
import UIKit

struct PresView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss

    private var showsIPhoneBackButton: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    fileprivate struct GoalKickerPresentationItem: Identifiable {
        let id = UUID()
        let name: String
        let goals: Int
        let oppositionGoals: Int

        var goalsDisplayText: String {
            let oppositionGoals = max(0, min(oppositionGoals, goals))
            guard oppositionGoals > 0 else { return "\(goals)" }
            return "\(goals) (\(oppositionGoals))"
        }
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
        let closingMessage: String
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
    @FocusState private var isAINarrationPreviewFocused: Bool
    @State private var isGeneratingAINarrationAudio = false
    @State private var welcomeMessage = "Thank You and welome everyone. Its great to see so many here and I hope everyone has enjoyed their day and can stick around for a while longer tonight............ Ok, we'll get started with football presentations.............."
    @State private var openingAnnouncement = ""
    @State private var closingAnnouncement = "Thats a wrap for presentations, thanks again for sticking around, I hope you enjoy your night and safe travels home. Thank you!"
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
        Dictionary(orderedGrades.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
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
        Dictionary(grades.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var playerNameByID: [UUID: String] {
        Dictionary(players.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
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
            closingMessage: closingAnnouncement,
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Last 5 Days")
                    .font(.title3.weight(.bold))

                VStack(alignment: .leading, spacing: 10) {
                    if sortedGames.isEmpty {
                        ContentUnavailableView(
                            "No games in the last 5 days",
                            systemImage: "calendar",
                            description: Text("Recent games will appear here.")
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .clubGlassSurface(cornerRadius: 14)
                    } else {
                        ForEach(gradeSections) { section in
                            Button {
                                selectedPresentationGrade = section
                            } label: {
                                PresGradeRow(
                                    gradeName: section.grade.name,
                                    gameCount: section.games.count
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .clubGlassSurface(cornerRadius: 14)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(14)
                .clubGlassSurface()

                Text("Announcements")
                    .font(.title3.weight(.bold))

                VStack(alignment: .leading, spacing: 10) {
                    announcementSubCard(title: "Welcome message", text: $welcomeMessage)

                    ForEach(gradeSections) { section in
                        announcementSubCard(
                            title: "\(section.grade.name) announcement",
                            text: gradeAnnouncementBinding(for: section.grade.id)
                        )
                    }

                    announcementSubCard(title: "Closing message", text: $closingAnnouncement)
                }
                .padding(14)
                .clubGlassSurface()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.clear)
    }

    @ViewBuilder
    private func announcementSubCard(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(title, text: text, axis: .vertical)
                .lineLimit(2...4)
        }
        .padding(12)
        .clubGlassSurface(cornerRadius: 14)
    }

    private var toolbarAIButton: some View {
        Button {
            handleAIButtonTapped()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: aiHasApprovedNarration ? "play.circle.fill" : "sparkles")
                    .font(.system(size: 14, weight: .bold))
                Text("AI")
                    .font(.system(size: 15, weight: .bold))
            }
                .foregroundStyle(.white)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 64, minHeight: 34)
                .padding(.horizontal, 10)
                .background(Color.purple, in: Capsule(style: .continuous))
                .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .disabled(gradeSections.isEmpty || isGeneratingAINarrationAudio)
        .opacity((gradeSections.isEmpty || isGeneratingAINarrationAudio) ? 0.45 : 1.0)
    }

    private var pauseResumeButton: some View {
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
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.orange, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var stopAIButton: some View {
        Button {
            aiNarrator.stop()
        } label: {
            Label("Stop", systemImage: "stop.circle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.red, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var toolbarStartButton: some View {
        Button {
            startPresentations()
        } label: {
            Text("Start")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 72, minHeight: 34)
                .padding(.horizontal, 10)
                .background(Color.blue, in: Capsule(style: .continuous))
                .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .disabled(gradeSections.isEmpty)
        .opacity(gradeSections.isEmpty ? 0.45 : 1.0)
    }

    @ViewBuilder
    private var aiPlaybackControls: some View {
        if aiNarrator.isSpeaking {
            HStack(spacing: 12) {
                pauseResumeButton
                stopAIButton
            }
            .padding(.horizontal, 20)
        }
    }

    private var contentStack: some View {
        VStack(spacing: 20) {
            presentationList
            aiPlaybackControls
        }
    }

    private var aiPreviewSheet: some View {
        NavigationStack {
            ScrollView {
                TextEditor(text: $aiNarrationPreview)
                    .focused($isAINarrationPreviewFocused)
                    .frame(maxWidth: .infinity, minHeight: 320, alignment: .leading)
                    .padding()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isAINarrationPreviewFocused = true
                    }
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
        if id == GameGoalKickerEntry.oppositionPlayerID {
            return GameGoalKickerEntry.oppositionPlayerName
        }
        return playerNameByID[id] ?? "Unknown"
    }

    private func goalKickerItems(for game: Game) -> [GoalKickerPresentationItem] {
        guard !game.goalKickers.isEmpty else {
            return [GoalKickerPresentationItem(name: "None recorded", goals: 0, oppositionGoals: 0)]
        }

        return game.goalKickers
            .sorted { $0.goals > $1.goals }
            .map { GoalKickerPresentationItem(name: playerName(for: $0.playerID), goals: $0.goals, oppositionGoals: $0.oppositionGoals) }
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
        let ourLine = "\(teamName) - \(scoreReadout(goals: game.ourGoals, behinds: game.ourBehinds, total: game.ourScore))"
        let theirLine = "\(game.opponent) \(scoreReadout(goals: game.theirGoals, behinds: game.theirBehinds, total: game.theirScore))"

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

        if let closingLine = announcementLine(closingAnnouncement) {
            lines.append(closingLine)
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
                    return "And the Best Player today goes to...... \(dramaticAnnouncementName(name))......... Congratulations \(firstName). \(fourSecondPauseText)"
                }
                return "\(rank)\(ordinalSuffix(for: rank)) Best: \(name)."
            }
            .joined(separator: " ")

        return rankedLines
    }

    private func goalKickersNarration(for kickers: [GoalKickerPresentationItem]) -> String {
        let introLine = "Now to Goal Kickers....."

        let leadingGoalCount = kickers.map(\.goals).max() ?? 0
        let leadingKickers = kickers
            .filter { $0.goals == leadingGoalCount }
            .map(\.name)

        let regularLines = kickers
            .filter { $0.goals < leadingGoalCount }
            .map { "\($0.name), \($0.goalsDisplayText) goals." }
            .joined(separator: " ")

        let leadingLine: String
        if leadingKickers.count > 1 {
            let names = ListFormatter.localizedString(byJoining: leadingKickers.map(dramaticAnnouncementName))
            let firstNames = ListFormatter.localizedString(byJoining: leadingKickers.map(firstName(from:)))
            leadingLine = "And the leading goal kickers today were......... \(names) with \(goalCountText(leadingGoalCount)).. Congratulations \(firstNames)!! \(fourSecondPauseText)"
        } else if let name = leadingKickers.first {
            let firstName = firstName(from: name)
            leadingLine = "And the leading goal kicker today was......... \(dramaticAnnouncementName(name)) with \(goalCountText(leadingGoalCount)).. Congratulations \(firstName)!! \(fourSecondPauseText)"
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

    private func dramaticAnnouncementName(_ fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fullName.uppercased() }
        return trimmed.uppercased() + "!!"
    }

    private func scoreReadout(goals: Int, behinds: Int, total: Int) -> String {
        let goalWord = goals == 1 ? "goal" : "goals"
        return "\(goals) \(goalWord) \(behinds).. \(total)"
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
            ZStack {
                ClubTheme.bgGradient
                    .ignoresSafeArea()

                contentStack
            }
            .navigationTitle("Pres")
            .iPhoneTransparentTopChrome()
            .toolbar {
                if showsIPhoneBackButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") {
                            dismiss()
                        }
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    toolbarStartButton
                    toolbarAIButton
                }
            }
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
        .toolbarBackground(UIDevice.current.userInterfaceIdiom == .phone ? .hidden : .automatic, for: .navigationBar)
    }
}

private struct GeneratingNarrationOverlayView: View {

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                LoadingFootballView(
                    "AI is building voice…",
                    tint: .white,
                    size: 42,
                    font: .headline
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                                    if section.games.count == 2, !shouldShowScore(section.id) {
                                        twoGameBestPlayersOnlyLayout(
                                            games: section.games,
                                            width: proxy.size.width
                                        )
                                    } else {
                                        ForEach(Array(section.games.enumerated()), id: \.element.id) { index, game in
                                            presentationGameCard(
                                                game: game,
                                                shouldShowScore: shouldShowScore(section.id),
                                                width: proxy.size.width,
                                                gameIndex: index,
                                                totalGames: section.games.count
                                            )
                                        }
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
    private func twoGameBestPlayersOnlyLayout(games: [Game], width: CGFloat) -> some View {
        let ourStyle = ClubStyle.style(for: ourTeamLabel, configuration: clubConfiguration)
        let usesWideLayout = width > 700

        if usesWideLayout {
            HStack(alignment: .top, spacing: 20) {
                ForEach(Array(games.prefix(2).enumerated()), id: \.element.id) { index, game in
                    bestPlayersGamePanel(
                        title: "Game \(index + 1)",
                        game: game,
                        style: ourStyle,
                        width: width
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(games.prefix(2).enumerated()), id: \.element.id) { index, game in
                    bestPlayersGamePanel(
                        title: "Game \(index + 1)",
                        game: game,
                        style: ourStyle,
                        width: width
                    )
                }
            }
        }
    }

    private func bestPlayersGamePanel(title: String, game: Game, style: ClubStyle.Style, width: CGFloat) -> some View {
        VStack {
            presentationListColumn(
                title: title,
                items: bestPlayerItems(game),
                style: style,
                width: width
            )
        }
        .frame(maxWidth: .infinity, minHeight: width > 1000 ? 270 : 230, alignment: .topLeading)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
    private func presentationGameCard(
        game: Game,
        shouldShowScore: Bool,
        width: CGFloat,
        gameIndex: Int,
        totalGames: Int
    ) -> some View {
        let ourStyle = ClubStyle.style(for: ourTeamLabel, configuration: clubConfiguration)
        let oppositionStyle = ClubStyle.style(for: game.opponent, configuration: clubConfiguration)

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                if totalGames == 2 {
                    Text("Game \(gameIndex + 1)")
                        .font(.system(size: width > 1000 ? 22 : 18, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .center, spacing: -14) {
                    VStack(alignment: .center, spacing: 10) {
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
                    .frame(maxWidth: .infinity, alignment: .center)

                    PresentationResultBadge(
                        shouldShowScore: shouldShowScore,
                        ourScore: game.ourScore,
                        theirScore: game.theirScore,
                        size: width > 1000 ? 130 : 104
                    )
                    .zIndex(1)

                    VStack(alignment: .center, spacing: 10) {
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
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(24)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            HStack(alignment: .top, spacing: 20) {
                VStack {
                    presentationListColumn(
                        title: "Goal Kickers",
                        items: goalKickerItems(game),
                        style: ourStyle,
                        width: width
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack {
                    presentationListColumn(
                        title: "Best Players",
                        items: bestPlayerItems(game),
                        style: ourStyle,
                        width: width
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
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
                            Text("\(item.goalsDisplayText) -")
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

private struct PresentationResultBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    let shouldShowScore: Bool
    let ourScore: Int
    let theirScore: Int
    let size: CGFloat

    private var label: String {
        guard shouldShowScore else { return "V" }
        if ourScore > theirScore { return "W" }
        if ourScore < theirScore { return "L" }
        return "D"
    }

    private var fillColor: Color {
        guard shouldShowScore else { return Color.clear }
        if ourScore > theirScore { return .green }
        if ourScore < theirScore { return .red }
        return .orange
    }

    private var textColor: Color {
        guard shouldShowScore else { return colorScheme == .dark ? .white : .black }
        return .white
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(fillColor)
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: shouldShowScore ? 2 : 0)
            Text(label)
                .font(.system(size: size * 0.45, weight: .black))
                .foregroundStyle(textColor)
        }
        .frame(width: size, height: size)
    }
}
