import SwiftUI
import SwiftData
import UIKit
import PDFKit

@Model
final class StatType {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, isEnabled: Bool = true, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
    }
}

extension StatType {
    var voiceAliases: [String] {
        let canonical = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if canonical.isEmpty { return [] }
        let lowercase = canonical.lowercased()
        let builtIn: [String: [String]] = [
            "kick": ["kick", "kicks"],
            "handball": ["handball", "hand ball", "handpass", "hand pass"],
            "mark": ["mark", "marks"],
            "tackle": ["tackle", "tackles"],
            "goal": ["goal", "goals"],
            "behind": ["behind", "behinds", "point", "points", "rushed behind"]
        ]
        let aliases = builtIn[lowercase] ?? [canonical]
        return Array(Set(aliases + [canonical]))
    }
}

@Model
final class StatsSession {
    var sessionId: UUID
    var gradeId: UUID
    var opposition: String
    var date: Date
    var venue: String
    var createdAt: Date

    init(sessionId: UUID = UUID(), gradeId: UUID, opposition: String, date: Date, venue: String, createdAt: Date = Date()) {
        self.sessionId = sessionId
        self.gradeId = gradeId
        self.opposition = opposition
        self.date = date
        self.venue = venue
        self.createdAt = createdAt
    }
}

@Model
final class StatEvent {
    var id: UUID
    var sessionId: UUID
    var playerId: UUID
    var statTypeId: UUID
    var quarter: String
    var timestamp: Date
    var sourceRaw: String
    var transcript: String?
    var normalizedTranscript: String?
    var parserConfidence: Double?
    var efficiencyVoteRaw: String?

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        playerId: UUID,
        statTypeId: UUID,
        quarter: String,
        timestamp: Date = Date(),
        sourceRaw: String,
        transcript: String? = nil,
        normalizedTranscript: String? = nil,
        parserConfidence: Double? = nil,
        efficiencyVoteRaw: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.playerId = playerId
        self.statTypeId = statTypeId
        self.quarter = quarter
        self.timestamp = timestamp
        self.sourceRaw = sourceRaw
        self.transcript = transcript
        self.normalizedTranscript = normalizedTranscript
        self.parserConfidence = parserConfidence
        self.efficiencyVoteRaw = efficiencyVoteRaw
    }
}

enum StatsEventSource: String, CaseIterable {
    case manual
    case voice
}

private enum EfficiencyVote: String {
    case thumbsUp
    case thumbsDown
}

private struct StatRecordBanner: Equatable {
    let text: String
    let isSuccess: Bool
}

private enum StatsDefaults {
    static let statNames = ["Kick", "Handball", "Mark", "Tackle", "Goal", "Behind"]
}

struct StatsRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StatsSession.createdAt, order: .reverse) private var sessions: [StatsSession]
    @Query(sort: \Grade.displayOrder) private var grades: [Grade]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        StatsSessionSetupView()
                    } label: {
                        Label("New Stats Session", systemImage: "plus.circle.fill")
                    }
                }

                Section("Recent Sessions") {
                    if sessions.isEmpty {
                        Text("No sessions yet")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(sessions) { session in
                        NavigationLink {
                            LiveStatsView(session: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(gradeName(for: session.gradeId))
                                    .font(.headline)
                                Text("vs \(session.opposition) • \(session.date, format: Date.FormatStyle(date: .abbreviated, time: .omitted))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stats")
            .task {
                seedDefaultStatTypesIfNeeded()
            }
        }
    }

    private func gradeName(for id: UUID) -> String {
        grades.first(where: { $0.id == id })?.name ?? "Unknown Grade"
    }

    private func seedDefaultStatTypesIfNeeded() {
        let existing = (try? modelContext.fetch(FetchDescriptor<StatType>())) ?? []
        guard existing.isEmpty else { return }

        for (index, name) in StatsDefaults.statNames.enumerated() {
            modelContext.insert(StatType(name: name, isEnabled: true, sortOrder: index))
        }

        try? modelContext.save()
    }
}

struct StatsTypesSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StatType.sortOrder) private var statTypes: [StatType]
    @State private var newName = ""

    var body: some View {
        List {
            Section("Add Stat Type") {
                TextField("Stat name", text: $newName)
                Button("Add") {
                    addStatType()
                }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section("Stat Types") {
                ForEach(Array(statTypes.enumerated()), id: \.element.id) { index, type in
                    HStack {
                        TextField("Name", text: Binding(
                            get: { type.name },
                            set: {
                                type.name = $0
                                save()
                            }
                        ))

                        Toggle("Enabled", isOn: Binding(
                            get: { type.isEnabled },
                            set: {
                                type.isEnabled = $0
                                save()
                            }
                        ))
                        .labelsHidden()
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            modelContext.delete(type)
                            resequence()
                            save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .moveDisabled(false)
                    .onAppear {
                        if type.sortOrder != index {
                            type.sortOrder = index
                            save()
                        }
                    }
                }
                .onMove(perform: move)
            }

            Section("Speech") {
                NavigationLink {
                    SpeechSetupView()
                } label: {
                    Label("Speech Setup", systemImage: "waveform.badge.mic")
                }
            }
        }
        .navigationTitle("Stats")
        .toolbar {
            EditButton()
        }
        .task {
            seedDefaultStatTypesIfNeeded()
        }
    }

    private func addStatType() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(StatType(name: trimmed, isEnabled: true, sortOrder: statTypes.count))
        newName = ""
        save()
    }

    private func move(from source: IndexSet, to destination: Int) {
        var arranged = statTypes
        arranged.move(fromOffsets: source, toOffset: destination)
        for (index, type) in arranged.enumerated() {
            type.sortOrder = index
        }
        save()
    }

    private func resequence() {
        for (index, type) in statTypes.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
            type.sortOrder = index
        }
    }

    private func save() {
        try? modelContext.save()
    }

    private func seedDefaultStatTypesIfNeeded() {
        let existing = (try? modelContext.fetch(FetchDescriptor<StatType>())) ?? []
        guard existing.isEmpty else { return }
        for (index, name) in StatsDefaults.statNames.enumerated() {
            modelContext.insert(StatType(name: name, isEnabled: true, sortOrder: index))
        }
        save()
    }
}

private struct SpeechPromptResult: Identifiable, Codable {
    let id: UUID
    let expected: String
    let heard: String
    let passed: Bool
    let timestamp: Date
}

private struct SpeechPracticePrompt: Identifiable {
    enum Group: String, CaseIterable {
        case basicStats = "Basic Stat Words"
        case playerNames = "Player Names"
        case simpleCommands = "Simple Commands"
    }

    let id: String
    let group: Group
    let expected: String

    init(group: Group, expected: String) {
        self.group = group
        self.expected = expected
        self.id = "\(group.rawValue.lowercased())::\(expected.lowercased())"
    }
}

struct SpeechSetupView: View {
    @Query(sort: \Grade.displayOrder) private var grades: [Grade]
    @Query(sort: \Player.name) private var allPlayers: [Player]
    @Query(sort: \StatType.sortOrder) private var allStatTypes: [StatType]
    @Query(sort: \StatsSession.createdAt, order: .reverse) private var sessions: [StatsSession]

    @StateObject private var speechService = PressHoldSpeechService()
    private let parser = StatsVoiceParser()

    @State private var selectedGradeId: UUID?
    @State private var activePromptId: String?
    @State private var heardByPrompt: [String: String] = [:]
    @State private var passByPrompt: [String: Bool] = [:]
    @State private var freeTestHeard = ""
    @State private var freeTestActive = false
    @State private var recentResults: [SpeechPromptResult] = []
    @AppStorage("speech_setup_recent_results") private var recentResultsData = ""

