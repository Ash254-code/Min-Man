import SwiftUI
import SwiftData
import UIKit

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
            "behind": ["behind", "behinds"]
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
        parserConfidence: Double? = nil
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
    }
}

enum StatsEventSource: String, CaseIterable {
    case manual
    case voice
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

    var body: some View {
        Form {
            Picker("Grade", selection: $selectedGradeId) {
                Text("Select").tag(Optional<UUID>.none)
                ForEach(grades.filter { $0.isActive }) { grade in
                    Text(grade.name).tag(Optional(grade.id))
                }
            }

            TextField("Opposition", text: $opposition)
            DatePicker("Date", selection: $date, displayedComponents: .date)
            TextField("Venue", text: $venue)

            Button("Start Session") {
                startSession()
            }
            .disabled(!canStart)
        }
        .navigationTitle("New Stats Session")
        .navigationDestination(isPresented: $showLiveStats) {
            if let createdSession {
                LiveStatsView(session: createdSession)
            }
        }
    }

    private var canStart: Bool {
        selectedGradeId != nil && !opposition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

struct LiveStatsView: View {
    @Environment(\.modelContext) private var modelContext

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
    @State private var shareURL: URL?
    @StateObject private var speechService = PressHoldSpeechService()
    private let parser = StatsVoiceParser()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerCard
                quarterPicker
                voiceButton
                if let lastMessage {
                    Text(lastMessage)
                        .font(.headline)
                        .foregroundStyle(lastMessage.contains("Added:") ? .green : .red)
                        .padding(.horizontal)
                }
                manualEntryCard
                recentEventsCard
                totalsCard
                reportCard
            }
            .padding()
        }
        .navigationTitle("Live Stats")
        .sheet(item: $showEditEvent) { event in
            EditStatEventView(event: event, players: playersForGrade, statTypes: enabledStatTypes)
        }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
    }

    private var playersForGrade: [Player] {
        allPlayers.filter { $0.isActive && $0.gradeIDs.contains(session.gradeId) }
    }

    private var enabledStatTypes: [StatType] {
        allStatTypes.filter { $0.isEnabled }.sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    private var sessionEvents: [StatEvent] {
        allEvents.filter { $0.sessionId == session.sessionId }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(gradeName) vs \(session.opposition)")
                .font(.title3.bold())
            Text(session.date, format: Date.FormatStyle(date: .abbreviated, time: .omitted))
                .foregroundStyle(.secondary)
            if !session.venue.isEmpty {
                Text(session.venue)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var quarterPicker: some View {
        HStack(spacing: 8) {
            ForEach(["Q1", "Q2", "Q3", "Q4"], id: \.self) { quarter in
                Button(quarter) {
                    selectedQuarter = quarter
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedQuarter == quarter ? .blue : .gray)
                .font(.headline)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var voiceButton: some View {
        VStack(spacing: 8) {
                Text("Current Quarter: \(selectedQuarter)")
                    .font(.title2.bold())
            Button {
                // long-press driven
            } label: {
                Text(speechService.isRecording ? "Listening… release to add" : "Hold to Speak")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(speechService.isRecording ? Color.red.opacity(0.9) : Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.1)
                    .onEnded { _ in
                        speechService.startListening(vocabulary: speechVocabulary)
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { _ in
                        if speechService.isRecording {
                            let transcript = speechService.stopListening()
                            handleVoiceTranscript(transcript)
                        }
                    }
            )

            if !speechService.liveTranscript.isEmpty {
                Text("Heard: \(speechService.liveTranscript)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var manualEntryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manual Entry")
                .font(.headline)

            Picker("Player", selection: $selectedPlayerId) {
                Text("Select player").tag(Optional<UUID>.none)
                ForEach(playersForGrade) { player in
                    Text(playerDisplay(player)).tag(Optional(player.id))
                }
            }

            Picker("Stat", selection: $selectedStatTypeId) {
                Text("Select stat").tag(Optional<UUID>.none)
                ForEach(enabledStatTypes) { type in
                    Text(type.name).tag(Optional(type.id))
                }
            }

            HStack {
                Button("Add Event") {
                    addManualEvent()
                }
                .buttonStyle(.borderedProminent)

                Button("Undo Last") {
                    undoLastEvent()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var recentEventsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Events")
                .font(.headline)

            ForEach(sessionEvents.prefix(20)) { event in
                Button {
                    showEditEvent = event
                } label: {
                    HStack {
                        Text("\(statName(for: event.statTypeId)) — \(playerLabel(for: event.playerId)) — \(event.quarter)")
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            if sessionEvents.isEmpty {
                Text("No events yet")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Totals")
                .font(.headline)

            ForEach(totalsRows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(playerDisplay(row.player))
                        .font(.subheadline.bold())
                    Text(enabledStatTypes.map { "\($0.name): \(row.countsByStatId[$0.id, default: 0])" }.joined(separator: "  •  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var reportCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Report")
                .font(.headline)
            Button("Generate PDF & Share") {
                generateReport()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
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
                values.append(String(number))
            }
            return values
        }
        return Array(Set(statPhrases + rosterPhrases)).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var totalsRows: [TotalsRow] {
        playersForGrade.map { player in
            let events = sessionEvents.filter { $0.playerId == player.id }
            var counts: [UUID: Int] = [:]
            for event in events {
                counts[event.statTypeId, default: 0] += 1
            }
            return TotalsRow(player: player, countsByStatId: counts)
        }
    }

    private func playerDisplay(_ player: Player) -> String {
        if let number = player.number {
            return "#\(number) \(player.name)"
        }
        return player.name
    }

    private func playerLabel(for id: UUID) -> String {
        guard let player = allPlayers.first(where: { $0.id == id }) else { return "Unknown" }
        return playerDisplay(player)
    }

    private func statName(for id: UUID) -> String {
        allStatTypes.first(where: { $0.id == id })?.name ?? "Unknown"
    }

    private func addManualEvent() {
        guard let selectedPlayerId, let selectedStatTypeId else {
            lastMessage = "Select player and stat type"
            return
        }

        let event = StatEvent(
            sessionId: session.sessionId,
            playerId: selectedPlayerId,
            statTypeId: selectedStatTypeId,
            quarter: selectedQuarter,
            sourceRaw: StatsEventSource.manual.rawValue,
            transcript: nil
        )
        modelContext.insert(event)
        try? modelContext.save()

        lastMessage = "Added: \(statName(for: selectedStatTypeId)) — \(playerLabel(for: selectedPlayerId)) — \(selectedQuarter)"
    }

    private func undoLastEvent() {
        guard let latest = sessionEvents.first else { return }
        modelContext.delete(latest)
        try? modelContext.save()
        lastMessage = "Undid last event"
    }

    private func handleVoiceTranscript(_ transcript: String) {
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

#if DEBUG
        print("VOICE_PARSE raw='\(result.rawTranscript)' normalized='\(result.normalizedTranscript)' status='\(result.parseStatus)' confidence='\(result.confidence)'")
#endif

        guard result.parseStatus == .success,
              let statTypeId = result.matchedStatTypeId,
              let playerId = result.matchedPlayerId else {
            lastMessage = parseFailureMessage(result)
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

        let playerText = playerLabel(for: playerId)
        let statText = statName(for: statTypeId)
        lastMessage = "Added: \(statText) — \(playerText) — \(selectedQuarter)"
    }

    private func parseFailureMessage(_ result: VoiceParseResult) -> String {
        switch result.parseStatus {
        case .emptyTranscript:
            return "No speech detected"
        case .noStatFound:
            return "Stat type not recognised"
        case .noPlayerFound:
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
        let columns = enabledStatTypes
        let rows = totalsRows
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 points
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 24

            if let logo = UIImage(named: "club_logo") {
                logo.draw(in: CGRect(x: 24, y: y, width: 48, height: 48))
            }
            y += 8
            ("Stats Report" as NSString).draw(at: CGPoint(x: 84, y: y), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 22)])
            y += 30
            let details = "Grade: \(gradeName)   Opposition: \(session.opposition)   Date: \(session.date.formatted(date: .abbreviated, time: .omitted))   Venue: \(session.venue)"
            (details as NSString).draw(in: CGRect(x: 24, y: y, width: pageRect.width - 48, height: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
            y += 36

            let totalColumns = CGFloat(2 + columns.count)
            let usableWidth = pageRect.width - 48
            let colWidth = usableWidth / max(totalColumns, 1)

            drawCell("Player", x: 24, y: y, width: colWidth * 1.5, bold: true)
            drawCell("#", x: 24 + colWidth * 1.5, y: y, width: colWidth * 0.5, bold: true)
            for (index, column) in columns.enumerated() {
                drawCell(column.name, x: 24 + colWidth * 2 + (CGFloat(index) * colWidth), y: y, width: colWidth, bold: true)
            }
            y += 22

            for row in rows {
                if y > pageRect.height - 36 {
                    context.beginPage()
                    y = 24
                }

                drawCell(row.player.name, x: 24, y: y, width: colWidth * 1.5)
                drawCell(row.player.number.map(String.init) ?? "", x: 24 + colWidth * 1.5, y: y, width: colWidth * 0.5)
                for (index, column) in columns.enumerated() {
                    drawCell("\(row.countsByStatId[column.id, default: 0])", x: 24 + colWidth * 2 + (CGFloat(index) * colWidth), y: y, width: colWidth)
                }
                y += 20
            }
        }

        let fileName = "Stats_\(gradeName.replacingOccurrences(of: " ", with: "_"))_\(session.date.formatted(date: .numeric, time: .omitted)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            shareURL = url
        } catch {
            lastMessage = "Failed to build report"
        }
    }

    private func drawCell(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, bold: Bool = false) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: bold ? UIFont.boldSystemFont(ofSize: 10) : UIFont.systemFont(ofSize: 10)
        ]
        (text as NSString).draw(in: CGRect(x: x + 2, y: y + 3, width: width - 4, height: 18), withAttributes: attributes)
        let path = UIBezierPath(rect: CGRect(x: x, y: y, width: width, height: 20))
        UIColor.systemGray4.setStroke()
        path.stroke()
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