    var body: some View {
        List {
            Section("Introduction") {
                Text("Test what speech recognition hears for stats entry. This checks stat words, player names, and simple commands. It helps setup testing, but does not permanently train your voice.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Setup Grade") {
                Picker("Grade", selection: $selectedGradeId) {
                    Text("Select Grade").tag(Optional<UUID>.none)
                    ForEach(grades.filter { $0.isActive }) { grade in
                        Text(grade.name).tag(Optional(grade.id))
                    }
                }
                if sessions.isEmpty {
                    Text("No active stats session found. Select a grade to load player names and numbers for speech testing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Vocabulary Preview") {
                ForEach(vocabularyPreview, id: \.self) { token in
                    Text(token)
                        .font(.body.monospaced())
                }
                if vocabularyPreview.isEmpty {
                    Text("No vocabulary available for this grade.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Guided Practice") {
                ForEach(SpeechPracticePrompt.Group.allCases, id: \.rawValue) { group in
                    let prompts = promptsForGroup(group)
                    if !prompts.isEmpty {
                        Text(group.rawValue)
                            .font(.headline)
                            .padding(.top, 6)

                        ForEach(prompts) { prompt in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(prompt.expected)
                                    .font(.title3.weight(.semibold))

                                Button {
                                    // press-and-hold only
                                } label: {
                                    Label("Speak", systemImage: "mic.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(activePromptId == prompt.id ? .red : .blue)
                                .onLongPressGesture(minimumDuration: 0.01, maximumDistance: .infinity, pressing: { isPressing in
                                    if isPressing {
                                        activePromptId = prompt.id
                                        speechService.startListening(vocabulary: speechVocabulary)
                                    } else if activePromptId == prompt.id {
                                        speechService.stopListening { transcript in
                                            applyPromptResult(prompt: prompt, transcript: transcript)
                                        }
                                    }
                                }, perform: {})

                                Text("Expected: \(prompt.expected)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Heard: \(heardByPrompt[prompt.id] ?? "—")")
                                    .font(.caption)
                                if let passed = passByPrompt[prompt.id] {
                                    Text(passed ? "Result: Pass" : "Result: Mismatch")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(passed ? .green : .red)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            Section("Free Speech Test") {
                Button {
                    // press-and-hold only
                } label: {
                    Label("Speak", systemImage: "mic.circle.fill")
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(freeTestActive ? .red : .blue)
                .onLongPressGesture(minimumDuration: 0.01, maximumDistance: .infinity, pressing: { isPressing in
                    if isPressing {
                        freeTestActive = true
                        speechService.startListening(vocabulary: speechVocabulary)
                    } else if freeTestActive {
                        speechService.stopListening { transcript in
                            freeTestActive = false
                            freeTestHeard = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }, perform: {})

                Text("Heard: \(freeTestHeard.isEmpty ? "—" : freeTestHeard)")
                    .font(.body.monospaced())
            }

            Section("Recognition Summary") {
                Text("\(matchedCount) / \(attemptedCount) prompts matched")
                    .font(.headline)

                if problemItems.isEmpty {
                    Text("Problem items: None")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Problem items:")
                        .font(.subheadline.weight(.semibold))
                    ForEach(problemItems, id: \.self) { item in
                        Text(item)
                            .foregroundStyle(.red)
                    }
                }
            }

            if !recentResults.isEmpty {
                Section("Recent Tests") {
                    ForEach(recentResults) { result in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Expected: \(result.expected)")
                            Text("Heard: \(result.heard)")
                                .foregroundStyle(.secondary)
                            Text(result.passed ? "Pass" : "Mismatch")
                                .foregroundStyle(result.passed ? .green : .red)
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            }
        }
        .navigationTitle("Speech Setup")
        .onAppear {
            if selectedGradeId == nil {
                selectedGradeId = sessions.first?.gradeId ?? grades.first(where: { $0.isActive })?.id
            }
            loadRecentResults()
        }
    }

    private var selectedPlayers: [Player] {
        guard let selectedGradeId else { return [] }
        return allPlayers.filter { $0.isActive && $0.gradeIDs.contains(selectedGradeId) }
    }

    private var enabledStatTypes: [StatType] {
        allStatTypes.filter { $0.isEnabled }.sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    private var speechVocabulary: [String] {
        let statPhrases = enabledStatTypes.flatMap { $0.voiceAliases }
        let rosterPhrases = selectedPlayers.flatMap { player -> [String] in
            var values = [player.name, player.lastName]
            if let number = player.number {
                values.append(String(number))
                values.append("number \(number)")
            }
            return values
        }
        return Array(Set(statPhrases + rosterPhrases)).filter { !$0.isEmpty }
    }

    private var vocabularyPreview: [String] {
        speechVocabulary.sorted()
    }

    private var prompts: [SpeechPracticePrompt] {
        var values: [SpeechPracticePrompt] = enabledStatTypes.prefix(6).map {
            SpeechPracticePrompt(group: .basicStats, expected: $0.name)
        }

        for player in selectedPlayers.prefix(4) {
            values.append(SpeechPracticePrompt(group: .playerNames, expected: player.name))
            values.append(SpeechPracticePrompt(group: .playerNames, expected: player.lastName))
            if let number = player.number {
                values.append(SpeechPracticePrompt(group: .playerNames, expected: String(number)))
            }
        }

        if let playerWithNumber = selectedPlayers.first(where: { $0.number != nil }), let number = playerWithNumber.number {
            values.append(SpeechPracticePrompt(group: .simpleCommands, expected: "kick \(number)"))
            values.append(SpeechPracticePrompt(group: .simpleCommands, expected: "kick \(playerWithNumber.lastName)"))
        }
        if let player2 = selectedPlayers.dropFirst().first(where: { $0.number != nil }), let number2 = player2.number {
            values.append(SpeechPracticePrompt(group: .simpleCommands, expected: "handball \(number2)"))
            values.append(SpeechPracticePrompt(group: .simpleCommands, expected: "mark \(player2.lastName)"))
        }
        return values
    }

    private func promptsForGroup(_ group: SpeechPracticePrompt.Group) -> [SpeechPracticePrompt] {
        prompts.filter { $0.group == group }
    }

    private var attemptedCount: Int {
        passByPrompt.count
    }

    private var matchedCount: Int {
        passByPrompt.values.filter { $0 }.count
    }

    private var problemItems: [String] {
        prompts.compactMap { prompt in
            guard let pass = passByPrompt[prompt.id], pass == false else { return nil }
            return prompt.expected
        }
    }

    private func applyPromptResult(prompt: SpeechPracticePrompt, transcript: String) {
        activePromptId = nil
        let heard = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        heardByPrompt[prompt.id] = heard
        let passed = parser.normalize(heard) == parser.normalize(prompt.expected)
        passByPrompt[prompt.id] = passed

        let result = SpeechPromptResult(
            id: UUID(),
            expected: prompt.expected,
            heard: heard,
            passed: passed,
            timestamp: Date()
        )
        recentResults.insert(result, at: 0)
        recentResults = Array(recentResults.prefix(20))
        saveRecentResults()
    }

    private func loadRecentResults() {
        guard let data = recentResultsData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([SpeechPromptResult].self, from: data) else {
            recentResults = []
            return
        }
        recentResults = decoded
    }

    private func saveRecentResults() {
        guard let data = try? JSONEncoder().encode(recentResults),
              let value = String(data: data, encoding: .utf8) else { return }
        recentResultsData = value
    }
}

struct StatsSessionSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Grade.displayOrder) private var grades: [Grade]

    @State private var selectedGradeId: UUID?
    @State private var opposition = ""
    @State private var date = Date()
    @State private var venue = ""
    @State private var createdSession: StatsSession?
    @State private var showLiveStats = false
    @State private var clubConfiguration = ClubConfigurationStore.load()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                setupCard(title: "Session Setup", systemImage: "sportscourt") {
                    HStack(spacing: 12) {
                        rowLabel("Grade")
                        Spacer()
                        Menu {
                            Button("Select…") { selectedGradeId = nil }
                            ForEach(grades.filter { $0.isActive }) { grade in
                                Button(grade.name) {
                                    selectedGradeId = grade.id
                                }
                            }
                        } label: {
                            setupMenuLabel(title: selectedGradeName ?? "Select…")
                        }
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .font(.body)

                    HStack(spacing: 12) {
                        rowLabel("Opponent")
                        Spacer()
                        Menu {
                            Button("Select…") {
                                opposition = ""
                                if !venueOptions.contains(venue) {
                                    venue = ""
                                }
                            }
                            ForEach(oppositionNames, id: \.self) { name in
                                Button(name) {
                                    opposition = name
                                    if !venueOptions.contains(venue) {
                                        venue = ""
                                    }
                                }
                            }
                        } label: {
                            setupMenuLabel(title: opposition.isEmpty ? "Select…" : opposition)
                        }
                    }

                    HStack(spacing: 12) {
                        rowLabel("Venue")
                        Spacer()
                        Menu {
                            Button("Select…") { venue = "" }
                            ForEach(venueOptions, id: \.self) { name in
                                Button(name) {
                                    venue = name
                                }
                            }
                        } label: {
                            setupMenuLabel(title: venue.isEmpty ? "Select…" : venue)
                        }
                        .disabled(venueOptions.isEmpty)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            Button {
                startSession()
            } label: {
                Text("Start Session")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(canStart ? Color.accentColor : Color.gray.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .disabled(!canStart)
        }
        .navigationTitle("New Stats Session")
        .onAppear {
            clubConfiguration = ClubConfigurationStore.load()
        }
        .navigationDestination(isPresented: $showLiveStats) {
            if let createdSession {
                LiveStatsView(session: createdSession)
            }
        }
    }

    private var canStart: Bool {
        selectedGradeId != nil && !opposition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedGradeName: String? {
        grades.first(where: { $0.id == selectedGradeId })?.name
    }

    private var oppositionNames: [String] {
        clubConfiguration.sortedOppositions.map(\.name)
    }

    private var selectedOpposition: OppositionTeamProfile? {
        clubConfiguration.sortedOppositions.first(where: { $0.name == opposition })
    }

    private var venueOptions: [String] {
        let combined = clubConfiguration.clubTeam.sanitizedVenues + (selectedOpposition?.sanitizedVenues ?? [])
        return Array(Set(combined)).sorted()
    }

    private func rowLabel(_ title: String) -> some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
    }

    private func setupMenuLabel(title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.body)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func setupCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func startSession() {
        guard let selectedGradeId else { return }
        let session = StatsSession(
            gradeId: selectedGradeId,
            opposition: opposition.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date,
            venue: venue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(session)
        try? modelContext.save()
        createdSession = session
        showLiveStats = true
    }
}

private struct TotalsRow: Identifiable {
    let id = UUID()
    let player: Player
    let countsByStatId: [UUID: Int]
}

private enum PlayerGridOrder: String, CaseIterable, Identifiable {
    case number
    case firstName
    case lastName

    var id: String { rawValue }

    var title: String {
        switch self {
        case .number:
            return "Number"
        case .firstName:
            return "First Name"
        case .lastName:
            return "Last Name"
        }
    }
}

private struct ReportPreviewDocument: Identifiable {
    let id = UUID()
    let url: URL
}

struct LiveStatsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let session: StatsSession

    @Query(sort: \Grade.displayOrder) private var grades: [Grade]
    @Query(sort: \Player.name) private var allPlayers: [Player]
    @Query(sort: \StatType.sortOrder) private var allStatTypes: [StatType]
    @Query(sort: \StatEvent.timestamp, order: .reverse) private var allEvents: [StatEvent]

    @State private var selectedQuarter = "Q1"
    @State private var selectedPlayerId: UUID?
    @State private var selectedStatTypeId: UUID?
    @State private var lastMessage: String?
    @State private var showEditEvent: StatEvent?
    @State private var reportPreviewDocument: ReportPreviewDocument?
    @State private var shareURL: URL?
    @State private var showTotals = false
    @State private var feedbackToken = UUID()
    @State private var lastHeardTranscript = ""
    @State private var lastVoiceDebug: VoiceParseResult?
    @State private var remainingQuarterSeconds = 0
    @State private var isQuarterTimerRunning = false
    @State private var quarterTimerTask: Task<Void, Never>?
    @State private var visiblePlayerIDs: Set<UUID> = []
    @State private var savedVisiblePlayerIDs: Set<UUID> = []
    @State private var playerGridOrder: PlayerGridOrder = .number
    @State private var savedPlayerGridOrder: PlayerGridOrder = .number
    @State private var showPlayerVisibilityEditor = false
    @State private var pendingEfficiencyEventID: UUID?
    @State private var showEfficiencyVotePrompt = false
    @State private var showAllPlayers = false
    @State private var statusBanner: StatRecordBanner?
    @State private var statusBannerTask: Task<Void, Never>?
    @StateObject private var speechService = PressHoldSpeechService()
    private let parser = StatsVoiceParser()
    private let ourTeamStatPlayerID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA") ?? UUID()
    private let oppositionTeamStatPlayerID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB") ?? UUID()

    var body: some View {
        GeometryReader { proxy in
            let _: CGFloat = 8
            let availableWidth = max(proxy.size.width - 24, 640)
            let leftPanelWidth = min(max(availableWidth * 0.62, 420), availableWidth - 300)
            let rightPanelWidth = max(availableWidth - leftPanelWidth - 12, 290)
            VStack(spacing: 12) {
                headerBannerArea
                    .frame(height: 76)
                combinedScoreAndActionsPanel
                    .frame(height: topPanelHeight)

                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 10) {
                        playerSelectionPanel
                    }
                    .frame(width: leftPanelWidth)

                    VStack(spacing: 12) {
                        statButtonsPanel
                            .frame(height: rightStatActionsHeight)
                        recentEventsPanel
                    }
                    .frame(width: rightPanelWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                bottomControlBar
                    .frame(height: max(proxy.size.height * 0.11, 90))
                    .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
        .sheet(item: $showEditEvent) { event in
            EditStatEventView(event: event, players: playersForGrade, statTypes: enabledStatTypes)
        }
        .sheet(isPresented: $showTotals) {
            StatsTotalsView(
                rows: totalsRows,
                statTypes: enabledStatTypes
            )
        }
        .sheet(item: $reportPreviewDocument) { document in
            StatsReportPreviewSheet(
                url: document.url,
                onShare: { shareURL = document.url }
            )
        }
        .sheet(item: $reportPreviewDocument) { document in
            StatsReportPreviewSheet(
                url: document.url,
                onShare: { shareURL = document.url }
            )
        }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
        .sheet(isPresented: $showPlayerVisibilityEditor) {
            PlayerVisibilityEditorView(
                players: playersForGrade,
                initialSelection: savedVisiblePlayerIDs,
                initialGridOrder: savedPlayerGridOrder,
                onSave: { updatedSelection, updatedGridOrder in
                    savedVisiblePlayerIDs = updatedSelection
                    visiblePlayerIDs = updatedSelection
                    savedPlayerGridOrder = updatedGridOrder
                    playerGridOrder = updatedGridOrder
                    showAllPlayers = false
                    if let selectedPlayerId, !updatedSelection.contains(selectedPlayerId) {
                        self.selectedPlayerId = nil
                    }
                }
            )
        }
        .overlay {
            if showEfficiencyVotePrompt {
                efficiencyRatingPrompt
            }
        }
        .onDisappear {
            statusBannerTask?.cancel()
            stopQuarterTimer()
            if speechService.isRecording {
                speechService.stopListening()
            }
        }
        .onAppear {
            if visiblePlayerIDs.isEmpty {
                let defaults = Set(playersForGrade.map(\.id))
                visiblePlayerIDs = defaults
                savedVisiblePlayerIDs = defaults
            }
            playerGridOrder = savedPlayerGridOrder
            showAllPlayers = false
            configureQuarterTimer(reset: true)
        }
        .onChange(of: selectedQuarter) { _, _ in
            configureQuarterTimer(reset: true)
        }
        .onChange(of: feedbackToken) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                if !speechService.isRecording {
                    withAnimation(.easeOut(duration: 0.2)) {
                        lastMessage = nil
                    }
                }
            }
        }
    }

    private var playersForGrade: [Player] {
        allPlayers.filter { $0.isActive && $0.gradeIDs.contains(session.gradeId) }
    }

    private var displayedPlayers: [Player] {
        let source = playersForGrade
        let filtered = visiblePlayerIDs.isEmpty ? source : source.filter { visiblePlayerIDs.contains($0.id) }
        return filtered.sorted(by: playerSortPredicate)
    }

    private func playerSortPredicate(lhs: Player, rhs: Player) -> Bool {
        switch playerGridOrder {
        case .number:
            let leftNumber = lhs.number ?? Int.max
            let rightNumber = rhs.number ?? Int.max
            if leftNumber != rightNumber {
                return leftNumber < rightNumber
            }
            if lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) != .orderedSame {
                return lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) == .orderedAscending
            }
            return lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) == .orderedAscending
        case .firstName:
            if lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) != .orderedSame {
                return lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) == .orderedAscending
            }
            if lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) != .orderedSame {
                return lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) == .orderedAscending
            }
            return (lhs.number ?? Int.max) < (rhs.number ?? Int.max)
        case .lastName:
            if lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) != .orderedSame {
                return lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) == .orderedAscending
            }
            if lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) != .orderedSame {
                return lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) == .orderedAscending
            }
            return (lhs.number ?? Int.max) < (rhs.number ?? Int.max)
        }
    }

    private var enabledStatTypes: [StatType] {
        allStatTypes.filter { $0.isEnabled }.sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    private var sessionEvents: [StatEvent] {
        allEvents.filter { $0.sessionId == session.sessionId }
    }

    private var selectedGrade: Grade? {
        grades.first(where: { $0.id == session.gradeId })
    }

    private var configuredQuarterLengthSeconds: Int {
        min(max(selectedGrade?.quarterLengthMinutes ?? 20, 10), 30) * 60
    }

    private var ourStyle: ClubStyle.Style {
        let configuration = ClubConfigurationStore.load()
        let teamName = configuration.clubTeam.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ClubStyle.style(for: teamName.isEmpty ? "Min Man" : teamName, configuration: configuration)
    }

    private var oppositionStyle: ClubStyle.Style {
        ClubStyle.style(for: session.opposition, configuration: ClubConfigurationStore.load())
    }

    private func scoreSummary(includeEvent: (StatEvent) -> Bool) -> (goals: Int, behinds: Int, points: Int) {
        let goalTypeIDs = Set(enabledStatTypes.filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "goal" }.map(\.id))
        let behindTypeIDs = Set(enabledStatTypes.filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "behind" }.map(\.id))
        let goals = sessionEvents.filter { includeEvent($0) && goalTypeIDs.contains($0.statTypeId) }.count
        let behinds = sessionEvents.filter { includeEvent($0) && behindTypeIDs.contains($0.statTypeId) }.count
        return (goals, behinds, goals * 6 + behinds)
    }

    private var ourScoreSummary: (goals: Int, behinds: Int, points: Int) {
        scoreSummary { $0.playerId != oppositionTeamStatPlayerID }
    }

    private var oppositionScoreSummary: (goals: Int, behinds: Int, points: Int) {
        scoreSummary { $0.playerId == oppositionTeamStatPlayerID }
    }

    private var ourTeamName: String {
        let name = ClubConfigurationStore.load().clubTeam.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Min Man" : name
    }

    private var formattedQuarterTime: String {
        String(format: "%02d:%02d", remainingQuarterSeconds / 60, remainingQuarterSeconds % 60)
    }

    private var topPanelHeight: CGFloat {
        168
    }

    private var rightStatActionsHeight: CGFloat {
        224
    }

    private var headerBannerArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
            HStack(spacing: 10) {
                Text(gradeName)
                    .font(.title.weight(.black))
                    .lineLimit(1)
                Text("•")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(session.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)

            if let statusBanner {
                RoundedRectangle(cornerRadius: 12)
                    .fill(statusBanner.isSuccess ? Color.green : Color.red)
                    .overlay {
                        Text(statusBanner.text)
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 16)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: statusBanner)
    }

    private var combinedScoreAndActionsPanel: some View {
        HStack(spacing: 8) {
            combinedTeamPanel(
                teamName: ourTeamName,
                scoreText: "\(ourScoreSummary.goals).\(ourScoreSummary.behinds) (\(ourScoreSummary.points))",
                style: ourStyle,
                isOpposition: false
            )
            combinedTeamPanel(
                teamName: session.opposition,
                scoreText: "\(oppositionScoreSummary.goals).\(oppositionScoreSummary.behinds) (\(oppositionScoreSummary.points))",
                style: oppositionStyle,
                isOpposition: true
            )
        }
        .frame(maxWidth: .infinity, minHeight: 168, maxHeight: 168)
    }

    private var ourTeamEfficiencyText: String {
        guard !displayedPlayers.isEmpty else { return "0%" }
        let averageEfficiency = displayedPlayers.reduce(0.0) { partialResult, player in
            let (effectiveCount, nonEffectiveCount) = efficiencyVoteCounts(for: player.id, events: sessionEvents)
            let totalRatedDisposals = effectiveCount + nonEffectiveCount
            let playerEfficiency = totalRatedDisposals > 0
                ? (Double(effectiveCount) / Double(totalRatedDisposals))
                : 0
            return partialResult + playerEfficiency
        } / Double(displayedPlayers.count)
        return "\(Int(round(averageEfficiency * 100)))%"
    }

    private func combinedTeamPanel(
        teamName: String,
        scoreText: String,
        style: ClubStyle.Style,
        isOpposition: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ScorePill(teamName, style: style)
                    .font(.title3.weight(.bold))
                Text(scoreText)
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 8) {
                teamStatButton("Goal", name: "Goal", style: style, isOpposition: isOpposition)
                teamStatButton("Behind", name: "Behind", style: style, isOpposition: isOpposition)
                teamStatButton("Clearance", name: "Clearance", style: style, isOpposition: isOpposition, fallbackName: "Clearances")
                teamStatButton("Inside 50", name: "Inside 50", style: style, isOpposition: isOpposition, fallbackName: "Inside 50s")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            if !isOpposition {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Team Eff.")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(ourTeamEfficiencyText)
                        .font(.headline.weight(.black))
                        .monospacedDigit()
                }
                .padding(.top, 8)
                .padding(.trailing, 10)
            }
        }
    }

    private var quarterPicker: some View {
        HStack(spacing: 10) {
            ForEach(["Q1", "Q2", "Q3", "Q4"], id: \.self) { quarter in
                Button(quarter) {
                    selectedQuarter = quarter
                }
                .buttonStyle(.bordered)
                .tint(selectedQuarter == quarter ? .blue : .gray)
                .font(.title3.weight(.bold))
                .frame(width: 100, height: 62)
                .background(selectedQuarter == quarter ? Color.blue.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var playerNumberRingColors: (stroke: Color, text: Color) {
        let team = ClubConfigurationStore.load().clubTeam
        return (
            stroke: Color(hex: team.secondaryColorHex!, fallback: ourStyle.text),
            text: Color(hex: team.primaryColorHex, fallback: ourStyle.background)
        )
    }

    private func playerCardContent(player: Player) -> some View {
        let ringColors = playerNumberRingColors
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(ringColors.stroke)
                    .frame(width: 38, height: 38)
                Circle()
                    .strokeBorder(ringColors.stroke, lineWidth: 2)
                    .frame(width: 38, height: 38)
                Text(player.number.map(String.init) ?? "—")
                    .font(.headline.weight(.black))
                    .foregroundStyle(ringColors.text)
            }
            Text(player.lastName.uppercased())
                .font(.headline.weight(.semibold))
                .lineLimit(1)
            Text(player.firstName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var gridPlayers: [Player] {
        displayedPlayers
    }

    private var playerSelectionPanel: some View {
        GeometryReader { panelProxy in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Button {
                        showPlayerVisibilityEditor = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }

                let columnsCount = max(Int(panelProxy.size.width / 128), 3)
                let maxRows = 4
                let maxVisibleCards = columnsCount * maxRows
                let hasOverflow = !showAllPlayers && gridPlayers.count > maxVisibleCards
                let visiblePlayers = hasOverflow ? Array(gridPlayers.prefix(max(maxVisibleCards - 1, 0))) : gridPlayers
                let rowsCount = showAllPlayers
                    ? max(Int(ceil(Double(max(gridPlayers.count, 1)) / Double(columnsCount))), 1)
                    : maxRows
                let topFixedHeight = 40.0
                let usableGridHeight = max(panelProxy.size.height - topFixedHeight, 180)
                let cellHeight = max(72, min(132, (usableGridHeight - (CGFloat(rowsCount - 1) * 8)) / CGFloat(rowsCount)))
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: columnsCount)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(visiblePlayers) { player in
                        Button {
                            selectPlayer(player.id)
                        } label: {
                            playerCardContent(player: player)
                                .frame(maxWidth: .infinity, minHeight: cellHeight)
                                .background(selectedPlayerId == player.id ? Color.blue : Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }

                    if hasOverflow {
                        Button {
                            showAllPlayers = true
                        } label: {
                            VStack {
                                Text("…")
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: cellHeight)
                            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var statButtonsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stat Actions")
                .font(.title3.bold())

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(playerStatTypes) { type in
                    Button {
                        addManualEvent(statTypeId: type.id)
                    } label: {
                        Text(type.name)
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 58)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(selectedPlayerId == nil ? .gray : .blue)
                    .disabled(selectedPlayerId == nil)
                }
            }
            if selectedPlayerId == nil {
                Text("Select a player first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func teamStatButton(
        _ title: String,
        name: String,
        style: ClubStyle.Style,
        isOpposition: Bool,
        fallbackName: String? = nil
    ) -> some View {
        let statType = statType(named: name, fallbackName: fallbackName)
        let appliesToSelectedPlayer = !isOpposition && isGoalOrBehindStat(named: name)
        return Button {
            guard let statType else { return }
            if appliesToSelectedPlayer {
                addManualEvent(statTypeId: statType.id)
            } else {
                addTeamEvent(statTypeId: statType.id, isOpposition: isOpposition)
            }
        } label: {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(style.text)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(style.background)
        .disabled(statType == nil)
    }

    private func isGoalOrBehindStat(named value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "goal" || normalized == "behind"
    }

    private var recentEventsPanel: some View {
        let recent = Array(sessionEvents.prefix(8))
        return VStack(alignment: .leading, spacing: 8) {
            Text("Recent Events")
                .font(.title3.bold())

            LazyVStack(spacing: 6) {
                ForEach(recent) { event in
                    Button {
                        showEditEvent = event
                    } label: {
                        HStack(spacing: 6) {
                            Text(playerNameForRecentEvent(for: event.playerId))
                                .font(.title3)
                                .lineLimit(1)
                            Text("-")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text(statName(for: event.statTypeId))
                                .font(.title3.weight(.bold))
                                .lineLimit(1)
                            Text("-")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            if sessionEvents.isEmpty {
                Text("No events yet")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 300, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var bottomControlBar: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 10) {
                Button("View Totals") {
                    showTotals = true
                }
                .buttonStyle(.borderedProminent)

                Button("Generate Report") {
                    generateReport()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Text(formattedQuarterTime)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 140, alignment: .trailing)

                HStack(spacing: 8) {
                    Button {
                        if isQuarterTimerRunning {
                            stopQuarterTimer()
                        } else {
                            startQuarterTimer()
                        }
                    } label: {
                        Image(systemName: isQuarterTimerRunning ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        configureQuarterTimer(reset: true)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()
                    .frame(width: 28)

                quarterPicker
            }
            .frame(minWidth: 360, alignment: .leading)

            Spacer()

            Button("Undo") {
                undoLastEvent()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(sessionEvents.isEmpty)

            Button {
                // press-and-hold driven
            } label: {
                ZStack {
                    Circle()
                        .fill(speechService.isRecording ? Color.red : Color.red.opacity(0.9))
                        .frame(width: 92, height: 92)
                    Text("Speak")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }
            }
            .onLongPressGesture(minimumDuration: 0.01, maximumDistance: .infinity, pressing: { isPressing in
                if isPressing {
                    speechService.startListening(vocabulary: speechVocabulary)
                } else if speechService.isRecording {
                    speechService.stopListening { transcript in
                        handleVoiceTranscript(transcript)
                    }
                }
            }, perform: {})
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var gradeName: String {
        grades.first(where: { $0.id == session.gradeId })?.name ?? "Unknown Grade"
    }

    private var speechVocabulary: [String] {
        let statPhrases = enabledStatTypes.flatMap { $0.voiceAliases }
        let rosterPhrases = playersForGrade.flatMap { player -> [String] in
            var values = [player.name, player.firstName, player.lastName]
            if let number = player.number {
                values.append("number \(number)")
                values.append("no \(number)")
                values.append(String(number))
            }
            return values
        }
        return Array(Set(statPhrases + rosterPhrases)).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var totalsRows: [TotalsRow] {
        displayedPlayers.map { player in
            let events = sessionEvents.filter { $0.playerId == player.id }
            var counts: [UUID: Int] = [:]
            for event in events {
                counts[event.statTypeId, default: 0] += 1
            }
            return TotalsRow(player: player, countsByStatId: counts)
        }
    }

    private var playerStatTypes: [StatType] {
        let teamOnly = Set(["goal", "behind", "clearance", "clearances", "inside 50", "inside 50s"])
        return enabledStatTypes.filter { !teamOnly.contains($0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
    }

    private func statType(named name: String, fallbackName: String? = nil) -> StatType? {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let primary = enabledStatTypes.first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == target }) {
            return primary
        }
        guard let fallbackName else { return nil }
        let fallback = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return enabledStatTypes.first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == fallback })
    }

    private func playerDisplay(_ player: Player) -> String {
        if let number = player.number {
            return "\(number) \(player.name)"
        }
        return player.name
    }

    private func playerLabel(for id: UUID) -> String {
        guard let player = allPlayers.first(where: { $0.id == id }) else { return "Unknown" }
        return playerDisplay(player)
    }

    private func playerNameForRecentEvent(for id: UUID) -> String {
        if id == ourTeamStatPlayerID {
            return ourTeamName
        }
        if id == oppositionTeamStatPlayerID {
            return session.opposition
        }
        guard let player = allPlayers.first(where: { $0.id == id }) else { return "Unknown" }
        return player.name
    }

    private func playerShortLabel(for id: UUID) -> String {
        if id == ourTeamStatPlayerID {
            return ourTeamName
        }
        if id == oppositionTeamStatPlayerID {
            return session.opposition
        }
        guard let player = allPlayers.first(where: { $0.id == id }) else { return "Unknown" }
        if let number = player.number {
            return "\(number) \(player.lastName)"
        }
        return player.lastName
    }

    private func selectPlayer(_ id: UUID) {
        selectedPlayerId = id
    }

    private func configureQuarterTimer(reset: Bool) {
        if reset {
            stopQuarterTimer()
            remainingQuarterSeconds = configuredQuarterLengthSeconds
        } else if remainingQuarterSeconds <= 0 {
            remainingQuarterSeconds = configuredQuarterLengthSeconds
        }
    }

    private func startQuarterTimer() {
        if remainingQuarterSeconds <= 0 {
            remainingQuarterSeconds = configuredQuarterLengthSeconds
        }
        guard !isQuarterTimerRunning else { return }
        isQuarterTimerRunning = true
        quarterTimerTask?.cancel()
        quarterTimerTask = Task {
            while !Task.isCancelled && isQuarterTimerRunning {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    guard isQuarterTimerRunning else { return }
                    if remainingQuarterSeconds > 0 {
                        remainingQuarterSeconds -= 1
                    } else {
                        stopQuarterTimer()
                    }
                }
            }
        }
    }

    private func stopQuarterTimer() {
        isQuarterTimerRunning = false
        quarterTimerTask?.cancel()
        quarterTimerTask = nil
    }

    private func statName(for id: UUID) -> String {
        allStatTypes.first(where: { $0.id == id })?.name ?? "Unknown"
    }

    private func addManualEvent() {
        guard let currentSelectedPlayerId = selectedPlayerId else {
            lastMessage = "Select a player first"
            showStatusBanner(text: "ERROR • Select a player first", isSuccess: false)
            feedbackToken = UUID()
            return
        }
        guard let selectedStatTypeId else { return }

        let event = StatEvent(
            sessionId: session.sessionId,
            playerId: currentSelectedPlayerId,
            statTypeId: selectedStatTypeId,
            quarter: selectedQuarter,
            sourceRaw: StatsEventSource.manual.rawValue,
            transcript: nil
        )
        modelContext.insert(event)
        try? modelContext.save()

        promptEfficiencyVoteIfNeeded(for: event)
        selectedPlayerId = nil

        lastMessage = "Added: \(statName(for: selectedStatTypeId)) — \(playerLabel(for: currentSelectedPlayerId)) — \(selectedQuarter)"
        showSuccessBanner(for: event)
        feedbackToken = UUID()
    }

    private func addManualEvent(statTypeId: UUID) {
        selectedStatTypeId = statTypeId
        addManualEvent()
    }

    private func addTeamEvent(statTypeId: UUID, isOpposition: Bool) {
        let playerID = isOpposition ? oppositionTeamStatPlayerID : ourTeamStatPlayerID
        let event = StatEvent(
            sessionId: session.sessionId,
            playerId: playerID,
            statTypeId: statTypeId,
            quarter: selectedQuarter,
            sourceRaw: StatsEventSource.manual.rawValue
        )
        modelContext.insert(event)
        try? modelContext.save()
        lastMessage = "Added: \(statName(for: statTypeId)) — \(isOpposition ? session.opposition : ourTeamName) — \(selectedQuarter)"
        showSuccessBanner(for: event)
        feedbackToken = UUID()
    }

    private func undoLastEvent() {
        guard let latest = sessionEvents.first else { return }
        modelContext.delete(latest)
        try? modelContext.save()
        lastMessage = "Undid last event"
        showStatusBanner(text: "UNDO • Last event removed", isSuccess: false)
        feedbackToken = UUID()
    }

    private func handleVoiceTranscript(_ transcript: String) {
        lastHeardTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
#if DEBUG
        print("Heard: \(lastHeardTranscript)")
#endif
        guard !lastHeardTranscript.isEmpty else {
            lastMessage = "Heard: (empty)"
            showStatusBanner(text: "ERROR • Heard empty input", isSuccess: false)
            feedbackToken = UUID()
            return
        }

        let descriptors = enabledStatTypes.map {
            VoiceStatTypeDescriptor(id: $0.id, canonicalName: $0.name, aliases: $0.voiceAliases)
        }
        let roster = playersForGrade.map {
            VoiceRosterPlayer(
                id: $0.id,
                number: $0.number,
                firstName: $0.firstName,
                lastName: $0.lastName,
                fullName: $0.name
            )
        }

        let result = parser.parse(transcript: transcript, statTypes: descriptors, roster: roster)
        lastVoiceDebug = result

#if DEBUG
        print("VOICE_PARSE raw='\(result.rawTranscript)' normalized='\(result.normalizedTranscript)' status='\(result.parseStatus)' confidence='\(result.confidence)' statCandidates='\(result.detectedStatCandidates)' playerCandidates='\(result.detectedPlayerCandidates)' matchedStat='\(result.matchedStatName ?? "nil")' matchedPlayer='\(result.matchedPlayerName ?? "nil")' reason='\(result.failureReason ?? "none")'")
#endif

        guard result.parseStatus == .success,
              let statTypeId = result.matchedStatTypeId,
              let playerId = result.matchedPlayerId else {
            if result.shouldOfferReview,
               let guessedStat = result.matchedStatName,
               let guessedPlayer = result.matchedPlayerName {
                lastMessage = "Did you mean \(guessedStat) — \(guessedPlayer)?"
                showStatusBanner(text: "ERROR • Did you mean \(guessedPlayer) \(guessedStat)?", isSuccess: false)
            } else {
            lastMessage = parseFailureMessage(result)
                showStatusBanner(text: "ERROR • \(parseFailureMessage(result))", isSuccess: false)
            }
            feedbackToken = UUID()
            return
        }

        let event = StatsEventCreationService.makeVoiceEvent(
            sessionId: session.sessionId,
            playerId: playerId,
            statTypeId: statTypeId,
            quarter: selectedQuarter,
            transcript: result.rawTranscript,
            normalizedTranscript: result.normalizedTranscript,
            confidence: result.confidence
        )
        modelContext.insert(event)
        try? modelContext.save()
        promptEfficiencyVoteIfNeeded(for: event)
        selectedPlayerId = nil

        let playerText = playerLabel(for: playerId)
        let statText = statName(for: statTypeId)
        lastMessage = "Added: \(statText) — \(playerText) — \(selectedQuarter)"
        showSuccessBanner(for: event)
        feedbackToken = UUID()
    }

    private func promptEfficiencyVoteIfNeeded(for event: StatEvent) {
        let normalized = statName(for: event.statTypeId).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized == "kick" || normalized == "handball" else { return }
        pendingEfficiencyEventID = event.id
        showEfficiencyVotePrompt = true
    }

    private func applyEfficiencyVote(_ vote: EfficiencyVote) {
        guard let eventID = pendingEfficiencyEventID,
              let event = sessionEvents.first(where: { $0.id == eventID }) else {
            pendingEfficiencyEventID = nil
            showEfficiencyVotePrompt = false
            return
        }
        event.efficiencyVoteRaw = vote.rawValue
        try? modelContext.save()
        showSuccessBanner(for: event)
        pendingEfficiencyEventID = nil
        showEfficiencyVotePrompt = false
    }

    private func dismissEfficiencyVotePrompt() {
        pendingEfficiencyEventID = nil
        showEfficiencyVotePrompt = false
    }

    private func showSuccessBanner(for event: StatEvent) {
        showStatusBanner(text: successBannerText(for: event), isSuccess: true)
    }

    private func showStatusBanner(text: String, isSuccess: Bool) {
        statusBannerTask?.cancel()
        withAnimation {
            statusBanner = StatRecordBanner(text: text, isSuccess: isSuccess)
        }
        statusBannerTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    statusBanner = nil
                }
            }
        }
    }

    private func successBannerText(for event: StatEvent) -> String {
        let playerText = playerBannerLabel(for: event.playerId)
        let statText = statName(for: event.statTypeId).uppercased()
        if let vote = event.efficiencyVoteRaw {
            let emoji = vote == EfficiencyVote.thumbsUp.rawValue ? "👍" : "👎"
            return "\(playerText) • \(statText) • EFFICIENCY \(emoji)"
        }
        return "\(playerText) • \(statText)"
    }

    private func playerBannerLabel(for id: UUID) -> String {
        if id == ourTeamStatPlayerID {
            return ourTeamName.uppercased()
        }
        if id == oppositionTeamStatPlayerID {
            return session.opposition.uppercased()
        }
        guard let player = allPlayers.first(where: { $0.id == id }) else { return "UNKNOWN" }
        return player.lastName.uppercased()
    }

    private var efficiencyRatingPrompt: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissEfficiencyVotePrompt()
                }

            VStack(spacing: 14) {
                Text("Efficiency Rating")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Was this kick/handball effective?")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.88))

                VStack(spacing: 10) {
                    Button {
                        applyEfficiencyVote(.thumbsUp)
                    } label: {
                        Text("👍")
                            .font(.system(size: 84))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .background(Capsule().fill(Color.white.opacity(0.17)))

                    Button {
                        applyEfficiencyVote(.thumbsDown)
                    } label: {
                        Text("👎")
                            .font(.system(size: 84))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .background(Capsule().fill(Color.white.opacity(0.17)))

                    Button("Skip") {
                        dismissEfficiencyVotePrompt()
                    }
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(ClubTheme.navy)
                    .background(Capsule().fill(Color.white.opacity(0.17)))
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: 460)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 8)
            .padding(.horizontal, 20)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func parseFailureMessage(_ result: VoiceParseResult) -> String {
        switch result.parseStatus {
        case .emptyTranscript:
            return "No speech detected"
        case .noStatFound:
            return "Stat type not recognised"
        case .noPlayerFound:
            if let guessed = result.matchedPlayerName {
                return "Player not found. Closest: \(guessed)"
            }
            return "Player not found"
        case .ambiguousPlayer:
            if let first = result.candidatePlayerIds.first {
                return "Multiple players match '\(playerLabel(for: first))'"
            }
            return "Multiple players match"
        case .ambiguousStat:
            return "Multiple stat types matched"
        case .lowConfidence:
            return "Could not confidently interpret command"
        case .success:
            return ""
        }
    }

    private func generateReport() {
        let quarterOrder = ["Q1", "Q2", "Q3", "Q4"]
        let trackedStats: [(label: String, aliases: [String])] = [
            ("K", ["kick"]),
            ("H", ["handball", "hand ball", "handpass", "hand pass"]),
            ("M", ["mark"]),
            ("T", ["tackle"]),
            ("G", ["goal"]),
            ("B", ["behind"])
        ]
        let inside50Stat = statTypeMatching(aliases: ["inside 50", "inside50", "inside 50s"])
        let clearanceStat = statTypeMatching(aliases: ["clearance", "clearances"])

        let players = displayedPlayers
        let playerIDs = Set(players.map(\.id))
        let eventsForPlayers = sessionEvents.filter { playerIDs.contains($0.playerId) }
        let byPlayerQuarterAndStat = Dictionary(grouping: eventsForPlayers) { event in
            "\(event.playerId.uuidString)|\(event.quarter)|\(event.statTypeId.uuidString)"
        }

        let pageRect = CGRect(x: 0, y: 0, width: 842, height: 595) // A4 landscape points
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 20

            if let logo = UIImage(named: "club_logo") {
                logo.draw(in: CGRect(x: 24, y: y, width: 56, height: 56))
            }
            ("Stats Report" as NSString).draw(at: CGPoint(x: 96, y: y + 10), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 24)])
            y += 62
            let details = "Grade: \(gradeName)   Opposition: \(session.opposition)   Date: \(session.date.formatted(date: .abbreviated, time: .omitted))   Venue: \(session.venue)"
            (details as NSString).draw(
                in: CGRect(x: 24, y: y, width: pageRect.width - 48, height: 30),
                withAttributes: [.font: UIFont.systemFont(ofSize: 11)]
            )
            y += 24

            let inside50Us = teamStatCount(statType: inside50Stat, teamPlayerId: ourTeamStatPlayerID)
            let inside50Them = teamStatCount(statType: inside50Stat, teamPlayerId: oppositionTeamStatPlayerID)
            let clearancesUs = teamStatCount(statType: clearanceStat, teamPlayerId: ourTeamStatPlayerID)
            let clearancesThem = teamStatCount(statType: clearanceStat, teamPlayerId: oppositionTeamStatPlayerID)
            let inside50Summary = "Inside 50: \(ourTeamName) \(inside50Us)  |  \(session.opposition) \(inside50Them)"
            let clearancesSummary = "Clearances: \(ourTeamName) \(clearancesUs)  |  \(session.opposition) \(clearancesThem)"
            (inside50Summary as NSString).draw(
                at: CGPoint(x: 24, y: y),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 11)]
            )
            (clearancesSummary as NSString).draw(
                at: CGPoint(x: 24, y: y + 16),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 11)]
            )
            y += 42

            let leftMargin: CGFloat = 24
            let numberColumnWidth: CGFloat = 42
            let playerColumnWidth: CGFloat = 108
            let statColumnWidth: CGFloat = 19
            let efficiencyColumnWidth: CGFloat = 42
            let headerRowHeight: CGFloat = 20
            let maxPlayersPerPage: CGFloat = 26
            let footerReservedHeight: CGFloat = 18
            let availableHeightForDataRows = max(
                12 * maxPlayersPerPage,
                (pageRect.height - y - (headerRowHeight * 2) - footerReservedHeight)
            )
            let dataRowHeight = floor(availableHeightForDataRows / maxPlayersPerPage)
            let blockWidth = CGFloat(trackedStats.count) * statColumnWidth

            drawCell("No", x: leftMargin, y: y, width: numberColumnWidth, height: headerRowHeight, bold: true)
            drawCell("Player", x: leftMargin + numberColumnWidth, y: y, width: playerColumnWidth, height: headerRowHeight, bold: true)
            var x = leftMargin + numberColumnWidth + playerColumnWidth
            for quarter in quarterOrder {
                drawCell(quarter, x: x, y: y, width: blockWidth, height: headerRowHeight, bold: true)
                x += blockWidth
            }
            drawCell("Totals", x: x, y: y, width: blockWidth, height: headerRowHeight, bold: true)
            x += blockWidth
            drawCell("Eff %", x: x, y: y, width: efficiencyColumnWidth, height: headerRowHeight, bold: true)
            y += headerRowHeight

            drawCell("", x: leftMargin, y: y, width: numberColumnWidth, height: headerRowHeight, bold: true)
            drawCell("", x: leftMargin + numberColumnWidth, y: y, width: playerColumnWidth, height: headerRowHeight, bold: true)
            x = leftMargin + numberColumnWidth + playerColumnWidth
            for _ in quarterOrder {
                for stat in trackedStats {
                    drawCell(stat.label, x: x, y: y, width: statColumnWidth, height: headerRowHeight, bold: true)
                    x += statColumnWidth
                }
            }
            for stat in trackedStats {
                drawCell(stat.label, x: x, y: y, width: statColumnWidth, height: headerRowHeight, bold: true)
                x += statColumnWidth
            }
            drawCell("", x: x, y: y, width: efficiencyColumnWidth, height: headerRowHeight, bold: true)
            y += headerRowHeight

            for player in players {
                if y + dataRowHeight > pageRect.height - footerReservedHeight {
                    context.beginPage()
                    y = 24
                }

                let playerLabel = player.lastName.uppercased()
                drawCell(player.number.map(String.init) ?? "", x: leftMargin, y: y, width: numberColumnWidth, height: dataRowHeight)
                drawCell(playerLabel, x: leftMargin + numberColumnWidth, y: y, width: playerColumnWidth, height: dataRowHeight)

                x = leftMargin + numberColumnWidth + playerColumnWidth
                for quarter in quarterOrder {
                    for stat in trackedStats {
                        let count = statCount(
                            for: player.id,
                            quarter: quarter,
                            aliases: stat.aliases,
                            lookup: byPlayerQuarterAndStat
                        )
                        drawCell("\(count)", x: x, y: y, width: statColumnWidth, height: dataRowHeight)
                        x += statColumnWidth
                    }
                }
                for stat in trackedStats {
                    let total = quarterOrder.reduce(0) { partialResult, quarter in
                        partialResult + statCount(
                            for: player.id,
                            quarter: quarter,
                            aliases: stat.aliases,
                            lookup: byPlayerQuarterAndStat
                        )
                    }
                    drawCell("\(total)", x: x, y: y, width: statColumnWidth, height: dataRowHeight, bold: true)
                    x += statColumnWidth
                }
                let efficiencyText: String
                let (effectiveCount, nonEffectiveCount) = efficiencyVoteCounts(for: player.id, events: eventsForPlayers)
                let totalRatedDisposals = effectiveCount + nonEffectiveCount
                if totalRatedDisposals > 0 {
                    let efficiency = Int(round((Double(effectiveCount) / Double(totalRatedDisposals)) * 100))
                    efficiencyText = "\(efficiency)%"
                } else {
                    efficiencyText = "-"
                }
                drawCell(efficiencyText, x: x, y: y, width: efficiencyColumnWidth, height: dataRowHeight, bold: true)
                y += dataRowHeight
            }

        }

        let safeDate = session.date.formatted(.dateTime.year().month().day())
        let fileName = "Stats_\(gradeName.replacingOccurrences(of: " ", with: "_"))_\(safeDate).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            reportPreviewDocument = ReportPreviewDocument(url: url)
            lastMessage = "Report generated"
        } catch {
            lastMessage = "Failed to build report"
        }
    }

    private func statTypeMatching(aliases: [String]) -> StatType? {
        let normalizedAliases = Set(aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return enabledStatTypes.first { statType in
            normalizedAliases.contains(statType.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }

    private func statCount(
        for playerID: UUID,
        quarter: String,
        aliases: [String],
        lookup: [String: [StatEvent]]
    ) -> Int {
        let matchingStatIDs = enabledStatTypes.filter { type in
            aliases.contains { alias in
                type.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == alias.lowercased()
            }
        }.map(\.id)

        return matchingStatIDs.reduce(0) { partialResult, statID in
            let key = "\(playerID.uuidString)|\(quarter)|\(statID.uuidString)"
            return partialResult + (lookup[key]?.count ?? 0)
        }
    }

    private func teamStatCount(statType: StatType?, teamPlayerId: UUID) -> Int {
        guard let statType else { return 0 }
        return sessionEvents.filter { $0.playerId == teamPlayerId && $0.statTypeId == statType.id }.count
    }

    private func efficiencyVoteCounts(for playerID: UUID, events: [StatEvent]) -> (effective: Int, nonEffective: Int) {
        let ratedEvents = events.filter { $0.playerId == playerID }
        let effective = ratedEvents.reduce(0) { partialResult, event in
            partialResult + (event.efficiencyVoteRaw == EfficiencyVote.thumbsUp.rawValue ? 1 : 0)
        }
        let nonEffective = ratedEvents.reduce(0) { partialResult, event in
            partialResult + (event.efficiencyVoteRaw == EfficiencyVote.thumbsDown.rawValue ? 1 : 0)
        }
        return (effective, nonEffective)
    }

    private func drawCell(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 20, bold: Bool = false, emphasize: Bool = false) {
        if emphasize {
            UIColor.systemGray6.setFill()
            UIBezierPath(rect: CGRect(x: x, y: y, width: width, height: height)).fill()
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: bold ? UIFont.boldSystemFont(ofSize: 10) : UIFont.systemFont(ofSize: 10)
        ]
        let textInsetY = max(1, (height - 14) / 2)
        (text as NSString).draw(in: CGRect(x: x + 2, y: y + textInsetY, width: width - 4, height: max(12, height - 2)), withAttributes: attributes)
        let path = UIBezierPath(rect: CGRect(x: x, y: y, width: width, height: height))
        UIColor.systemGray4.setStroke()
        path.stroke()
    }
}

private struct StatsReportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let onShare: () -> Void

    var body: some View {
        NavigationStack {
            StatsPDFPreview(url: url)
                .navigationTitle("Report Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Share") {
                            onShare()
                        }
                    }
                }
        }
    }
}

private struct StatsPDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}

private struct PlayerVisibilityEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let players: [Player]
    let initialSelection: Set<UUID>
    let initialGridOrder: PlayerGridOrder
    let onSave: (Set<UUID>, PlayerGridOrder) -> Void

    @State private var selectedIDs: Set<UUID>
    @State private var gridOrder: PlayerGridOrder
    @State private var showDiscardAlert = false

    init(
        players: [Player],
        initialSelection: Set<UUID>,
        initialGridOrder: PlayerGridOrder,
        onSave: @escaping (Set<UUID>, PlayerGridOrder) -> Void
    ) {
        self.players = players
        self.initialSelection = initialSelection
        self.initialGridOrder = initialGridOrder
        self.onSave = onSave
        _selectedIDs = State(initialValue: initialSelection)
        _gridOrder = State(initialValue: initialGridOrder)
    }

    private var hasUnsavedChanges: Bool {
        selectedIDs != initialSelection || gridOrder != initialGridOrder
    }

    private var orderedPlayers: [Player] {
        players.sorted(by: playerSortPredicate)
    }

    private func playerSortPredicate(lhs: Player, rhs: Player) -> Bool {
        switch gridOrder {
        case .number:
            let leftNumber = lhs.number ?? Int.max
            let rightNumber = rhs.number ?? Int.max
            if leftNumber != rightNumber {
                return leftNumber < rightNumber
            }
            if lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) != .orderedSame {
                return lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) == .orderedAscending
            }
            return lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) == .orderedAscending
        case .firstName:
            if lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) != .orderedSame {
                return lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) == .orderedAscending
            }
            if lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) != .orderedSame {
                return lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) == .orderedAscending
            }
            return (lhs.number ?? Int.max) < (rhs.number ?? Int.max)
        case .lastName:
            if lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) != .orderedSame {
                return lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) == .orderedAscending
            }
            if lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) != .orderedSame {
                return lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) == .orderedAscending
            }
            return (lhs.number ?? Int.max) < (rhs.number ?? Int.max)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Visible Players")
                        .font(.largeTitle.bold())
                    Spacer()
                    Text("\(selectedIDs.count) Included")
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                HStack {
                    Text("Grid order")
                        .font(.headline)
                    Spacer()
                    Picker("Grid order", selection: $gridOrder) {
                        ForEach(PlayerGridOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 6)

                List(orderedPlayers) { player in
                    Button {
                        if selectedIDs.contains(player.id) {
                            selectedIDs.remove(player.id)
                        } else {
                            selectedIDs.insert(player.id)
                        }
                    }
                    label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedIDs.contains(player.id) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(selectedIDs.contains(player.id) ? .blue : .secondary)
                            Text(player.number.map { "#\($0)" } ?? "—")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.lastName.uppercased())
                                    .font(.headline)
                                Text(player.firstName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") {
                        if hasUnsavedChanges {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(selectedIDs, gridOrder)
                        dismiss()
                    }
                    .saveButtonBehavior(isEnabled: hasUnsavedChanges)
                }
            }
            .alert("Discard unsaved changes?", isPresented: $showDiscardAlert) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard", role: .destructive) { dismiss() }
            } message: {
                Text("You have unsaved player visibility changes.")
            }
        }
    }
}

private struct EditStatEventView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let event: StatEvent
    let players: [Player]
    let statTypes: [StatType]

    @State private var playerId: UUID
    @State private var statTypeId: UUID
    @State private var quarter: String

    init(event: StatEvent, players: [Player], statTypes: [StatType]) {
        self.event = event
        self.players = players
        self.statTypes = statTypes
        _playerId = State(initialValue: event.playerId)
        _statTypeId = State(initialValue: event.statTypeId)
        _quarter = State(initialValue: event.quarter)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Player", selection: $playerId) {
                    ForEach(players) { player in
                        Text(player.name).tag(player.id)
                    }
                }

                Picker("Stat Type", selection: $statTypeId) {
                    ForEach(statTypes) { stat in
                        Text(stat.name).tag(stat.id)
                    }
                }

                Picker("Quarter", selection: $quarter) {
                    ForEach(["Q1", "Q2", "Q3", "Q4"], id: \.self) {
                        Text($0)
                    }
                }

                Button("Delete Event", role: .destructive) {
                    modelContext.delete(event)
                    try? modelContext.save()
                    dismiss()
                }
            }
            .navigationTitle("Edit Event")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        event.playerId = playerId
                        event.statTypeId = statTypeId
                        event.quarter = quarter
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PlayerSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let players: [Player]
    @Binding var selectedPlayerId: UUID?
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List(filteredPlayers) { player in
                Button {
                    selectedPlayerId = player.id
                    dismiss()
                } label: {
                    HStack {
                        Text(player.number.map { "#\($0)" } ?? "#–")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)
                        Text(player.name)
                        Spacer()
                        if selectedPlayerId == player.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "Find player")
            .navigationTitle("Select Player")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var filteredPlayers: [Player] {
        let base = players.sorted { lhs, rhs in
            if lhs.number != rhs.number {
                return (lhs.number ?? Int.max) < (rhs.number ?? Int.max)
            }
            return lhs.name < rhs.name
        }
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return base
        }
        let key = searchText.lowercased()
        return base.filter {
            $0.name.lowercased().contains(key)
            || $0.firstName.lowercased().contains(key)
            || $0.lastName.lowercased().contains(key)
            || ($0.number.map(String.init)?.contains(key) ?? false)
        }
    }
}

private struct StatsTotalsView: View {
    @Environment(\.dismiss) private var dismiss
    let rows: [TotalsRow]
    let statTypes: [StatType]

    private struct TotalsSummaryRow: Identifiable {
        let id: UUID
        let playerLabel: String
        let kicks: Int
        let handballs: Int
        let possessions: Int
        let marks: Int
        let tackles: Int
        let goals: Int
        let behinds: Int
    }

    private var summaryRows: [TotalsSummaryRow] {
        rows.map { row in
            let kicks = count(for: "kick", in: row)
            let handballs = count(for: "handball", in: row)
            let possessions = kicks + handballs
            return TotalsSummaryRow(
                id: row.id,
                playerLabel: row.player.number.map { "\($0) \(row.player.name)" } ?? row.player.name,
                kicks: kicks,
                handballs: handballs,
                possessions: possessions,
                marks: count(for: "mark", in: row),
                tackles: count(for: "tackle", in: row),
                goals: count(for: "goal", in: row),
                behinds: count(for: "behind", in: row)
            )
        }
        .sorted { lhs, rhs in
            if lhs.possessions != rhs.possessions { return lhs.possessions > rhs.possessions }
            return lhs.playerLabel < rhs.playerLabel
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(summaryRows.enumerated()), id: \.element.id) { index, row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(index + 1). \(row.playerLabel)")
                                    .font(.headline)
                                Spacer()
                                Text("\(row.possessions)")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                            }

                            HStack(spacing: 14) {
                                compactValue(title: "Kicks", value: row.kicks)
                                compactValue(title: "Handballs", value: row.handballs)
                                compactValue(title: "Marks", value: row.marks)
                                compactValue(title: "Tackles", value: row.tackles)
                                compactValue(title: "G/B", value: "\(row.goals)/\(row.behinds)")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Totals")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func count(for statName: String, in row: TotalsRow) -> Int {
        statTypes.first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == statName }).map {
            row.countsByStatId[$0.id, default: 0]
        } ?? 0
    }

    private func compactValue(title: String, value: Int) -> some View {
        Text("\(title): \(value)")
    }

    private func compactValue(title: String, value: String) -> some View {
        Text("\(title): \(value)")
    }
}
