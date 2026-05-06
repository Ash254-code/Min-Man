import SwiftUI
import SwiftData
import UIKit
import PDFKit
import MessageUI

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
            "kick": ["kick", "kicks", "cake", "click"],
            "handball": ["handball", "hand ball", "handpass", "hand pass", "hamble", "ambo", "ammo", "cambell"],
            "mark": ["mark", "marks"],
            "tackle": ["tackle", "tackles"],
            "goal": ["goal", "goals", "go", "no", "cow", "call"],
            "behind": ["behind", "behinds", "point", "points", "rushed behind", "time", "holland"],
            "inside 50": ["inside 50", "inside fifty", "inside 50s"],
            "clearance": ["clearance", "clearances"],
            "hit out": ["hit out", "hitouts", "hit outs"],
            "free kick": ["free kick", "free kicks", "freakick", "freakicks"],
            "turnover": ["turnover", "turnovers"],
            "intercept": ["intercept", "intercepts"]
        ]
        let aliases = builtIn[lowercase] ?? [canonical]
        let detectedWords = SpeechDetectedWordsStore.words(for: id)
        return SpeechDetectedWordsStore.mergedAliases(
            canonical: canonical,
            builtIn: aliases,
            detected: detectedWords
        )
    }
}

private enum SpeechDetectedWordsStore {
    static let storageKey = "speech_setup_detected_words"

    static func words(for statTypeID: UUID) -> [String] {
        let key = "builtin::\(statTypeID.uuidString)"
        let map = load()
        return map[key] ?? []
    }

    static func words(forSectionKey sectionKey: String) -> [String] {
        let map = load()
        return map[sectionKey] ?? []
    }

    static func mergedAliases(canonical: String, builtIn: [String], detected: [String]) -> [String] {
        let canonicalTrimmed = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = [canonicalTrimmed] + builtIn + detected
        var seen: Set<String> = []
        var ordered: [String] = []

        for alias in combined {
            let normalized = alias
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                ordered.append(normalized)
            }
        }

        return ordered
    }

    private static func load() -> [String: [String]] {
        guard let json = UserDefaults.standard.string(forKey: storageKey),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            return [:]
        }

        return decoded.mapValues { values in
            values.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            .filter { !$0.isEmpty }
        }
    }
}

private enum SpeechVoteSection {
    static let contestedKey = "meta::contested"
    static let uncontestedKey = "meta::uncontested"
    static let effectiveKey = "meta::effective"
    static let ineffectiveKey = "meta::ineffective"

    static let all: [(key: String, name: String, defaultAliases: [String])] = [
        (contestedKey, "Contested", ["contested"]),
        (uncontestedKey, "Uncontested", ["uncontested"]),
        (effectiveKey, "Effective", ["effective", "efficient", "effecient"]),
        (ineffectiveKey, "Ineffective", ["ineffective", "inefficient", "ineffecient", "non effective", "noneffective"])
    ]
}

@Model
final class StatsSession {
    var sessionId: UUID
    var gradeId: UUID
    var opposition: String
    var date: Date
    var venue: String
    var enabledStatTypeIDsRaw: String
    var statCollectionModesRaw: String
    var displayOrderStatTypeIDsRaw: String
    var usesLiveGameScoreSync: Bool
    var createdAt: Date
    var isSaved: Bool
    var savedAt: Date?

    init(
        sessionId: UUID = UUID(),
        gradeId: UUID,
        opposition: String,
        date: Date,
        venue: String,
        enabledStatTypeIDsRaw: String = "",
        statCollectionModesRaw: String = "",
        displayOrderStatTypeIDsRaw: String = "",
        usesLiveGameScoreSync: Bool = false,
        createdAt: Date = Date(),
        isSaved: Bool = false,
        savedAt: Date? = nil
    ) {
        self.sessionId = sessionId
        self.gradeId = gradeId
        self.opposition = opposition
        self.date = date
        self.venue = venue
        self.enabledStatTypeIDsRaw = enabledStatTypeIDsRaw
        self.statCollectionModesRaw = statCollectionModesRaw
        self.displayOrderStatTypeIDsRaw = displayOrderStatTypeIDsRaw
        self.usesLiveGameScoreSync = usesLiveGameScoreSync
        self.createdAt = createdAt
        self.isSaved = isSaved
        self.savedAt = savedAt
    }
}

extension StatsSession {
    var enabledStatTypeIDs: Set<UUID> {
        Set(
            enabledStatTypeIDsRaw
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0)) }
        )
    }

    func setEnabledStatTypeIDs(_ ids: [UUID]) {
        enabledStatTypeIDsRaw = ids.map(\.uuidString).joined(separator: ",")
    }

    var displayOrderStatTypeIDs: [UUID] {
        displayOrderStatTypeIDsRaw
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
    }

    func setDisplayOrderStatTypeIDs(_ ids: [UUID]) {
        displayOrderStatTypeIDsRaw = ids.map(\.uuidString).joined(separator: ",")
    }

    fileprivate var statCollectionModes: [UUID: SessionStatCollectionMode] {
        Dictionary(
            uniqueKeysWithValues: statCollectionModesRaw
                .split(separator: ",")
                .compactMap { entry in
                    let components = entry.split(separator: ":", maxSplits: 1).map(String.init)
                    guard components.count == 2,
                          let id = UUID(uuidString: components[0]),
                          let mode = SessionStatCollectionMode(rawValue: components[1]) else {
                        return nil
                    }
                    return (id, mode)
                }
        )
    }

    fileprivate func setStatCollectionModes(_ modes: [UUID: SessionStatCollectionMode]) {
        statCollectionModesRaw = modes
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .map { "\($0.key.uuidString):\($0.value.rawValue)" }
            .joined(separator: ",")
    }
}

enum SessionStatCollectionMode: String, CaseIterable, Identifiable {
    case team = "Team"
    case individual = "Individual"

    var id: String { rawValue }
}

private let legacyWizardStatTypeIDsByTitle: [String: UUID] = [
    "Kick": UUID(uuidString: "10000000-0000-0000-0000-000000000001") ?? UUID(),
    "Handball": UUID(uuidString: "10000000-0000-0000-0000-000000000002") ?? UUID(),
    "Mark": UUID(uuidString: "10000000-0000-0000-0000-000000000003") ?? UUID(),
    "Tackle": UUID(uuidString: "10000000-0000-0000-0000-000000000004") ?? UUID(),
    "Hit Out": UUID(uuidString: "10000000-0000-0000-0000-000000000005") ?? UUID(),
    "Clearance": UUID(uuidString: "10000000-0000-0000-0000-000000000006") ?? UUID(),
    "Inside 50": UUID(uuidString: "10000000-0000-0000-0000-000000000007") ?? UUID(),
    "Free Kick": UUID(uuidString: "10000000-0000-0000-0000-000000000008") ?? UUID(),
    "Turnover": UUID(uuidString: "10000000-0000-0000-0000-000000000009") ?? UUID(),
    "Intercept": UUID(uuidString: "10000000-0000-0000-0000-000000000010") ?? UUID(),
    "Disposal Efficiency": UUID(uuidString: "10000000-0000-0000-0000-000000000011") ?? UUID(),
    "Contested Possession": UUID(uuidString: "10000000-0000-0000-0000-000000000012") ?? UUID(),
    "Goal": UUID(uuidString: "10000000-0000-0000-0000-000000000013") ?? UUID(),
    "Behind": UUID(uuidString: "10000000-0000-0000-0000-000000000014") ?? UUID()
]

private let legacyWizardStatTitlesByID: [UUID: String] = Dictionary(
    uniqueKeysWithValues: legacyWizardStatTypeIDsByTitle.map { ($0.value, $0.key) }
)

private func legacyWizardStatTypeID(for title: String) -> UUID {
    legacyWizardStatTypeIDsByTitle[title] ?? UUID()
}

private func legacyWizardStatTitle(for statTypeID: UUID) -> String? {
    legacyWizardStatTitlesByID[statTypeID]
}

private func resolvedEnabledStatTypeIDs(for session: StatsSession, allStatTypes: [StatType]) -> Set<UUID> {
    let allowedIDs = session.enabledStatTypeIDs
    let configuredModeIDs = Set(session.statCollectionModes.keys)
    let alwaysIncludedNames = Set(["inside 50", "inside50", "inside 50s"])
    guard !allowedIDs.isEmpty else {
        return Set(allStatTypes.filter(\.isEnabled).map(\.id))
    }

    let allowedLegacyTitles = Set(
        allowedIDs
            .compactMap(legacyWizardStatTitle(for:))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    )

    let resolvedIDs = allStatTypes.reduce(into: Set<UUID>()) { partialResult, type in
        let normalizedName = type.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if allowedIDs.contains(type.id)
            || allowedLegacyTitles.contains(normalizedName)
            || configuredModeIDs.contains(type.id)
            || alwaysIncludedNames.contains(normalizedName) {
            partialResult.insert(type.id)
        }
    }

    return resolvedIDs
}

private func orderedEnabledStatTypes(for session: StatsSession, allStatTypes: [StatType]) -> [StatType] {
    let resolvedEnabledIDs = resolvedEnabledStatTypeIDs(for: session, allStatTypes: allStatTypes)
    return orderedStatTypesForDisplayOrder(for: session, allStatTypes: allStatTypes).filter { type in
        type.isEnabled && resolvedEnabledIDs.contains(type.id)
    }
}

private func orderedStatTypesForDisplayOrder(for session: StatsSession, allStatTypes: [StatType]) -> [StatType] {
    let displayOrderByID = Dictionary(
        uniqueKeysWithValues: session.displayOrderStatTypeIDs.enumerated().map { ($0.element, $0.offset) }
    )

    return allStatTypes.sorted { lhs, rhs in
        let leftPosition = displayOrderByID[lhs.id] ?? Int.max
        let rightPosition = displayOrderByID[rhs.id] ?? Int.max
        if leftPosition != rightPosition {
            return leftPosition < rightPosition
        }
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

private func defaultSessionStatCollectionMode(for statName: String) -> SessionStatCollectionMode {
    let normalizedName = statName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let legacyTeamModes = Set([
        "clearance",
        "clearances",
        "inside 50",
        "inside50",
        "inside 50s",
        "free kick",
        "free kicks",
        "freakick",
        "freakicks",
        "turnover",
        "turnovers",
        "intercept",
        "intercepts",
        "disposal efficiency",
        "contested possession"
    ])
    return legacyTeamModes.contains(normalizedName) ? .team : .individual
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
    var contestedVoteRaw: String?
    var remoteRecordName: String?

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
        efficiencyVoteRaw: String? = nil,
        contestedVoteRaw: String? = nil,
        remoteRecordName: String? = nil
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
        self.contestedVoteRaw = contestedVoteRaw
        self.remoteRecordName = remoteRecordName
    }
}

enum StatsEventSource: String, CaseIterable {
    case manual
    case voice
    case remoteInvite
    case liveGameSync
}

@Model
final class StatsInviteAssignment {
    var id: UUID
    var contactId: UUID
    var assignedStatTypeIDsRaw: String
    var inviteLinkToken: String
    var inviteLinkURL: String
    var inviteeEmail: String
    var inviteeName: String
    var cloudRecordName: String
    var sessionIDRaw: String
    var sessionSummary: String
    var lastInvitedAt: Date
    var isConnected: Bool
    var lastConnectedAt: Date?

    init(
        id: UUID = UUID(),
        contactId: UUID,
        assignedStatTypeIDsRaw: String,
        inviteLinkToken: String,
        inviteLinkURL: String,
        inviteeEmail: String = "",
        inviteeName: String = "",
        cloudRecordName: String = "",
        sessionIDRaw: String = "",
        sessionSummary: String = "",
        lastInvitedAt: Date = Date(),
        isConnected: Bool = false,
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.contactId = contactId
        self.assignedStatTypeIDsRaw = assignedStatTypeIDsRaw
        self.inviteLinkToken = inviteLinkToken
        self.inviteLinkURL = inviteLinkURL
        self.inviteeEmail = inviteeEmail
        self.inviteeName = inviteeName
        self.cloudRecordName = cloudRecordName
        self.sessionIDRaw = sessionIDRaw
        self.sessionSummary = sessionSummary
        self.lastInvitedAt = lastInvitedAt
        self.isConnected = isConnected
        self.lastConnectedAt = lastConnectedAt
    }
}

extension StatsInviteAssignment {
    fileprivate var assignedSelections: [StatsInviteSelection] {
        assignedStatTypeIDsRaw
            .split(separator: ",")
            .compactMap { StatsInviteSelection(rawValue: String($0)) }
    }

    var assignedStatTypeIDs: [UUID] {
        Array(Set(assignedSelections.map(\.statTypeID)))
    }

    func setAssignedStatTypeIDs(_ ids: [UUID]) {
        setAssignedSelections(ids.map { StatsInviteSelection(statTypeID: $0, side: .ourClub) })
    }

    fileprivate func setAssignedSelections(_ selections: [StatsInviteSelection]) {
        assignedStatTypeIDsRaw = selections.map(\.rawValue).joined(separator: ",")
    }
}

private enum StatsInviteTeamSide: String, CaseIterable, Hashable {
    case ourClub
    case opposition

    var title: String {
        switch self {
        case .ourClub:
            return "Us"
        case .opposition:
            return "Opposition"
        }
    }

    var selectionPrefix: String {
        switch self {
        case .ourClub:
            return "Our"
        case .opposition:
            return "Their"
        }
    }
}

private struct StatsInviteSelection: Hashable, Identifiable {
    let statTypeID: UUID
    let side: StatsInviteTeamSide

    init(statTypeID: UUID, side: StatsInviteTeamSide) {
        self.statTypeID = statTypeID
        self.side = side
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "|", maxSplits: 1).map(String.init)
        if parts.count == 1, let statTypeID = UUID(uuidString: parts[0]) {
            self.init(statTypeID: statTypeID, side: .ourClub)
            return
        }
        guard
            parts.count == 2,
            let statTypeID = UUID(uuidString: parts[0]),
            let side = StatsInviteTeamSide(rawValue: parts[1])
        else {
            return nil
        }
        self.init(statTypeID: statTypeID, side: side)
    }

    var id: String { rawValue }

    var rawValue: String {
        "\(statTypeID.uuidString)|\(side.rawValue)"
    }
}

private func statsInviteSelectionNames(
    for selections: [StatsInviteSelection],
    statTypes: [StatType]
) -> [String] {
    let typeNames = Dictionary(uniqueKeysWithValues: statTypes.map { ($0.id, $0.name) })
    return selections.compactMap { selection in
        guard let name = typeNames[selection.statTypeID] else { return nil }
        return "\(selection.side.selectionPrefix) \(name)"
    }
}

private func statsInviteSelectionDisplayNamesByRawValue(
    for selections: [StatsInviteSelection],
    statTypes: [StatType]
) -> [String: String] {
    let typeNames = Dictionary(uniqueKeysWithValues: statTypes.map { ($0.id, $0.name) })
    return selections.reduce(into: [:]) { result, selection in
        guard let name = typeNames[selection.statTypeID] else { return }
        result[selection.rawValue] = "\(selection.side.selectionPrefix) \(name)"
    }
}

private func statsInviteSelectionCollectionModesByRawValue(
    for selections: [StatsInviteSelection],
    session: StatsSession,
    statTypes: [StatType]
) -> [String: String] {
    let statNamesByID = Dictionary(uniqueKeysWithValues: statTypes.map { ($0.id, $0.name) })
    return selections.reduce(into: [:]) { result, selection in
        let defaultName = statNamesByID[selection.statTypeID] ?? ""
        let mode = session.statCollectionModes[selection.statTypeID] ?? defaultSessionStatCollectionMode(for: defaultName)
        result[selection.rawValue] = mode.rawValue
    }
}

private func cloudRosterPlayers(from players: [Player]) -> [CloudStatsInviteRosterPlayer] {
    players.map { player in
        CloudStatsInviteRosterPlayer(
            id: player.id,
            name: player.name.trimmingCharacters(in: .whitespacesAndNewlines),
            number: player.number
        )
    }
}

private enum StatsInviteDraftStore {
    static let selectionKey = "statsInviteDraftSelections"

    static func loadSelections() -> Set<StatsInviteSelection> {
        let raw = UserDefaults.standard.string(forKey: selectionKey) ?? ""
        let selections = raw
            .split(separator: ",")
            .compactMap { StatsInviteSelection(rawValue: String($0)) }
        return Set(selections)
    }

    static func saveSelections(_ selections: Set<StatsInviteSelection>) {
        let raw = selections.map(\.rawValue).joined(separator: ",")
        UserDefaults.standard.set(raw, forKey: selectionKey)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { index in
            Array(self[index..<Swift.min(index + size, count)])
        }
    }
}

private enum EfficiencyVote: String {
    case thumbsUp
    case thumbsDown
}

private enum ContestedPossessionVote: String {
    case contested
    case uncontested
}

private struct StatRecordBanner: Equatable {
    let text: String
    let isSuccess: Bool
}

private struct QuickStatPieSlice: Shape {
    let startAngle: CGFloat
    let endAngle: CGFloat
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = Angle(degrees: startAngle)
        let end = Angle(degrees: endAngle)

        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

private enum StatsDefaults {
    static let statNames = [
        "Kick",
        "Handball",
        "Mark",
        "Tackle",
        "Goal",
        "Behind",
        "Inside 50",
        "Clearance",
        "Hit Out",
        "Free Kick",
        "Turnover",
        "Intercept",
        "Disposal Efficiency",
        "Contested Possession"
    ]
}

@MainActor
struct StatsRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigationState: AppNavigationState
    @Query(sort: \StatsSession.createdAt, order: .reverse) private var sessions: [StatsSession]
    @Query(sort: \Grade.displayOrder) private var grades: [Grade]
    @State private var showNewSession = false
    @State private var selectedSession: StatsSession?
    @State private var showUnsavedSessionAlert = false
    @State private var sessionPendingDeletion: StatsSession?

    var body: some View {
        NavigationStack {
            List {
                if navigationState.currentRole.canStartStatsSessions {
                    Section {
                        Button {
                            openNewSessionIfAllowed()
                        } label: {
                            Label("New Stats Session", systemImage: "plus.circle.fill")
                        }
                    }
                }

                Section("Recent Sessions") {
                    if sessions.isEmpty {
                        Text("No sessions yet")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(sessions) { session in
                        Button {
                            selectedSession = session
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(gradeName(for: session.gradeId))
                                        .font(.headline)
                                    Text("vs \(session.opposition) • \(session.date, format: Date.FormatStyle(date: .abbreviated, time: .omitted))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(sessionStatusText(for: session))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(session.isSaved ? .green : .orange)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(session.isSaved ? Color.green.opacity(0.14) : Color.orange.opacity(0.14))
                                    .clipShape(Capsule())
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                sessionPendingDeletion = session
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stats")
            .navigationDestination(isPresented: $showNewSession) {
                StatsSessionSetupView()
            }
            .navigationDestination(item: $selectedSession) { session in
                LiveStatsView(
                    session: session,
                    onSessionSaved: {
                        selectedSession = nil
                    }
                )
            }
            .task {
                seedDefaultStatTypesIfNeeded()
            }
            .onChange(of: navigationState.startNewStatsSessionToken) { _, _ in
                openNewSessionIfAllowed()
            }
            .alert("Current Session In Progress", isPresented: $showUnsavedSessionAlert) {
                Button("Yes") {
                    saveInProgressSessionAndStartNew()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let latestUnsavedSession {
                    Text("The current stats session for \(gradeName(for: latestUnsavedSession.gradeId)) vs \(latestUnsavedSession.opposition) is still in progress. Would you like to save that session and start a new session?")
                } else {
                    Text("A stats session is still in progress. Would you like to save that session and start a new session?")
                }
            }
            .alert("Delete Stats Session?", isPresented: deleteConfirmationPresented, presenting: sessionPendingDeletion) { session in
                Button("Delete", role: .destructive) {
                    deleteSession(session)
                }
                Button("Cancel", role: .cancel) {
                    sessionPendingDeletion = nil
                }
            } message: { session in
                Text("Delete the \(gradeName(for: session.gradeId)) session vs \(session.opposition)? This will permanently remove the session and its recorded stats.")
            }
        }
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { sessionPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    sessionPendingDeletion = nil
                }
            }
        )
    }

    private var latestUnsavedSession: StatsSession? {
        sessions.first(where: { !$0.isSaved })
    }

    private func gradeName(for id: UUID) -> String {
        grades.first(where: { $0.id == id })?.name ?? "Unknown Grade"
    }

    private func sessionStatusText(for session: StatsSession) -> String {
        session.isSaved ? "Saved" : "In Progress"
    }

    private func openNewSessionIfAllowed() {
        guard navigationState.currentRole.canStartStatsSessions else { return }
        if latestUnsavedSession != nil {
            showUnsavedSessionAlert = true
        } else {
            showNewSession = true
        }
    }

    private func saveInProgressSessionAndStartNew() {
        guard let latestUnsavedSession else {
            showNewSession = true
            return
        }

        latestUnsavedSession.isSaved = true
        latestUnsavedSession.savedAt = Date()
        if navigationState.activeStatsSessionID == latestUnsavedSession.sessionId {
            navigationState.clearActiveStatsSession()
        }
        try? modelContext.save()
        showNewSession = true
    }

    private func deleteSession(_ session: StatsSession) {
        let sessionID = session.sessionId
        let sessionIDRaw = sessionID.uuidString

        if navigationState.activeStatsSessionID == sessionID {
            navigationState.clearActiveStatsSession()
        }
        if selectedSession?.persistentModelID == session.persistentModelID {
            selectedSession = nil
        }

        let eventDescriptor = FetchDescriptor<StatEvent>(
            predicate: #Predicate { event in
                event.sessionId == sessionID
            }
        )
        let assignmentDescriptor = FetchDescriptor<StatsInviteAssignment>(
            predicate: #Predicate { assignment in
                assignment.sessionIDRaw == sessionIDRaw
            }
        )

        if let events = try? modelContext.fetch(eventDescriptor) {
            for event in events {
                modelContext.delete(event)
            }
        }

        if let assignments = try? modelContext.fetch(assignmentDescriptor) {
            for assignment in assignments {
                modelContext.delete(assignment)
            }
        }

        modelContext.delete(session)
        try? modelContext.save()
        sessionPendingDeletion = nil

        Task {
            await CloudKitStatsInviteService.shared.deleteSessionArtifacts(sessionID: sessionID)
        }
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
    private enum StatsLayoutOption: String, CaseIterable, Identifiable {
        case edge = "Edge"
        case simple = "Simple"

        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StatType.sortOrder) private var statTypes: [StatType]
    @AppStorage("statsLayout") private var statsLayout = StatsLayoutOption.simple.rawValue
    @AppStorage("app.testFlightURL") private var testFlightURL = ""

    var body: some View {
        sharedControlsPane
            .padding()
        .navigationTitle("Stats")
        .task {
            if statsLayout == "Standard" {
                statsLayout = StatsLayoutOption.simple.rawValue
            }
            seedDefaultStatTypesIfNeeded()
            ensureAlwaysOnStatTypesIfNeeded()
            ensureRequiredTeamComparisonStatTypesIfNeeded()
            removeDeprecatedStatTypesIfNeeded()
            ensureGoalAndBehindStatTypesIfNeeded()
        }
    }

    private var sharedControlsPane: some View {
        List {
            Section("Layout") {
                Picker("Layout", selection: $statsLayout) {
                    ForEach(StatsLayoutOption.allCases) { layout in
                        Text(layout.rawValue).tag(layout.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Speech") {
                NavigationLink {
                    SpeechSetupView()
                } label: {
                    Label("Speech Setup", systemImage: "waveform.badge.mic")
                }
            }

            Section("Stat Taker TestFlight Link") {
                TextField("https://testflight.apple.com/join/...", text: $testFlightURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Set the public TestFlight invite used when sharing CloudKit stat taker assignments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .listStyle(.insetGrouped)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    private func ensureAlwaysOnStatTypesIfNeeded() {
        var existing = (try? modelContext.fetch(FetchDescriptor<StatType>())) ?? []
        let alwaysOnNames = ["Inside 50"]

        for name in alwaysOnNames {
            if let match = existing.first(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
                match.isEnabled = true
            } else {
                let type = StatType(name: name, isEnabled: true, sortOrder: existing.count)
                modelContext.insert(type)
                existing.append(type)
            }
        }
        save()
    }

    private func ensureRequiredTeamComparisonStatTypesIfNeeded() {
        var existing = (try? modelContext.fetch(FetchDescriptor<StatType>())) ?? []
        let requiredNames = [
            "Clearance",
            "Hit Out",
            "Free Kick",
            "Turnover",
            "Intercept",
            "Disposal Efficiency",
            "Contested Possession"
        ]
        var didChange = false

        for name in requiredNames {
            if let match = existing.first(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
                if !match.isEnabled {
                    match.isEnabled = true
                    didChange = true
                }
                continue
            }

            let type = StatType(name: name, isEnabled: true, sortOrder: existing.count)
            modelContext.insert(type)
            existing.append(type)
            didChange = true
        }

        if didChange {
            resequence()
            save()
        }
    }

    private func removeDeprecatedStatTypesIfNeeded() {
        let deprecatedNames = Set(["scores"])
        let existing = (try? modelContext.fetch(FetchDescriptor<StatType>())) ?? []
        let deprecated = existing.filter { deprecatedNames.contains($0.name.lowercased()) }
        guard !deprecated.isEmpty else { return }

        deprecated.forEach { modelContext.delete($0) }
        resequence()
        save()
    }

    private func ensureGoalAndBehindStatTypesIfNeeded() {
        var existing = (try? modelContext.fetch(FetchDescriptor<StatType>())) ?? []
        let requiredNames = ["Goal", "Behind"]

        var didChange = false
        for name in requiredNames {
            if existing.contains(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
                continue
            }
            let type = StatType(name: name, isEnabled: true, sortOrder: existing.count)
            modelContext.insert(type)
            existing.append(type)
            didChange = true
        }

        if didChange {
            resequence()
            save()
        }
    }
}

private struct CustomSpeechStatSection: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
}

struct SpeechSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StatType.sortOrder) private var allStatTypes: [StatType]

    @StateObject private var speechService = PressHoldSpeechService()
    @State private var activeSectionID: String?
    @State private var newSectionName = ""
    @State private var showUnsavedChangesAlert = false

    @AppStorage("speech_setup_custom_sections") private var customSectionsData = ""
    @AppStorage("speech_setup_detected_words") private var detectedWordsData = ""

    @State private var customSections: [CustomSpeechStatSection] = []
    @State private var detectedWordsBySection: [String: [String]] = [:]
    @State private var savedCustomSections: [CustomSpeechStatSection] = []
    @State private var savedDetectedWordsBySection: [String: [String]] = [:]

    var body: some View {
        List {
            Section("Add Custom Stat Type") {
                TextField("New stat type", text: $newSectionName)
                Button {
                    addCustomSection()
                } label: {
                    Label("Add Section", systemImage: "plus.circle.fill")
                }
                .disabled(newSectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ForEach(allSections) { section in
                Section(section.name) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(activeSectionID == section.storageKey ? "Listening…" : "Hold to speak")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Press and hold the mic button to capture words.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            TextField(
                                "Add words manually, or speak and edit the result.",
                                text: editableWordsBinding(for: section.storageKey),
                                axis: .vertical
                            )
                            .textFieldStyle(.roundedBorder)

                            let words = detectedWordsBySection[section.storageKey] ?? []
                            if !words.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(words, id: \.self) { word in
                                            HStack(spacing: 6) {
                                                Text(word)
                                                    .font(.subheadline)
                                                Button {
                                                    removeWord(word, from: section.storageKey)
                                                } label: {
                                                    Image(systemName: "xmark")
                                                        .font(.caption.weight(.bold))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 10)
                                            .background(
                                                Capsule()
                                                    .fill(Color(.secondarySystemBackground))
                                            )
                                        }
                                    }
                                }
                            }

                            HStack {
                                Spacer()
                                Button("Clear") {
                                    clearWords(for: section.storageKey)
                                }
                                .disabled((detectedWordsBySection[section.storageKey] ?? []).isEmpty)
                            }
                        }

                        Button {
                            // press-and-hold only
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(activeSectionID == section.storageKey ? .red : .blue)
                                Image(systemName: "mic.fill")
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 74, height: 74)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                        .onLongPressGesture(minimumDuration: 0.01, maximumDistance: .infinity, pressing: { isPressing in
                            if isPressing {
                                activeSectionID = section.storageKey
                                speechService.startListening(vocabulary: sectionVocabulary(for: section))
                            } else if activeSectionID == section.storageKey {
                                speechService.stopListening { transcript in
                                    appendDetectedWords(transcript, to: section.storageKey)
                                    activeSectionID = nil
                                }
                            }
                        }, perform: {})
                    }
                }
            }
        }
        .navigationTitle("Speech Recognition")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    handleBackButtonPressed()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saveAllChanges()
                }
                .saveButtonBehavior(isEnabled: hasUnsavedChanges)
            }
        }
        .alert("Unsaved Changes", isPresented: $showUnsavedChangesAlert) {
            Button("Discard Changes", role: .destructive) {
                dismiss()
            }
            Button("Save and Leave") {
                saveAllChanges()
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved changes. Save before leaving this page?")
        }
        .onAppear {
            loadCustomSections()
            loadDetectedWords()
            snapshotSavedState()
        }
    }

    private var hasUnsavedChanges: Bool {
        customSections != savedCustomSections || detectedWordsBySection != savedDetectedWordsBySection
    }

    private var allSections: [SpeechSection] {
        let builtIn = allStatTypes
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .map { SpeechSection(storageKey: "builtin::\($0.id.uuidString)", name: $0.name, defaultVocabulary: []) }

        let voteSections = SpeechVoteSection.all.map {
            SpeechSection(storageKey: $0.key, name: $0.name, defaultVocabulary: $0.defaultAliases)
        }

        let custom = customSections.map {
            SpeechSection(storageKey: "custom::\($0.id.uuidString)", name: $0.name, defaultVocabulary: [])
        }

        return builtIn + voteSections + custom
    }

    private var allDetectedWords: [String] {
        Array(Set(detectedWordsBySection.values.flatMap { $0 }))
            .sorted()
    }

    private func sectionVocabulary(for section: SpeechSection) -> [String] {
        Array(Set([section.name] + section.defaultVocabulary + allDetectedWords))
    }

    private func handleBackButtonPressed() {
        if hasUnsavedChanges {
            showUnsavedChangesAlert = true
        } else {
            dismiss()
        }
    }

    private func saveAllChanges() {
        persistCustomSections()
        persistDetectedWords()
        snapshotSavedState()
    }

    private func snapshotSavedState() {
        savedCustomSections = customSections
        savedDetectedWordsBySection = detectedWordsBySection
    }

    private func appendDetectedWords(_ transcript: String, to storageKey: String) {
        let newTokens = parseWords(from: transcript)
        guard !newTokens.isEmpty else { return }

        let existing = detectedWordsBySection[storageKey] ?? []
        detectedWordsBySection[storageKey] = deduplicatedWords(existing + newTokens)
    }

    private func removeWord(_ word: String, from storageKey: String) {
        let existing = detectedWordsBySection[storageKey] ?? []
        detectedWordsBySection[storageKey] = existing.filter { $0 != word }
    }

    private func clearWords(for storageKey: String) {
        detectedWordsBySection[storageKey] = []
    }

    private func editableWordsBinding(for storageKey: String) -> Binding<String> {
        Binding(
            get: {
                (detectedWordsBySection[storageKey] ?? []).joined(separator: ", ")
            },
            set: { rawValue in
                detectedWordsBySection[storageKey] = parseWords(from: rawValue)
            }
        )
    }

    private func parseWords(from rawValue: String) -> [String] {
        let tokens = rawValue
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return deduplicatedWords(tokens)
    }

    private func deduplicatedWords(_ words: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for word in words {
            guard seen.insert(word).inserted else { continue }
            result.append(word)
        }

        return result
    }

    private func addCustomSection() {
        let trimmed = newSectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        customSections.append(CustomSpeechStatSection(id: UUID(), name: trimmed))
        customSections.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        newSectionName = ""
    }

    private func loadCustomSections() {
        guard !customSectionsData.isEmpty,
              let data = customSectionsData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([CustomSpeechStatSection].self, from: data)
        else {
            customSections = []
            return
        }
        customSections = decoded
    }

    private func persistCustomSections() {
        guard let data = try? JSONEncoder().encode(customSections),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        customSectionsData = json
    }

    private func loadDetectedWords() {
        guard !detectedWordsData.isEmpty,
              let data = detectedWordsData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            detectedWordsBySection = [:]
            return
        }
        detectedWordsBySection = decoded
    }

    private func persistDetectedWords() {
        guard let data = try? JSONEncoder().encode(detectedWordsBySection),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        detectedWordsData = json
    }
}

private struct SpeechSection: Identifiable {
    let storageKey: String
    let name: String
    let defaultVocabulary: [String]

    var id: String { storageKey }
}

struct StatsSessionSetupView: View {
    private enum Step: Int, CaseIterable {
        case details
        case statCollection
        case oppositionStatCollection
        case comparisonStats
        case inviteUsers
    }

    private enum StatsCollectionMode: String, CaseIterable, Identifiable {
        case team = "Team"
        case individual = "Individual"

        var id: String { rawValue }
    }

    private enum MatchEventDeliveryMode: String, CaseIterable, Identifiable {
        case liveGame = "Live Game"
        case invite = "Invite"

        var id: String { rawValue }
    }

    private struct StatsCollectionOption: Identifiable {
        let id: String
        let title: String
        var isEnabled: Bool
        var mode: StatsCollectionMode
        var matchEventDeliveryMode: MatchEventDeliveryMode

        init(
            title: String,
            isEnabled: Bool = true,
            mode: StatsCollectionMode,
            matchEventDeliveryMode: MatchEventDeliveryMode = .liveGame
        ) {
            self.id = title
            self.title = title
            self.isEnabled = isEnabled
            self.mode = mode
            self.matchEventDeliveryMode = matchEventDeliveryMode
        }
    }

    fileprivate struct WizardInviteAssignment: Identifiable, Equatable {
        let id: UUID
        let contact: PhoneInviteContact
        var selectionRawValues: [String]
    }

    fileprivate struct WizardInviteDispatchItem: Identifiable, Equatable {
        let id: UUID
        let contact: PhoneInviteContact
        let selections: [StatsInviteSelection]
        let shareText: String
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var navigationState: AppNavigationState
    @AppStorage("app.testFlightURL") private var testFlightURL = ""
    @Query(sort: \Grade.displayOrder) private var grades: [Grade]
    @Query(sort: \Player.name) private var wizardPlayers: [Player]
    @Query(sort: \StatType.sortOrder) private var allStatTypes: [StatType]
    @Query(sort: \Contact.name) private var contacts: [Contact]
    @Query(sort: \StatsInviteAssignment.lastInvitedAt, order: .reverse) private var inviteAssignments: [StatsInviteAssignment]
    @Query(sort: \StatsSession.createdAt, order: .reverse) private var existingSessions: [StatsSession]

    @State private var selectedGradeId: UUID?
    @State private var opposition = ""
    @State private var date = Date()
    @State private var venue = ""
    @State private var clubConfiguration = ClubConfigurationStore.load()
    @State private var step: Step = .details
    @State private var statOptions: [StatsCollectionOption] = [
        StatsCollectionOption(title: "Kick", mode: .individual),
        StatsCollectionOption(title: "Handball", mode: .individual),
        StatsCollectionOption(title: "Mark", mode: .individual),
        StatsCollectionOption(title: "Tackle", mode: .individual),
        StatsCollectionOption(title: "Hit Out", isEnabled: false, mode: .individual),
        StatsCollectionOption(title: "Clearance", isEnabled: false, mode: .team),
        StatsCollectionOption(title: "Inside 50", isEnabled: false, mode: .team),
        StatsCollectionOption(title: "Free Kick", isEnabled: false, mode: .team),
        StatsCollectionOption(title: "Turnover", isEnabled: false, mode: .team),
        StatsCollectionOption(title: "Intercept", isEnabled: false, mode: .team),
        StatsCollectionOption(title: "Disposal Efficiency", isEnabled: false, mode: .team),
        StatsCollectionOption(title: "Contested Possession", isEnabled: false, mode: .team)
    ]
    @State private var oppositionStatOptions: [StatsCollectionOption] = [
        StatsCollectionOption(title: "Kick", mode: .team),
        StatsCollectionOption(title: "Handball", mode: .team),
        StatsCollectionOption(title: "Mark", mode: .team),
        StatsCollectionOption(title: "Tackle", mode: .team),
        StatsCollectionOption(title: "Hit Out", isEnabled: false, mode: .team),
        StatsCollectionOption(title: "Clearance", isEnabled: false, mode: .team),
        StatsCollectionOption(title: "Inside 50", isEnabled: false, mode: .team),
        StatsCollectionOption(title: "Free Kick", isEnabled: false, mode: .team),
        StatsCollectionOption(title: "Turnover", isEnabled: false, mode: .team),
        StatsCollectionOption(title: "Intercept", isEnabled: false, mode: .team),
        StatsCollectionOption(title: "Disposal Efficiency", isEnabled: false, mode: .team),
        StatsCollectionOption(title: "Contested Possession", isEnabled: false, mode: .team)
    ]
    @State private var comparisonStatOptions: [StatsCollectionOption] = [
        StatsCollectionOption(title: "Goal", mode: .individual),
        StatsCollectionOption(title: "Behind", mode: .individual)
    ]
    @State private var oppositionComparisonStatOptions: [StatsCollectionOption] = [
        StatsCollectionOption(title: "Goal", mode: .team),
        StatsCollectionOption(title: "Behind", mode: .team)
    ]
    @State private var wizardInviteAssignments: [WizardInviteAssignment] = []
    @State private var draftInviteName = ""
    @State private var draftInvitePhone = ""
    @State private var draftInviteMobile = ""
    @State private var draftInviteSelectionRawValues: Set<String> = []
    @State private var selectedSavedInviteEmail = ""
    @State private var showWizardContactPicker = false
    @State private var showAddWizardInvitePersonSheet = false
    @State private var showWizardStatPicker = false
    @State private var previewInviteAssignment: WizardInviteAssignment?
    @State private var editingWizardInviteAssignment: WizardInviteAssignment?
    @State private var startedSession: StatsSession?
    @State private var showLiveStats = false
    @State private var inviteDispatchItems: [WizardInviteDispatchItem] = []
    @State private var showInviteDispatchSheet = false
    @State private var duplicateSessionWarning = false
    @State private var isStartingSession = false

    var body: some View {
        VStack(spacing: 0) {
            wizardHeader

            ProgressView(value: Double(step.rawValue), total: Double(max(Step.allCases.count - 1, 1)))
                .padding(.horizontal)
                .padding(.top, 14)
                .padding(.bottom, 10)

            TabView(selection: $step) {
                detailsStep
                    .tag(Step.details)

                statsCollectionStep
                    .tag(Step.statCollection)

                oppositionStatsCollectionStep
                    .tag(Step.oppositionStatCollection)

                comparisonStatsStep
                    .tag(Step.comparisonStats)

                inviteUsersStep
                    .tag(Step.inviteUsers)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                if step == .details {
                    Button("Cancel") {
                        dismiss()
                    }
                } else {
                    Button("Back") {
                        back()
                    }
                }

                Spacer()

                Button(primaryActionTitle) {
                    performPrimaryAction()
                }
                .disabled(!canProceed || isStartingSession)
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .font(.system(size: isIPhoneWizardLayout ? 18 : (isCompactLayout ? 24 : 28), weight: .semibold))
            .controlSize(isIPhoneWizardLayout ? .regular : (isCompactLayout ? .large : .extraLarge))
            .padding(.horizontal, isIPhoneWizardLayout ? 16 : (isCompactLayout ? 18 : 26))
            .padding(.vertical, isIPhoneWizardLayout ? 10 : (isCompactLayout ? 14 : 18))
            .background(.ultraThinMaterial)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showLiveStats) {
            if let startedSession {
                LiveStatsView(session: startedSession, onSessionSaved: nil)
            }
        }
        .onAppear {
            clubConfiguration = ClubConfigurationStore.load()
            if selectedGradeId == nil, activeGrades.count == 1 {
                selectedGradeId = activeGrades.first?.id
            }
        }
        .sheet(isPresented: $showInviteDispatchSheet, onDismiss: {
            if startedSession != nil, !showLiveStats {
                showLiveStats = true
            }
        }) {
            WizardInviteDispatchSheet(
                items: inviteDispatchItems,
                clubConfiguration: clubConfiguration,
                clubName: ourTeamName,
                gradeTitle: selectedGradeName,
                oppositionName: oppositionTeamName,
                statTypes: wizardPreviewStatTypes,
                onFinished: {
                    showInviteDispatchSheet = false
                    showLiveStats = true
                }
            )
        }
        .alert("Stats Session Already Exists", isPresented: $duplicateSessionWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A stats session already exists for this grade, venue and date. Change one of those details before creating a new session.")
        }
        .overlay {
            if isStartingSession {
                ZStack {
                    Color.black.opacity(0.24)
                        .ignoresSafeArea()

                    VStack(spacing: 14) {
                        LoadingFootballView(
                            "Starting stats session…",
                            tint: .orange,
                            size: 34,
                            font: .headline
                        )
                        Text("Setting up invites and getting everything ready.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .padding(24)
                }
                .transition(.opacity)
            }
        }
    }

    private var isCompactLayout: Bool {
        horizontalSizeClass == .compact
    }

    private var isIPhoneWizardLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var wizardPrimaryTitleFont: Font {
        .system(size: isIPhoneWizardLayout ? 28 : (isCompactLayout ? 40 : 52), weight: .bold)
    }

    private var wizardSecondaryTitleFont: Font {
        .system(size: isIPhoneWizardLayout ? 18 : (isCompactLayout ? 22 : 30), weight: .semibold)
    }

    private var wizardStepSubtitleFont: Font {
        .system(size: isIPhoneWizardLayout ? 13 : (isCompactLayout ? 16 : 20), weight: .semibold)
    }

    private var wizardBodyFont: Font {
        .system(size: isIPhoneWizardLayout ? 16 : (isCompactLayout ? 20 : 24), weight: .regular)
    }

    private var activeGrades: [Grade] {
        grades.filter(\.isActive)
    }

    private var selectedGradeName: String {
        grades.first(where: { $0.id == selectedGradeId })?.name ?? "Select Grade"
    }

    private var oppositionNames: [String] {
        clubConfiguration.sortedOppositions.map(\.name)
    }

    private var selectedOpposition: OppositionTeamProfile? {
        clubConfiguration.sortedOppositions.first(where: { $0.name == opposition })
    }

    private var venueOptions: [String] {
        let combined = clubConfiguration.clubTeam.sanitizedVenues + (selectedOpposition?.sanitizedVenues ?? [])
        var seen = Set<String>()
        return combined.filter { seen.insert($0).inserted }
    }

    private var ourTeamName: String {
        let trimmed = clubConfiguration.clubTeam.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Our Team" : trimmed
    }

    private var ourTeamStyle: ClubStyle.Style {
        ClubStyle.style(for: ourTeamName, configuration: clubConfiguration)
    }

    private var oppositionTeamName: String {
        let trimmed = opposition.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Opposition" : trimmed
    }

    private var oppositionTeamStyle: ClubStyle.Style {
        ClubStyle.style(for: oppositionTeamName, configuration: clubConfiguration)
    }

    private var canProceed: Bool {
        switch step {
        case .details:
            selectedGradeId != nil &&
            !opposition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !venue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .statCollection:
            canProceedFromStatCollection
        case .oppositionStatCollection:
            canProceedFromOppositionStatCollection
        case .comparisonStats:
            canProceedFromComparisonStats
        case .inviteUsers:
            canProceedFromInviteUsers
        }
    }

    private var canProceedFromStatCollection: Bool {
        statOptions.contains(where: \.isEnabled)
    }

    private var canProceedFromOppositionStatCollection: Bool {
        oppositionStatOptions.contains(where: \.isEnabled)
    }

    private var canProceedFromComparisonStats: Bool {
        comparisonStatOptions.contains(where: \.isEnabled) &&
        oppositionComparisonStatOptions.contains(where: \.isEnabled)
    }

    private var canProceedFromInviteUsers: Bool {
        !wizardInviteAssignments.isEmpty &&
        availableWizardInviteSelections.isEmpty
    }

    private var primaryActionTitle: String {
        step == .inviteUsers ? "Start" : "Next"
    }

    private var wizardHeader: some View {
        HStack(alignment: .top, spacing: isIPhoneWizardLayout ? 8 : 12) {
            VStack(alignment: .leading, spacing: isCompactLayout ? 2 : 4) {
                Text("New Stats Session")
                    .font(wizardPrimaryTitleFont)
                    .minimumScaleFactor(0.75)

                Text(stepSubtitle)
                    .font(wizardStepSubtitleFont)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(selectedGradeName)
                .font(wizardSecondaryTitleFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.horizontal, isIPhoneWizardLayout ? 16 : (isCompactLayout ? 20 : 28))
        .padding(.top, isIPhoneWizardLayout ? 4 : (isCompactLayout ? 8 : 14))
        .padding(.bottom, isIPhoneWizardLayout ? 8 : (isCompactLayout ? 12 : 16))
    }

    private var stepSubtitle: String {
        switch step {
        case .details:
            return "Game Details"
        case .statCollection:
            return "Stats To Collect"
        case .oppositionStatCollection:
            return "Opposition Stats"
        case .comparisonStats:
            return "Match Events"
        case .inviteUsers:
            return "Invite Stat Takers"
        }
    }

    private var detailsStep: some View {
        ScrollView {
            VStack(spacing: 14) {
                StatsWizardCard(title: "Game Details", systemImage: "calendar", compactStyle: isIPhoneWizardLayout) {
                    if activeGrades.count != 1 {
                        HStack(spacing: 12) {
                            rowLabel("Grade")
                            Spacer()
                            setupMenuButton(title: selectedGradeId == nil ? "Select…" : selectedGradeName) {
                                Button("Select…") {
                                    selectedGradeId = nil
                                }
                                ForEach(activeGrades) { grade in
                                    Button(grade.name) {
                                        selectedGradeId = grade.id
                                    }
                                }
                            }
                        }
                    }

                    DatePicker("Date & Time", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .font(wizardBodyFont)

                    HStack(spacing: 12) {
                        rowLabel("Opponent")
                        Spacer()
                        setupMenuButton(title: opposition.isEmpty ? "Select…" : opposition) {
                            Button("Select…") {
                                opposition = ""
                                venue = ""
                            }
                            ForEach(oppositionNames, id: \.self) { name in
                                Button(name) {
                                    opposition = name
                                    if !venueOptions.contains(venue) {
                                        venue = ""
                                    }
                                }
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        rowLabel("Venue")
                        Spacer()
                        setupMenuButton(
                            title: venue.isEmpty ? "Select…" : venue,
                            isDisabled: venueOptions.isEmpty
                        ) {
                            Button("Select…") {
                                venue = ""
                            }
                            ForEach(venueOptions, id: \.self) { name in
                                Button(name) {
                                    venue = name
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .dynamicTypeSize(.large ... .accessibility2)
        .background(Color(.systemGroupedBackground))
    }

    private var statsCollectionStep: some View {
        statsCollectionStepContent(
            title: "Stats To Collect",
            pillTitle: ourTeamName,
            pillStyle: ourTeamStyle,
            options: $statOptions
        )
    }

    private var oppositionStatsCollectionStep: some View {
        statsCollectionStepContent(
            title: "Opposition Stats",
            pillTitle: oppositionTeamName,
            pillStyle: oppositionTeamStyle,
            options: $oppositionStatOptions
        )
    }

    private var comparisonStatsStep: some View {
        ScrollView {
            VStack(spacing: 14) {
                StatsWizardCard(title: "Match Events", systemImage: "square.split.2x1", compactStyle: isIPhoneWizardLayout) {
                    LazyVGrid(columns: statsSelectionColumns, spacing: 16) {
                        comparisonStatsColumn(
                            pillTitle: ourTeamName,
                            pillStyle: ourTeamStyle,
                            options: $comparisonStatOptions
                        )

                        comparisonStatsColumn(
                            pillTitle: oppositionTeamName,
                            pillStyle: oppositionTeamStyle,
                            options: $oppositionComparisonStatOptions
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .dynamicTypeSize(.large ... .accessibility2)
        .background(Color(.systemGroupedBackground))
    }

    private var inviteUsersStep: some View {
        ScrollView {
            VStack(spacing: 14) {
                StatsWizardCard(title: "Invite Stat Takers", systemImage: "person.badge.plus", compactStyle: isIPhoneWizardLayout) {
                    inviteUsersOverviewHeader

                    LazyVGrid(columns: inviteWizardColumns, alignment: .leading, spacing: 16) {
                        invitePeopleComposerCard
                        inviteAssignmentsOverviewCard
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .dynamicTypeSize(.large ... .accessibility2)
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showWizardStatPicker) {
            NavigationStack {
                List {
                    if availableWizardInviteSelections.isEmpty {
                        Text("No unallocated stats remain.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableWizardInviteSelections, id: \.id) { selection in
                            Button {
                                toggleDraftInviteSelection(selection)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(wizardSelectionDisplayName(selection))
                                            .foregroundStyle(.primary)
                                        Text(selection.side == .ourClub ? ourTeamName : oppositionTeamName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if draftInviteSelectionRawValues.contains(selection.rawValue) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .navigationTitle("Choose Stats")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(draftInviteSelectionRawValues.isEmpty ? "Done" : "Done & Save") {
                            finalizeDraftInviteFromStatPicker()
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $previewInviteAssignment) { assignment in
            NavigationStack {
                StatsInviteLivePreviewView(
                    clubConfiguration: clubConfiguration,
                    clubName: ourTeamName,
                    gradeTitle: selectedGradeName,
                    oppositionName: oppositionTeamName,
                    selections: wizardSelections(for: assignment),
                    statTypes: wizardPreviewStatTypes
                )
            }
        }
        .sheet(item: $editingWizardInviteAssignment) { assignment in
            WizardInviteEditorSheet(
                assignment: assignment,
                availableSelections: availableWizardInviteSelections(for: assignment),
                teamNameForSelection: { selection in
                    selection.side == StatsInviteTeamSide.ourClub ? ourTeamName : oppositionTeamName
                },
                selectionDisplayName: { selection in
                    wizardSelectionDisplayName(selection)
                },
                previewSelections: { editedAssignment in
                    wizardSelections(for: editedAssignment)
                },
                previewStatTypes: wizardPreviewStatTypes,
                clubConfiguration: clubConfiguration,
                clubName: ourTeamName,
                gradeTitle: selectedGradeName,
                oppositionName: oppositionTeamName,
                onSave: { updated in
                    updateWizardInviteAssignment(updated)
                }
            )
        }
        .sheet(isPresented: $showAddWizardInvitePersonSheet) {
            NavigationStack {
                WizardInvitePersonSheet(
                    name: $draftInviteName,
                    email: $draftInvitePhone,
                    mobile: $draftInviteMobile
                )
            }
        }
    }

    private var inviteUsersOverviewHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Build your stat crew quickly. Load a previous person first, allocate a few stats, then move straight to the next person.")
                .font(wizardBodyFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: isIPhoneWizardLayout ? 150 : 180), spacing: 10)], spacing: 10) {
                inviteSummaryPill(
                    title: "Unassigned",
                    value: "\(unassignedWizardSelectionCount)",
                    tint: unassignedWizardSelectionCount == 0 ? .green : .orange
                )
                inviteSummaryPill(
                    title: "Stat Takers",
                    value: "\(wizardInviteAssignments.count)",
                    tint: .blue
                )
                inviteSummaryPill(
                    title: "Enabled Stats",
                    value: "\(enabledWizardInviteSelections.count)",
                    tint: .teal
                )
            }
        }
    }

    private var inviteWizardColumns: [GridItem] {
        if isIPhoneWizardLayout {
            return [GridItem(.flexible(), spacing: 12, alignment: .top)]
        }
        return [
            GridItem(.flexible(minimum: 320, maximum: 520), spacing: 16, alignment: .top),
            GridItem(.flexible(minimum: 320, maximum: 720), spacing: 16, alignment: .top)
        ]
    }

    private var invitePeopleComposerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Add People Fast", systemImage: "person.crop.circle.badge.plus")
                .font(.headline.weight(.bold))

            if !savedWizardInviteContacts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Previous stat takers")
                        .font(.system(size: isIPhoneWizardLayout ? 18 : 22, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .center, spacing: 12) {
                        Picker("Previous stat takers", selection: $selectedSavedInviteEmail) {
                            Text("Choose a saved person").tag("")
                            ForEach(savedWizardInviteContacts) { contact in
                                Text(contact.title).tag(contact.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedSavedInviteEmail) { _, newValue in
                            applySavedInviteContact(email: newValue)
                        }

                        Spacer(minLength: 0)

                        Button {
                            prepareForNewWizardInvitePerson()
                        } label: {
                            Label("Add New", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Button {
                    prepareForNewWizardInvitePerson()
                } label: {
                    Label("Add New", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current person")
                            .font(.system(size: isIPhoneWizardLayout ? 18 : 22, weight: .semibold))
                        Text(hasDraftInviteIdentity ? "Choose stats for this person, then press Done to save and move to the next one." : "Pick a saved person or add someone new to begin.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if hasDraftInviteIdentity {
                        Button("Edit") {
                            showAddWizardInvitePersonSheet = true
                        }
                        .buttonStyle(.bordered)
                    }
                    if hasDraftInviteIdentity || !draftInviteSelectionRawValues.isEmpty {
                        Button("Clear") {
                            clearDraftInvite()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if hasDraftInviteIdentity {
                    currentDraftInviteCard
                } else {
                    ContentUnavailableView(
                        "No Person Selected",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("Use the picker above or tap Add New.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Allocated stats")
                            .font(.system(size: isIPhoneWizardLayout ? 18 : 22, weight: .semibold))
                        Text(draftInviteSelectionRawValues.isEmpty ? "Pick one or more stats for this person." : "\(draftInviteSelectionRawValues.count) selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        showWizardStatPicker = true
                    } label: {
                        Label(draftInviteSelectionRawValues.isEmpty ? "Choose Stats" : "Edit Stats", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(availableWizardInviteSelections.isEmpty || !canPrepareDraftInvite)
                }

                if !draftInviteSelectionRawValues.isEmpty {
                    wizardSelectionTagWrap(selections: draftInviteSelections)
                } else if availableWizardInviteSelections.isEmpty {
                    Text("All enabled stats have already been allocated.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    inviteEmptySelectionState
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(inviteGlassBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private var inviteAssignmentsOverviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Allocation Overview", systemImage: "square.grid.3x3.topleft.filled")
                .font(.headline.weight(.bold))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Still to assign")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(unassignedWizardSelectionCount)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(unassignedWizardSelectionCount == 0 ? .green : .orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }

                if unassignedWizardSelections.isEmpty {
                    Label("Everything enabled is allocated.", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    wizardSelectionTagWrap(selections: unassignedWizardSelections)
                }
            }

            Divider()

            if wizardInviteAssignments.isEmpty {
                ContentUnavailableView(
                    "No Stat Takers Added",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("Load a previous person or create a new one, then assign a few stats.")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Who is doing what")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(wizardInviteAssignments.count) people")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(wizardInviteAssignments) { assignment in
                        wizardInviteAssignmentCard(assignment)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(inviteGlassBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private var inviteEmptySelectionState: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("No stats selected yet")
                    .font(.subheadline.weight(.semibold))
                Text("Tap Choose Stats and allocate a couple of stats to this person.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var currentDraftInviteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(draftInviteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? draftInvitePhone : draftInviteName)
                .font(.system(size: isIPhoneWizardLayout ? 22 : 26, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            if !draftInvitePhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(draftInvitePhone.trimmingCharacters(in: .whitespacesAndNewlines), systemImage: "envelope")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !draftInviteMobile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(draftInviteMobile.formattedMobileNumber, systemImage: "phone")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var inviteGlassBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(0.12),
                Color.white.opacity(0.06),
                Color.black.opacity(0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var unassignedWizardSelections: [StatsInviteSelection] {
        enabledWizardInviteSelections.filter { !allocatedWizardSelectionRawValues.contains($0.rawValue) }
    }

    private func inviteSummaryPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.black))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func inviteTextField(
        _ title: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        capitalization: TextInputAutocapitalization = .sentences,
        disableAutocorrection: Bool = false
    ) -> some View {
        TextField(title, text: text)
            .keyboardType(keyboardType)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled(disableAutocorrection)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private func statsCollectionStepContent(
        title: String,
        pillTitle: String,
        pillStyle: ClubStyle.Style,
        options: Binding<[StatsCollectionOption]>
    ) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                StatsWizardCard(title: title, systemImage: "chart.bar", compactStyle: isIPhoneWizardLayout) {
                    HStack {
                        wizardTeamPill(pillTitle, style: pillStyle)
                        Spacer()
                    }

                    Text("Choose which stats to collect. For each enabled stat, select whether it is tracked at team level or allocated to an individual player.")
                        .font(wizardBodyFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    LazyVGrid(columns: statsSelectionColumns, spacing: 12) {
                        ForEach(options) { $option in
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle(isOn: $option.isEnabled) {
                                    Text(option.title)
                                        .font(wizardBodyFont)
                                }
                                .toggleStyle(.switch)

                                if option.isEnabled {
                                    HStack(spacing: 8) {
                                        ForEach(standardStatsCollectionModes) { mode in
                                            setupChoiceButton(
                                                title: mode.rawValue,
                                                isSelected: option.mode == mode
                                            ) {
                                                option.mode = mode
                                            }
                                        }
                                    }
                                    .padding(.leading, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .dynamicTypeSize(.large ... .accessibility2)
        .background(Color(.systemGroupedBackground))
    }

    private var enabledWizardInviteSelections: [StatsInviteSelection] {
        var selections: [StatsInviteSelection] = []

        for option in statOptions where option.isEnabled {
            selections.append(wizardInviteSelection(title: option.title, side: .ourClub))
        }
        for option in oppositionStatOptions where option.isEnabled {
            selections.append(wizardInviteSelection(title: option.title, side: .opposition))
        }
        for option in comparisonStatOptions where shouldIncludeComparisonOptionInInviteSelections(option) {
            selections.append(wizardInviteSelection(title: option.title, side: .ourClub))
        }
        for option in oppositionComparisonStatOptions where shouldIncludeComparisonOptionInInviteSelections(option) {
            selections.append(wizardInviteSelection(title: option.title, side: .opposition))
        }

        var seen = Set<String>()
        return selections.filter { seen.insert($0.id).inserted }
    }

    private var allocatedWizardSelectionRawValues: Set<String> {
        Set(wizardInviteAssignments.flatMap(\.selectionRawValues))
    }

    private var availableWizardInviteSelections: [StatsInviteSelection] {
        enabledWizardInviteSelections.filter { !allocatedWizardSelectionRawValues.contains($0.rawValue) || draftInviteSelectionRawValues.contains($0.rawValue) }
    }

    private var unassignedWizardSelectionCount: Int {
        enabledWizardInviteSelections.count - allocatedWizardSelectionRawValues.count
    }

    private var draftInviteSelections: [StatsInviteSelection] {
        enabledWizardInviteSelections.filter { draftInviteSelectionRawValues.contains($0.rawValue) }
    }

    private var savedWizardInviteContacts: [PhoneInviteContact] {
        var seenEmails: Set<String> = []
        var savedContacts: [PhoneInviteContact] = []

        for assignment in inviteAssignments {
            let email = normalizedInviteAddress(assignment.inviteeEmail)
            guard !email.isEmpty, seenEmails.insert(email).inserted else { continue }

            let existingContact = contacts.first { normalizedInviteAddress($0.email) == email }
            let trimmedName = assignment.inviteeName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = trimmedName.isEmpty
                ? (existingContact?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? existingContact?.name ?? email : email)
                : trimmedName
            let mobile = existingContact?.mobile.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            savedContacts.append(
                PhoneInviteContact(
                    email: email,
                    displayName: displayName,
                    mobileNumber: mobile
                )
            )
        }

        for contact in contacts {
            let email = normalizedInviteAddress(contact.email)
            guard !email.isEmpty, seenEmails.insert(email).inserted else { continue }
            let displayName = contact.name.trimmingCharacters(in: .whitespacesAndNewlines)
            savedContacts.append(
                PhoneInviteContact(
                    email: email,
                    displayName: displayName.isEmpty ? email : displayName,
                    mobileNumber: contact.mobile.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }

        return savedContacts.sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private var usesLiveGameScoreSyncForMatchEvents: Bool {
        let matchEventOptions = (comparisonStatOptions + oppositionComparisonStatOptions)
            .filter { option in
                option.isEnabled && ["goal", "behind"].contains(option.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            }
        guard !matchEventOptions.isEmpty else { return false }
        return matchEventOptions.allSatisfy { $0.matchEventDeliveryMode == .liveGame }
    }

    private func shouldIncludeComparisonOptionInInviteSelections(_ option: StatsCollectionOption) -> Bool {
        guard option.isEnabled else { return false }
        let normalizedTitle = option.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedTitle == "goal" || normalizedTitle == "behind" else { return true }
        return option.matchEventDeliveryMode == .invite
    }

    private var canAddDraftInvite: Bool {
        canPrepareDraftInvite &&
        !draftInviteSelectionRawValues.isEmpty
    }

    private var canPrepareDraftInvite: Bool {
        !draftInviteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !normalizedInviteAddress(draftInvitePhone).isEmpty &&
        !draftInviteMobile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasDraftInviteIdentity: Bool {
        !draftInviteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !normalizedInviteAddress(draftInvitePhone).isEmpty ||
        !draftInviteMobile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var wizardPreviewStatTypes: [StatType] {
        let enabledTitles = Array(Set(enabledWizardInviteSelections.map { wizardStatTitle(for: $0.statTypeID) })).sorted()
        return enabledTitles.enumerated().map { index, title in
            StatType(id: wizardStatTypeID(for: title), name: title, isEnabled: true, sortOrder: index)
        }
    }

    private var standardStatsCollectionModes: [StatsCollectionMode] {
        [.team, .individual]
    }

    private var matchEventDeliveryModes: [MatchEventDeliveryMode] {
        [.liveGame, .invite]
    }

    @ViewBuilder
    private func comparisonStatsColumn(
        pillTitle: String,
        pillStyle: ClubStyle.Style,
        options: Binding<[StatsCollectionOption]>
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                wizardTeamPill(pillTitle, style: pillStyle)
                Spacer()
            }

            ForEach(options) { $option in
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $option.isEnabled) {
                        Text(option.title)
                            .font(wizardBodyFont)
                    }
                    .toggleStyle(.switch)

                    if option.isEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                ForEach(standardStatsCollectionModes) { mode in
                                    setupChoiceButton(
                                        title: mode.rawValue,
                                        isSelected: option.mode == mode
                                    ) {
                                        option.mode = mode
                                    }
                                }
                            }

                            HStack(spacing: 8) {
                                ForEach(matchEventDeliveryModes) { mode in
                                    setupChoiceButton(
                                        title: mode.rawValue,
                                        isSelected: option.matchEventDeliveryMode == mode
                                    ) {
                                        option.matchEventDeliveryMode = mode
                                    }
                                }
                            }
                        }
                        .padding(.leading, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func wizardSelectionTagWrap(selections: [StatsInviteSelection]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
            ForEach(selections, id: \.id) { selection in
                Text(wizardSelectionDisplayName(selection))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
            }
        }
    }

    @ViewBuilder
    private func wizardInviteAssignmentCard(_ assignment: WizardInviteAssignment) -> some View {
        let selections = wizardSelections(for: assignment)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.95), Color.blue.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(String(assignment.contact.name.prefix(1)).uppercased())
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(assignment.contact.name)
                            .font(.headline.weight(.bold))
                            .lineLimit(1)
                        Text("\(selections.count) stats")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }

                    Text(assignment.contact.subtitle.isEmpty ? assignment.contact.phoneNumber : assignment.contact.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Menu {
                    Button("Preview") {
                        previewInviteAssignment = assignment
                    }
                    Button("Edit") {
                        editingWizardInviteAssignment = assignment
                    }
                    Button("Remove", role: .destructive) {
                        removeWizardInviteAssignment(assignment)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            wizardSelectionTagWrap(selections: selections)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var statsSelectionColumns: [GridItem] {
        isIPhoneWizardLayout
            ? [GridItem(.flexible(), spacing: 10, alignment: .top)]
            : [
                GridItem(.flexible(), spacing: 12, alignment: .top),
                GridItem(.flexible(), spacing: 12, alignment: .top)
            ]
    }

    private func wizardTeamPill(_ title: String, style: ClubStyle.Style) -> some View {
        Text(title)
            .font(.system(size: isIPhoneWizardLayout ? 22 : (isCompactLayout ? 30 : 40), weight: .black))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(style.text)
            .padding(.horizontal, isIPhoneWizardLayout ? 22 : (isCompactLayout ? 42 : 54))
            .padding(.vertical, isIPhoneWizardLayout ? 12 : (isCompactLayout ? 18 : 24))
            .background(
                Capsule(style: .continuous)
                    .fill(style.background)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(style.border.opacity(0.95), lineWidth: 2.5)
            )
            .accessibilityLabel(Text(title))
    }

    private func rowLabel(_ title: String) -> some View {
        Text(title)
            .font(wizardBodyFont)
    }

    private func wizardInviteSelection(title: String, side: StatsInviteTeamSide) -> StatsInviteSelection {
        StatsInviteSelection(statTypeID: wizardStatTypeID(for: title), side: side)
    }

    private var enabledWizardCollectionModesByStatTypeID: [UUID: SessionStatCollectionMode] {
        var modes: [UUID: SessionStatCollectionMode] = [:]
        let allOptions = statOptions + comparisonStatOptions + oppositionStatOptions + oppositionComparisonStatOptions
        for option in allOptions where option.isEnabled {
            let statTypeID = wizardStatTypeID(for: option.title)
            guard modes[statTypeID] == nil else { continue }
            modes[statTypeID] = option.mode == .team ? .team : .individual
        }
        return modes
    }

    private func wizardStatTypeID(for title: String) -> UUID {
        if let persisted = allStatTypes.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(title) == .orderedSame
        }) {
            return persisted.id
        }
        return legacyWizardStatTypeID(for: title)
    }

    private func statTitle(for selection: StatsInviteSelection) -> String {
        wizardStatTitle(for: selection.statTypeID)
    }

    private func wizardSelectionDisplayName(_ selection: StatsInviteSelection) -> String {
        let prefix = selection.side == .ourClub ? ourTeamName : oppositionTeamName
        return "\(prefix) • \(statTitle(for: selection))"
    }

    private func wizardStatTitle(for statTypeID: UUID) -> String {
        if let persisted = allStatTypes.first(where: { $0.id == statTypeID }) {
            return persisted.name
        }
        return legacyWizardStatTitle(for: statTypeID) ?? "Stat"
    }

    private func normalizedInviteAddress(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func toggleDraftInviteSelection(_ selection: StatsInviteSelection) {
        if draftInviteSelectionRawValues.contains(selection.rawValue) {
            draftInviteSelectionRawValues.remove(selection.rawValue)
        } else {
            draftInviteSelectionRawValues.insert(selection.rawValue)
        }
    }

    private func applySavedInviteContact(email: String) {
        guard !email.isEmpty,
              let contact = savedWizardInviteContacts.first(where: { $0.id == email })
        else {
            return
        }

        draftInviteName = contact.displayName
        draftInvitePhone = contact.email
        draftInviteMobile = contact.mobileNumber
    }

    private func prepareForNewWizardInvitePerson() {
        selectedSavedInviteEmail = ""
        draftInviteName = ""
        draftInvitePhone = ""
        draftInviteMobile = ""
        showAddWizardInvitePersonSheet = true
    }

    private func addWizardInviteAssignment() {
        guard canAddDraftInvite else { return }
        let email = draftInvitePhone.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let displayName = draftInviteName.trimmingCharacters(in: .whitespacesAndNewlines)
        let mobileNumber = draftInviteMobile.formattedMobileNumber

        let assignment = WizardInviteAssignment(
            id: UUID(),
            contact: PhoneInviteContact(
                email: email,
                displayName: displayName,
                mobileNumber: mobileNumber
            ),
            selectionRawValues: draftInviteSelectionRawValues.sorted()
        )
        wizardInviteAssignments.append(assignment)
        upsertSavedInviteContact(email: email, name: displayName, mobile: mobileNumber)
        clearDraftInvite()
    }

    private func finalizeDraftInviteFromStatPicker() {
        if canAddDraftInvite {
            addWizardInviteAssignment()
        }
        showWizardStatPicker = false
    }

    private func availableWizardInviteSelections(for assignment: WizardInviteAssignment) -> [StatsInviteSelection] {
        let reserved = Set(
            wizardInviteAssignments
                .filter { $0.id != assignment.id }
                .flatMap(\.selectionRawValues)
        )
        let current = Set(assignment.selectionRawValues)
        return enabledWizardInviteSelections.filter {
            !reserved.contains($0.rawValue) || current.contains($0.rawValue)
        }
    }

    private func clearDraftInvite() {
        draftInviteName = ""
        draftInvitePhone = ""
        draftInviteMobile = ""
        draftInviteSelectionRawValues = []
        selectedSavedInviteEmail = ""
    }

    private func upsertSavedInviteContact(email: String, name: String, mobile: String) {
        let normalizedEmail = normalizedInviteAddress(email)
        guard !normalizedEmail.isEmpty else { return }

        if let existing = contacts.first(where: { normalizedInviteAddress($0.email) == normalizedEmail }) {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedMobile = mobile.formattedMobileNumber
            if !trimmedName.isEmpty {
                existing.name = trimmedName
            }
            if !trimmedMobile.isEmpty {
                existing.mobile = trimmedMobile
            }
            existing.email = normalizedEmail
        } else {
            modelContext.insert(
                Contact(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    mobile: mobile.formattedMobileNumber,
                    email: normalizedEmail
                )
            )
        }

        try? modelContext.save()
    }

    private func removeWizardInviteAssignment(_ assignment: WizardInviteAssignment) {
        wizardInviteAssignments.removeAll { $0.id == assignment.id }
        if previewInviteAssignment?.id == assignment.id {
            previewInviteAssignment = nil
        }
        if editingWizardInviteAssignment?.id == assignment.id {
            editingWizardInviteAssignment = nil
        }
    }

    private func updateWizardInviteAssignment(_ updated: WizardInviteAssignment) {
        guard let index = wizardInviteAssignments.firstIndex(where: { $0.id == updated.id }) else { return }
        wizardInviteAssignments[index] = updated
        upsertSavedInviteContact(
            email: updated.contact.email,
            name: updated.contact.displayName,
            mobile: updated.contact.mobileNumber
        )
        editingWizardInviteAssignment = nil
    }

    private func performPrimaryAction() {
        if step == .inviteUsers {
            startWizardSession()
        } else {
            next()
        }
    }

    private func startWizardSession() {
        guard !isStartingSession else { return }
        guard let selectedGradeId else { return }
        guard !hasDuplicateSession(for: selectedGradeId) else {
            duplicateSessionWarning = true
            return
        }
        isStartingSession = true
        let enabledStatTypeIDs = Array(Set(enabledWizardInviteSelections.map(\.statTypeID))).sorted {
            wizardStatTitle(for: $0) < wizardStatTitle(for: $1)
        }
        UserDefaults.standard.set("Simple", forKey: "statsLayout")

        let session = StatsSession(
            gradeId: selectedGradeId,
            opposition: opposition.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date,
            venue: venue.trimmingCharacters(in: .whitespacesAndNewlines),
            enabledStatTypeIDsRaw: enabledStatTypeIDs.map(\.uuidString).joined(separator: ","),
            statCollectionModesRaw: enabledStatTypeIDs
                .compactMap { id in
                    guard let mode = enabledWizardCollectionModesByStatTypeID[id] else { return nil }
                    return "\(id.uuidString):\(mode.rawValue)"
                }
                .joined(separator: ","),
            usesLiveGameScoreSync: usesLiveGameScoreSyncForMatchEvents
        )
        modelContext.insert(session)
        try? modelContext.save()
        navigationState.activateStatsSession(id: session.sessionId)
        startedSession = session

        Task {
            let items = await persistWizardInviteAssignmentsAndBuildDispatchItems(session: session)
            await MainActor.run {
                isStartingSession = false
                inviteDispatchItems = items
                if inviteDispatchItems.isEmpty {
                    showLiveStats = true
                } else {
                    showInviteDispatchSheet = true
                }
            }
        }
    }

    private func hasDuplicateSession(for gradeID: UUID) -> Bool {
        let normalizedVenue = normalizedSessionField(venue)
        return existingSessions.contains { session in
            session.gradeId == gradeID
                && Calendar.current.isDate(session.date, inSameDayAs: date)
                && normalizedSessionField(session.venue) == normalizedVenue
        }
    }

    private func normalizedSessionField(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private var selectedGradePlayers: [Player] {
        guard let selectedGradeId else { return [] }
        return wizardPlayers.filter { $0.isActive && $0.gradeIDs.contains(selectedGradeId) }
    }

    private func persistWizardInviteAssignmentsAndBuildDispatchItems(session: StatsSession) async -> [WizardInviteDispatchItem] {
        let sessionLine = "\(selectedGradeName) vs \(session.opposition) • \(session.date.formatted(date: .abbreviated, time: .omitted))"
        let statTypes = wizardPreviewStatTypes
        let rosterPlayers = cloudRosterPlayers(from: selectedGradePlayers)
        let availablePlayerPayloadJSON = encodeRosterPlayers(rosterPlayers)

        do {
            _ = try await CloudKitStatsInviteService.shared.saveSessionRoster(
                sessionID: session.sessionId,
                players: rosterPlayers
            )
        } catch {
        }

        var items: [WizardInviteDispatchItem] = []

        for assignment in wizardInviteAssignments {
            let selections = wizardSelections(for: assignment)
            guard !selections.isEmpty else { continue }
            let selectionDisplayNamesByRawValue = statsInviteSelectionDisplayNamesByRawValue(
                for: selections,
                statTypes: statTypes
            )
            let selectionCollectionModesByRawValue = statsInviteSelectionCollectionModesByRawValue(
                for: selections,
                session: session,
                statTypes: statTypes
            )

            let recordName = CloudKitStatsInviteService.recordName(
                sessionID: session.sessionId,
                inviteeEmail: assignment.contact.email
            )

            do {
                _ = try await CloudKitUserAccessService.shared.inviteUser(
                    email: assignment.contact.email,
                    role: .statTaker
                )
                let cloudAssignment = try await CloudKitStatsInviteService.shared.saveAssignment(
                    inviteeEmail: assignment.contact.email,
                    inviteeName: assignment.contact.displayName,
                    sessionID: session.sessionId,
                    gradeName: selectedGradeName,
                    oppositionName: session.opposition,
                    venue: session.venue,
                    sessionDate: session.date,
                    assignedSelectionRawValues: selections.map(\.rawValue),
                    assignedSelectionDisplayNames: selections.map { selectionDisplayNamesByRawValue[$0.rawValue] ?? $0.side.selectionPrefix },
                    assignedSelectionCollectionModes: selections.map {
                        selectionCollectionModesByRawValue[$0.rawValue] ?? SessionStatCollectionMode.team.rawValue
                    },
                    availablePlayerPayloadJSON: availablePlayerPayloadJSON
                )

                if let existing = inviteAssignments.first(where: { $0.cloudRecordName == recordName }) {
                    existing.inviteeEmail = assignment.contact.email
                    existing.inviteeName = assignment.contact.displayName
                    existing.cloudRecordName = cloudAssignment.id
                    existing.sessionIDRaw = session.sessionId.uuidString
                    existing.sessionSummary = sessionLine
                    existing.lastInvitedAt = cloudAssignment.lastInvitedAt
                    existing.isConnected = cloudAssignment.hasConnected
                    existing.lastConnectedAt = cloudAssignment.lastConnectedAt
                    existing.setAssignedSelections(selections)
                } else {
                    let persisted = StatsInviteAssignment(
                        contactId: UUID(),
                        assignedStatTypeIDsRaw: selections.map(\.rawValue).joined(separator: ","),
                        inviteLinkToken: "",
                        inviteLinkURL: "",
                        inviteeEmail: assignment.contact.email,
                        inviteeName: assignment.contact.displayName,
                        cloudRecordName: cloudAssignment.id,
                        sessionIDRaw: session.sessionId.uuidString,
                        sessionSummary: sessionLine,
                        lastInvitedAt: cloudAssignment.lastInvitedAt,
                        isConnected: cloudAssignment.hasConnected,
                        lastConnectedAt: cloudAssignment.lastConnectedAt
                    )
                    modelContext.insert(persisted)
                }

                let assignedNames = statsInviteSelectionNames(
                    for: selections.sorted {
                        if $0.side != $1.side {
                            return $0.side == .ourClub
                        }
                        return wizardStatTitle(for: $0.statTypeID) < wizardStatTitle(for: $1.statTypeID)
                    },
                    statTypes: statTypes
                ).joined(separator: ", ")

                items.append(
                    WizardInviteDispatchItem(
                        id: assignment.id,
                        contact: assignment.contact,
                        selections: selections,
                        shareText: statsInviteShareText(
                            recipient: assignment.contact,
                            sessionID: session.sessionId,
                            recordName: cloudAssignment.id,
                            sessionLine: sessionLine,
                            assignedNames: assignedNames
                        )
                    )
                )
            } catch {
                await MainActor.run {
                    startedSession = session
                }
            }
        }

        try? modelContext.save()
        return items
    }

    private func statsInviteShareText(
        recipient: StatsInviteRecipient,
        sessionID: UUID,
        recordName: String,
        sessionLine: String,
        assignedNames: String
    ) -> String {
        buildStatsInviteMessage(
            recipient: recipient,
            sessionID: sessionID,
            recordName: recordName,
            sessionLine: sessionLine,
            assignedNames: assignedNames,
            testFlightURL: testFlightURL
        )
    }

    @MainActor
    private func wizardSelections(for assignment: WizardInviteAssignment) -> [StatsInviteSelection] {
        assignment.selectionRawValues.compactMap(StatsInviteSelection.init(rawValue:))
    }

    @ViewBuilder
    private func setupMenuButton<Content: View>(
        title: String,
        isDisabled: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(wizardBodyFont)
                    .foregroundStyle(title == "Select…" ? .secondary : .primary)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: isCompactLayout ? 13 : 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, isCompactLayout ? 14 : 18)
            .padding(.vertical, isCompactLayout ? 10 : 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func setupChoiceButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(isIPhoneWizardLayout ? .system(size: 14, weight: .medium) : wizardBodyFont)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, isIPhoneWizardLayout ? 10 : (isCompactLayout ? 12 : 14))
                .padding(.vertical, isIPhoneWizardLayout ? 7 : (isCompactLayout ? 8 : 10))
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private func back() {
        switch step {
        case .details:
            break
        case .statCollection:
            step = .details
        case .oppositionStatCollection:
            step = .statCollection
        case .comparisonStats:
            step = .oppositionStatCollection
        case .inviteUsers:
            step = .comparisonStats
        }
    }

    private func next() {
        switch step {
        case .details:
            step = .statCollection
        case .statCollection:
            step = .oppositionStatCollection
        case .oppositionStatCollection:
            step = .comparisonStats
        case .comparisonStats:
            step = .inviteUsers
        case .inviteUsers:
            break
        }
    }
}

private struct StatsWizardCard<Content: View>: View {
    let title: String
    let systemImage: String
    let compactStyle: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: compactStyle ? 10 : 12) {
            HStack(spacing: compactStyle ? 8 : 10) {
                Image(systemName: systemImage)
                    .font(.system(size: compactStyle ? 15 : 18, weight: .semibold))
                Text(title.uppercased())
                    .font(.system(size: compactStyle ? 12 : 14, weight: .bold))
                    .tracking(0.9)
                Spacer()
            }
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: compactStyle ? 12 : 16) {
                content
            }
            .padding(compactStyle ? 12 : 16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: compactStyle ? 14 : 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: compactStyle ? 14 : 18, style: .continuous)
                    .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
            )
        }
    }
}

private struct WizardInvitePersonSheet: View {
    @Binding var name: String
    @Binding var email: String
    @Binding var mobile: String

    @Environment(\.dismiss) private var dismiss

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !mobile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("Person") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)

                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Mobile", text: $mobile)
                    .keyboardType(.phonePad)
            }
        }
        .navigationTitle("Add New")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    mobile = mobile.formattedMobileNumber
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }
}

private struct WizardInviteEditorSheet: View {
    let assignment: StatsSessionSetupView.WizardInviteAssignment
    let availableSelections: [StatsInviteSelection]
    let teamNameForSelection: (StatsInviteSelection) -> String
    let selectionDisplayName: (StatsInviteSelection) -> String
    let previewSelections: (StatsSessionSetupView.WizardInviteAssignment) -> [StatsInviteSelection]
    let previewStatTypes: [StatType]
    let clubConfiguration: ClubConfiguration
    let clubName: String
    let gradeTitle: String
    let oppositionName: String
    let onSave: (StatsSessionSetupView.WizardInviteAssignment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var phone: String
    @State private var mobile: String
    @State private var selectionRawValues: Set<String>
    @State private var showContactPicker = false
    @State private var showStatPicker = false
    @State private var showPreview = false

    init(
        assignment: StatsSessionSetupView.WizardInviteAssignment,
        availableSelections: [StatsInviteSelection],
        teamNameForSelection: @escaping (StatsInviteSelection) -> String,
        selectionDisplayName: @escaping (StatsInviteSelection) -> String,
        previewSelections: @escaping (StatsSessionSetupView.WizardInviteAssignment) -> [StatsInviteSelection],
        previewStatTypes: [StatType],
        clubConfiguration: ClubConfiguration,
        clubName: String,
        gradeTitle: String,
        oppositionName: String,
        onSave: @escaping (StatsSessionSetupView.WizardInviteAssignment) -> Void
    ) {
        self.assignment = assignment
        self.availableSelections = availableSelections
        self.teamNameForSelection = teamNameForSelection
        self.selectionDisplayName = selectionDisplayName
        self.previewSelections = previewSelections
        self.previewStatTypes = previewStatTypes
        self.clubConfiguration = clubConfiguration
        self.clubName = clubName
        self.gradeTitle = gradeTitle
        self.oppositionName = oppositionName
        self.onSave = onSave
        _name = State(initialValue: assignment.contact.name)
        _phone = State(initialValue: assignment.contact.email)
        _mobile = State(initialValue: assignment.contact.mobileNumber)
        _selectionRawValues = State(initialValue: Set(assignment.selectionRawValues))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Text("Edit the stat taker's name, invited email and SMS number.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button("Preview") {
                            showPreview = true
                        }
                        .buttonStyle(.bordered)
                    }

                    TextField("Stat taker name", text: $name)
                        .textInputAutocapitalization(.words)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )

                    TextField("Invited email", text: $phone)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                        )

                    TextField("Mobile for SMS", text: $mobile)
                        .keyboardType(.phonePad)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )

                    Button {
                        showStatPicker = true
                    } label: {
                        HStack {
                            Text(selectionRawValues.isEmpty ? "Choose stats" : "Chosen stats: \(selectionRawValues.count)")
                                .foregroundStyle(selectionRawValues.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                    .buttonStyle(.plain)

                    if currentSelections.isEmpty {
                        Text("No stats selected.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
                            ForEach(currentSelections, id: \.id) { selection in
                                Text(selectionDisplayName(selection))
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color(.secondarySystemBackground))
                                    )
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Edit Stat Taker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let updated = StatsSessionSetupView.WizardInviteAssignment(
                            id: assignment.id,
                            contact: PhoneInviteContact(
                                email: phone.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                                displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                mobileNumber: mobile.trimmingCharacters(in: .whitespacesAndNewlines)
                            ),
                            selectionRawValues: selectionRawValues.sorted()
                        )
                        onSave(updated)
                    }
                    .disabled(!canSave)
                }
            }
        }
        .sheet(isPresented: $showStatPicker) {
            NavigationStack {
                List {
                    if availableSelections.isEmpty {
                        Text("No stats available.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableSelections, id: \.id) { selection in
                            Button {
                                toggleSelection(selection)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(selectionDisplayName(selection))
                                            .foregroundStyle(.primary)
                                        Text(teamNameForSelection(selection))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectionRawValues.contains(selection.rawValue) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .navigationTitle("Choose Stats")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showStatPicker = false
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showPreview) {
            NavigationStack {
                StatsInviteLivePreviewView(
                    clubConfiguration: clubConfiguration,
                    clubName: clubName,
                    gradeTitle: gradeTitle,
                    oppositionName: oppositionName,
                    selections: previewSelections(previewAssignment),
                    statTypes: previewStatTypes
                )
            }
        }
    }

    private var currentSelections: [StatsInviteSelection] {
        availableSelections.filter { selectionRawValues.contains($0.rawValue) }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !mobile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectionRawValues.isEmpty
    }

    private var previewAssignment: StatsSessionSetupView.WizardInviteAssignment {
        StatsSessionSetupView.WizardInviteAssignment(
            id: assignment.id,
            contact: PhoneInviteContact(
                email: phone.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
                mobileNumber: mobile.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            selectionRawValues: selectionRawValues.sorted()
        )
    }

    private func toggleSelection(_ selection: StatsInviteSelection) {
        if selectionRawValues.contains(selection.rawValue) {
            selectionRawValues.remove(selection.rawValue)
        } else {
            selectionRawValues.insert(selection.rawValue)
        }
    }
}

private struct WizardInviteDispatchSheet: View {
    let items: [StatsSessionSetupView.WizardInviteDispatchItem]
    let clubConfiguration: ClubConfiguration
    let clubName: String
    let gradeTitle: String
    let oppositionName: String
    let statTypes: [StatType]
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sentIDs: Set<UUID> = []
    @State private var messageDraft: StatsInviteMessageDraft?
    @State private var shareDraft: ShareDraft?

    var body: some View {
        NavigationStack {
            List {
                Section("Send Invites") {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.contact.name)
                                        .font(.headline)
                                    Text(item.contact.subtitle.isEmpty ? item.contact.phoneNumber : item.contact.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if sentIDs.contains(item.id) {
                                    Label("Sent", systemImage: "checkmark.circle.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.green)
                                } else {
                                    Button(item.contact.canSendTextInvite ? "Text" : "Share") {
                                        if item.contact.canSendTextInvite, MFMessageComposeViewController.canSendText() {
                                            messageDraft = StatsInviteMessageDraft(
                                                recipients: [item.contact.phoneNumber],
                                                body: item.shareText
                                            )
                                        } else {
                                            shareDraft = ShareDraft(text: item.shareText)
                                        }
                                        sentIDs.insert(item.id)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }

                            Text(statsInviteSelectionNames(for: item.selections, statTypes: statTypes).joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(item.contact.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Send Invites")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $messageDraft) { draft in
                StatsInviteMessageComposer(draft: draft)
            }
            .sheet(item: $shareDraft) { draft in
                ShareSheet(items: [draft.text])
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(sentIDs.count == items.count ? "Open Stats" : "Skip") {
                        dismiss()
                        onFinished()
                    }
                }
            }
        }
    }
}

private struct TotalsRow: Identifiable {
    let id = UUID()
    let player: Player
    let countsByStatId: [UUID: Int]
    let events: [StatEvent]
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

@MainActor
struct LiveStatsView: View {
    private enum StatsLayoutOption: String {
        case edge = "Edge"
        case simple = "Simple"
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var navigationState: AppNavigationState
    @AppStorage("trackDisposalEfficiency") private var trackDisposalEfficiency = true
    @AppStorage("trackContestedPossessions") private var trackContestedPossessions = true
    @AppStorage("trackIndividualTracking") private var trackIndividualTracking = true
    @AppStorage("oppTrackPossessions") private var oppositionTrackPossessions = true
    @AppStorage("oppTrackDisposalEfficiency") private var oppositionTrackDisposalEfficiency = true
    @AppStorage("oppTrackContestedPossessions") private var oppositionTrackContestedPossessions = true
    @AppStorage("statsLayout") private var statsLayout = StatsLayoutOption.simple.rawValue

    let session: StatsSession
    let onSessionSaved: (() -> Void)?

    @Query(sort: \Grade.displayOrder) private var grades: [Grade]
    @Query(sort: \Player.name) private var allPlayers: [Player]
    @Query(sort: \StatType.sortOrder) private var allStatTypes: [StatType]
    @Query(sort: \StatEvent.timestamp, order: .reverse) private var allEvents: [StatEvent]
    @Query(sort: \Contact.name) private var contacts: [Contact]
    @Query(sort: \StatsInviteAssignment.lastInvitedAt, order: .reverse) private var inviteAssignments: [StatsInviteAssignment]

    @State private var selectedQuarter = "Q1"
    @State private var selectedPlayerId: UUID?
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
    @State private var quarterTimerAnchorUptime: TimeInterval?
    @State private var quarterTimerAnchorSeconds: Int?
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
    @State private var showStatsSettings = false
    @State private var showStatTakers = false
    @State private var showStatDisplayOrderEditor = false
    @State private var showSyncStatusPopover = false
    @State private var selectedStatTakerAssignmentID: UUID?
    @State private var editingStatTakerAssignment: StatsInviteAssignment?
    @State private var composedShareText: String?
    @State private var selectedInviteContact: PhoneInviteContact?
    @State private var selectedInviteSelections: Set<StatsInviteSelection> = []
    @State private var showQuarterChangeReminder = false
    @State private var showQuarterPickerDialog = false
    @State private var showTimerModeEditor = false
    @State private var showLiveGameSyncPrompt = false
    @State private var promptedForLiveGameSyncSessionID: UUID?
    @State private var customQuarterMinutes = 20
    @State private var activeEfficiencyButtonKey: String?
    @State private var activeEfficiencyHoverVote: EfficiencyVote?
    @State private var activeContestedHoverVote: ContestedPossessionVote?
    @State private var suppressTapForButtonKey: String?
    @State private var activePlayerQuickStatsPlayerID: UUID?
    @State private var activePlayerQuickCardFrameGlobal: CGRect = .zero
    @State private var playerCardFramesGlobal: [UUID: CGRect] = [:]
    @State private var interfaceScreenWidth: CGFloat = 1024
    @State private var interfaceScreenHeight: CGFloat = 768
    @State private var hoveredPlayerQuickStatName: String?
    @State private var hoveredPlayerQuickEfficiencyVote: EfficiencyVote?
    @State private var hoveredPlayerQuickContestedVote: ContestedPossessionVote?
    @State private var lastHapticQuickStatName: String?
    @State private var lastHapticQuickContestedVote: ContestedPossessionVote?
    @State private var lastHapticQuickEfficiencyVote: EfficiencyVote?
    @State private var remoteInviteTallies: [CloudStatsInviteTally] = []
    @State private var remoteInviteCountsByTallyID: [String: Int] = [:]
    @State private var cloudInviteAssignmentsByRecordName: [String: CloudStatsInviteAssignment] = [:]
    @State private var lastRemoteInviteTallyUpdateAt: Date?
    @State private var lastRemoteInvitePlayerEventUpdateAt: Date?
    @State private var lastPublishedInviteSnapshotToken: String?
    @State private var liveStatsInviteSyncError: String?
    @State private var quarterCountsUp = false
    @State private var activeSideSpeakPresses = 0
    @StateObject private var speechService = PressHoldSpeechService()
    private let statTakerConnectionTimeout: TimeInterval = 45
    private let parser = StatsVoiceParser()
    private let ourTeamStatPlayerID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA") ?? UUID()
    private let oppositionTeamStatPlayerID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB") ?? UUID()
    private let longPressHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let stepHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let playerQuickStatsLongPressDuration: Double = 0.45
    private let remoteInvitePollIntervalNanoseconds: UInt64 = 250_000_000
    private let liveStatsInvitePublishIntervalNanoseconds: UInt64 = 250_000_000
    
    private var isSessionActive: Bool {
        navigationState.activeStatsSessionID == session.sessionId && !session.isSaved
    }

    private var isReadOnlyMode: Bool {
        !navigationState.currentRole.canModifyStatsSessions
    }

    private var liveStatsSessionDescriptor: LiveStatsSyncSessionDescriptor {
        LiveStatsSyncSessionDescriptor(
            sessionID: session.sessionId,
            gradeID: session.gradeId,
            opposition: session.opposition,
            date: session.date
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let _: CGFloat = 8
            let availableWidth = max(proxy.size.width - 24, 640)
            let leftWidthRatio: CGFloat = oppositionTrackPossessions ? 0.72 : 0.62
            let leftPanelWidth = min(max(availableWidth * leftWidthRatio, 420), availableWidth - 300)
            let rightPanelWidth = max(availableWidth - leftPanelWidth - 12, 290)
            Group {
                if isEdgeLayoutActive {
                    edgeLayoutContent(proxy: proxy)
                } else if isSimpleLayoutActive {
                    simpleLayoutContent
                } else {
                    VStack(spacing: 12) {
                        headerBannerArea
                            .frame(height: headerBannerHeight)
                        combinedScoreAndActionsPanel
                            .frame(height: topPanelHeight)

                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 10) {
                                playerSelectionPanel
                            }
                            .frame(width: leftPanelWidth)

                            VStack(spacing: 12) {
                                if !oppositionTrackPossessions {
                                    statButtonsPanel
                                        .frame(height: rightStatActionsHeight)
                                }
                                recentEventsPanel
                                liveLeadersPanel
                                    .frame(height: 340)
                            }
                            .frame(width: rightPanelWidth)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
            }
            .allowsHitTesting(!isReadOnlyMode)
            .task(id: proxy.size.width) {
                interfaceScreenWidth = max(proxy.size.width, 1)
            }
            .task(id: proxy.size.height) {
                interfaceScreenHeight = max(proxy.size.height, 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    returnToStatsList()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                statsSyncStatusButton
            }
            if !isReadOnlyMode {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSessionActive ? "Save" : "Resume") {
                        if isSessionActive {
                            saveSession()
                        } else {
                            resumeSession()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if !isReadOnlyMode {
                        Button("Settings") {
                            showStatsSettings = true
                        }
                        Button("Stat Takers") {
                            showStatTakers = true
                        }
                        Button("Display Order") {
                            showStatDisplayOrderEditor = true
                        }
                    }
                    Button("Generate Report") {
                        generateReport()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .onAppear {
            navigationState.setActiveLiveStatsSession(liveStatsSessionDescriptor)
            navigationState.updateLiveStatsInviteSnapshot(liveStatsInviteSnapshot)
            if !session.isSaved && !isReadOnlyMode {
                navigationState.activateStatsSession(id: session.sessionId)
            }
            maybePromptToSyncWithLiveGame()
            applySyncedLiveGameStateIfNeeded()
        }
        .task(id: session.sessionId) {
            await monitorInviteConnectionStatuses()
        }
        .task(id: remoteInviteTalliesTaskID) {
            await monitorRemoteInviteTallies()
        }
        .onReceive(NotificationCenter.default.publisher(for: .statsTalliesDidChange)) { notification in
            if let tally = CloudKitStatsInviteService.tally(from: notification),
               tally.sessionID == session.sessionId {
                applyRemoteInviteTallyUpdate(tally)
            } else {
                Task {
                    await refreshRemoteInviteTallies(forceFullRefresh: false)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .statsPlayerEventsDidChange)) { notification in
            if let event = CloudKitStatsInviteService.playerEvent(from: notification),
               event.sessionID == session.sessionId {
                reconcileRemoteInvitePlayerEvents([event], removingMissing: false)
                lastRemoteInvitePlayerEventUpdateAt = max(
                    lastRemoteInvitePlayerEventUpdateAt ?? .distantPast,
                    event.updatedAt
                )
            } else {
                Task {
                    await syncRemoteInvitePlayerEvents(forceFullRefresh: true)
                }
            }
        }
        .sheet(item: $showEditEvent) { event in
            EditStatEventView(event: event, players: playersForGrade, statTypes: enabledStatTypes)
        }
        .fullScreenCover(isPresented: $showTotals) {
            StatsTotalsView(
                rows: totalsRows,
                statTypes: enabledStatTypes,
                sessionEvents: sessionEvents,
                remoteInviteTallies: remoteInviteTallies,
                ourTeamName: ourTeamName,
                oppositionName: session.opposition,
                ourStyle: ourStyle,
                oppositionStyle: oppositionStyle,
                ourScoreSummary: ourScoreSummary,
                oppositionScoreSummary: oppositionScoreSummary
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
        .sheet(isPresented: Binding(get: { composedShareText != nil }, set: { if !$0 { composedShareText = nil } })) {
            if let composedShareText {
                ShareSheet(items: [composedShareText])
            }
        }
        .fullScreenCover(isPresented: $showStatsSettings) {
            LiveStatsSessionSettingsView(session: session)
        }
        .fullScreenCover(isPresented: $showStatTakers) {
            StatsStatTakersView(
                contacts: contacts,
                inviteAssignments: inviteAssignments,
                statTypes: enabledStatTypes,
                activeSession: session,
                activeSessionGradeName: gradeName,
                selectedContact: $selectedInviteContact,
                selectedSelections: $selectedInviteSelections,
                onSendInvite: sendInvite,
                onSaveAssignments: { assignment, selections in
                    updateInviteAssignment(assignment, selections: selections)
                },
                onReinviteAssignment: { assignment in
                    assignment.lastInvitedAt = Date()
                    try? modelContext.save()
                }
            )
        }
        .sheet(item: $editingStatTakerAssignment) { assignment in
            StatsInviteManagementSheet(
                assignment: assignment,
                allStatTypes: enabledStatTypes,
                onSave: { selections in
                    updateInviteAssignment(assignment, selections: selections)
                },
                onReinvite: {
                    assignment.lastInvitedAt = Date()
                    try? modelContext.save()
                }
            )
        }
        .sheet(isPresented: $showStatDisplayOrderEditor) {
            StatDisplayOrderEditorView(
                statTypes: orderedStatTypesForDisplayOrder(for: session, allStatTypes: allStatTypes),
                enabledStatTypeIDs: Set(enabledStatTypes.map(\.id)),
                onSave: { reorderedIDs in
                    session.setDisplayOrderStatTypeIDs(reorderedIDs)
                    try? modelContext.save()
                }
            )
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
                    ensureSimpleLayoutSelection()
                }
            )
        }
        .overlay {
            if showEfficiencyVotePrompt {
                efficiencyRatingPrompt
            }
        }
        .overlay(alignment: .topTrailing) {
            if isReadOnlyMode {
                Text("View Only")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .padding(.trailing, 12)
            }
        }
        .overlay(alignment: .top) {
            EmptyView()
        }
        .overlay {
            if shouldShowSideSpeakMicOverlay && !isReadOnlyMode {
                sideSpeakMicOverlay
            }
        }
        .alert("Change quarter?", isPresented: $showQuarterChangeReminder) {
            Button("No", role: .cancel) { }
            Button("Yes") {
                advanceQuarter()
            }
        } message: {
            Text("Current: \(selectedQuarter). Move to the next quarter now?")
        }
        .alert("Sync Live Game View with Live Stats View?", isPresented: $showLiveGameSyncPrompt) {
            Button("Not now", role: .cancel) {}
            Button("Sync") {
                acceptLiveGameSync()
            }
        } message: {
            Text("Use Live Game View as the source of truth for score, timer and quarter in this Live Stats session.")
        }
        .onDisappear {
            statusBannerTask?.cancel()
            stopQuarterTimer()
            activeSideSpeakPresses = 0
            navigationState.clearActiveLiveStatsSession(id: session.sessionId)
            navigationState.updateLiveStatsInviteSnapshot(nil)
            if speechService.isRecording {
                speechService.stopListening()
            }
        }
        .onAppear {
            ensureRequiredTeamComparisonStatTypesIfNeeded()
            if visiblePlayerIDs.isEmpty {
                let defaults = Set(playersForGrade.map(\.id))
                visiblePlayerIDs = defaults
                savedVisiblePlayerIDs = defaults
            }
            playerGridOrder = savedPlayerGridOrder
            showAllPlayers = false
            customQuarterMinutes = max(1, configuredQuarterLengthSeconds / 60)
            configureQuarterTimer(reset: true)
            ensureSimpleLayoutSelection()
            maybePromptToSyncWithLiveGame()
            applySyncedLiveGameStateIfNeeded()
            reconcileSyncedLiveGameGoalKickersIfNeeded()
        }
        .onChange(of: navigationState.activeLiveGameSnapshot) { _, _ in
            maybePromptToSyncWithLiveGame()
            applySyncedLiveGameStateIfNeeded()
            reconcileSyncedLiveGameGoalKickersIfNeeded()
        }
        .onChange(of: navigationState.selectedTab) { _, newTab in
            guard newTab == .stats else { return }
            maybePromptToSyncWithLiveGame()
            applySyncedLiveGameStateIfNeeded()
            reconcileSyncedLiveGameGoalKickersIfNeeded()
        }
        .task(id: liveGameTimerRefreshToken) {
            guard syncedLiveGameSnapshot?.isTimerRunning == true else { return }
            while !Task.isCancelled && syncedLiveGameSnapshot?.isTimerRunning == true {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                applySyncedLiveGameStateIfNeeded()
            }
        }
        .task(id: session.sessionId) {
            await monitorLiveStatsInviteSnapshotPublishing()
        }
        .onChange(of: selectedQuarter) { _, _ in
            guard !isLiveGameControllingMatchState else { return }
            configureQuarterTimer(reset: true)
        }
        .onChange(of: statsLayout) { _, _ in
            ensureSimpleLayoutSelection()
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

    private func saveSession() {
        guard !isReadOnlyMode else { return }
        session.isSaved = true
        session.savedAt = Date()
        if navigationState.activeStatsSessionID == session.sessionId {
            navigationState.clearActiveStatsSession()
        }
        try? modelContext.save()
        onSessionSaved?()
        dismiss()
    }

    private func returnToStatsList() {
        dismiss()
    }

    private func resumeSession() {
        guard !isReadOnlyMode else { return }
        session.isSaved = false
        session.savedAt = nil
        navigationState.activateStatsSession(id: session.sessionId)
        try? modelContext.save()
        showStatusBanner(text: "STATS SESSION RESUMED", isSuccess: true)
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
        orderedEnabledStatTypes(for: session, allStatTypes: allStatTypes)
    }

    private func hasEnabledStat(aliases: [String]) -> Bool {
        let normalizedAliases = Set(aliases.map(normalizedStatName))
        return enabledStatTypes.contains { normalizedAliases.contains(normalizedStatName($0.name)) }
    }

    private func statCollectionMode(for statType: StatType) -> SessionStatCollectionMode {
        if let mode = session.statCollectionModes[statType.id] {
            return mode
        }
        return defaultSessionStatCollectionMode(for: statType.name)
    }

    private func isTeamCollectionStat(_ statType: StatType) -> Bool {
        statCollectionMode(for: statType) == .team
    }

    private var disposalEfficiencyStatType: StatType? {
        statTypeMatching(aliases: ["disposal efficiency"])
    }

    private var contestedPossessionStatType: StatType? {
        statTypeMatching(aliases: ["contested possession"])
    }

    private var isTeamModeDisposalEfficiency: Bool {
        guard let disposalEfficiencyStatType else { return false }
        return statCollectionMode(for: disposalEfficiencyStatType) == .team
    }

    private var isTeamModeContestedPossession: Bool {
        guard let contestedPossessionStatType else { return false }
        return statCollectionMode(for: contestedPossessionStatType) == .team
    }

    private var sessionTracksGoalStats: Bool {
        hasEnabledStat(aliases: ["goal", "scores"])
    }

    private var sessionTracksDisposalEfficiency: Bool {
        trackDisposalEfficiency && hasEnabledStat(aliases: ["disposal efficiency"])
    }

    private var sessionTracksContestedPossessions: Bool {
        trackContestedPossessions && hasEnabledStat(aliases: ["contested possession"])
    }

    private func sessionTracksDisposalEfficiency(isOpposition: Bool) -> Bool {
        let trackingEnabled = isOpposition ? oppositionTrackDisposalEfficiency : trackDisposalEfficiency
        return trackingEnabled && hasEnabledStat(aliases: ["disposal efficiency"])
    }

    private func sessionTracksContestedPossessions(isOpposition: Bool) -> Bool {
        let trackingEnabled = isOpposition ? oppositionTrackContestedPossessions : trackContestedPossessions
        return trackingEnabled && hasEnabledStat(aliases: ["contested possession"])
    }

    private func sessionTracksDisposalEfficiencyVotes(isOpposition: Bool = false) -> Bool {
        let trackingEnabled = isOpposition ? oppositionTrackDisposalEfficiency : trackDisposalEfficiency
        return trackingEnabled && hasEnabledStat(aliases: ["disposal efficiency"]) && !isTeamModeDisposalEfficiency
    }

    private func sessionTracksContestedPossessionVotes(isOpposition: Bool = false) -> Bool {
        let trackingEnabled = isOpposition ? oppositionTrackContestedPossessions : trackContestedPossessions
        return trackingEnabled && hasEnabledStat(aliases: ["contested possession"]) && !isTeamModeContestedPossession
    }

    private var connectedInviteAssignments: [StatsInviteAssignment] {
        inviteAssignments.filter(isCurrentlyConnected)
    }

    private var sessionInviteAssignments: [StatsInviteAssignment] {
        inviteAssignments
            .filter { $0.sessionIDRaw == session.sessionId.uuidString }
            .sorted { lhs, rhs in
                let leftName = displayName(for: lhs)
                let rightName = displayName(for: rhs)
                return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
            }
    }

    private var allSessionStatTakersConnected: Bool {
        !sessionInviteAssignments.isEmpty && sessionInviteAssignments.allSatisfy(isCurrentlyConnected)
    }

    private var connectedInviteSelectionIDs: Set<String> {
        Set(connectedInviteAssignments.flatMap { $0.assignedSelections.map(\.id) })
    }

    private func isConnectedAssignedStat(statTypeID: UUID, side: StatsInviteTeamSide) -> Bool {
        connectedInviteSelectionIDs.contains(StatsInviteSelection(statTypeID: statTypeID, side: side).id)
    }

    private struct TeamStatEntry: Identifiable {
        let title: String
        let name: String
        let fallback: String?

        var id: String { "\(title)|\(name)|\(fallback ?? "")" }
    }

    private struct LiveLeaderboardRow: Identifiable {
        let id: UUID
        let playerLabel: String
        let kicks: Int
        let handballs: Int
        let possessions: Int
        let goals: Int
        let behinds: Int
    }

    private func availableTeamStatEntries(_ entries: [TeamStatEntry]) -> [TeamStatEntry] {
        entries.filter { entry in
            statType(
                named: entry.name,
                fallbackName: entry.fallback,
                extraFallbackNames: ["Scores"]
            ) != nil
        }
    }

    private func isDerivedStatName(_ name: String) -> Bool {
        let normalized = normalizedStatName(name)
        return normalized == "disposal efficiency" || normalized == "contested possession"
    }

    private var orderedTeamButtonStatTypes: [StatType] {
        enabledStatTypes.filter { statType in
            let normalized = normalizedStatName(statType.name)
            if normalized == "scores" || normalized == "score" {
                return false
            }
            if isDerivedStatName(statType.name) {
                return isTeamCollectionStat(statType)
            }
            return true
        }
    }

    private func ensureRequiredTeamComparisonStatTypesIfNeeded() {
        var existing = (try? modelContext.fetch(FetchDescriptor<StatType>())) ?? []
        let requiredNames = [
            "Clearance",
            "Hit Out",
            "Free Kick",
            "Turnover",
            "Intercept",
            "Disposal Efficiency",
            "Contested Possession"
        ]
        var didChange = false

        for name in requiredNames {
            if let match = existing.first(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
                if !match.isEnabled {
                    match.isEnabled = true
                    didChange = true
                }
                continue
            }

            let type = StatType(name: name, isEnabled: true, sortOrder: existing.count)
            modelContext.insert(type)
            existing.append(type)
            didChange = true
        }

        if didChange {
            for (index, type) in existing.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
                type.sortOrder = index
            }
            try? modelContext.save()
        }
    }

    private var sessionEvents: [StatEvent] {
        allEvents.filter { $0.sessionId == session.sessionId }
    }

    private var hasRemoteIndividualInviteSelections: Bool {
        sessionInviteAssignments.contains { assignment in
            assignment.assignedSelections.contains { selection in
                guard let statType = allStatTypes.first(where: { $0.id == selection.statTypeID }) else {
                    return false
                }
                return statCollectionMode(for: statType) == .individual
            }
        }
    }

    private var remoteInviteTalliesTaskID: String {
        session.sessionId.uuidString
    }

    private var sessionStatNamesByID: [UUID: Set<String>] {
        var namesByID: [UUID: Set<String>] = [:]

        for type in allStatTypes where type.isEnabled {
            namesByID[type.id, default: []].insert(normalizedStatName(type.name))
        }

        for assignment in sessionInviteAssignments {
            if let cloudAssignment = cloudInviteAssignmentsByRecordName[assignment.cloudRecordName] {
                for rawValue in cloudAssignment.assignedSelectionRawValues {
                    guard let selection = StatsInviteSelection(rawValue: rawValue) else { continue }
                    let displayName = cloudAssignment.assignedSelectionDisplayNameByRawValue[rawValue] ?? ""
                    let strippedName = displayName.replacingOccurrences(
                        of: "\(selection.side.selectionPrefix) ",
                        with: ""
                    )
                    let normalizedName = normalizedStatName(strippedName)
                    if !normalizedName.isEmpty {
                        namesByID[selection.statTypeID, default: []].insert(normalizedName)
                    }
                }
            } else {
                for selection in assignment.assignedSelections {
                    let localName = allStatTypes.first(where: { $0.id == selection.statTypeID })?.name ?? ""
                    let normalizedName = normalizedStatName(localName)
                    if !normalizedName.isEmpty, normalizedName != "unknown" {
                        namesByID[selection.statTypeID, default: []].insert(normalizedName)
                    }
                }
            }
        }

        return namesByID
    }

    private func remoteInviteCount(statTypeID: UUID, isOpposition: Bool) -> Int {
        let sideRawValue = isOpposition ? StatsInviteTeamSide.opposition.rawValue : StatsInviteTeamSide.ourClub.rawValue
        return remoteInviteTallies.reduce(0) { partialResult, tally in
            guard tally.statTypeID == statTypeID, tally.sideRawValue == sideRawValue else { return partialResult }
            return partialResult + tally.count
        }
    }

    private func monitorRemoteInviteTallies() async {
        await refreshRemoteInviteTallies(forceFullRefresh: true)
        await syncRemoteInvitePlayerEvents(forceFullRefresh: true)
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: remoteInvitePollIntervalNanoseconds)
            guard !Task.isCancelled else { return }
            await refreshRemoteInviteTallies(forceFullRefresh: false)
            await syncRemoteInvitePlayerEvents(forceFullRefresh: false)
        }
    }

    @MainActor
    private func refreshRemoteInviteTallies(forceFullRefresh: Bool) async {
        let statTypeIDs = Array(sessionStatNamesByID.keys)
        let sideRawValues = StatsInviteTeamSide.allCases.map(\.rawValue)
        guard !statTypeIDs.isEmpty else {
            remoteInviteTallies = []
            remoteInviteCountsByTallyID = [:]
            lastRemoteInviteTallyUpdateAt = nil
            return
        }

        do {
            let tallies: [CloudStatsInviteTally]
            if forceFullRefresh || lastRemoteInviteTallyUpdateAt == nil {
                tallies = try await CloudKitStatsInviteService.shared.fetchTallies(
                    sessionID: session.sessionId,
                    statTypeIDs: statTypeIDs,
                    sideRawValues: sideRawValues
                )
                remoteInviteTallies = tallies
                remoteInviteCountsByTallyID = Dictionary(uniqueKeysWithValues: tallies.map { ($0.id, $0.count) })
            } else if let lastRemoteInviteTallyUpdateAt {
                tallies = try await CloudKitStatsInviteService.shared.fetchTallies(
                    sessionID: session.sessionId,
                    statTypeIDs: statTypeIDs,
                    sideRawValues: sideRawValues,
                    updatedAfter: lastRemoteInviteTallyUpdateAt
                )
                mergeRemoteInviteTallies(tallies)
            } else {
                tallies = []
            }

            if let latestUpdatedAt = (forceFullRefresh ? remoteInviteTallies : tallies)
                .map(\.updatedAt)
                .max() {
                lastRemoteInviteTallyUpdateAt = max(lastRemoteInviteTallyUpdateAt ?? .distantPast, latestUpdatedAt)
            }
        } catch {
            return
        }
    }

    @MainActor
    private func applyRemoteInviteTallyUpdate(_ tally: CloudStatsInviteTally) {
        mergeRemoteInviteTallies([tally])
        lastRemoteInviteTallyUpdateAt = max(lastRemoteInviteTallyUpdateAt ?? .distantPast, tally.updatedAt)
        if isRemoteInviteIndividualTally(tally) {
            Task {
                await syncRemoteInvitePlayerEvents(forceFullRefresh: false)
            }
        }
    }

    @MainActor
    private func mergeRemoteInviteTallies(_ tallies: [CloudStatsInviteTally]) {
        guard !tallies.isEmpty else { return }
        var talliesByID = Dictionary(uniqueKeysWithValues: remoteInviteTallies.map { ($0.id, $0) })
        for tally in tallies {
            let previousCount = remoteInviteCountsByTallyID[tally.id] ?? talliesByID[tally.id]?.count ?? 0
            talliesByID[tally.id] = tally
            if tally.count > previousCount, !isRemoteInviteIndividualTally(tally) {
                showRemoteInviteBanner(for: tally, delta: tally.count - previousCount)
            }
        }
        remoteInviteTallies = talliesByID.values.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
        remoteInviteCountsByTallyID = Dictionary(uniqueKeysWithValues: remoteInviteTallies.map { ($0.id, $0.count) })
    }

    @MainActor
    private func syncRemoteInvitePlayerEvents(forceFullRefresh: Bool) async {
        let existingRemoteEvents = sessionEvents.filter { $0.sourceRaw == StatsEventSource.remoteInvite.rawValue }
        guard hasRemoteIndividualInviteSelections else {
            guard !existingRemoteEvents.isEmpty else { return }
            existingRemoteEvents.forEach(modelContext.delete)
            try? modelContext.save()
            lastRemoteInvitePlayerEventUpdateAt = nil
            return
        }

        do {
            let remoteEvents: [CloudStatsInvitePlayerEvent]
            if forceFullRefresh || lastRemoteInvitePlayerEventUpdateAt == nil {
                remoteEvents = try await CloudKitStatsInviteService.shared.fetchPlayerEvents(sessionID: session.sessionId)
            } else if let lastRemoteInvitePlayerEventUpdateAt {
                remoteEvents = try await CloudKitStatsInviteService.shared.fetchPlayerEvents(
                    sessionID: session.sessionId,
                    updatedAfter: lastRemoteInvitePlayerEventUpdateAt
                )
            } else {
                remoteEvents = []
            }

            reconcileRemoteInvitePlayerEvents(remoteEvents, removingMissing: forceFullRefresh)
            if forceFullRefresh, remoteEvents.isEmpty {
                lastRemoteInvitePlayerEventUpdateAt = nil
            } else if let latestUpdatedAt = remoteEvents.map(\.updatedAt).max() {
                lastRemoteInvitePlayerEventUpdateAt = max(
                    lastRemoteInvitePlayerEventUpdateAt ?? .distantPast,
                    latestUpdatedAt
                )
            }
        } catch {
            return
        }
    }

    @MainActor
    private func reconcileRemoteInvitePlayerEvents(
        _ remoteEvents: [CloudStatsInvitePlayerEvent],
        removingMissing: Bool
    ) {
        let existingRemoteEvents = sessionEvents.filter { $0.sourceRaw == StatsEventSource.remoteInvite.rawValue }
        let existingByRecordName = Dictionary(
            uniqueKeysWithValues: existingRemoteEvents.compactMap { event in
                event.remoteRecordName.map { ($0, event) }
            }
        )
        var didChange = false

        for remoteEvent in remoteEvents {
            if let existing = existingByRecordName[remoteEvent.id] {
                if existing.playerId != remoteEvent.playerID {
                    existing.playerId = remoteEvent.playerID
                    didChange = true
                }
                if existing.statTypeId != remoteEvent.statTypeID {
                    existing.statTypeId = remoteEvent.statTypeID
                    didChange = true
                }
                if existing.quarter != remoteEvent.quarter {
                    existing.quarter = remoteEvent.quarter
                    didChange = true
                }
                if existing.timestamp != remoteEvent.timestamp {
                    existing.timestamp = remoteEvent.timestamp
                    didChange = true
                }
                if existing.remoteRecordName != remoteEvent.id {
                    existing.remoteRecordName = remoteEvent.id
                    didChange = true
                }
            } else {
                showRemoteInvitePlayerEventBanner(remoteEvent)
                modelContext.insert(
                    StatEvent(
                        id: remoteEvent.eventID,
                        sessionId: remoteEvent.sessionID,
                        playerId: remoteEvent.playerID,
                        statTypeId: remoteEvent.statTypeID,
                        quarter: remoteEvent.quarter,
                        timestamp: remoteEvent.timestamp,
                        sourceRaw: StatsEventSource.remoteInvite.rawValue,
                        remoteRecordName: remoteEvent.id
                    )
                )
                didChange = true
            }
        }

        if removingMissing {
            let remoteRecordNames = Set(remoteEvents.map(\.id))
            for existing in existingRemoteEvents {
                guard let remoteRecordName = existing.remoteRecordName,
                      !remoteRecordNames.contains(remoteRecordName) else {
                    continue
                }
                modelContext.delete(existing)
                didChange = true
            }
        }

        if didChange {
            try? modelContext.save()
        }
    }

    private func isRemoteInviteIndividualTally(_ tally: CloudStatsInviteTally) -> Bool {
        guard tally.sideRawValue == StatsInviteTeamSide.ourClub.rawValue,
              let statType = allStatTypes.first(where: { $0.id == tally.statTypeID }) else {
            return false
        }
        return statCollectionMode(for: statType) == .individual
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

    private func scoreSummary(isOpposition: Bool, includeEvent: (StatEvent) -> Bool) -> (goals: Int, behinds: Int, points: Int) {
        let goalTypeIDs = Set(enabledStatTypes.filter { normalizedStatName($0.name) == "goal" }.map(\.id))
        let behindTypeIDs = Set(enabledStatTypes.filter { normalizedStatName($0.name) == "behind" }.map(\.id))
        let scoresTypeIDs = Set(enabledStatTypes.filter { normalizedStatName($0.name) == "scores" }.map(\.id))

        let goals: Int
        let behinds: Int

        if !goalTypeIDs.isEmpty || !behindTypeIDs.isEmpty {
            let localGoals = sessionEvents.filter { includeEvent($0) && goalTypeIDs.contains($0.statTypeId) }.count
            let localBehinds = sessionEvents.filter { includeEvent($0) && behindTypeIDs.contains($0.statTypeId) }.count
            let remoteGoals = goalTypeIDs.reduce(0) { $0 + remoteInviteCount(statTypeID: $1, isOpposition: isOpposition) }
            let remoteBehinds = behindTypeIDs.reduce(0) { $0 + remoteInviteCount(statTypeID: $1, isOpposition: isOpposition) }
            goals = localGoals + remoteGoals
            behinds = localBehinds + remoteBehinds
        } else {
            goals = sessionEvents.filter {
                includeEvent($0)
                    && scoresTypeIDs.contains($0.statTypeId)
                    && normalizedStatName($0.transcript ?? "") == "goal"
            }.count
            behinds = sessionEvents.filter {
                includeEvent($0)
                    && scoresTypeIDs.contains($0.statTypeId)
                    && normalizedStatName($0.transcript ?? "") == "behind"
            }.count
        }
        return (goals, behinds, goals * 6 + behinds)
    }

    private var ourScoreSummary: (goals: Int, behinds: Int, points: Int) {
        if let snapshot = syncedLiveGameSnapshot {
            return (snapshot.ourGoals, snapshot.ourBehinds, snapshot.ourPoints)
        }
        return scoreSummary(isOpposition: false) { $0.playerId != oppositionTeamStatPlayerID }
    }

    private var oppositionScoreSummary: (goals: Int, behinds: Int, points: Int) {
        if let snapshot = syncedLiveGameSnapshot {
            return (snapshot.theirGoals, snapshot.theirBehinds, snapshot.theirPoints)
        }
        return scoreSummary(isOpposition: true) { $0.playerId == oppositionTeamStatPlayerID }
    }

    private var syncedLiveGameSnapshot: LiveGameSyncSnapshot? {
        guard navigationState.syncedStatsSessionID == session.sessionId,
              navigationState.activeLiveStatsSessionID == session.sessionId,
              let snapshot = navigationState.activeLiveGameSnapshot,
              canSync(with: snapshot) else { return nil }
        return snapshot
    }

    private var isLiveGameControllingMatchState: Bool {
        syncedLiveGameSnapshot != nil
    }

    private var liveGameTimerRefreshToken: String {
        guard let snapshot = syncedLiveGameSnapshot else { return "no-live-game-sync" }
        return [
            snapshot.gradeID.uuidString,
            snapshot.currentQuarter,
            String(snapshot.remainingSeconds),
            snapshot.isTimerRunning ? "running" : "paused",
            snapshot.timerAnchorDate?.description ?? "no-anchor",
            String(snapshot.timerAnchorSecondsRemaining ?? snapshot.remainingSeconds)
        ].joined(separator: "|")
    }

    private var syncedLiveGoalKickers: [(name: String, goals: Int)] {
        guard let snapshot = syncedLiveGameSnapshot else { return [] }
        return snapshot.goalKickers
            .compactMap { entry in
                guard let player = playersForGrade.first(where: { $0.id == entry.playerID }) else { return nil }
                return (name: player.name, goals: entry.goals)
            }
            .sorted { lhs, rhs in
                if lhs.goals != rhs.goals { return lhs.goals > rhs.goals }
                return lhs.name < rhs.name
            }
    }

    private var syncableLiveGameSnapshot: LiveGameSyncSnapshot? {
        guard let snapshot = navigationState.activeLiveGameSnapshot,
              navigationState.activeLiveStatsSessionID == session.sessionId,
              canSync(with: snapshot) else { return nil }
        return snapshot
    }

    private var isStatsSyncedToLiveGame: Bool {
        syncedLiveGameSnapshot != nil
    }

    private var liveSyncStatus: LiveStatsSyncStatus {
        navigationState.liveStatsSyncStatus
    }

    private var statsSyncStatusIconName: String {
        switch liveSyncStatus.state {
        case .green, .red:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .orange:
            return "arrow.triangle.2.circlepath.circle"
        }
    }

    private var statsSyncStatusTint: Color {
        if !sessionInviteAssignments.isEmpty, !allSessionStatTakersConnected {
            return .orange
        }

        switch liveSyncStatus.state {
        case .green:
            return liveBrightGreen
        case .red:
            return .red
        case .orange:
            return .orange
        }
    }

    private var statsSyncAccessibilityLabel: String {
        switch liveSyncStatus.state {
        case .green:
            return "Live Game, Live Stats and user view are synced"
        case .red:
            return "Live Stats sync issues detected"
        case .orange:
            if liveSyncStatus.canManuallySyncGameAndStats {
                return "Live Stats sync available"
            }
            if liveSyncStatus.isGameAndStatsLinked {
                return "Live Game and Live Stats are linked, waiting for user view"
            }
            return "Live Stats waiting for a matching Live Game or user view"
        }
    }

    private var isStatsSyncStatusDisabled: Bool {
        false
    }

    private var liveSyncIssuesMessage: String {
        liveSyncStatus.issues.map(\.message).joined(separator: "\n")
    }

    private var liveStatsInviteSnapshot: LiveStatsInviteSnapshot {
        LiveStatsInviteSnapshot(
            sessionID: session.sessionId,
            currentQuarter: selectedQuarter,
            remainingSeconds: remainingQuarterSeconds,
            isTimerRunning: isQuarterTimerRunning,
            ourPoints: ourScoreSummary.points,
            theirPoints: oppositionScoreSummary.points
        )
    }

    private var liveStatsInviteSnapshotToken: String {
        [
            session.sessionId.uuidString,
            selectedQuarter,
            String(remainingQuarterSeconds),
            isQuarterTimerRunning ? "running" : "paused",
            String(ourScoreSummary.points),
            String(oppositionScoreSummary.points)
        ].joined(separator: "|")
    }

    private func pushLiveStatsInviteSnapshotToCloud() async throws {
        _ = try await CloudKitStatsInviteService.shared.saveSessionState(
            sessionID: session.sessionId,
            currentQuarter: selectedQuarter,
            remainingSeconds: remainingQuarterSeconds,
            isTimerRunning: isQuarterTimerRunning,
            ourPoints: ourScoreSummary.points,
            theirPoints: oppositionScoreSummary.points
        )
    }

    private func monitorLiveStatsInviteSnapshotPublishing() async {
        while !Task.isCancelled {
            await publishLiveStatsInviteSnapshotIfNeeded()
            try? await Task.sleep(nanoseconds: liveStatsInvitePublishIntervalNanoseconds)
        }
    }

    @MainActor
    private func publishLiveStatsInviteSnapshotIfNeeded() async {
        navigationState.updateLiveStatsInviteSnapshot(liveStatsInviteSnapshot)
        let token = liveStatsInviteSnapshotToken
        if token == lastPublishedInviteSnapshotToken, liveStatsInviteSyncError == nil {
            return
        }
        do {
            try await pushLiveStatsInviteSnapshotToCloud()
            lastPublishedInviteSnapshotToken = token
            liveStatsInviteSyncError = nil
        } catch {
            liveStatsInviteSyncError = "Live session sync failed: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private var statsSyncStatusButton: some View {
        Button {
            showSyncStatusPopover.toggle()
        } label: {
            Image(systemName: statsSyncStatusIconName)
                .imageScale(.large)
                .foregroundStyle(statsSyncStatusTint)
                .opacity(isStatsSyncStatusDisabled ? 0.55 : 1)
        }
        .disabled(isStatsSyncStatusDisabled)
        .accessibilityLabel(statsSyncAccessibilityLabel)
        .popover(isPresented: $showSyncStatusPopover, attachmentAnchor: .point(.bottomTrailing), arrowEdge: .top) {
            syncStatusPopoverContent
        }
    }

    private func maybePromptToSyncWithLiveGame() {
        if attemptAutomaticLiveGameSyncIfNeeded() {
            return
        }
        guard !isReadOnlyMode,
              let snapshot = navigationState.activeLiveGameSnapshot,
              canSync(with: snapshot),
              !session.usesLiveGameScoreSync,
              navigationState.syncedStatsSessionID == nil,
              promptedForLiveGameSyncSessionID != session.sessionId else { return }
        promptedForLiveGameSyncSessionID = session.sessionId
        showLiveGameSyncPrompt = true
    }

    private func acceptLiveGameSync() {
        navigationState.syncActiveLiveGame(toStatsSessionID: session.sessionId)
        applySyncedLiveGameStateIfNeeded()
    }

    @discardableResult
    private func attemptAutomaticLiveGameSyncIfNeeded() -> Bool {
        guard session.usesLiveGameScoreSync,
              let snapshot = navigationState.activeLiveGameSnapshot,
              canSync(with: snapshot) else { return false }
        if navigationState.syncedStatsSessionID != session.sessionId {
            navigationState.syncActiveLiveGame(toStatsSessionID: session.sessionId)
        }
        showLiveGameSyncPrompt = false
        promptedForLiveGameSyncSessionID = session.sessionId
        applySyncedLiveGameStateIfNeeded()
        return true
    }

    private func isScoreStatLockedToLiveGame(_ normalizedName: String) -> Bool {
        syncedLiveGameSnapshot != nil && (normalizedName == "goal" || normalizedName == "behind")
    }

    private func applySyncedLiveGameStateIfNeeded() {
        guard let snapshot = syncedLiveGameSnapshot else { return }
        stopQuarterTimer()
        quarterCountsUp = false
        customQuarterMinutes = max(1, snapshot.periodMinutes)
        selectedQuarter = snapshot.currentQuarter
        remainingQuarterSeconds = snapshot.syncedRemainingSeconds()
        isQuarterTimerRunning = snapshot.isTimerActive()
        showQuarterPickerDialog = false
        showQuarterChangeReminder = false
        showTimerModeEditor = false
    }

    private func reconcileSyncedLiveGameGoalKickersIfNeeded() {
        guard let snapshot = syncedLiveGameSnapshot,
              let goalStatType = statType(named: "Goal", fallbackName: "Scores", extraFallbackNames: ["Behind"]),
              let behindStatType = statType(named: "Behind", fallbackName: "Scores", extraFallbackNames: ["Goal"]) else {
            return
        }

        var didChange = false
        didChange = reconcileSyncedLiveGameStatEvents(
            targetCounts: Dictionary(
                uniqueKeysWithValues: snapshot.goalKickers.map { ($0.playerID, max(0, $0.goals)) }
            ),
            statType: goalStatType,
            transcript: "goal"
        ) || didChange

        didChange = reconcileSyncedLiveGameStatEvents(
            targetCounts: Dictionary(
                uniqueKeysWithValues: snapshot.goalKickers.map { ($0.playerID, max(0, $0.points)) }
            ),
            statType: behindStatType,
            transcript: "behind"
        ) || didChange

        if didChange {
            try? modelContext.save()
        }
    }

    private func reconcileSyncedLiveGameStatEvents(
        targetCounts: [UUID: Int],
        statType: StatType,
        transcript: String
    ) -> Bool {
        let syncedEvents = sessionEvents
            .filter {
                $0.sourceRaw == StatsEventSource.liveGameSync.rawValue
                    && $0.statTypeId == statType.id
                    && normalizedStatName($0.transcript ?? transcript) == transcript
            }
            .sorted { $0.timestamp < $1.timestamp }

        let currentCounts = syncedEvents.reduce(into: [UUID: Int]()) { result, event in
            result[event.playerId, default: 0] += 1
        }

        var didChange = false
        let playerIDs = Set(targetCounts.keys).union(currentCounts.keys)
        for playerID in playerIDs {
            let target = targetCounts[playerID, default: 0]
            let current = currentCounts[playerID, default: 0]

            if current < target {
                for _ in 0..<(target - current) {
                    modelContext.insert(
                        StatEvent(
                            sessionId: session.sessionId,
                            playerId: playerID,
                            statTypeId: statType.id,
                            quarter: selectedQuarter,
                            sourceRaw: StatsEventSource.liveGameSync.rawValue,
                            transcript: transcript
                        )
                    )
                }
                didChange = true
            } else if current > target {
                let extras = syncedEvents
                    .filter { $0.playerId == playerID }
                    .suffix(current - target)
                for event in extras {
                    modelContext.delete(event)
                }
                didChange = true
            }
        }
        return didChange
    }

    private func canSync(with snapshot: LiveGameSyncSnapshot) -> Bool {
        snapshot.gradeID == session.gradeId
            && Calendar.current.isDate(snapshot.date, inSameDayAs: session.date)
            && snapshot.opposition.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(session.opposition.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private var ourTeamName: String {
        let name = ClubConfigurationStore.load().clubTeam.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Min Man" : name
    }

    private var formattedQuarterTime: String {
        let absolute = abs(remainingQuarterSeconds)
        let sign = remainingQuarterSeconds < 0 ? "-" : ""
        return sign + String(format: "%02d:%02d", absolute / 60, absolute % 60)
    }

    private var liveBrightGreen: Color {
        Color(red: 0.0, green: 0.82, blue: 0.36)
    }

    private var timerBackgroundColor: Color {
        if isQuarterTimerRunning {
            if !quarterCountsUp && remainingQuarterSeconds <= (2 * 60) {
                return .red
            }
            return liveBrightGreen
        }
        return .gray
    }

    private var quarterBadgeBackgroundColor: Color {
        (isQuarterTimerRunning && remainingQuarterSeconds >= 0) ? liveBrightGreen.opacity(0.22) : Color(.systemGray5)
    }

    private var isEdgeLayoutActive: Bool {
        statsLayout == StatsLayoutOption.edge.rawValue
    }

    private var isSimpleLayoutActive: Bool {
        statsLayout == StatsLayoutOption.simple.rawValue
    }

    private var isIPhoneStatsLayout: Bool {
        horizontalSizeClass == .compact
    }

    private var headerBannerHeight: CGFloat {
        isIPhoneStatsLayout ? 86 : 102
    }

    private var topPanelHeight: CGFloat {
        if oppositionTrackPossessions {
            return isIPhoneStatsLayout ? 376 : 472
        }
        return isIPhoneStatsLayout ? 150 : 168
    }

    private var rightStatActionsHeight: CGFloat {
        220
    }

    private var edgeIsPortrait: Bool {
        interfaceScreenHeight > interfaceScreenWidth
    }

    private var edgeTeamStatColumns: Int {
        (isEdgeLayoutActive && edgeIsPortrait) ? 2 : 4
    }

    private var headerBannerArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
            HStack(alignment: .center, spacing: isIPhoneStatsLayout ? 10 : 14) {
                timerBadge

                VStack(spacing: isIPhoneStatsLayout ? 4 : 8) {
                    Group {
                        if isIPhoneStatsLayout {
                            VStack(spacing: 1) {
                                Text(gradeName)
                                    .font(.title3.weight(.black))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                Text(session.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        } else {
                            HStack(spacing: 10) {
                                Text(gradeName)
                                    .font(.title.weight(.black))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                Text("•")
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.secondary)
                                Text(session.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    if syncedLiveGameSnapshot != nil {
                        Text("Live Game controls score, timer and quarter")
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(liveBrightGreen.opacity(0.22), in: Capsule())
                    } else if !connectedInviteAssignments.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(connectedInviteAssignments.prefix(3)) { assignment in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(liveBrightGreen)
                                        .frame(width: 7, height: 7)
                                    Text(contacts.first(where: { $0.id == assignment.contactId })?.name ?? "Connected")
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(liveBrightGreen.opacity(0.16), in: Capsule())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    quarterBadge
                }
            }
            .padding(.horizontal, isIPhoneStatsLayout ? 14 : 18)

            if let statusBanner {
                RoundedRectangle(cornerRadius: 12)
                    .fill(statusBanner.isSuccess ? liveBrightGreen : Color.red)
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
        .confirmationDialog("Select Quarter", isPresented: $showQuarterPickerDialog, titleVisibility: .visible) {
            ForEach(["Q1", "Q2", "Q3", "Q4"], id: \.self) { quarter in
                Button(quarter) {
                    selectedQuarter = quarter
                }
            }
        }
    }

    private var combinedScoreAndActionsPanel: some View {
        Group {
            if oppositionTrackPossessions {
                comparisonScoreCardPanel
            } else {
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
            }
        }
        .frame(maxWidth: .infinity, minHeight: topPanelHeight, maxHeight: topPanelHeight)
    }

    private var ourTeamEfficiencyText: String {
        efficiencyDisplayText(isOpposition: false, emptyFallback: "0%")
    }

    private func efficiencyDisplayText(isOpposition: Bool, emptyFallback: String) -> String {
        if isTeamModeDisposalEfficiency {
            let disposals = teamTotal(aliases: ["kick", "handball"], isOpposition: isOpposition)
            guard disposals > 0 else { return emptyFallback }
            let effective = teamTotal(aliases: ["disposal efficiency"], isOpposition: isOpposition)
            let percent = (Double(effective) / Double(disposals)) * 100
            return "\(Int(round(percent)))%"
        }

        guard !displayedPlayers.isEmpty else { return emptyFallback }
        let totals = displayedPlayers.reduce((effective: 0, nonEffective: 0)) { partialResult, player in
            let counts = efficiencyVoteCounts(for: player.id, events: sessionEvents)
            return (
                effective: partialResult.effective + counts.effective,
                nonEffective: partialResult.nonEffective + counts.nonEffective
            )
        }
        let ratedCount = totals.effective + totals.nonEffective
        guard ratedCount > 0 else { return emptyFallback }
        let efficiency = Int(round((Double(totals.effective) / Double(ratedCount)) * 100))
        return "\(efficiency)%"
    }

    private func combinedTeamPanel(
        teamName: String,
        scoreText: String,
        style: ClubStyle.Style,
        isOpposition: Bool
    ) -> some View {
        let isOppositionTeam = isOpposition
        return VStack(alignment: .leading, spacing: 8) {
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

            if isEdgeLayoutActive && !isOppositionTeam && sessionTracksDisposalEfficiency {
                HStack(spacing: 8) {
                    Text("Team Efficiency")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(ourTeamEfficiencyText)
                        .font(.title3.weight(.black))
                        .monospacedDigit()
                }
                .padding(.horizontal, 4)
            }

            if !isOppositionTeam, sessionTracksGoalStats, !syncedLiveGoalKickers.isEmpty {
                syncedLiveGoalKickersPanel
            }

            if oppositionTrackPossessions {
                teamStatsExpandedGrid(style: style, isOpposition: isOppositionTeam)
            } else {
                let entries = availableTeamStatEntries([
                    TeamStatEntry(title: "Goal", name: "Goal", fallback: nil),
                    TeamStatEntry(title: "Behind", name: "Behind", fallback: nil),
                    TeamStatEntry(title: "Clearance", name: "Clearance", fallback: "Clearances"),
                    TeamStatEntry(title: "Inside 50", name: "Inside 50", fallback: "Inside 50s")
                ])
                let derivedEntries = availableTeamStatEntries([
                    TeamStatEntry(title: "Efficiency", name: "Disposal Efficiency", fallback: nil),
                    TeamStatEntry(title: "Contested", name: "Contested Possession", fallback: nil)
                ]).filter { entry in
                    guard let type = statType(named: entry.name, fallbackName: entry.fallback) else { return false }
                    return isTeamCollectionStat(type)
                }
                HStack(spacing: 8) {
                    ForEach(entries) { entry in
                        teamStatButton(
                            entry.title,
                            name: entry.name,
                            style: style,
                            isOpposition: isOppositionTeam,
                            fallbackName: entry.fallback
                        )
                    }
                }
                if !derivedEntries.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(derivedEntries) { entry in
                            teamStatButton(
                                entry.title,
                                name: entry.name,
                                style: style,
                                isOpposition: isOppositionTeam,
                                fallbackName: entry.fallback
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            if !isEdgeLayoutActive && !isOppositionTeam && sessionTracksDisposalEfficiency {
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

    private var syncedLiveGoalKickersPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Goal kickers")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            ForEach(Array(syncedLiveGoalKickers.prefix(5).enumerated()), id: \.offset) { _, scorer in
                HStack(spacing: 8) {
                    Text(scorer.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(scorer.goals)")
                        .font(.subheadline.weight(.black))
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func teamStatsExpandedGrid(style: ClubStyle.Style, isOpposition: Bool) -> some View {
        let statTypes = orderedTeamButtonStatTypes
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: edgeTeamStatColumns)
        let remainingSlots = max(edgeTeamStatColumns - (statTypes.count % edgeTeamStatColumns), 0) % edgeTeamStatColumns

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(statTypes, id: \.id) { statType in
                teamStatButton(statType.name, name: statType.name, style: style, isOpposition: isOpposition)
            }
            ForEach(0..<remainingSlots, id: \.self) { _ in
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var comparisonScoreCardPanel: some View {
        return VStack(spacing: 8) {
            edgeScoreSummaryPanel
            edgeComparisonMetricsPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var edgeScoreSummaryPanel: some View {
        HStack(spacing: isIPhoneStatsLayout ? 8 : 12) {
            edgeTeamScoreBlock(
                name: ourTeamName,
                scoreText: "\(ourScoreSummary.goals).\(ourScoreSummary.behinds) (\(ourScoreSummary.points))",
                style: ourStyle
            )

            edgeTeamScoreBlock(
                name: session.opposition,
                scoreText: "\(oppositionScoreSummary.goals).\(oppositionScoreSummary.behinds) (\(oppositionScoreSummary.points))",
                style: oppositionStyle
            )
        }
        .padding(.horizontal, isIPhoneStatsLayout ? 10 : 14)
        .padding(.vertical, isIPhoneStatsLayout ? 8 : 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func edgeTeamScoreBlock(name: String, scoreText: String, style: ClubStyle.Style) -> some View {
        VStack(spacing: isIPhoneStatsLayout ? 4 : 6) {
            Text(name)
                .font((isIPhoneStatsLayout ? Font.subheadline : .headline).weight(.bold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.72)

            Text(scoreText)
                .font(.system(size: isIPhoneStatsLayout ? 50 : 58, weight: .black, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(style.text)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 10)
        .padding(.vertical, isIPhoneStatsLayout ? 10 : 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(style.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(style.border.opacity(0.95), lineWidth: 1.5)
        )
    }

    private var edgeComparisonMetricsPanel: some View {
        let metrics = scoreComparisonMetrics
        return Group {
            if isIPhoneStatsLayout {
                VStack(spacing: 4) {
                    ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                        comparisonMetricRow(metric)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                            comparisonMetricRow(metric)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var scoreComparisonMetrics: [(label: String, ourValue: String, oppositionValue: String, ourNumeric: Double, oppositionNumeric: Double)] {
        let ourEfficiency = efficiencyComparisonValues(isOpposition: false)
        let oppositionEfficiency = efficiencyComparisonValues(isOpposition: true)
        let ourContested = contestedComparisonValues(isOpposition: false)
        let oppositionContested = contestedComparisonValues(isOpposition: true)
        let ourKicks = teamTotal(aliases: ["kick"], isOpposition: false)
        let oppositionKicks = teamTotal(aliases: ["kick"], isOpposition: true)
        let ourHandballs = teamTotal(aliases: ["handball"], isOpposition: false)
        let oppositionHandballs = teamTotal(aliases: ["handball"], isOpposition: true)
        let ourDisposals = ourKicks + ourHandballs
        let oppositionDisposals = oppositionKicks + oppositionHandballs
        let ourMarks = teamTotal(aliases: ["mark"], isOpposition: false)
        let oppositionMarks = teamTotal(aliases: ["mark"], isOpposition: true)
        let ourTackles = teamTotal(aliases: ["tackle"], isOpposition: false)
        let oppositionTackles = teamTotal(aliases: ["tackle"], isOpposition: true)
        let ourInside50 = teamTotal(aliases: ["inside 50", "inside50", "inside 50s"], isOpposition: false)
        let oppositionInside50 = teamTotal(aliases: ["inside 50", "inside50", "inside 50s"], isOpposition: true)
        let ourClearances = teamTotal(aliases: ["clearance", "clearances"], isOpposition: false)
        let oppositionClearances = teamTotal(aliases: ["clearance", "clearances"], isOpposition: true)
        let ourHitOuts = teamTotal(aliases: ["hit out", "hitouts", "hit outs"], isOpposition: false)
        let oppositionHitOuts = teamTotal(aliases: ["hit out", "hitouts", "hit outs"], isOpposition: true)
        let ourFreeKicks = teamTotal(aliases: ["free kick", "free kicks", "freakick", "freakicks"], isOpposition: false)
        let oppositionFreeKicks = teamTotal(aliases: ["free kick", "free kicks", "freakick", "freakicks"], isOpposition: true)
        let ourTurnovers = teamTotal(aliases: ["turnover", "turnovers"], isOpposition: false)
        let oppositionTurnovers = teamTotal(aliases: ["turnover", "turnovers"], isOpposition: true)
        let ourIntercepts = teamTotal(aliases: ["intercept", "intercepts"], isOpposition: false)
        let oppositionIntercepts = teamTotal(aliases: ["intercept", "intercepts"], isOpposition: true)

        var rows: [(label: String, ourValue: String, oppositionValue: String, ourNumeric: Double, oppositionNumeric: Double)] = []

        if shouldShowEfficiencyMetric {
            rows.append((
                label: "Efficiency",
                ourValue: ourEfficiency.text,
                oppositionValue: oppositionEfficiency.text,
                ourNumeric: ourEfficiency.percent,
                oppositionNumeric: oppositionEfficiency.percent
            ))
        }

        if shouldShowContestedMetric {
            rows.append((
                label: "Contested Possession",
                ourValue: ourContested.text,
                oppositionValue: oppositionContested.text,
                ourNumeric: ourContested.total,
                oppositionNumeric: oppositionContested.total
            ))
        }

        rows.append((
            label: "Disposals",
            ourValue: "\(ourDisposals)",
            oppositionValue: "\(oppositionDisposals)",
            ourNumeric: Double(ourDisposals),
            oppositionNumeric: Double(oppositionDisposals)
        ))

        if hasEnabledStat(aliases: ["kick"]) {
            rows.append((
                label: "Kicks",
                ourValue: "\(ourKicks)",
                oppositionValue: "\(oppositionKicks)",
                ourNumeric: Double(ourKicks),
                oppositionNumeric: Double(oppositionKicks)
            ))
        }
        if hasEnabledStat(aliases: ["handball"]) {
            rows.append((
                label: "Handball",
                ourValue: "\(ourHandballs)",
                oppositionValue: "\(oppositionHandballs)",
                ourNumeric: Double(ourHandballs),
                oppositionNumeric: Double(oppositionHandballs)
            ))
        }
        if hasEnabledStat(aliases: ["mark"]) {
            rows.append((
                label: "Marks",
                ourValue: "\(ourMarks)",
                oppositionValue: "\(oppositionMarks)",
                ourNumeric: Double(ourMarks),
                oppositionNumeric: Double(oppositionMarks)
            ))
        }
        if hasEnabledStat(aliases: ["tackle"]) {
            rows.append((
                label: "Tackles",
                ourValue: "\(ourTackles)",
                oppositionValue: "\(oppositionTackles)",
                ourNumeric: Double(ourTackles),
                oppositionNumeric: Double(oppositionTackles)
            ))
        }
        if hasEnabledStat(aliases: ["inside 50", "inside50", "inside 50s"]) {
            rows.append((
                label: "Inside 50",
                ourValue: "\(ourInside50)",
                oppositionValue: "\(oppositionInside50)",
                ourNumeric: Double(ourInside50),
                oppositionNumeric: Double(oppositionInside50)
            ))
        }
        if hasEnabledStat(aliases: ["clearance", "clearances"]) {
            rows.append((
                label: "Clearance",
                ourValue: "\(ourClearances)",
                oppositionValue: "\(oppositionClearances)",
                ourNumeric: Double(ourClearances),
                oppositionNumeric: Double(oppositionClearances)
            ))
        }
        if hasEnabledStat(aliases: ["hit out", "hitouts", "hit outs"]) {
            rows.append((
                label: "Hit Out",
                ourValue: "\(ourHitOuts)",
                oppositionValue: "\(oppositionHitOuts)",
                ourNumeric: Double(ourHitOuts),
                oppositionNumeric: Double(oppositionHitOuts)
            ))
        }
        if hasEnabledStat(aliases: ["free kick", "free kicks", "freakick", "freakicks"]) {
            rows.append((
                label: "Free Kick",
                ourValue: "\(ourFreeKicks)",
                oppositionValue: "\(oppositionFreeKicks)",
                ourNumeric: Double(ourFreeKicks),
                oppositionNumeric: Double(oppositionFreeKicks)
            ))
        }
        if hasEnabledStat(aliases: ["turnover", "turnovers"]) {
            rows.append((
                label: "Turnover",
                ourValue: "\(ourTurnovers)",
                oppositionValue: "\(oppositionTurnovers)",
                ourNumeric: Double(ourTurnovers),
                oppositionNumeric: Double(oppositionTurnovers)
            ))
        }
        if hasEnabledStat(aliases: ["intercept", "intercepts"]) {
            rows.append((
                label: "Intercept",
                ourValue: "\(ourIntercepts)",
                oppositionValue: "\(oppositionIntercepts)",
                ourNumeric: Double(ourIntercepts),
                oppositionNumeric: Double(oppositionIntercepts)
            ))
        }

        let displayOrderByName = Dictionary(
            uniqueKeysWithValues: enabledStatTypes.enumerated().map { (offset: Int, type: StatType) in
                (normalizedStatName(type.name), offset)
            }
        )

        func normalizedMetricName(_ label: String) -> String {
            switch label {
            case "Efficiency":
                return "disposal efficiency"
            case "Disposals":
                return hasEnabledStat(aliases: ["kick"]) ? "kick" : "handball"
            case "Kicks":
                return "kick"
            case "Handball":
                return "handball"
            case "Marks":
                return "mark"
            case "Tackles":
                return "tackle"
            default:
                return normalizedStatName(label)
            }
        }

        return rows.sorted { lhs, rhs in
            let leftIndex = displayOrderByName[normalizedMetricName(lhs.label)] ?? Int.max
            let rightIndex = displayOrderByName[normalizedMetricName(rhs.label)] ?? Int.max
            if leftIndex != rightIndex {
                return leftIndex < rightIndex
            }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    private var shouldShowEfficiencyMetric: Bool {
        sessionTracksDisposalEfficiency
    }

    private var shouldShowContestedMetric: Bool {
        sessionTracksContestedPossessions
    }

    private func comparisonMetricRow(_ metric: (label: String, ourValue: String, oppositionValue: String, ourNumeric: Double, oppositionNumeric: Double)) -> some View {
        let ourIsLeading = metric.ourNumeric > metric.oppositionNumeric
        let oppositionIsLeading = metric.oppositionNumeric > metric.ourNumeric
        let ourBackground = ourIsLeading ? Color.green.opacity(0.85) : (oppositionIsLeading ? Color.red.opacity(0.78) : Color.gray.opacity(0.45))
        let oppositionBackground = oppositionIsLeading ? Color.green.opacity(0.85) : (ourIsLeading ? Color.red.opacity(0.78) : Color.gray.opacity(0.45))
        let tappableMetrics = Set(["Inside 50", "Clearance", "Hit Out", "Free Kick", "Turnover", "Intercept"])
        let isTappableMetric = tappableMetrics.contains(metric.label)

        return HStack(spacing: isIPhoneStatsLayout ? 6 : 10) {
            comparisonMetricSide(
                label: metric.label,
                value: metric.ourValue,
                isOpposition: false,
                background: ourBackground,
                mirrored: false,
                isTappableMetric: isTappableMetric
            )

            comparisonMetricSide(
                label: metric.label,
                value: metric.oppositionValue,
                isOpposition: true,
                background: oppositionBackground,
                mirrored: true,
                isTappableMetric: isTappableMetric
            )
        }
    }

    private func comparisonMetricSide(
        label: String,
        value: String,
        isOpposition: Bool,
        background: Color,
        mirrored: Bool,
        isTappableMetric: Bool
    ) -> some View {
        let content = HStack(spacing: isIPhoneStatsLayout ? 3 : 6) {
            if mirrored {
                Text(value)
                    .font((isIPhoneStatsLayout ? Font.headline : .title3).weight(.black))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: isIPhoneStatsLayout ? 3 : 8)
                Text(label)
                    .font((isIPhoneStatsLayout ? Font.subheadline : .headline).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            } else {
                Text(label)
                    .font((isIPhoneStatsLayout ? Font.subheadline : .headline).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Spacer(minLength: isIPhoneStatsLayout ? 3 : 8)
                Text(value)
                    .font((isIPhoneStatsLayout ? Font.headline : .title3).weight(.black))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, isIPhoneStatsLayout ? 6 : 10)
        .padding(.horizontal, isIPhoneStatsLayout ? 8 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
        )

        return Group {
            if isTappableMetric {
                Button {
                    addTeamComparisonMetric(label: label, isOpposition: isOpposition)
                } label: { content }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private func addTeamComparisonMetric(label: String, isOpposition: Bool) {
        let aliases: [String]
        switch label {
        case "Inside 50":
            aliases = ["inside 50", "inside50", "inside 50s"]
        case "Clearance":
            aliases = ["clearance", "clearances"]
        case "Hit Out":
            aliases = ["hit out", "hitouts", "hit outs"]
        case "Free Kick":
            aliases = ["free kick", "free kicks", "freakick", "freakicks"]
        case "Turnover":
            aliases = ["turnover", "turnovers"]
        case "Intercept":
            aliases = ["intercept", "intercepts"]
        default:
            return
        }
        guard let type = statTypeMatching(aliases: aliases) else { return }
        addTeamEvent(statTypeId: type.id, isOpposition: isOpposition)
    }

    private func efficiencyComparisonValues(isOpposition: Bool) -> (text: String, percent: Double) {
        if isTeamModeDisposalEfficiency {
            let disposals = teamTotal(aliases: ["kick", "handball"], isOpposition: isOpposition)
            guard disposals > 0 else { return ("0%", 0) }
            let effective = teamTotal(aliases: ["disposal efficiency"], isOpposition: isOpposition)
            let percent = (Double(effective) / Double(disposals)) * 100
            return ("\(Int(round(percent)))%", percent)
        }
        let teamEvents = eventsForComparison(isOpposition: isOpposition)
        let effective = teamEvents.filter { $0.efficiencyVoteRaw == EfficiencyVote.thumbsUp.rawValue }.count
        let nonEffective = teamEvents.filter { $0.efficiencyVoteRaw == EfficiencyVote.thumbsDown.rawValue }.count
        let total = effective + nonEffective
        guard total > 0 else { return ("0%", 0) }
        let percent = (Double(effective) / Double(total)) * 100
        return ("\(Int(round(percent)))%", percent)
    }

    private func contestedComparisonValues(isOpposition: Bool) -> (text: String, total: Double) {
        if isTeamModeContestedPossession {
            let contested = teamTotal(aliases: ["contested possession"], isOpposition: isOpposition)
            return ("\(contested)", Double(contested))
        }
        let teamEvents = eventsForComparison(isOpposition: isOpposition)
        let contested = teamEvents.filter { $0.contestedVoteRaw == ContestedPossessionVote.contested.rawValue }.count
        return ("\(contested)", Double(contested))
    }

    private func eventsForComparison(isOpposition: Bool) -> [StatEvent] {
        sessionEvents.filter { event in
            let isOppositionEvent = event.playerId == oppositionTeamStatPlayerID
            return isOppositionEvent == isOpposition
        }
    }

    private func teamTotal(aliases: [String], isOpposition: Bool) -> Int {
        let normalizedAliases = Set(aliases.map(normalizedStatName))
        let matchingIDs: Set<UUID> = Set(
            sessionStatNamesByID.compactMap { entry in
                let (statTypeID, names) = entry
                return names.contains(where: { normalizedAliases.contains($0) }) ? statTypeID : nil
            }
        )
        if matchingIDs.isEmpty {
            let fallbackIDs: Set<UUID> = Set(
                allStatTypes.compactMap { type in
                    guard type.isEnabled, normalizedAliases.contains(normalizedStatName(type.name)) else { return nil }
                    return type.id
                }
            )
            if fallbackIDs.isEmpty {
                return 0
            }
            let localTotal = eventsForComparison(isOpposition: isOpposition)
                .filter { fallbackIDs.contains($0.statTypeId) }
                .count
            let remoteTotal = fallbackIDs.reduce(0) { partialResult, statTypeID in
                partialResult + remoteInviteCount(statTypeID: statTypeID, isOpposition: isOpposition)
            }
            return localTotal + remoteTotal
        }
        let localTotal = eventsForComparison(isOpposition: isOpposition)
            .filter { matchingIDs.contains($0.statTypeId) }
            .count
        let remoteTotal = matchingIDs.reduce(0) { partialResult, statTypeID in
            partialResult + remoteInviteCount(statTypeID: statTypeID, isOpposition: isOpposition)
        }
        return localTotal + remoteTotal
    }

    private var timerBadge: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(formattedQuarterTime)
                .font(.system(size: isIPhoneStatsLayout ? 24 : 30, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle((!quarterCountsUp && remainingQuarterSeconds <= (2 * 60)) ? .white : .primary)
            Text(quarterCountsUp ? "Count up" : "Count down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, isIPhoneStatsLayout ? 10 : 12)
        .padding(.vertical, isIPhoneStatsLayout ? 6 : 8)
        .frame(minWidth: isIPhoneStatsLayout ? 92 : 112, minHeight: isIPhoneStatsLayout ? 58 : 68, alignment: .leading)
        .background(timerBackgroundColor.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            guard !isLiveGameControllingMatchState else { return }
            if isQuarterTimerRunning {
                stopQuarterTimer()
            } else {
                startQuarterTimer()
            }
        }
        .onLongPressGesture {
            guard !isLiveGameControllingMatchState else { return }
            showTimerModeEditor = true
        }
        .popover(isPresented: $showTimerModeEditor, attachmentAnchor: .point(.bottomLeading), arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Timer settings")
                    .font(.headline)
                Stepper("Minutes: \(customQuarterMinutes)", value: $customQuarterMinutes, in: 1...60, step: 1)
                Toggle("Count up instead", isOn: $quarterCountsUp)
                Button("Restart timer") {
                    stopQuarterTimer()
                    remainingQuarterSeconds = quarterCountsUp ? 0 : customQuarterMinutes * 60
                }
                .buttonStyle(.bordered)
                Button("Reset counter") {
                    configureQuarterTimer(reset: true)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(width: 260)
        }
    }

    private var quarterBadge: some View {
        Text(selectedQuarter)
            .font((isIPhoneStatsLayout ? Font.title3 : .title2).weight(.black))
            .frame(minWidth: isIPhoneStatsLayout ? 92 : 112, minHeight: isIPhoneStatsLayout ? 58 : 68)
            .background(quarterBadgeBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onLongPressGesture {
                guard !isLiveGameControllingMatchState else { return }
                showQuarterChangeReminder = true
            }
    }

    private var syncStatusPopoverContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sync Status")
                    .font(.headline.weight(.bold))
                Spacer(minLength: 12)
                Text(allSessionStatTakersConnected ? "Ready" : "Waiting")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(allSessionStatTakersConnected ? liveBrightGreen : .orange)
            }

            if !liveSyncIssuesMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Issues")
                    .font(.subheadline.weight(.semibold))
                Text(liveSyncIssuesMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if liveSyncStatus.state == .orange && liveSyncStatus.canManuallySyncGameAndStats {
                    Button("Sync now") {
                        acceptLiveGameSync()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Divider()
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Invited Users")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                if !sessionInviteAssignments.isEmpty {
                    Text(allSessionStatTakersConnected ? "Connected" : "Not all connected")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(allSessionStatTakersConnected ? liveBrightGreen : .orange)
                }
            }

            if sessionInviteAssignments.isEmpty {
                Text("No invited stat takers for this session.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(sessionInviteAssignments) { assignment in
                            statTakerStatusRow(assignment)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private func statTakerStatusRow(_ assignment: StatsInviteAssignment) -> some View {
        let isConnected = isCurrentlyConnected(assignment)
        let isSelected = selectedStatTakerAssignmentID == assignment.id

        return Button {
            if isSelected {
                showSyncStatusPopover = false
                editingStatTakerAssignment = assignment
            } else {
                selectedStatTakerAssignmentID = assignment.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(displayName(for: assignment))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(isConnected ? "Connected" : "Waiting")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isConnected ? .green : .orange)
                }

                Text("Stats: \(assignedStatsSummary(for: assignment))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isSelected {
                    Text("Tap again to manage assignments")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (isSelected ? Color.green.opacity(0.14) : Color.white.opacity(0.06)),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
    }

    private func displayName(for assignment: StatsInviteAssignment) -> String {
        let trimmedName = assignment.inviteeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }
        if let contactName = contacts.first(where: { $0.id == assignment.contactId })?.name,
           !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return contactName
        }
        let trimmedEmail = assignment.inviteeEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedEmail.isEmpty ? "Stat Taker" : trimmedEmail
    }

    private func assignedStatsSummary(for assignment: StatsInviteAssignment) -> String {
        let names = assignmentSummaryNames(for: assignment)
        if names.isEmpty {
            return "No stats assigned"
        }
        return names.joined(separator: ", ")
    }

    private func isCurrentlyConnected(_ assignment: StatsInviteAssignment) -> Bool {
        guard let lastConnectedAt = assignment.lastConnectedAt else { return false }
        return Date().timeIntervalSince(lastConnectedAt) <= statTakerConnectionTimeout
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
                Text(player.number.map { String($0) } ?? "—")
                    .font(.headline.weight(.black))
                    .foregroundStyle(ringColors.text)
            }
            Text(player.lastName.uppercased())
                .font(.headline.weight(.semibold))
                .lineLimit(1)
            Text(player.displayFirstName)
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
                        playerCardContent(player: player)
                            .frame(maxWidth: .infinity, minHeight: cellHeight)
                            .background(activePlayerQuickStatsPlayerID == player.id ? Color.blue : Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                        .background {
                            GeometryReader { cardProxy in
                                Color.clear
                                    .task(id: cardProxy.frame(in: .global)) {
                                        let frame = cardProxy.frame(in: .global)
                                        playerCardFramesGlobal[player.id] = frame

                                        if activePlayerQuickStatsPlayerID == player.id {
                                            activePlayerQuickCardFrameGlobal = frame
                                        }
                                    }
                            }
                        }
                        .highPriorityGesture(
                            LongPressGesture(minimumDuration: playerQuickStatsLongPressDuration)
                                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                                .onChanged { value in
                                    switch value {
                                    case .first(true):
                                        selectedPlayerId = player.id
                                        activePlayerQuickStatsPlayerID = player.id
                                        activePlayerQuickCardFrameGlobal = playerCardFramesGlobal[player.id] ?? .zero
                                        clearPendingPlayerQuickStat()
                                    case .second(true, let drag?):
                                        if activePlayerQuickStatsPlayerID != player.id {
                                            activePlayerQuickStatsPlayerID = player.id
                                            activePlayerQuickCardFrameGlobal = .zero
                                            clearPendingPlayerQuickStat()
                                        }
                                        activePlayerQuickStatsPlayerID = player.id
                                        let cardSize = activePlayerQuickCardFrameGlobal.size == .zero
                                            ? CGSize(width: panelProxy.size.width / CGFloat(columnsCount), height: cellHeight)
                                            : activePlayerQuickCardFrameGlobal.size
                                        updateQuickStatHover(location: drag.location, cardSize: cardSize)
                                    default:
                                        break
                                    }
                                }
                                .onEnded { _ in
                                    guard activePlayerQuickStatsPlayerID == player.id else {
                                        clearPendingPlayerQuickStat()
                                        activePlayerQuickStatsPlayerID = nil
                                        activePlayerQuickCardFrameGlobal = .zero
                                        return
                                    }
                                    commitPendingPlayerQuickStatIfValid(playerID: player.id)
                                    clearPendingPlayerQuickStat()
                                    activePlayerQuickStatsPlayerID = nil
                                    activePlayerQuickCardFrameGlobal = .zero
                                }
                        )
                        .onTapGesture {
                            // Intentionally no-op: quick stats should only respond to long press.
                        }
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
                .overlay {
                    GeometryReader { overlayProxy in
                        if activePlayerQuickStatsPlayerID != nil, activePlayerQuickCardFrameGlobal != .zero {
                            let overlayFrame = overlayProxy.frame(in: .global)
                            let cardFrame = activePlayerQuickCardFrameGlobal
                            playerQuickStatsFan(cardSize: cardFrame.size, globalMidX: cardFrame.midX)
                                .frame(width: cardFrame.width, height: cardFrame.height)
                                .position(
                                    x: cardFrame.midX - overlayFrame.minX,
                                    y: cardFrame.midY - overlayFrame.minY
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                                .zIndex(6000)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .zIndex(6000)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var simpleLayoutContent: some View {
        VStack(spacing: 12) {
            headerBannerArea
                .frame(height: 76)

            if oppositionTrackPossessions {
                edgeScoreSummaryPanel
                edgeComparisonMetricsPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                combinedScoreAndActionsPanel
                    .frame(height: topPanelHeight)

                statButtonsPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            liveLeadersPanel
                .frame(height: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func edgeLayoutContent(proxy: GeometryProxy) -> some View {
        let sideWidth = min(max(proxy.size.width * 0.16, 128), 180)
        let centerWidth = max(proxy.size.width - (sideWidth * 2) - 48, 320)
        let splitIndex = Int(ceil(Double(gridPlayers.count) / 2.0))
        let leftPlayers = Array(gridPlayers.prefix(splitIndex).prefix(12))
        let rightPlayers = Array(gridPlayers.dropFirst(splitIndex).prefix(12))
        let recentAreaHeight = max(280, min(proxy.size.height * 0.33, 360))
        let sectionGap: CGFloat = 12

        return VStack(spacing: sectionGap) {
            HStack(alignment: .top, spacing: sectionGap) {
                VStack(spacing: sectionGap) {
                    edgePlayerColumn(players: leftPlayers, isTrailingSide: false)
                }
                .frame(width: sideWidth)

                VStack(spacing: sectionGap) {
                    headerBannerArea
                        .frame(height: 76)
                        .frame(maxWidth: centerWidth)

                    if oppositionTrackPossessions {
                        edgeScoreSummaryPanel

                        edgeComparisonMetricsPanel
                            .frame(maxHeight: .infinity, alignment: .top)
                    } else {
                        combinedScoreAndActionsPanel
                            .frame(height: topPanelHeight, alignment: .top)
                            .clipped()

                        statButtonsPanel
                            .frame(height: rightStatActionsHeight)
                    }

                    recentEventsPanel
                        .frame(height: recentAreaHeight)

                    liveLeadersPanel
                        .frame(height: 340)
                }
                .frame(width: centerWidth)
                .frame(maxHeight: .infinity, alignment: .top)

                VStack(spacing: sectionGap) {
                    edgePlayerColumn(players: rightPlayers, isTrailingSide: true)
                }
                .frame(width: sideWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var sideSpeakButtonSize: CGFloat { 138 }

    private func edgePlayerColumn(players: [Player], isTrailingSide: Bool) -> some View {
        GeometryReader { panelProxy in
            let topControlsHeight = sideSpeakButtonSize + 20
            let bottomButtonReserve: CGFloat = 40
            let listVerticalSpacing: CGFloat = 8
            let availableHeight = max(0, panelProxy.size.height - topControlsHeight - bottomButtonReserve)
            let estimatedHeight = (availableHeight - (listVerticalSpacing * 11)) / 12
            let cardHeight = max(58, min(82, estimatedHeight))

            VStack(spacing: 10) {
                HStack {
                    if isTrailingSide {
                        Spacer()
                        speakButton(isOpposition: true)
                    } else {
                        speakButton(isOpposition: false)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)

                edgePlayerColumnList(
                    players: players,
                    panelProxy: panelProxy,
                    cardHeight: cardHeight,
                    spacing: listVerticalSpacing
                )
                .frame(maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .top) {
                    if players.count < 12 {
                        VStack(spacing: listVerticalSpacing) {
                            ForEach(0..<(12 - players.count), id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.black.opacity(0.04))
                                    .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }
                .overlay {
                    GeometryReader { overlayProxy in
                        if activePlayerQuickStatsPlayerID != nil, activePlayerQuickCardFrameGlobal != .zero {
                            let overlayFrame = overlayProxy.frame(in: .global)
                            let cardFrame = activePlayerQuickCardFrameGlobal
                            playerQuickStatsFan(cardSize: cardFrame.size, globalMidX: cardFrame.midX)
                                .frame(width: cardFrame.width, height: cardFrame.height)
                                .position(
                                    x: cardFrame.midX - overlayFrame.minX,
                                    y: cardFrame.midY - overlayFrame.minY
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                                .zIndex(6000)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .zIndex(6000)
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: isTrailingSide ? .bottomTrailing : .bottomLeading) {
                Button {
                    showPlayerVisibilityEditor = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
    }

    private func edgePlayerColumnList(
        players: [Player],
        panelProxy: GeometryProxy,
        cardHeight: CGFloat,
        spacing: CGFloat
    ) -> some View {
        return VStack(spacing: spacing) {
            ForEach(Array(players.enumerated()), id: \.element.id) { _, player in
                edgePlayerCard(player: player, panelProxy: panelProxy, minHeight: cardHeight)
            }
        }
    }

    private func edgePlayerCard(player: Player, panelProxy: GeometryProxy, minHeight: CGFloat) -> some View {
        playerCardContent(player: player)
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight)
            .background(
                activePlayerQuickStatsPlayerID == player.id ? Color.blue : Color.black.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 10)
            )
        .background {
            GeometryReader { cardProxy in
                Color.clear
                    .task(id: cardProxy.frame(in: .global)) {
                        let frame = cardProxy.frame(in: .global)
                        playerCardFramesGlobal[player.id] = frame

                        if activePlayerQuickStatsPlayerID == player.id {
                            activePlayerQuickCardFrameGlobal = frame
                        }
                    }
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: playerQuickStatsLongPressDuration)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                .onChanged { value in
                    switch value {
                    case .first(true):
                        selectedPlayerId = player.id
                        activePlayerQuickStatsPlayerID = player.id
                        activePlayerQuickCardFrameGlobal = playerCardFramesGlobal[player.id] ?? .zero
                        clearPendingPlayerQuickStat()
                        triggerStrongHaptic()
                    case .second(true, let drag?):
                        if activePlayerQuickStatsPlayerID != player.id {
                            activePlayerQuickStatsPlayerID = player.id
                            activePlayerQuickCardFrameGlobal = .zero
                            clearPendingPlayerQuickStat()
                            triggerStrongHaptic()
                        }
                        activePlayerQuickStatsPlayerID = player.id
                        let fallbackWidth = max(panelProxy.size.width - 8, 120)
                        let cardSize = activePlayerQuickCardFrameGlobal.size == .zero
                            ? CGSize(width: fallbackWidth, height: 82)
                            : activePlayerQuickCardFrameGlobal.size
                        updateQuickStatHover(location: drag.location, cardSize: cardSize)
                    default:
                        break
                    }
                }
                .onEnded { _ in
                    guard activePlayerQuickStatsPlayerID == player.id else {
                        clearPendingPlayerQuickStat()
                        activePlayerQuickStatsPlayerID = nil
                        activePlayerQuickCardFrameGlobal = .zero
                        return
                    }
                    commitPendingPlayerQuickStatIfValid(playerID: player.id)
                    clearPendingPlayerQuickStat()
                    activePlayerQuickStatsPlayerID = nil
                    activePlayerQuickCardFrameGlobal = .zero
                }
        )
        .onTapGesture {
            // Intentionally no-op: quick stats should only respond to long press.
        }
    }

    private var statButtonsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Stat Actions")
                    .font(.title3.bold())

                if selectedPlayerId == nil {
                    Text("Select a player first")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(playerStatTypes) { type in
                    let isConnectedAssignment = isConnectedAssignedStat(statTypeID: type.id, side: .ourClub)
                    Button {
                        addManualEvent(statTypeId: type.id)
                    } label: {
                        Text(type.name)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(selectedPlayerId == nil ? Color.accentColor : Color.white)
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .background(
                                selectedPlayerId == nil ? Color.accentColor.opacity(0.16) : Color.blue,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isConnectedAssignment ? Color.blue : Color.clear, lineWidth: 3)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedPlayerId == nil)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func teamStatButton(
        _ title: String,
        name: String,
        style: ClubStyle.Style,
        isOpposition: Bool,
        fallbackName: String? = nil
    ) -> AnyView {
        let statType = statType(
            named: name,
            fallbackName: fallbackName,
            extraFallbackNames: ["Scores"]
        )
        let normalizedName = normalizedStatName(name)
        let scoreKind: String? = (normalizedName == "goal" || normalizedName == "behind") ? normalizedName : nil
        let isLockedToLiveGame = isScoreStatLockedToLiveGame(normalizedName)
        let isTeamOnlyStat = statType.map(isTeamCollectionStat) ?? (defaultSessionStatCollectionMode(for: name) == .team)
        let buttonKey = "\(normalizedName)-\(isOpposition ? "opp" : "our")"
        let supportsEfficiencyLongPress = supportsEfficiencyLongPress(for: normalizedName, isOpposition: isOpposition)
        let showEfficiencyVote = sessionTracksDisposalEfficiencyVotes(isOpposition: isOpposition) && statRequiresEfficiencyVote(normalizedName)
        let showContestedVote = sessionTracksContestedPossessionVotes(isOpposition: isOpposition) && statSupportsContestedVote(normalizedName)
        let isConnectedAssignment = statType.map {
            isConnectedAssignedStat(
                statTypeID: $0.id,
                side: isOpposition ? .opposition : .ourClub
            )
        } ?? false
        let baseButton = Button {
            if suppressTapForButtonKey == buttonKey {
                suppressTapForButtonKey = nil
                return
            }
            guard !isLockedToLiveGame else { return }
            guard let statType else { return }
            handleTeamStatAction(
                statTypeId: statType.id,
                isOpposition: isOpposition,
                scoreKind: scoreKind,
                isTeamOnlyStat: isTeamOnlyStat,
                efficiencyVote: nil
            )
        } label: {
            Text(title)
                .font(.title3.weight(.black))
                .foregroundStyle(style.text)
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(style.background.opacity(statType == nil ? 0.35 : (isLockedToLiveGame ? 0.45 : 1)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(isConnectedAssignment ? Color.blue : Color.clear, lineWidth: 3)
                )
        }
        .disabled(isLockedToLiveGame)
        .overlay(alignment: .top) {
            GeometryReader { proxy in
                if activeEfficiencyButtonKey == buttonKey {
                    let popupShift = popupHorizontalShift(for: proxy.frame(in: .global).midX)
                    if showEfficiencyVote && showContestedVote {
                        ZStack {
                            contestedSlidePopup
                                .offset(y: 46)
                            efficiencySlidePopup
                                .offset(x: efficiencyPopupHorizontalOffset, y: -46)
                        }
                        .offset(x: popupShift, y: -132)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    } else {
                        VStack(spacing: 8) {
                            if showEfficiencyVote {
                                efficiencySlidePopup
                            }
                            if showContestedVote {
                                contestedSlidePopup
                            }
                        }
                        .offset(x: popupShift, y: -88)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            if isLockedToLiveGame {
                Text("Live")
                    .font(.caption2.weight(.black))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
        .disabled(statType == nil)
        .zIndex(activeEfficiencyButtonKey == buttonKey ? 2000 : 0)

        if supportsEfficiencyLongPress {
            return AnyView(baseButton.highPriorityGesture(
                LongPressGesture(minimumDuration: 0.28)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onChanged { value in
                        switch value {
                        case .first(true):
                            activeEfficiencyButtonKey = buttonKey
                            activeEfficiencyHoverVote = nil
                            activeContestedHoverVote = nil
                            triggerStrongHaptic()
                        case .second(true, let drag?):
                            let previousEfficiencyVote = activeEfficiencyHoverVote
                            let previousContestedVote = activeContestedHoverVote
                            if showEfficiencyVote && showContestedVote {
                                if drag.location.y < -76 {
                                    activeEfficiencyHoverVote = drag.location.x < 110 ? .thumbsUp : .thumbsDown
                                } else {
                                    activeContestedHoverVote = drag.location.x < 110 ? .contested : .uncontested
                                }
                            } else if showEfficiencyVote {
                                activeEfficiencyHoverVote = drag.location.x < 110 ? .thumbsUp : .thumbsDown
                            } else if showContestedVote {
                                activeContestedHoverVote = drag.location.x < 110 ? .contested : .uncontested
                            }
                            if previousEfficiencyVote != activeEfficiencyHoverVote || previousContestedVote != activeContestedHoverVote {
                                triggerSelectionStepHaptic()
                            }
                        default:
                            break
                        }
                    }
                    .onEnded { value in
                        guard let statType else {
                            activeEfficiencyButtonKey = nil
                            activeEfficiencyHoverVote = nil
                            activeContestedHoverVote = nil
                            return
                        }
                        var didCommit = false
                        switch value {
                        case .second(true, _):
                            let vote = activeEfficiencyHoverVote
                            let contestedVote = activeContestedHoverVote
                            let hasRequiredEfficiency = !showEfficiencyVote || vote != nil
                            let hasRequiredContested = !showContestedVote || contestedVote != nil
                            if hasRequiredEfficiency && hasRequiredContested {
                                suppressTapForButtonKey = buttonKey
                                handleTeamStatAction(
                                    statTypeId: statType.id,
                                    isOpposition: isOpposition,
                                    scoreKind: scoreKind,
                                    isTeamOnlyStat: isTeamOnlyStat,
                                    efficiencyVote: vote,
                                    contestedVote: contestedVote
                                )
                                didCommit = true
                            }
                        default:
                            break
                        }
                        if !didCommit {
                            suppressTapForButtonKey = nil
                        }
                        activeEfficiencyButtonKey = nil
                        activeEfficiencyHoverVote = nil
                        activeContestedHoverVote = nil
                    }
            ))
        } else {
            return AnyView(baseButton)
        }
    }

    private var efficiencySlidePopup: some View {
        HStack(spacing: 8) {
            efficiencySlideOption(title: "Effective", vote: .thumbsUp, tint: .green)
            efficiencySlideOption(title: "Non effective", vote: .thumbsDown, tint: .red)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 3)
    }

    private func efficiencySlideOption(title: String, vote: EfficiencyVote, tint: Color) -> some View {
        let isSelected = activeEfficiencyHoverVote == vote
        return Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .frame(width: 102, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? tint : Color.gray.opacity(0.35))
            )
    }

    private var contestedSlidePopup: some View {
        HStack(spacing: 8) {
            contestedSlideOption(title: "Contested", vote: .contested, tint: .orange)
            contestedSlideOption(title: "Uncontested", vote: .uncontested, tint: .blue)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 3)
    }

    private var efficiencyPopupHorizontalOffset: CGFloat {
        switch activeContestedHoverVote {
        case .contested:
            return -55
        case .uncontested:
            return 55
        default:
            return 0
        }
    }

    private func popupHorizontalShift(for buttonMidX: CGFloat) -> CGFloat {
        let screenWidth = interfaceScreenWidth
        let edgePadding: CGFloat = 12
        let halfWidth: CGFloat = (sessionTracksDisposalEfficiency && sessionTracksContestedPossessions) ? 170 : 112
        let leftOverflow = max(0, (edgePadding + halfWidth) - buttonMidX)
        let rightOverflow = max(0, buttonMidX + halfWidth - (screenWidth - edgePadding))
        return leftOverflow - rightOverflow
    }

    private func contestedSlideOption(title: String, vote: ContestedPossessionVote, tint: Color) -> some View {
        let isSelected = activeContestedHoverVote == vote
        return Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .frame(width: 102, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? tint : Color.gray.opacity(0.35))
            )
    }

    private func supportsEfficiencyLongPress(for normalizedName: String, isOpposition: Bool) -> Bool {
        guard supportsLongPressVotes(for: normalizedName) else { return false }
        guard !isOpposition else { return false }
        return true
    }

    private func supportsLongPressVotes(for normalizedName: String) -> Bool {
        let supportsEfficiency = sessionTracksDisposalEfficiencyVotes() && statRequiresEfficiencyVote(normalizedName)
        let supportsContested = sessionTracksContestedPossessionVotes() && statSupportsContestedVote(normalizedName)
        return supportsEfficiency || supportsContested
    }

    private func statRequiresEfficiencyVote(_ normalizedName: String) -> Bool {
        normalizedName == "kick" || normalizedName == "handball"
    }

    private func statSupportsContestedVote(_ normalizedName: String) -> Bool {
        normalizedName == "kick" || normalizedName == "handball" || normalizedName == "mark"
    }

    private func handleTeamStatAction(
        statTypeId: UUID,
        isOpposition: Bool,
        scoreKind: String?,
        isTeamOnlyStat: Bool,
        efficiencyVote: EfficiencyVote?,
        contestedVote: ContestedPossessionVote? = nil
    ) {
        let requiresSelectedPlayer = !isOpposition && trackIndividualTracking && !isTeamOnlyStat
        if isOpposition {
            addTeamEvent(
                statTypeId: statTypeId,
                isOpposition: true,
                scoreKind: scoreKind,
                efficiencyVote: efficiencyVote,
                contestedVote: contestedVote
            )
            return
        }

        if !trackIndividualTracking {
            addTeamEvent(statTypeId: statTypeId, isOpposition: false, scoreKind: scoreKind, efficiencyVote: efficiencyVote, contestedVote: contestedVote)
        } else if isTeamOnlyStat {
            addTeamEvent(statTypeId: statTypeId, isOpposition: false, scoreKind: scoreKind, efficiencyVote: efficiencyVote, contestedVote: contestedVote)
        } else if requiresSelectedPlayer {
            addManualEvent(statTypeId: statTypeId, transcript: scoreKind, efficiencyVote: efficiencyVote, contestedVote: contestedVote)
        } else {
            addTeamEvent(statTypeId: statTypeId, isOpposition: false, scoreKind: scoreKind, efficiencyVote: efficiencyVote, contestedVote: contestedVote)
        }
    }

    private func efficiencyEmojiForRecentEvent(_ event: StatEvent) -> String? {
        guard let vote = event.efficiencyVoteRaw else { return nil }
        return vote == EfficiencyVote.thumbsUp.rawValue ? "👍" : "👎"
    }

    private var recentEventsPanel: some View {
        let recent = Array(sessionEvents.prefix(6))
        return VStack(alignment: .leading, spacing: 8) {
            LazyVStack(spacing: 6) {
                ForEach(recent) { event in
                    Button {
                        showEditEvent = event
                    } label: {
                        HStack(spacing: 6) {
                            Spacer(minLength: 0)
                            Text(playerNameForRecentEvent(for: event.playerId))
                                .font(.title.weight(.medium))
                                .lineLimit(1)
                            Text("-")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text(recentEventStatLabel(event))
                                .font(.title.weight(.black))
                                .lineLimit(1)
                            if let efficiencyEmoji = efficiencyEmojiForRecentEvent(event) {
                                Text(efficiencyEmoji)
                                    .font(.title)
                                    .lineLimit(1)
                            }
                            Text("-")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.title)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .transition(
                        .asymmetric(
                            insertion: .modifier(
                                active: RollingInModifier(rotation: -18, xOffset: 56, yOffset: -10, opacity: 0),
                                identity: RollingInModifier(rotation: 0, xOffset: 0, yOffset: 0, opacity: 1)
                            ),
                            removal: .opacity
                        )
                    )
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: recent.map(\.id))

            if sessionEvents.isEmpty {
                Text("No events yet")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 300, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private struct RollingInModifier: ViewModifier {
        let rotation: Double
        let xOffset: CGFloat
        let yOffset: CGFloat
        let opacity: Double

        func body(content: Content) -> some View {
            content
                .rotationEffect(.degrees(rotation))
                .offset(x: xOffset, y: yOffset)
                .opacity(opacity)
        }
    }

    private func speakButton(isOpposition: Bool) -> some View {
        Button {
            // press-and-hold driven
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill((isOpposition ? oppositionStyle.background : ourStyle.background).opacity(speechService.isRecording ? 0.72 : 0.94))
                    .frame(width: sideSpeakButtonSize, height: sideSpeakButtonSize)
                Text("Speak")
                    .font(.title2.bold())
                    .foregroundStyle(isOpposition ? oppositionStyle.text : ourStyle.text)
            }
        }
        .onLongPressGesture(minimumDuration: 0.01, maximumDistance: .infinity, pressing: { isPressing in
            if isPressing {
                activeSideSpeakPresses += 1
                triggerStrongHaptic()
                speechService.startListening(vocabulary: speechVocabulary)
            } else if speechService.isRecording {
                activeSideSpeakPresses = max(0, activeSideSpeakPresses - 1)
                speechService.stopListening { transcript in
                    if isOpposition {
                        handleTeamVoiceTranscript(transcript, isOpposition: true)
                    } else {
                        handleVoiceTranscript(transcript)
                    }
                }
            } else {
                activeSideSpeakPresses = max(0, activeSideSpeakPresses - 1)
            }
        }, perform: {})
        .buttonStyle(.plain)
    }

    private var shouldShowSideSpeakMicOverlay: Bool {
        activeSideSpeakPresses > 0
    }

    private var sideSpeakMicOverlay: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 150, weight: .black))
            .foregroundStyle(.red)
            .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .animation(.easeInOut(duration: 0.12), value: shouldShowSideSpeakMicOverlay)
    }

    private func addRushedBehindForOurTeam() {
        guard let behindType = statType(named: "Behind", fallbackName: "Scores", extraFallbackNames: ["Goal"]) else {
            showStatusBanner(text: "ERROR • Behind stat unavailable", isSuccess: false)
            return
        }
        addTeamEvent(
            statTypeId: behindType.id,
            isOpposition: false,
            scoreKind: "rushed behind"
        )
    }

    private var gradeName: String {
        grades.first(where: { $0.id == session.gradeId })?.name ?? "Unknown Grade"
    }

    private func recentEventStatLabel(_ event: StatEvent) -> String {
        let base = statName(for: event.statTypeId)
        guard normalizedStatName(base) == "scores" else { return base }
        let normalizedTranscript = normalizedStatName(event.transcript ?? "")
        if normalizedTranscript == "goal" { return "Goal" }
        if normalizedTranscript == "behind" || normalizedTranscript == "rushed behind" { return "Behind" }
        return base
    }

    private var speechVocabulary: [String] {
        let statPhrases = enabledStatTypes.flatMap { $0.voiceAliases }
        let votePhrases = SpeechVoteSection.all.flatMap { section in
            section.defaultAliases + SpeechDetectedWordsStore.words(forSectionKey: section.key)
        }
        let rosterPhrases = playersForGrade.flatMap { player -> [String] in
            var values = [player.name, player.displayFirstName, player.firstName, player.lastName]
            if let number = player.number {
                values.append("number \(number)")
                values.append("no \(number)")
                values.append(String(number))
            }
            return values
        }
        return Array(Set(statPhrases + votePhrases + rosterPhrases)).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var totalsRows: [TotalsRow] {
        displayedPlayers.map { player in
            let events = sessionEvents.filter { $0.playerId == player.id }
            var counts: [UUID: Int] = [:]
            for event in events {
                counts[event.statTypeId, default: 0] += 1
            }
            return TotalsRow(player: player, countsByStatId: counts, events: events)
        }
    }

    private var liveLeaderboardRows: [LiveLeaderboardRow] {
        totalsRows
            .map { row in
                let kicks = count(for: "kick", in: row)
                let handballs = count(for: "handball", in: row)
                let goals = count(for: "goal", in: row)
                let behinds = count(for: "behind", in: row)
                return LiveLeaderboardRow(
                    id: row.player.id,
                    playerLabel: playerNameDisplay(row.player),
                    kicks: kicks,
                    handballs: handballs,
                    possessions: kicks + handballs,
                    goals: goals,
                    behinds: behinds
                )
            }
            .sorted { lhs, rhs in
                if lhs.possessions != rhs.possessions { return lhs.possessions > rhs.possessions }
                return lhs.playerLabel.localizedCaseInsensitiveCompare(rhs.playerLabel) == .orderedAscending
            }
    }

    private var syncedLiveGameGoalKickerRows: [LiveLeaderboardRow] {
        guard let snapshot = syncedLiveGameSnapshot else { return [] }

        return snapshot.goalKickers.compactMap { kicker in
            guard let player = allPlayers.first(where: { $0.id == kicker.playerID }) else { return nil }

            let existingRow = liveLeaderboardRows.first(where: { $0.id == kicker.playerID })
            return LiveLeaderboardRow(
                id: kicker.playerID,
                playerLabel: playerNameDisplay(player),
                kicks: existingRow?.kicks ?? 0,
                handballs: existingRow?.handballs ?? 0,
                possessions: existingRow?.possessions ?? 0,
                goals: max(0, kicker.goals),
                behinds: max(0, kicker.points)
            )
        }
    }

    private var topPossessionGetters: [LiveLeaderboardRow] {
        liveLeaderboardRows
            .filter { $0.possessions > 0 }
            .prefix(5)
            .map { $0 }
    }

    private var topGoalKickers: [LiveLeaderboardRow] {
        let sourceRows = syncedLiveGameGoalKickerRows.isEmpty ? liveLeaderboardRows : syncedLiveGameGoalKickerRows
        return sourceRows
            .filter { $0.goals > 0 || $0.behinds > 0 }
            .sorted { lhs, rhs in
                if lhs.goals != rhs.goals { return lhs.goals > rhs.goals }
                if lhs.behinds != rhs.behinds { return lhs.behinds > rhs.behinds }
                return lhs.playerLabel.localizedCaseInsensitiveCompare(rhs.playerLabel) == .orderedAscending
            }
            .prefix(5)
            .map { $0 }
    }

    private var playerStatTypes: [StatType] {
        enabledStatTypes.filter { statCollectionMode(for: $0) == .individual }
    }

    private func ensureSimpleLayoutSelection() {
        guard isSimpleLayoutActive, !oppositionTrackPossessions, selectedPlayerId == nil else { return }
        selectedPlayerId = displayedPlayers.first?.id
    }

    private func statType(named name: String, fallbackName: String? = nil, extraFallbackNames: [String] = []) -> StatType? {
        let target = normalizedStatName(name)
        if let primary = enabledStatTypes.first(where: { normalizedStatName($0.name) == target }) {
            return primary
        }
        let fallbacks = ([fallbackName].compactMap { $0 } + extraFallbackNames).map(normalizedStatName)
        for fallback in fallbacks {
            if let stat = enabledStatTypes.first(where: { normalizedStatName($0.name) == fallback }) {
                return stat
            }
        }
        return nil
    }

    private func normalizedStatName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func count(for statName: String, in row: TotalsRow) -> Int {
        let normalizedName = normalizedStatName(statName)
        let directCount = statTypes(named: [normalizedName]).reduce(0) { partialResult, statType in
            partialResult + row.countsByStatId[statType.id, default: 0]
        }

        let scoresCount = statTypes(named: ["scores"]).reduce(0) { partialResult, statType in
            partialResult + row.events.filter {
                $0.statTypeId == statType.id && normalizedStatName($0.transcript ?? "") == normalizedName
            }.count
        }

        return directCount + scoresCount
    }

    private func statTypes(named names: [String]) -> [StatType] {
        let normalizedNames = Set(names.map(normalizedStatName))
        return enabledStatTypes.filter { normalizedNames.contains(normalizedStatName($0.name)) }
    }

    private func playerDisplay(_ player: Player) -> String {
        if let number = player.number {
            return "\(number) \(player.name)"
        }
        return player.name
    }

    private func playerNameDisplay(_ player: Player) -> String {
        player.name
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

    private var liveLeadersPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            liveLeaderboardColumn(
                title: "Top 5 Goal Kickers",
                entries: topGoalKickers.map {
                    ($0.playerLabel, "\($0.goals)", nil)
                },
                emptyText: "No goals yet."
            )
            liveLeaderboardColumn(
                title: "Top 5 Possession Getters",
                entries: topPossessionGetters.map {
                    ($0.playerLabel, "\($0.possessions)", nil)
                },
                emptyText: "No possessions yet."
            )
        }
    }

    private func liveLeaderboardColumn(
        title: String,
        entries: [(name: String, value: String, detail: String?)],
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.black))
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if entries.isEmpty {
                Spacer(minLength: 0)
                Text(emptyText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    HStack(alignment: .center, spacing: 10) {
                        Text("\(index + 1).")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .font(.title3.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            if let detail = entry.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.headline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 8)

                        Text(entry.value)
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(height: 46)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private struct PlayerQuickStatOption: Identifiable {
        let id: String
        let title: String
        let transcript: String?
        let statType: StatType?
    }

    private var playerQuickStatOptions: [PlayerQuickStatOption] {
        [
            PlayerQuickStatOption(
                id: "kick",
                title: "Kick",
                transcript: nil,
                statType: statType(named: "Kick")
            ),
            PlayerQuickStatOption(
                id: "handball",
                title: "Handball",
                transcript: nil,
                statType: statType(named: "Handball")
            ),
            PlayerQuickStatOption(
                id: "mark",
                title: "Mark",
                transcript: nil,
                statType: statType(named: "Mark")
            ),
            PlayerQuickStatOption(
                id: "tackle",
                title: "Tackle",
                transcript: nil,
                statType: statType(named: "Tackle")
            ),
            PlayerQuickStatOption(
                id: "goal",
                title: "Goal",
                transcript: "goal",
                statType: statType(named: "Goal", fallbackName: "Scores", extraFallbackNames: ["Behind"])
            ),
            PlayerQuickStatOption(
                id: "behind",
                title: "Point",
                transcript: "behind",
                statType: statType(named: "Behind", fallbackName: "Scores", extraFallbackNames: ["Goal"])
            )
        ]
        .filter { $0.statType != nil }
    }

    private func playerQuickStatsFan(cardSize: CGSize, globalMidX: CGFloat) -> some View {
        let layout = quickStatPieLayout(cardSize: cardSize, globalMidX: globalMidX)
        let selectedFirstTierAngle = selectedQuickStatMidAngle(layout: layout)
        let contestedLayout = votePopupPieLayout(primaryLayout: layout, selectedAngle: selectedFirstTierAngle, tier: 1)
        let selectedSecondTierAngle = selectedVoteMidAngle(
            layout: contestedLayout,
            leftSelected: hoveredPlayerQuickContestedVote == .contested,
            rightSelected: hoveredPlayerQuickContestedVote == .uncontested
        )
        let efficiencyLayout = votePopupPieLayout(primaryLayout: layout, selectedAngle: selectedSecondTierAngle, tier: 2)
        return ZStack {
            ForEach(Array(playerQuickStatOptions.enumerated()), id: \.element.id) { index, option in
                let isHovered = hoveredPlayerQuickStatName == option.id
                let isConnectedAssignment = option.statType.map {
                    isConnectedAssignedStat(statTypeID: $0.id, side: .ourClub)
                } ?? false
                let segment = quickStatSegmentAngles(index: index, total: playerQuickStatOptions.count, spanStart: layout.startAngle, spanEnd: layout.endAngle)
                let midAngle = (segment.start + segment.end) / 2
                let labelRadius = (layout.innerRadius + layout.outerRadius) / 2
                let labelWidth = quickStatLabelWidth(radius: labelRadius, startAngle: segment.start, endAngle: segment.end, minimum: 88, maximum: 126)

                QuickStatPieSlice(startAngle: segment.start, endAngle: segment.end, innerRadius: layout.innerRadius, outerRadius: layout.outerRadius)
                    .fill(isHovered ? Color.blue : (option.statType == nil ? Color.gray.opacity(0.32) : Color.gray.opacity(0.56)))
                    .overlay {
                        QuickStatPieSlice(startAngle: segment.start, endAngle: segment.end, innerRadius: layout.innerRadius, outerRadius: layout.outerRadius)
                            .stroke(
                                isConnectedAssignment ? Color.blue : Color.white.opacity(isHovered ? 0.8 : 0.45),
                                lineWidth: isConnectedAssignment ? 3 : (isHovered ? 2.5 : 1.2)
                            )
                    }
                    .overlay {
                        sliceLabel(
                            option.title,
                            center: layout.center,
                            radius: labelRadius,
                            angle: midAngle,
                            width: labelWidth,
                            font: .headline.weight(.semibold)
                        )
                    }
            }

            if shouldShowContestedPopup {
                votePiePopup(
                    leftTitle: "Contested",
                    leftActive: hoveredPlayerQuickContestedVote == .contested,
                    rightTitle: "Uncontested",
                    rightActive: hoveredPlayerQuickContestedVote == .uncontested,
                    layout: contestedLayout
                )
            }

            if shouldShowEfficiencyPopup {
                votePiePopup(
                    leftTitle: "Effective",
                    leftActive: hoveredPlayerQuickEfficiencyVote == .thumbsUp,
                    rightTitle: "Non Effective",
                    rightActive: hoveredPlayerQuickEfficiencyVote == .thumbsDown,
                    layout: efficiencyLayout
                )
            }
        }
    }

    private func votePiePopup(
        leftTitle: String,
        leftActive: Bool,
        rightTitle: String,
        rightActive: Bool,
        layout: (center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, startAngle: CGFloat, endAngle: CGFloat)
    ) -> some View {
        return ZStack {
            ForEach(0..<2, id: \.self) { idx in
                let segment = quickStatSegmentAngles(index: idx, total: 2, spanStart: layout.startAngle, spanEnd: layout.endAngle)
                let isActive = idx == 0 ? leftActive : rightActive
                let title = idx == 0 ? leftTitle : rightTitle
                let midAngle = (segment.start + segment.end) / 2
                let labelRadius = (layout.innerRadius + layout.outerRadius) / 2
                let labelWidth = quickStatLabelWidth(radius: labelRadius, startAngle: segment.start, endAngle: segment.end, minimum: 88, maximum: 112)
                QuickStatPieSlice(startAngle: segment.start, endAngle: segment.end, innerRadius: layout.innerRadius, outerRadius: layout.outerRadius)
                    .fill(isActive ? Color.blue : Color.gray.opacity(0.56))
                    .overlay {
                        QuickStatPieSlice(startAngle: segment.start, endAngle: segment.end, innerRadius: layout.innerRadius, outerRadius: layout.outerRadius)
                            .stroke(Color.white.opacity(isActive ? 0.8 : 0.45), lineWidth: isActive ? 2.3 : 1.1)
                    }
                    .overlay {
                        sliceLabel(
                            title,
                            center: layout.center,
                            radius: labelRadius,
                            angle: midAngle,
                            width: labelWidth,
                            font: .subheadline.weight(.bold)
                        )
                    }
            }
        }
    }

    private var shouldShowContestedPopup: Bool {
        guard let statID = hoveredPlayerQuickStatName else { return false }
        let contestedEnabled = activePlayerQuickStatsPlayerID == oppositionTeamStatPlayerID
            ? sessionTracksContestedPossessionVotes(isOpposition: true)
            : sessionTracksContestedPossessionVotes()
        return needsQuickStatContestedVote(for: statID, trackingEnabled: nil) && contestedEnabled
    }

    private var shouldShowEfficiencyPopup: Bool {
        guard let statID = hoveredPlayerQuickStatName else { return false }
        let efficiencyEnabled = activePlayerQuickStatsPlayerID == oppositionTeamStatPlayerID
            ? sessionTracksDisposalEfficiencyVotes(isOpposition: true)
            : sessionTracksDisposalEfficiencyVotes()
        let contestedEnabled = activePlayerQuickStatsPlayerID == oppositionTeamStatPlayerID
            ? sessionTracksContestedPossessionVotes(isOpposition: true)
            : sessionTracksContestedPossessionVotes()
        guard needsQuickStatEfficiencyVote(for: statID, trackingEnabled: nil), efficiencyEnabled else { return false }
        if contestedEnabled {
            return hoveredPlayerQuickContestedVote != nil
        }
        return true
    }

    private func quickStatPieLayout(cardSize: CGSize, globalMidX: CGFloat) -> (center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, startAngle: CGFloat, endAngle: CGFloat) {
        let innerRadius: CGFloat = 82
        let outerRadius: CGFloat = 182

        // Anchor the pie to the pressed player button center.
        let center = CGPoint(x: cardSize.width / 2, y: cardSize.height / 2)
        if globalMidX < 210 {
            return (center, innerRadius, outerRadius, -95, 95)
        }
        if globalMidX > interfaceScreenWidth - 210 {
            return (center, innerRadius, outerRadius, 85, 275)
        }
        return (center, innerRadius, outerRadius, -180, 0)
    }

    private func quickStatLabelWidth(radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        let spanRadians = abs(endAngle - startAngle) * (.pi / 180)
        let arcLength = radius * spanRadians
        return min(maximum, max(minimum, arcLength * 0.72))
    }

    private func quickStatSegmentAngles(index: Int, total: Int, spanStart: CGFloat, spanEnd: CGFloat) -> (start: CGFloat, end: CGFloat) {
        let span = (spanEnd - spanStart) / CGFloat(max(total, 1))
        let start = spanStart + (span * CGFloat(index))
        return (start, start + span)
    }

    private func votePopupPieLayout(
        primaryLayout: (center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, startAngle: CGFloat, endAngle: CGFloat),
        selectedAngle: CGFloat,
        tier: Int
    ) -> (center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, startAngle: CGFloat, endAngle: CGFloat) {
        let ringThickness: CGFloat = 78
        let ringSpacing: CGFloat = 2
        let inner = primaryLayout.outerRadius + ringSpacing + (CGFloat(max(tier - 1, 0)) * (ringThickness + ringSpacing))
        let outer = inner + ringThickness
        let halfSpan: CGFloat = 34
        return (center: primaryLayout.center, innerRadius: inner, outerRadius: outer, startAngle: selectedAngle - halfSpan, endAngle: selectedAngle + halfSpan)
    }

    private func polarPoint(center: CGPoint, radius: CGFloat, angleDegrees: CGFloat) -> CGPoint {
        let radians = angleDegrees * (.pi / 180)
        return CGPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
    }

    private func sliceLabel(
        _ text: String,
        center: CGPoint,
        radius: CGFloat,
        angle: CGFloat,
        width: CGFloat,
        font: Font
    ) -> some View {
        let point = polarPoint(center: center, radius: radius, angleDegrees: angle)
        return Text(text)
            .font(font)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .allowsTightening(true)
            .lineLimit(2)
            .minimumScaleFactor(0.68)
            .frame(width: width)
            .rotationEffect(labelRotation(for: angle))
            .position(x: point.x, y: point.y)
    }

    private func labelRotation(for angle: CGFloat) -> Angle {
        let tangent = angle + 90
        let normalized = normalizedAngle(tangent)
        let upright = (normalized > 90 && normalized < 270) ? tangent + 180 : tangent
        return .degrees(upright)
    }

    private func sliceLockedLabel(
        _ text: String,
        center: CGPoint,
        radius: CGFloat,
        angle: CGFloat,
        width: CGFloat,
        font: Font,
        segment: (start: CGFloat, end: CGFloat),
        innerRadius: CGFloat,
        outerRadius: CGFloat
    ) -> some View {
        sliceLabel(text, center: center, radius: radius, angle: angle, width: width, font: font)
            .clipShape(
                QuickStatPieSlice(
                    startAngle: segment.start,
                    endAngle: segment.end,
                    innerRadius: innerRadius,
                    outerRadius: outerRadius
                )
            )
    }

    private func selectedQuickStatMidAngle(layout: (center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, startAngle: CGFloat, endAngle: CGFloat)) -> CGFloat {
        guard let idx = hoveredQuickStatIndex else { return (layout.startAngle + layout.endAngle) / 2 }
        let segment = quickStatSegmentAngles(index: idx, total: playerQuickStatOptions.count, spanStart: layout.startAngle, spanEnd: layout.endAngle)
        return (segment.start + segment.end) / 2
    }

    private func selectedVoteMidAngle(
        layout: (center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, startAngle: CGFloat, endAngle: CGFloat),
        leftSelected: Bool,
        rightSelected: Bool
    ) -> CGFloat {
        if leftSelected {
            let segment = quickStatSegmentAngles(index: 0, total: 2, spanStart: layout.startAngle, spanEnd: layout.endAngle)
            return (segment.start + segment.end) / 2
        }
        if rightSelected {
            let segment = quickStatSegmentAngles(index: 1, total: 2, spanStart: layout.startAngle, spanEnd: layout.endAngle)
            return (segment.start + segment.end) / 2
        }
        return (layout.startAngle + layout.endAngle) / 2
    }

    private func unitDirection(angleDegrees: CGFloat) -> CGVector {
        let radians = angleDegrees * (.pi / 180)
        return CGVector(dx: cos(radians), dy: sin(radians))
    }

    private func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        return normalized
    }

    private func angleIsWithinSpan(_ angle: CGFloat, start: CGFloat, end: CGFloat) -> Bool {
        let currentAngle = normalizedAngle(angle)
        let normalizedStart = normalizedAngle(start)
        let normalizedEnd = normalizedAngle(end)
        if normalizedStart <= normalizedEnd {
            return currentAngle >= normalizedStart && currentAngle <= normalizedEnd
        }
        return currentAngle >= normalizedStart || currentAngle <= normalizedEnd
    }

    private func hoveredQuickStatAnchor(layout: (center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, startAngle: CGFloat, endAngle: CGFloat)) -> CGPoint {
        guard let idx = hoveredQuickStatIndex else {
            return polarPoint(
                center: layout.center,
                radius: (layout.innerRadius + layout.outerRadius) / 2,
                angleDegrees: (layout.startAngle + layout.endAngle) / 2
            )
        }
        let segment = quickStatSegmentAngles(index: idx, total: playerQuickStatOptions.count, spanStart: layout.startAngle, spanEnd: layout.endAngle)
        return polarPoint(center: layout.center, radius: (layout.innerRadius + layout.outerRadius) / 2, angleDegrees: (segment.start + segment.end) / 2)
    }

    private var hoveredQuickStatIndex: Int? {
        guard let hoveredPlayerQuickStatName else { return nil }
        return playerQuickStatOptions.firstIndex(where: { $0.id == hoveredPlayerQuickStatName })
    }

    private func updateQuickStatHover(location: CGPoint, cardSize: CGSize) {
        let previousQuickStatName = hoveredPlayerQuickStatName
        let previousContestedVote = hoveredPlayerQuickContestedVote
        let previousEfficiencyVote = hoveredPlayerQuickEfficiencyVote
        let isOppositionQuick = activePlayerQuickStatsPlayerID == oppositionTeamStatPlayerID
        let contestedEnabled = isOppositionQuick ? sessionTracksContestedPossessions(isOpposition: true) : sessionTracksContestedPossessions
        let efficiencyEnabled = isOppositionQuick ? sessionTracksDisposalEfficiency(isOpposition: true) : sessionTracksDisposalEfficiency
        let globalMidX = activePlayerQuickCardFrameGlobal == .zero ? (interfaceScreenWidth / 2) : activePlayerQuickCardFrameGlobal.midX
        let layout = quickStatPieLayout(cardSize: cardSize, globalMidX: globalMidX)
        let distance = hypot(location.x - layout.center.x, location.y - layout.center.y)
        let angle = atan2(location.y - layout.center.y, location.x - layout.center.x) * 180 / .pi
        let inPieBand = distance >= layout.innerRadius && distance <= layout.outerRadius

        if inPieBand,
           let statIndex = (0..<playerQuickStatOptions.count).first(where: { idx in
               let segment = quickStatSegmentAngles(index: idx, total: playerQuickStatOptions.count, spanStart: layout.startAngle, spanEnd: layout.endAngle)
               return angleIsWithinSpan(angle, start: segment.start, end: segment.end)
           }) {
            hoveredPlayerQuickStatName = playerQuickStatOptions[statIndex].id
            hoveredPlayerQuickContestedVote = nil
            hoveredPlayerQuickEfficiencyVote = nil
            triggerQuickSelectionHapticIfNeeded(
                previousQuickStatName: previousQuickStatName,
                previousContestedVote: previousContestedVote,
                previousEfficiencyVote: previousEfficiencyVote
            )
            return
        }

        guard let statID = hoveredPlayerQuickStatName, needsQuickStatVotes(for: statID) else { return }
        let requiresContestedVote = needsQuickStatContestedVote(for: statID, trackingEnabled: contestedEnabled)
        let requiresEfficiencyVote = needsQuickStatEfficiencyVote(for: statID, trackingEnabled: efficiencyEnabled)

        let selectedFirstTierAngle = selectedQuickStatMidAngle(layout: layout)
        let contestedLayout = votePopupPieLayout(primaryLayout: layout, selectedAngle: selectedFirstTierAngle, tier: 1)
        if contestedEnabled && requiresContestedVote {
            let selection = votePopupSelectionIndex(location: location, layout: contestedLayout)
            if selection == 0 {
                hoveredPlayerQuickContestedVote = .contested
            } else if selection == 1 {
                hoveredPlayerQuickContestedVote = .uncontested
            }
        }

        if !requiresEfficiencyVote { return }
        if contestedEnabled && requiresContestedVote && hoveredPlayerQuickContestedVote == nil { return }

        let selectedSecondTierAngle = selectedVoteMidAngle(
            layout: contestedLayout,
            leftSelected: hoveredPlayerQuickContestedVote == .contested,
            rightSelected: hoveredPlayerQuickContestedVote == .uncontested
        )
        let efficiencyLayout = votePopupPieLayout(primaryLayout: layout, selectedAngle: selectedSecondTierAngle, tier: 2)
        let efficiencySelection = votePopupSelectionIndex(location: location, layout: efficiencyLayout)
        if efficiencySelection == 0 {
            hoveredPlayerQuickEfficiencyVote = .thumbsUp
        } else if efficiencySelection == 1 {
            hoveredPlayerQuickEfficiencyVote = .thumbsDown
        }
        triggerQuickSelectionHapticIfNeeded(
            previousQuickStatName: previousQuickStatName,
            previousContestedVote: previousContestedVote,
            previousEfficiencyVote: previousEfficiencyVote
        )
    }

    private func votePopupSelectionIndex(
        location: CGPoint,
        layout: (center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, startAngle: CGFloat, endAngle: CGFloat)
    ) -> Int? {
        let distance = hypot(location.x - layout.center.x, location.y - layout.center.y)
        guard distance >= layout.innerRadius && distance <= layout.outerRadius else { return nil }
        let angle = atan2(location.y - layout.center.y, location.x - layout.center.x) * 180 / .pi
        return (0..<2).first { idx in
            let segment = quickStatSegmentAngles(index: idx, total: 2, spanStart: layout.startAngle, spanEnd: layout.endAngle)
            return angleIsWithinSpan(angle, start: segment.start, end: segment.end)
        }
    }

    private func needsQuickStatVotes(for statID: String) -> Bool {
        needsQuickStatEfficiencyVote(for: statID, trackingEnabled: nil)
            || needsQuickStatContestedVote(for: statID, trackingEnabled: nil)
    }

    private func needsQuickStatEfficiencyVote(for statID: String, trackingEnabled: Bool?) -> Bool {
        let trackingEnabled = trackingEnabled ?? sessionTracksDisposalEfficiencyVotes()
        return (statID == "kick" || statID == "handball") && trackingEnabled
    }

    private func needsQuickStatContestedVote(for statID: String, trackingEnabled: Bool?) -> Bool {
        let trackingEnabled = trackingEnabled ?? sessionTracksContestedPossessionVotes()
        return (statID == "kick" || statID == "mark" || statID == "handball") && trackingEnabled
    }

    private func commitPendingPlayerQuickStatIfValid(playerID: UUID) {
        guard
            let statID = hoveredPlayerQuickStatName,
            let option = playerQuickStatOptions.first(where: { $0.id == statID }),
            let statType = option.statType
        else {
            clearPendingPlayerQuickStat()
            return
        }

        let isOppositionQuick = playerID == oppositionTeamStatPlayerID
        let efficiencyEnabled = isOppositionQuick ? sessionTracksDisposalEfficiencyVotes(isOpposition: true) : sessionTracksDisposalEfficiencyVotes()
        let contestedEnabled = isOppositionQuick ? sessionTracksContestedPossessionVotes(isOpposition: true) : sessionTracksContestedPossessionVotes()
        let hasRequiredEfficiency = !needsQuickStatEfficiencyVote(for: statID, trackingEnabled: efficiencyEnabled) || hoveredPlayerQuickEfficiencyVote != nil
        let hasRequiredContested = !needsQuickStatContestedVote(for: statID, trackingEnabled: contestedEnabled) || hoveredPlayerQuickContestedVote != nil
        guard hasRequiredEfficiency && hasRequiredContested else { return }

        if playerID == oppositionTeamStatPlayerID {
            addTeamEvent(
                statTypeId: statType.id,
                isOpposition: true,
                scoreKind: option.transcript,
                efficiencyVote: hoveredPlayerQuickEfficiencyVote,
                contestedVote: hoveredPlayerQuickContestedVote
            )
        } else {
            addManualEvent(
                statTypeId: statType.id,
                playerID: playerID,
                transcript: option.transcript,
                efficiencyVote: hoveredPlayerQuickEfficiencyVote,
                contestedVote: hoveredPlayerQuickContestedVote
            )
        }
        clearPendingPlayerQuickStat()
        activePlayerQuickStatsPlayerID = nil
    }

    private func clearPendingPlayerQuickStat() {
        hoveredPlayerQuickStatName = nil
        hoveredPlayerQuickEfficiencyVote = nil
        hoveredPlayerQuickContestedVote = nil
        lastHapticQuickStatName = nil
        lastHapticQuickContestedVote = nil
        lastHapticQuickEfficiencyVote = nil
    }

    private func triggerStrongHaptic() {
        longPressHaptic.prepare()
        longPressHaptic.impactOccurred(intensity: 1.0)
    }

    private func triggerSelectionStepHaptic() {
        stepHaptic.prepare()
        stepHaptic.impactOccurred(intensity: 1.0)
    }

    private func triggerQuickSelectionHapticIfNeeded(
        previousQuickStatName: String?,
        previousContestedVote: ContestedPossessionVote?,
        previousEfficiencyVote: EfficiencyVote?
    ) {
        let didChangeQuickStat = hoveredPlayerQuickStatName != previousQuickStatName
        let didChangeContested = hoveredPlayerQuickContestedVote != previousContestedVote
        let didChangeEfficiency = hoveredPlayerQuickEfficiencyVote != previousEfficiencyVote
        guard didChangeQuickStat || didChangeContested || didChangeEfficiency else { return }

        let isSameAsLastHaptic =
            lastHapticQuickStatName == hoveredPlayerQuickStatName &&
            lastHapticQuickContestedVote == hoveredPlayerQuickContestedVote &&
            lastHapticQuickEfficiencyVote == hoveredPlayerQuickEfficiencyVote
        guard !isSameAsLastHaptic else { return }

        lastHapticQuickStatName = hoveredPlayerQuickStatName
        lastHapticQuickContestedVote = hoveredPlayerQuickContestedVote
        lastHapticQuickEfficiencyVote = hoveredPlayerQuickEfficiencyVote
        triggerSelectionStepHaptic()
    }

    private func configureQuarterTimer(reset: Bool) {
        if reset {
            stopQuarterTimer()
            remainingQuarterSeconds = quarterCountsUp ? 0 : customQuarterMinutes * 60
            quarterTimerAnchorUptime = nil
            quarterTimerAnchorSeconds = nil
        } else if !quarterCountsUp && remainingQuarterSeconds <= 0 {
            remainingQuarterSeconds = customQuarterMinutes * 60
            quarterTimerAnchorUptime = nil
            quarterTimerAnchorSeconds = nil
        }
    }

    private func startQuarterTimer() {
        if !quarterCountsUp && remainingQuarterSeconds == 0 {
            remainingQuarterSeconds = customQuarterMinutes * 60
        }
        guard !isQuarterTimerRunning else { return }
        quarterTimerAnchorSeconds = remainingQuarterSeconds
        quarterTimerAnchorUptime = ProcessInfo.processInfo.systemUptime
        isQuarterTimerRunning = true
        quarterTimerTask?.cancel()
        quarterTimerTask = Task {
            while !Task.isCancelled && isQuarterTimerRunning {
                try? await Task.sleep(nanoseconds: 250_000_000)
                await MainActor.run {
                    syncQuarterTimer()
                }
            }
        }
    }

    private func stopQuarterTimer() {
        syncQuarterTimer()
        isQuarterTimerRunning = false
        quarterTimerTask?.cancel()
        quarterTimerTask = nil
        quarterTimerAnchorUptime = nil
        quarterTimerAnchorSeconds = nil
    }

    private func syncQuarterTimer(referenceUptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard isQuarterTimerRunning,
              let anchorUptime = quarterTimerAnchorUptime,
              let anchorSeconds = quarterTimerAnchorSeconds else { return }
        let elapsedSeconds = max(0, Int(referenceUptime - anchorUptime))
        if quarterCountsUp {
            remainingQuarterSeconds = anchorSeconds + elapsedSeconds
        } else {
            remainingQuarterSeconds = anchorSeconds - elapsedSeconds
        }
    }

    private func statName(for id: UUID) -> String {
        if let known = allStatTypes.first(where: { $0.id == id })?.name,
           known.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return known
        }

        if let fallback = sessionStatNamesByID[id]?
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return fallback.capitalized
        }

        return "Unknown"
    }

    private func sortInviteSelections(_ selections: [StatsInviteSelection]) -> [StatsInviteSelection] {
        Array(Set(selections)).sorted { lhs, rhs in
            if lhs.side != rhs.side {
                return lhs.side == .ourClub
            }
            return statName(for: lhs.statTypeID).localizedCaseInsensitiveCompare(statName(for: rhs.statTypeID)) == .orderedAscending
        }
    }

    private func assignmentSummaryNames(for assignment: StatsInviteAssignment) -> [String] {
        let localNames = statsInviteSelectionNames(for: assignment.assignedSelections, statTypes: allStatTypes)
        if !localNames.isEmpty {
            return localNames
        }

        guard let cloudAssignment = cloudInviteAssignmentsByRecordName[assignment.cloudRecordName] else {
            return assignment.assignedSelections.isEmpty ? [] : ["\(assignment.assignedSelections.count) stats assigned"]
        }

        let syncedNames = cloudAssignment.assignedSelectionRawValues.compactMap {
            cloudAssignment.assignedSelectionDisplayNameByRawValue[$0]
        }
        if !syncedNames.isEmpty {
            return syncedNames
        }

        if !cloudAssignment.assignedSelectionDisplayNames.isEmpty {
            return cloudAssignment.assignedSelectionDisplayNames
        }

        return assignment.assignedSelections.isEmpty ? [] : ["\(assignment.assignedSelections.count) stats assigned"]
    }

    private func updateInviteAssignment(_ assignment: StatsInviteAssignment, selections: [StatsInviteSelection]) {
        let orderedSelections = sortInviteSelections(selections)
        let recordName = CloudKitStatsInviteService.recordName(
            sessionID: session.sessionId,
            inviteeEmail: assignment.inviteeEmail
        )
        let inviteeName = displayName(for: assignment)
        let selectionDisplayNamesByRawValue = statsInviteSelectionDisplayNamesByRawValue(
            for: orderedSelections,
            statTypes: enabledStatTypes
        )
        let rosterPlayers = cloudRosterPlayers(from: playersForGrade)
        let availablePlayerPayloadJSON = encodeRosterPlayers(rosterPlayers)

        assignment.inviteeName = inviteeName
        assignment.cloudRecordName = recordName
        assignment.sessionIDRaw = session.sessionId.uuidString
        assignment.setAssignedSelections(orderedSelections)
        try? modelContext.save()

        Task {
            do {
                _ = try? await CloudKitStatsInviteService.shared.saveSessionRoster(
                    sessionID: session.sessionId,
                    players: rosterPlayers
                )
                let selectionCollectionModesByRawValue = statsInviteSelectionCollectionModesByRawValue(
                    for: orderedSelections,
                    session: session,
                    statTypes: allStatTypes
                )
                let cloudAssignment = try await CloudKitStatsInviteService.shared.saveAssignment(
                    inviteeEmail: assignment.inviteeEmail,
                    inviteeName: inviteeName,
                    sessionID: session.sessionId,
                    gradeName: gradeName,
                    oppositionName: session.opposition,
                    venue: session.venue,
                    sessionDate: session.date,
                    assignedSelectionRawValues: orderedSelections.map(\.rawValue),
                    assignedSelectionDisplayNames: orderedSelections.map {
                        selectionDisplayNamesByRawValue[$0.rawValue] ?? $0.side.selectionPrefix
                    },
                    assignedSelectionCollectionModes: orderedSelections.map {
                        selectionCollectionModesByRawValue[$0.rawValue] ?? SessionStatCollectionMode.team.rawValue
                    },
                    availablePlayerPayloadJSON: availablePlayerPayloadJSON
                )

                await MainActor.run {
                    cloudInviteAssignmentsByRecordName[cloudAssignment.id] = cloudAssignment
                    assignment.lastInvitedAt = cloudAssignment.lastInvitedAt
                    assignment.isConnected = cloudAssignment.hasConnected
                    assignment.lastConnectedAt = cloudAssignment.lastConnectedAt
                    try? modelContext.save()
                    showStatusBanner(text: "STAT TAKER ASSIGNMENTS UPDATED", isSuccess: true)
                }
            } catch {
                await MainActor.run {
                    showStatusBanner(text: "FAILED TO UPDATE ASSIGNMENTS • \(error.localizedDescription)", isSuccess: false)
                }
            }
        }
    }

    private func addManualEvent(
        statTypeId: UUID,
        playerID: UUID? = nil,
        transcript: String? = nil,
        efficiencyVote: EfficiencyVote? = nil,
        contestedVote: ContestedPossessionVote? = nil
    ) {
        guard let currentSelectedPlayerId = playerID ?? selectedPlayerId else {
            lastMessage = "Select a player first"
            showStatusBanner(text: "ERROR • Select a player first", isSuccess: false)
            feedbackToken = UUID()
            return
        }

        let event = StatEvent(
            sessionId: session.sessionId,
            playerId: currentSelectedPlayerId,
            statTypeId: statTypeId,
            quarter: selectedQuarter,
            sourceRaw: StatsEventSource.manual.rawValue,
            transcript: transcript
        )
        if let efficiencyVote {
            event.efficiencyVoteRaw = efficiencyVote.rawValue
        }
        if let contestedVote {
            event.contestedVoteRaw = contestedVote.rawValue
        }
        modelContext.insert(event)
        try? modelContext.save()

        let shouldDelaySuccessBanner = promptEfficiencyVoteIfNeeded(for: event, preselectedVote: efficiencyVote)
        if !isSimpleLayoutActive {
            selectedPlayerId = nil
        }

        lastMessage = "Added: \(statName(for: statTypeId)) — \(playerLabel(for: currentSelectedPlayerId)) — \(selectedQuarter)"
        if !shouldDelaySuccessBanner {
            showSuccessBanner(for: event)
        }
        feedbackToken = UUID()
    }

    private func addTeamEvent(
        statTypeId: UUID,
        isOpposition: Bool,
        scoreKind: String? = nil,
        efficiencyVote: EfficiencyVote? = nil,
        contestedVote: ContestedPossessionVote? = nil
    ) {
        let playerID = isOpposition ? oppositionTeamStatPlayerID : ourTeamStatPlayerID
        let event = StatEvent(
            sessionId: session.sessionId,
            playerId: playerID,
            statTypeId: statTypeId,
            quarter: selectedQuarter,
            sourceRaw: StatsEventSource.manual.rawValue,
            transcript: scoreKind
        )
        if let efficiencyVote {
            event.efficiencyVoteRaw = efficiencyVote.rawValue
        }
        if let contestedVote {
            event.contestedVoteRaw = contestedVote.rawValue
        }
        modelContext.insert(event)
        try? modelContext.save()
        lastMessage = "Added: \(statName(for: statTypeId)) — \(isOpposition ? session.opposition : ourTeamName) — \(selectedQuarter)"
        let shouldDelaySuccessBanner = promptEfficiencyVoteIfNeeded(for: event, preselectedVote: efficiencyVote)
        if !shouldDelaySuccessBanner {
            showSuccessBanner(for: event)
        }
        feedbackToken = UUID()
    }

    private func sendInvite(contact: PhoneInviteContact, selections: Set<StatsInviteSelection>) {
        guard !selections.isEmpty else { return }
        let statTypes = enabledStatTypes
        let testFlightURL = (UserDefaults.standard.string(forKey: "app.testFlightURL") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionLine = "\(gradeName) vs \(session.opposition) • \(session.date.formatted(date: .abbreviated, time: .omitted))"
        let recordName = CloudKitStatsInviteService.recordName(sessionID: session.sessionId, inviteeEmail: contact.email)
        let assignment: StatsInviteAssignment

        if let existing = inviteAssignments.first(where: { $0.cloudRecordName == recordName }) {
            assignment = existing
            assignment.inviteeEmail = contact.email
            assignment.inviteeName = contact.displayName
            assignment.cloudRecordName = recordName
            assignment.sessionIDRaw = session.sessionId.uuidString
            assignment.sessionSummary = sessionLine
            assignment.inviteLinkToken = ""
            assignment.inviteLinkURL = ""
            assignment.lastInvitedAt = Date()
            assignment.setAssignedSelections(Array(selections))
        } else {
            assignment = StatsInviteAssignment(
                contactId: UUID(),
                assignedStatTypeIDsRaw: Array(selections).map(\.rawValue).joined(separator: ","),
                inviteLinkToken: "",
                inviteLinkURL: "",
                inviteeEmail: contact.email,
                inviteeName: contact.displayName,
                cloudRecordName: recordName,
                sessionIDRaw: session.sessionId.uuidString,
                sessionSummary: sessionLine,
                lastInvitedAt: Date()
            )
            modelContext.insert(assignment)
        }

        let assignedNames = statsInviteSelectionNames(
            for: Array(selections).sorted {
                if $0.side != $1.side {
                    return $0.side == .ourClub
                }
                return statName(for: $0.statTypeID) < statName(for: $1.statTypeID)
            },
            statTypes: enabledStatTypes
        ).joined(separator: ", ")

        composedShareText = buildStatsInviteMessage(
            recipient: contact,
            sessionID: session.sessionId,
            recordName: recordName,
            sessionLine: sessionLine,
            assignedNames: assignedNames,
            testFlightURL: testFlightURL
        )
        try? modelContext.save()

        Task {
            let orderedSelections = Array(selections)
            let selectionDisplayNamesByRawValue = statsInviteSelectionDisplayNamesByRawValue(
                for: orderedSelections,
                statTypes: statTypes
            )
            let selectionCollectionModesByRawValue = statsInviteSelectionCollectionModesByRawValue(
                for: orderedSelections,
                session: session,
                statTypes: statTypes
            )
            let rosterPlayers = cloudRosterPlayers(from: playersForGrade)
            let availablePlayerPayloadJSON = encodeRosterPlayers(rosterPlayers)
            do {
                _ = try? await CloudKitStatsInviteService.shared.saveSessionRoster(
                    sessionID: session.sessionId,
                    players: rosterPlayers
                )
                _ = try await CloudKitUserAccessService.shared.inviteUser(
                    email: contact.email,
                    role: .statTaker
                )
                let cloudAssignment = try await CloudKitStatsInviteService.shared.saveAssignment(
                    inviteeEmail: contact.email,
                    inviteeName: contact.displayName,
                    sessionID: session.sessionId,
                    gradeName: gradeName,
                    oppositionName: session.opposition,
                    venue: session.venue,
                    sessionDate: session.date,
                    assignedSelectionRawValues: orderedSelections.map(\.rawValue),
                    assignedSelectionDisplayNames: orderedSelections.map { selectionDisplayNamesByRawValue[$0.rawValue] ?? $0.side.selectionPrefix },
                    assignedSelectionCollectionModes: orderedSelections.map {
                        selectionCollectionModesByRawValue[$0.rawValue] ?? SessionStatCollectionMode.team.rawValue
                    },
                    availablePlayerPayloadJSON: availablePlayerPayloadJSON
                )
                await MainActor.run {
                    cloudInviteAssignmentsByRecordName[cloudAssignment.id] = cloudAssignment
                    assignment.lastInvitedAt = cloudAssignment.lastInvitedAt
                    assignment.isConnected = cloudAssignment.hasConnected
                    assignment.lastConnectedAt = cloudAssignment.lastConnectedAt
                    try? modelContext.save()
                }
            } catch {
                await MainActor.run {
                    showStatusBanner(text: "CLOUDKIT INVITE FAILED • \(error.localizedDescription)", isSuccess: false)
                }
            }
        }
    }

    private func monitorInviteConnectionStatuses() async {
        await refreshInviteConnectionStatuses()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            await refreshInviteConnectionStatuses()
        }
    }

    @MainActor
    private func refreshInviteConnectionStatuses() async {
        let sessionAssignments = inviteAssignments.filter {
            $0.sessionIDRaw == session.sessionId.uuidString && !$0.cloudRecordName.isEmpty
        }
        let recordNames = Array(Set(sessionAssignments.map(\.cloudRecordName)))
        guard !recordNames.isEmpty else { return }

        do {
            let cloudAssignments = try await CloudKitStatsInviteService.shared.fetchAssignments(recordNames: recordNames)
            let assignmentsByRecordName = cloudAssignments.reduce(into: [String: CloudStatsInviteAssignment]()) { result, assignment in
                result[assignment.id] = assignment
            }
            cloudInviteAssignmentsByRecordName = assignmentsByRecordName
            backfillMissingCloudRostersIfNeeded(
                sessionAssignments: sessionAssignments,
                assignmentsByRecordName: assignmentsByRecordName
            )
            var didChange = false

            for assignment in sessionAssignments {
                guard let cloudAssignment = assignmentsByRecordName[assignment.cloudRecordName] else { continue }
                let syncedSelectionsRaw = cloudAssignment.assignedSelectionRawValues.joined(separator: ",")
                if assignment.assignedStatTypeIDsRaw != syncedSelectionsRaw {
                    assignment.assignedStatTypeIDsRaw = syncedSelectionsRaw
                    didChange = true
                }
                if assignment.isConnected != cloudAssignment.hasConnected {
                    assignment.isConnected = cloudAssignment.hasConnected
                    didChange = true
                }
                if assignment.lastConnectedAt != cloudAssignment.lastConnectedAt {
                    assignment.lastConnectedAt = cloudAssignment.lastConnectedAt
                    didChange = true
                }
                if assignment.lastInvitedAt != cloudAssignment.lastInvitedAt {
                    assignment.lastInvitedAt = cloudAssignment.lastInvitedAt
                    didChange = true
                }
            }

            if didChange {
                try? modelContext.save()
            }
        } catch {
            return
        }
    }

    private func backfillMissingCloudRostersIfNeeded(
        sessionAssignments: [StatsInviteAssignment],
        assignmentsByRecordName: [String: CloudStatsInviteAssignment]
    ) {
        let rosterPlayers = cloudRosterPlayers(from: playersForGrade)
        guard !rosterPlayers.isEmpty else { return }

        let assignmentsNeedingBackfill = sessionAssignments.compactMap { assignment -> CloudStatsInviteAssignment? in
            guard let cloudAssignment = assignmentsByRecordName[assignment.cloudRecordName] else { return nil }
            return cloudAssignment.availablePlayers.isEmpty ? cloudAssignment : nil
        }

        guard !assignmentsNeedingBackfill.isEmpty else { return }

        let availablePlayerPayloadJSON = encodeRosterPlayers(rosterPlayers)
        Task {
            _ = try? await CloudKitStatsInviteService.shared.saveSessionRoster(
                sessionID: session.sessionId,
                players: rosterPlayers
            )

            for cloudAssignment in assignmentsNeedingBackfill {
                _ = try? await CloudKitStatsInviteService.shared.saveAssignment(
                    inviteeEmail: cloudAssignment.inviteeEmail,
                    inviteeName: cloudAssignment.inviteeName,
                    sessionID: cloudAssignment.sessionID,
                    gradeName: cloudAssignment.gradeName,
                    oppositionName: cloudAssignment.oppositionName,
                    venue: cloudAssignment.venue,
                    sessionDate: cloudAssignment.sessionDate,
                    assignedSelectionRawValues: cloudAssignment.assignedSelectionRawValues,
                    assignedSelectionDisplayNames: cloudAssignment.assignedSelectionDisplayNames,
                    assignedSelectionCollectionModes: cloudAssignment.assignedSelectionCollectionModes,
                    availablePlayerPayloadJSON: availablePlayerPayloadJSON
                )
            }
        }
    }

    private func undoLastEvent() {
        guard let latest = sessionEvents.first else { return }
        modelContext.delete(latest)
        try? modelContext.save()
        lastMessage = "Undid last event"
        showStatusBanner(text: "UNDO • Last event removed", isSuccess: false)
        feedbackToken = UUID()
    }

    private func advanceQuarter() {
        let order = ["Q1", "Q2", "Q3", "Q4"]
        guard let index = order.firstIndex(of: selectedQuarter) else {
            selectedQuarter = "Q1"
            configureQuarterTimer(reset: true)
            return
        }
        selectedQuarter = order[min(index + 1, order.count - 1)]
        configureQuarterTimer(reset: true)
    }

    private func handleTeamVoiceTranscript(_ transcript: String, isOpposition: Bool) {
        let normalizedTranscript = normalizedStatName(transcript)
        guard !normalizedTranscript.isEmpty else { return }
        let rankedTypes = enabledStatTypes.sorted { lhs, rhs in
            let leftLen = lhs.voiceAliases.map { normalizedStatName($0).count }.max() ?? 0
            let rightLen = rhs.voiceAliases.map { normalizedStatName($0).count }.max() ?? 0
            return leftLen > rightLen
        }
        guard let matchedType = rankedTypes.first(where: { type in
            type.voiceAliases.contains { alias in
                let normalizedAlias = normalizedStatName(alias)
                return !normalizedAlias.isEmpty && normalizedTranscript.contains(normalizedAlias)
            }
        }) else {
            showStatusBanner(text: "ERROR • Stat type not recognised", isSuccess: false)
            return
        }

        let normalizedName = normalizedStatName(matchedType.name)
        let scoreKind = normalizedName == "scores" ? voiceScoreKind(in: normalizedTranscript) : nil
        addTeamEvent(statTypeId: matchedType.id, isOpposition: isOpposition, scoreKind: scoreKind)
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
                firstName: $0.displayFirstName,
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

        let scoreKind = normalizedStatName(statName(for: statTypeId)) == "scores"
            ? voiceScoreKind(in: result.normalizedTranscript)
            : nil

        let event = StatsEventCreationService.makeVoiceEvent(
            sessionId: session.sessionId,
            playerId: playerId,
            statTypeId: statTypeId,
            quarter: selectedQuarter,
            transcript: scoreKind ?? result.rawTranscript,
            normalizedTranscript: result.normalizedTranscript,
            confidence: result.confidence
        )
        let supportsEfficiencyVoiceVotes = statSupportsVoiceEfficiencyVote(statTypeId)
        let supportsContestedVoiceVotes = statSupportsVoiceContestedVote(statTypeId)
        let efficiencyVote = supportsEfficiencyVoiceVotes && sessionTracksDisposalEfficiencyVotes()
            ? voiceEfficiencyVote(in: result.normalizedTranscript)
            : nil
        let contestedVote = supportsContestedVoiceVotes && sessionTracksContestedPossessionVotes()
            ? voiceContestedVote(in: result.normalizedTranscript)
            : nil
        if let efficiencyVote {
            event.efficiencyVoteRaw = efficiencyVote.rawValue
        }
        if let contestedVote {
            event.contestedVoteRaw = contestedVote.rawValue
        }
        modelContext.insert(event)
        try? modelContext.save()
        let shouldDelaySuccessBanner = promptEfficiencyVoteIfNeeded(for: event, preselectedVote: efficiencyVote)
        selectedPlayerId = nil

        let playerText = playerLabel(for: playerId)
        let statText = statName(for: statTypeId)
        lastMessage = "Added: \(statText) — \(playerText) — \(selectedQuarter)"
        if !shouldDelaySuccessBanner {
            showSuccessBanner(for: event)
        }
        feedbackToken = UUID()
    }

    private func promptEfficiencyVoteIfNeeded(for event: StatEvent, preselectedVote: EfficiencyVote? = nil) -> Bool {
        if let preselectedVote {
            event.efficiencyVoteRaw = preselectedVote.rawValue
            try? modelContext.save()
            return false
        }
        guard sessionTracksDisposalEfficiencyVotes() else { return false }
        let normalized = statName(for: event.statTypeId).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized == "kick" || normalized == "handball" else { return false }
        pendingEfficiencyEventID = event.id
        showEfficiencyVotePrompt = true
        return true
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
        if let eventID = pendingEfficiencyEventID,
           let event = sessionEvents.first(where: { $0.id == eventID }) {
            showSuccessBanner(for: event)
        }
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
        let statText = statName(for: event.statTypeId)
        let teamText = teamBannerLabel(for: event.playerId)
        var segments: [String]

        if let statType = enabledStatTypes.first(where: { $0.id == event.statTypeId }),
           statCollectionMode(for: statType) == .individual,
           let playerText = individualPlayerBannerLabel(for: event.playerId) {
            segments = [teamText, statText, playerText]
        } else {
            segments = [teamText, statText]
        }

        if let contestedEmoji = contestedEmojiForBanner(event) {
            segments.append(contestedEmoji)
        }

        if let effectivenessEmoji = effectivenessEmojiForBanner(event) {
            segments.append(effectivenessEmoji)
        }

        return segments.joined(separator: " - ")
    }

    private func showRemoteInviteBanner(for tally: CloudStatsInviteTally, delta: Int) {
        guard delta > 0 else { return }
        let sideLabel = tally.sideRawValue == StatsInviteTeamSide.opposition.rawValue
            ? session.opposition.uppercased()
            : ourTeamName.uppercased()
        let statLabel = statName(for: tally.statTypeID).uppercased()
        showStatusBanner(text: "\(sideLabel) - \(statLabel)", isSuccess: true)
    }

    private func showRemoteInvitePlayerEventBanner(_ event: CloudStatsInvitePlayerEvent) {
        let statLabel = statName(for: event.statTypeID).uppercased()
        let playerLabel = playerNameForRecentEvent(for: event.playerID).uppercased()
        showStatusBanner(text: "\(ourTeamName.uppercased()) - \(statLabel) - \(playerLabel)", isSuccess: true)
    }

    private func contestedEmojiForBanner(_ event: StatEvent) -> String? {
        guard let vote = event.contestedVoteRaw else { return nil }
        return vote == ContestedPossessionVote.contested.rawValue ? "😣" : "🙂"
    }

    private func effectivenessEmojiForBanner(_ event: StatEvent) -> String? {
        guard let vote = event.efficiencyVoteRaw else { return nil }
        return vote == EfficiencyVote.thumbsUp.rawValue ? "✅" : "❌"
    }

    private func teamBannerLabel(for id: UUID) -> String {
        if id == ourTeamStatPlayerID {
            return ourTeamName.uppercased()
        }
        if id == oppositionTeamStatPlayerID {
            return session.opposition.uppercased()
        }
        return ourTeamName.uppercased()
    }

    private func individualPlayerBannerLabel(for id: UUID) -> String? {
        guard id != ourTeamStatPlayerID, id != oppositionTeamStatPlayerID else { return nil }
        guard let player = allPlayers.first(where: { $0.id == id }) else { return nil }
        return player.lastName.isEmpty ? player.name : player.lastName
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
                    efficiencyVoteButton(emoji: "👍", color: .green, vote: .thumbsUp)
                    efficiencyVoteButton(emoji: "👎", color: .red, vote: .thumbsDown)

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

    private func efficiencyVoteButton(emoji: String, color: Color, vote: EfficiencyVote) -> some View {
        Button {
            applyEfficiencyVote(vote)
        } label: {
            Text(emoji)
                .font(.system(size: 84))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(color)
                .background(Capsule().fill(Color.white.opacity(0.17)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func parseFailureMessage(_ result: VoiceParseResult) -> String {
        let heardTranscript = result.normalizedTranscript.isEmpty
            ? result.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            : result.normalizedTranscript

        func withHeard(_ message: String) -> String {
            let cleaned = heardTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return message }
            return "\(message). Heard: \"\(cleaned)\""
        }

        switch result.parseStatus {
        case .emptyTranscript:
            return "No speech detected"
        case .noStatFound:
            let cleaned = heardTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "Nothing heard" : "Heard: \"\(cleaned)\""
        case .noPlayerFound:
            if let guessed = result.matchedPlayerName {
                return withHeard("Player not found. Closest: \(guessed)")
            }
            return withHeard("Player not found")
        case .ambiguousPlayer:
            if let first = result.candidatePlayerIds.first {
                return withHeard("Multiple players match '\(playerLabel(for: first))'")
            }
            return withHeard("Multiple players match")
        case .ambiguousStat:
            return withHeard("Multiple stat types matched")
        case .lowConfidence:
            return withHeard("Could not confidently interpret command")
        case .success:
            return ""
        }
    }

    private func statSupportsVoiceEfficiencyVote(_ statTypeId: UUID) -> Bool {
        let normalized = normalizedStatName(statName(for: statTypeId))
        return normalized == "kick" || normalized == "handball"
    }

    private func statSupportsVoiceContestedVote(_ statTypeId: UUID) -> Bool {
        let normalized = normalizedStatName(statName(for: statTypeId))
        return normalized == "kick" || normalized == "handball" || normalized == "mark"
    }

    private func voiceContestedVote(in normalizedTranscript: String) -> ContestedPossessionVote? {
        let words = Set(normalizedTranscript.split(separator: " ").map(String.init))
        let contestedAliases = voteAliases(
            defaultAliases: SpeechVoteSection.all.first(where: { $0.key == SpeechVoteSection.contestedKey })?.defaultAliases ?? [],
            sectionKey: SpeechVoteSection.contestedKey
        )
        let uncontestedAliases = voteAliases(
            defaultAliases: SpeechVoteSection.all.first(where: { $0.key == SpeechVoteSection.uncontestedKey })?.defaultAliases ?? [],
            sectionKey: SpeechVoteSection.uncontestedKey
        )
        if uncontestedAliases.contains(where: { containsVoiceAlias($0, in: normalizedTranscript, words: words) }) {
            return .uncontested
        }
        if contestedAliases.contains(where: { containsVoiceAlias($0, in: normalizedTranscript, words: words) }) {
            return .contested
        }
        return nil
    }

    private func voiceEfficiencyVote(in normalizedTranscript: String) -> EfficiencyVote? {
        let words = Set(normalizedTranscript.split(separator: " ").map(String.init))
        let effectiveAliases = voteAliases(
            defaultAliases: SpeechVoteSection.all.first(where: { $0.key == SpeechVoteSection.effectiveKey })?.defaultAliases ?? [],
            sectionKey: SpeechVoteSection.effectiveKey
        )
        let ineffectiveAliases = voteAliases(
            defaultAliases: SpeechVoteSection.all.first(where: { $0.key == SpeechVoteSection.ineffectiveKey })?.defaultAliases ?? [],
            sectionKey: SpeechVoteSection.ineffectiveKey
        )
        if ineffectiveAliases.contains(where: { containsVoiceAlias($0, in: normalizedTranscript, words: words) }) {
            return .thumbsDown
        }
        if effectiveAliases.contains(where: { containsVoiceAlias($0, in: normalizedTranscript, words: words) }) {
            return .thumbsUp
        }
        return nil
    }

    private func voteAliases(defaultAliases: [String], sectionKey: String) -> [String] {
        let detected = SpeechDetectedWordsStore.words(forSectionKey: sectionKey)
        return Array(Set(defaultAliases + detected)).map { $0.lowercased() }
    }

    private func containsVoiceAlias(_ alias: String, in transcript: String, words: Set<String>) -> Bool {
        if alias.contains(" ") {
            return transcript.contains(alias)
        }
        return words.contains(alias)
    }

    private func voiceScoreKind(in normalizedTranscript: String) -> String? {
        let words = Set(normalizedTranscript.split(separator: " ").map(String.init))
        if words.contains("goal") || words.contains("goals") || words.contains("go") {
            return "goal"
        }
        if words.contains("behind") || words.contains("behinds") || words.contains("point") || words.contains("points") {
            return "behind"
        }
        if normalizedTranscript.contains("rushed behind") {
            return "behind"
        }
        return nil
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
                drawCell(player.number.map { String($0) } ?? "", x: leftMargin, y: y, width: numberColumnWidth, height: dataRowHeight)
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
        let normalizedAliases = Set(aliases.map { $0.lowercased() })
        let matchingStatIDs = enabledStatTypes.filter { type in
            normalizedAliases.contains(type.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }.map(\.id)

        var total = matchingStatIDs.reduce(0) { partialResult, statID in
            let key = "\(playerID.uuidString)|\(quarter)|\(statID.uuidString)"
            return partialResult + (lookup[key]?.count ?? 0)
        }

        let scoreStatIDs = enabledStatTypes
            .filter { normalizedStatName($0.name) == "scores" }
            .map(\.id)

        total += scoreStatIDs.reduce(0) { partialResult, statID in
            let key = "\(playerID.uuidString)|\(quarter)|\(statID.uuidString)"
            let matchingEvents = lookup[key] ?? []
            return partialResult + matchingEvents.filter {
                normalizedAliases.contains(normalizedStatName($0.transcript ?? ""))
            }.count
        }

        return total
    }

    private func teamStatCount(statType: StatType?, teamPlayerId: UUID) -> Int {
        guard let statType else { return 0 }
        let isOpposition = teamPlayerId == oppositionTeamStatPlayerID
        let localCount = sessionEvents.filter { $0.playerId == teamPlayerId && $0.statTypeId == statType.id }.count
        return localCount + remoteInviteCount(statTypeID: statType.id, isOpposition: isOpposition)
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

private struct StatDisplayOrderEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let enabledStatTypeIDs: Set<UUID>
    let onSave: ([UUID]) -> Void

    @State private var orderedStatTypes: [StatType]
    @State private var editMode: EditMode = .active

    init(
        statTypes: [StatType],
        enabledStatTypeIDs: Set<UUID>,
        onSave: @escaping ([UUID]) -> Void
    ) {
        self.enabledStatTypeIDs = enabledStatTypeIDs
        self.onSave = onSave
        _orderedStatTypes = State(initialValue: statTypes)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(orderedStatTypes.enumerated()), id: \.element.id) { item in
                        let index = item.offset
                        let statType = item.element
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(statType.name)
                                    .font(.headline)
                                Text(enabledStatTypeIDs.contains(statType.id) ? "Included in this live session" : "Not currently in this live session")
                                    .font(.caption)
                                    .foregroundStyle(enabledStatTypeIDs.contains(statType.id) ? .orange : .secondary)
                            }

                            Spacer(minLength: 8)

                            if enabledStatTypeIDs.contains(statType.id) {
                                Text("Live")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.14), in: Capsule())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove(perform: moveStatTypes)
                } header: {
                    Text("Drag all stats to set the live display order")
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("Display Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(orderedStatTypes.map(\.id))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func moveStatTypes(from source: IndexSet, to destination: Int) {
        orderedStatTypes.move(fromOffsets: source, toOffset: destination)
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
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
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
                                Text(player.displayFirstName)
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        if hasUnsavedChanges {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
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
                ToolbarItem(placement: .navigationBarTrailing) {
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
            || ($0.number.map { String($0) }?.contains(key) ?? false)
        }
    }
}

private struct StatsTotalsView: View {
    @Environment(\.dismiss) private var dismiss
    let rows: [TotalsRow]
    let statTypes: [StatType]
    let sessionEvents: [StatEvent]
    let remoteInviteTallies: [CloudStatsInviteTally]
    let ourTeamName: String
    let oppositionName: String
    let ourStyle: ClubStyle.Style
    let oppositionStyle: ClubStyle.Style
    let ourScoreSummary: (goals: Int, behinds: Int, points: Int)
    let oppositionScoreSummary: (goals: Int, behinds: Int, points: Int)
    private let oppositionTeamStatPlayerID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB") ?? UUID()

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

    private var topPossessionRows: [TotalsSummaryRow] {
        Array(summaryRows.prefix(5))
    }

    private var topGoalKickers: [TotalsSummaryRow] {
        summaryRows
            .filter { $0.goals > 0 || $0.behinds > 0 }
            .sorted { lhs, rhs in
                if lhs.goals != rhs.goals { return lhs.goals > rhs.goals }
                if lhs.behinds != rhs.behinds { return lhs.behinds > rhs.behinds }
                return lhs.playerLabel < rhs.playerLabel
            }
            .prefix(5)
            .map { $0 }
    }

    private var inside50Stat: StatType? {
        statType(aliases: ["inside 50", "inside50", "inside 50s"])
    }

    private var clearanceStat: StatType? {
        statType(aliases: ["clearance", "clearances"])
    }

    private var ourInside50s: Int {
        teamCount(for: inside50Stat, isOpposition: false)
    }

    private var theirInside50s: Int {
        teamCount(for: inside50Stat, isOpposition: true)
    }

    private var ourClearances: Int {
        teamCount(for: clearanceStat, isOpposition: false)
    }

    private var theirClearances: Int {
        teamCount(for: clearanceStat, isOpposition: true)
    }

    private var ourTeamEfficiency: String {
        teamEfficiencyText(isOpposition: false)
    }

    private var oppositionTeamEfficiency: String {
        teamEfficiencyText(isOpposition: true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        scorePool(
                            teamName: ourTeamName,
                            goals: ourScoreSummary.goals,
                            behinds: ourScoreSummary.behinds,
                            points: ourScoreSummary.points,
                            style: ourStyle
                        )
                        scorePool(
                            teamName: oppositionName,
                            goals: oppositionScoreSummary.goals,
                            behinds: oppositionScoreSummary.behinds,
                            points: oppositionScoreSummary.points,
                            style: oppositionStyle
                        )
                    }

                    HStack(spacing: 12) {
                        teamStatPool(title: "Inside 50s", value: ourInside50s, style: ourStyle)
                        teamStatPool(title: "Clearances", value: ourClearances, style: ourStyle)
                        teamStatPool(title: "Inside 50s", value: theirInside50s, style: oppositionStyle)
                        teamStatPool(title: "Clearances", value: theirClearances, style: oppositionStyle)
                    }

                    HStack(spacing: 12) {
                        efficiencyPool(title: "\(ourTeamName) Efficiency", value: ourTeamEfficiency, style: ourStyle)
                        efficiencyPool(title: "\(oppositionName) Efficiency", value: oppositionTeamEfficiency, style: oppositionStyle)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        leaderboardPool(
                            title: "Top 5 Possession Getters",
                            entries: topPossessionRows.map {
                                ("\($0.playerLabel)", "\($0.possessions)", nil)
                            }
                        )
                        leaderboardPool(
                            title: "Top 5 Goal Kickers",
                            entries: topGoalKickers.map {
                                ("\($0.playerLabel)", "\($0.goals)", nil)
                            }
                        )
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Game Totals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func statType(aliases: [String]) -> StatType? {
        let normalizedAliases = Set(aliases.map { $0.lowercased() })
        return statTypes.first { type in
            normalizedAliases.contains(type.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }

    private var disposalEfficiencyStat: StatType? {
        statType(aliases: ["disposal efficiency"])
    }

    private var isTeamModeDisposalEfficiency: Bool {
        guard let disposalEfficiencyStat else { return false }
        return defaultSessionStatCollectionMode(for: disposalEfficiencyStat.name) == .team
    }

    private func teamCount(for statType: StatType?, isOpposition: Bool) -> Int {
        guard let statType else { return 0 }
        let localCount = sessionEvents.filter { event in
            let isOppositionEvent = event.playerId == oppositionTeamStatPlayerID
            return isOppositionEvent == isOpposition && event.statTypeId == statType.id
        }.count
        return localCount + remoteInviteCount(statTypeID: statType.id, isOpposition: isOpposition)
    }

    private func remoteInviteCount(statTypeID: UUID, isOpposition: Bool) -> Int {
        let sideRawValue = isOpposition ? StatsInviteTeamSide.opposition.rawValue : StatsInviteTeamSide.ourClub.rawValue
        return remoteInviteTallies.reduce(0) { partialResult, tally in
            guard tally.statTypeID == statTypeID, tally.sideRawValue == sideRawValue else { return partialResult }
            return partialResult + tally.count
        }
    }

    private func teamEfficiencyText(isOpposition: Bool) -> String {
        efficiencyDisplayText(isOpposition: isOpposition, emptyFallback: "-")
    }

    private func efficiencyDisplayText(isOpposition: Bool, emptyFallback: String) -> String {
        if isTeamModeDisposalEfficiency {
            let kickTotal = teamCount(for: statType(aliases: ["kick"]), isOpposition: isOpposition)
            let handballTotal = teamCount(for: statType(aliases: ["handball"]), isOpposition: isOpposition)
            let disposals = kickTotal + handballTotal
            guard disposals > 0 else { return emptyFallback }
            let effective = teamCount(for: disposalEfficiencyStat, isOpposition: isOpposition)
            let percent = (Double(effective) / Double(disposals)) * 100
            return "\(Int(round(percent)))%"
        }
        let relevant = sessionEvents.filter { event in
            let isOppositionEvent = event.playerId == oppositionTeamStatPlayerID
            return isOppositionEvent == isOpposition
        }
        let effective = relevant.filter { $0.efficiencyVoteRaw == EfficiencyVote.thumbsUp.rawValue }.count
        let nonEffective = relevant.filter { $0.efficiencyVoteRaw == EfficiencyVote.thumbsDown.rawValue }.count
        let total = effective + nonEffective
        guard total > 0 else { return emptyFallback }
        return "\(Int(round((Double(effective) / Double(total)) * 100)))%"
    }

    private func count(for statName: String, in row: TotalsRow) -> Int {
        func normalize(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        let normalizedName = normalize(statName)
        let directCount = statTypes
            .filter { normalize($0.name) == normalizedName }
            .reduce(0) { partialResult, statType in
                partialResult + row.countsByStatId[statType.id, default: 0]
            }

        let scoresCount = statTypes
            .filter { normalize($0.name) == "scores" }
            .reduce(0) { partialResult, statType in
                partialResult + row.events.filter {
                    $0.statTypeId == statType.id && normalize($0.transcript ?? "") == normalizedName
                }.count
            }

        return directCount + scoresCount
    }

    @ViewBuilder
    private func scorePool(teamName: String, goals: Int, behinds: Int, points: Int, style: ClubStyle.Style) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(teamName.uppercased())
                .font(.title3.weight(.black))
                .lineLimit(1)
            Text("\(goals).\(behinds) (\(points))")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("\(points) points")
                .font(.title2.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(style.text)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(style.border.opacity(0.75), lineWidth: 2)
        )
    }

    private func teamStatPool(title: String, value: Int, style: ClubStyle.Style) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
            Text("\(value)")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(style.text)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.background.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(style.border.opacity(0.75), lineWidth: 2)
        )
    }

    private func teamStatsPool(
        teamName: String,
        style: ClubStyle.Style,
        inside50s: Int,
        clearances: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(teamName.uppercased())
                .font(.headline.weight(.black))
                .lineLimit(1)

            HStack(spacing: 10) {
                teamStatPool(title: "Inside 50s", value: inside50s, style: style)
                teamStatPool(title: "Clearances", value: clearances, style: style)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func efficiencyPool(title: String, value: String, style: ClubStyle.Style) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.weight(.black))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 44, weight: .black, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(style.text)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(style.border.opacity(0.8), lineWidth: 2)
        )
    }

    private func leaderboardPool(title: String, entries: [(name: String, mainValue: String, subValue: String?)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.black))
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
            if entries.isEmpty {
                Spacer(minLength: 0)
                Text("No data yet.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    HStack(alignment: .center, spacing: 10) {
                        Text("\(index + 1).")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .font(.title3.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            if let subValue = entry.subValue, !subValue.isEmpty {
                                Text(subValue)
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(entry.mainValue)
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(height: 46)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 350, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct StatsStatTakersView: View {
    let contacts: [Contact]
    let inviteAssignments: [StatsInviteAssignment]
    let statTypes: [StatType]
    let activeSession: StatsSession?
    let activeSessionGradeName: String
    @Binding var selectedContact: PhoneInviteContact?
    @Binding var selectedSelections: Set<StatsInviteSelection>
    let onSendInvite: (PhoneInviteContact, Set<StatsInviteSelection>) -> Void
    let onSaveAssignments: (StatsInviteAssignment, [StatsInviteSelection]) -> Void
    let onReinviteAssignment: (StatsInviteAssignment) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            StatsInviteComposerContent(
                contacts: contacts,
                inviteAssignments: inviteAssignments,
                statTypes: statTypes,
                activeSession: activeSession,
                activeSessionGradeName: activeSessionGradeName,
                selectedContact: $selectedContact,
                selectedSelections: $selectedSelections,
                onSendInvite: onSendInvite,
                onSaveAssignments: onSaveAssignments,
                onReinviteAssignment: onReinviteAssignment,
                dismissAfterSMS: true,
                onSMSDismiss: { dismiss() }
            )
            .navigationTitle("Stat Takers")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct StatsInviteComposerContent: View {
    let contacts: [Contact]
    let inviteAssignments: [StatsInviteAssignment]
    let statTypes: [StatType]
    let activeSession: StatsSession?
    let activeSessionGradeName: String
    @Binding var selectedContact: PhoneInviteContact?
    @Binding var selectedSelections: Set<StatsInviteSelection>
    let onSendInvite: (PhoneInviteContact, Set<StatsInviteSelection>) -> Void
    var onStartSessionRequested: () -> Void = {}
    var onSaveAssignments: (StatsInviteAssignment, [StatsInviteSelection]) -> Void = { _, _ in }
    var onReinviteAssignment: (StatsInviteAssignment) -> Void = { _ in }
    var dismissAfterSMS = false
    var onSMSDismiss: () -> Void = {}

    @AppStorage("app.testFlightURL") private var testFlightURL = ""
    @State private var inviteeName = ""
    @State private var inviteeEmail = ""
    @State private var inviteeMobile = ""
    @State private var messageDraft: StatsInviteMessageDraft?
    @State private var shareDraft: ShareDraft?
    @State private var editingInvite: StatsInviteAssignment?
    @State private var showPreview = false

    private var sortedStatTypes: [StatType] {
        statTypes.sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    private var hasActiveSession: Bool {
        activeSession != nil
    }

    private var clubConfiguration: ClubConfiguration {
        ClubConfigurationStore.load()
    }

    private var clubName: String {
        let trimmed = clubConfiguration.clubTeam.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Min Man" : trimmed
    }

    private var oppositionName: String {
        let trimmed = activeSession?.opposition.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Opposition" : trimmed
    }

    private var ourTeamStyle: ClubStyle.Style {
        ClubStyle.style(for: clubName, configuration: clubConfiguration)
    }

    private var oppositionStyle: ClubStyle.Style {
        ClubStyle.style(for: oppositionName, configuration: clubConfiguration)
    }

    private var lockedSelectionOwners: [String: String] {
        var result: [String: String] = [:]
        for assignment in inviteAssignments {
            let contactName = assignment.inviteeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? assignment.inviteeEmail
                : assignment.inviteeName
            for selection in assignment.assignedSelections {
                result[selection.id] = contactName
            }
        }
        return result
    }

    var body: some View {
        List {
            Section("Active Stats Session") {
                if let activeSession {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(activeSessionGradeName)
                            .font(.headline)
                        HStack(spacing: 10) {
                            ScorePill(clubName, style: ourTeamStyle)
                            ScorePill(oppositionName, style: oppositionStyle)
                        }
                        Text("\(activeSession.date.formatted(date: .abbreviated, time: .omitted)) • \(activeSession.venue)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("No active Stats session, please start a stats session to proceed")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.secondary)
                        Button("Start Session") {
                            onStartSessionRequested()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                }
            }

            Section("Invite Stat Taker") {
                TextField("Stat taker name", text: $inviteeName)
                    .textInputAutocapitalization(.words)

                TextField("Invited email", text: $inviteeEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Mobile for text", text: $inviteeMobile)
                    .keyboardType(.phonePad)
                TextField("https://testflight.apple.com/join/...", text: $testFlightURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Assignments sync through CloudKit. The text invite includes the TestFlight link so the recipient can install the app before opening the Stat Taker tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let selectedContact {
                    Text(selectedContact.subtitle.isEmpty ? selectedContact.title : "\(selectedContact.title) • \(selectedContact.subtitle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button("Preview") {
                    showPreview = true
                }
                .buttonStyle(.bordered)
            }
            .disabled(!hasActiveSession)
            .opacity(hasActiveSession ? 1 : 0.4)

            Section("Choose Stats To Collect") {
                if sortedStatTypes.isEmpty {
                    Text("No enabled stat types available.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            Text("Stat")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 110, alignment: .leading)
                            teamPillHeader(title: clubName, style: ourTeamStyle)
                            teamPillHeader(title: oppositionName, style: oppositionStyle)
                        }

                        ForEach(sortedStatTypes) { type in
                            HStack(alignment: .top, spacing: 12) {
                                Text(type.name)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(width: 110, alignment: .leading)
                                    .padding(.top, 10)
                                selectionCell(for: type, side: .ourClub)
                                selectionCell(for: type, side: .opposition)
                            }
                        }
                    }
                }
            }
            .disabled(!hasActiveSession)
            .opacity(hasActiveSession ? 1 : 0.4)

            Section {
                Button("Generate Invite") {
                    sendInviteLink()
                }
                .disabled(
                    inviteeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    inviteeEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    inviteeMobile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    selectedSelections.isEmpty
                )

                if !selectedSelections.isEmpty {
                    Text("Assigned: \(selectedSelectionSummary)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if testFlightURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("TestFlight link is optional if the recipient already has ClubResults installed.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .disabled(!hasActiveSession)
            .opacity(hasActiveSession ? 1 : 0.4)

            Section("Invited Users") {
                if inviteAssignments.isEmpty {
                    Text("No invited users yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(inviteAssignments) { assignment in
                        invitedUserRow(assignment)
                    }
                }
            }
            .disabled(!hasActiveSession)
            .opacity(hasActiveSession ? 1 : 0.4)
        }
        .sheet(item: $shareDraft, onDismiss: {
            if dismissAfterSMS {
                onSMSDismiss()
            }
        }) { draft in
            ShareSheet(items: [draft.text])
        }
        .sheet(item: $messageDraft, onDismiss: {
            if dismissAfterSMS {
                onSMSDismiss()
            }
        }) { draft in
            StatsInviteMessageComposer(draft: draft)
        }
        .sheet(item: $editingInvite) { assignment in
            StatsInviteManagementSheet(
                assignment: assignment,
                allStatTypes: sortedStatTypes,
                onSave: { selections in
                    onSaveAssignments(assignment, selections)
                },
                onReinvite: {
                    onReinviteAssignment(assignment)
                }
            )
        }
        .fullScreenCover(isPresented: $showPreview) {
            NavigationStack {
                StatsInviteLivePreviewView(
                    clubConfiguration: clubConfiguration,
                    clubName: clubName,
                    gradeTitle: activeSessionGradeName,
                    oppositionName: oppositionName,
                    selections: orderedSelections,
                    statTypes: sortedStatTypes
                )
            }
        }
        .onAppear {
            loadDraftSelectionsIfNeeded()
            if inviteeName.isEmpty {
                inviteeName = selectedContact?.displayName ?? ""
            }
            if inviteeEmail.isEmpty {
                inviteeEmail = selectedContact?.email ?? ""
            }
            if inviteeMobile.isEmpty {
                inviteeMobile = selectedContact?.phoneNumber ?? ""
            }
        }
        .onChange(of: selectedSelections) { _, newValue in
            StatsInviteDraftStore.saveSelections(newValue)
        }
    }

    private var orderedSelections: [StatsInviteSelection] {
        let sortOrderByID = Dictionary(uniqueKeysWithValues: sortedStatTypes.map { ($0.id, $0.sortOrder) })
        return selectedSelections.sorted {
            let leftIndex = sortOrderByID[$0.statTypeID] ?? 0
            let rightIndex = sortOrderByID[$1.statTypeID] ?? 0
            if leftIndex != rightIndex {
                return leftIndex < rightIndex
            }
            if $0.side != $1.side {
                return $0.side == .ourClub
            }
            return false
        }
    }

    private var selectedSelectionSummary: String {
        let names = statsInviteSelectionNames(for: orderedSelections, statTypes: sortedStatTypes)
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }

    private func loadDraftSelectionsIfNeeded() {
        guard selectedSelections.isEmpty else { return }
        selectedSelections = Set(
            StatsInviteDraftStore.loadSelections().filter { !isLocked($0) }
        )
    }

    private func selectionFor(_ type: StatType, side: StatsInviteTeamSide) -> StatsInviteSelection {
        StatsInviteSelection(statTypeID: type.id, side: side)
    }

    private func isLocked(_ selection: StatsInviteSelection) -> Bool {
        lockedSelectionOwners[selection.id] != nil
    }

    private func lockedOwnerName(for selection: StatsInviteSelection) -> String? {
        lockedSelectionOwners[selection.id]
    }

    @ViewBuilder
    private func teamPillHeader(title: String, style: ClubStyle.Style) -> some View {
        ScorePill(title, style: style)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func selectionCell(for type: StatType, side: StatsInviteTeamSide) -> some View {
        let selection = selectionFor(type, side: side)
        let isSelected = selectedSelections.contains(selection)
        let lockedOwner = lockedOwnerName(for: selection)
        let locked = lockedOwner != nil

        Button {
            toggleSelection(selection)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                if let lockedOwner {
                    Label(lockedOwner, systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Assigned")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if isSelected {
                    Label("Ready to invite", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                    Text("Selected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Available", systemImage: "plus.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Tap to assign")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectionBackground(isSelected: isSelected, locked: locked))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selectionBorderColor(isSelected: isSelected, locked: locked), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }

    private func toggleSelection(_ selection: StatsInviteSelection) {
        guard !isLocked(selection) else { return }
        if selectedSelections.contains(selection) {
            selectedSelections.remove(selection)
        } else {
            selectedSelections.insert(selection)
        }
    }

    private func selectionBackground(isSelected: Bool, locked: Bool) -> Color {
        if locked {
            return Color(.tertiarySystemFill)
        }
        if isSelected {
            return Color.green.opacity(0.15)
        }
        return Color(.secondarySystemBackground)
    }

    private func selectionBorderColor(isSelected: Bool, locked: Bool) -> Color {
        if locked {
            return Color.gray.opacity(0.35)
        }
        if isSelected {
            return .green.opacity(0.7)
        }
        return Color.gray.opacity(0.2)
    }

    private func sendInviteLink() {
        guard let activeSession else { return }
        let selectedContact = StatsInviteRecipient(
            email: inviteeEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            displayName: inviteeName.trimmingCharacters(in: .whitespacesAndNewlines),
            mobileNumber: inviteeMobile.formattedMobileNumber
        )
        guard !selectedContact.email.isEmpty else { return }
        guard !selectedContact.phoneNumber.isEmpty else { return }
        let recordName = CloudKitStatsInviteService.recordName(
            sessionID: activeSession.sessionId,
            inviteeEmail: selectedContact.email
        )

        self.selectedContact = selectedContact
        onSendInvite(selectedContact, selectedSelections)
        selectedSelections.removeAll()
        let inviteText = buildStatsInviteMessage(
            recipient: selectedContact,
            sessionID: activeSession.sessionId,
            recordName: recordName,
            sessionLine: "\(activeSessionGradeName) vs \(activeSession.opposition) • \(activeSession.date.formatted(date: .abbreviated, time: .omitted))",
            assignedNames: selectedSelectionSummary,
            testFlightURL: testFlightURL
        )

        if MFMessageComposeViewController.canSendText() {
            messageDraft = StatsInviteMessageDraft(
                recipients: [selectedContact.phoneNumber],
                body: inviteText
            )
        } else {
            shareDraft = ShareDraft(text: inviteText)
        }
    }

    @ViewBuilder
    private func invitedUserRow(_ assignment: StatsInviteAssignment) -> some View {
        let contactName = assignment.inviteeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? assignment.inviteeEmail
            : assignment.inviteeName
        let statusText = assignment.isConnected ? "Connected" : "Waiting"
        let assignedNames = statsInviteSelectionNames(
            for: assignment.assignedSelections,
            statTypes: sortedStatTypes
        ).joined(separator: ", ")

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(assignment.isConnected ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 10, height: 10)
                Text(contactName)
                    .font(.headline)
                Spacer()
                Button("Manage") {
                    editingInvite = assignment
                }
                .buttonStyle(.bordered)
            }
            Text(statusText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(assignment.isConnected ? .green : .secondary)
            Text("Collecting: \(assignedNames.isEmpty ? "None" : assignedNames)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !assignment.inviteeEmail.isEmpty {
                Text(assignment.inviteeEmail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct StatsInviteLivePreviewView: View {
    let clubConfiguration: ClubConfiguration
    let clubName: String
    let gradeTitle: String
    let oppositionName: String
    let selections: [StatsInviteSelection]
    let statTypes: [StatType]
    var selectionDisplayNamesByRawValue: [String: String] = [:]
    var selectionCollectionModeByRawValue: [String: String] = [:]
    var availablePlayers: [Player] = []
    var sessionID: UUID? = nil
    var syncSessionDescriptor: LiveStatsSyncSessionDescriptor? = nil
    var showsDoneButton: Bool = true
    @EnvironmentObject private var navigationState: AppNavigationState
    @Environment(\.dismiss) private var dismiss
    @State private var persistedCountsBySelectionID: [String: Int] = [:]
    @State private var pendingSyncDeltasBySelectionID: [String: Int] = [:]
    @State private var inFlightSyncDeltasBySelectionID: [String: Int] = [:]
    @State private var persistedPlayerEventsByID: [String: CloudStatsInvitePlayerEvent] = [:]
    @State private var pendingCreatedPlayerEventsByID: [String: CloudStatsInvitePlayerEvent] = [:]
    @State private var pendingDeletedPlayerEventIDs: Set<String> = []
    @State private var recentEnteredSelections: [RecentInviteSelectionEntry] = []
    @State private var tallySyncError: String?
    @State private var lastPersistedTallyUpdateAt: Date?
    @State private var lastPersistedPlayerEventUpdateAt: Date?
    @State private var tallySyncTask: Task<Void, Never>?
    @State private var playerEventSyncTask: Task<Void, Never>?
    @State private var cloudSessionState: CloudStatsInviteSessionState?
    @State private var showSyncIssues = false
    @State private var showUndoLastStatPrompt = false
    @State private var selectedIndividualSelection: StatsInviteSelection?
    @State private var invitePlayerSortMode: InvitePlayerSortMode = .number
    @State private var showMissingPlayersAlert = false
    @State private var statusBanner: StatRecordBanner?
    @State private var statusBannerTask: Task<Void, Never>?
    @State private var highlightedInvitePlayerID: UUID?
    @State private var highlightedInvitePlayerTask: Task<Void, Never>?
    private let statTapHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let invitePollIntervalNanoseconds: UInt64 = 250_000_000
    private let liveSessionActivityTimeout: TimeInterval = 5

    private struct RecentInviteSelectionEntry: Identifiable {
        let id = UUID()
        let selection: StatsInviteSelection
        let playerEventID: String?
    }

    private enum InvitePlayerSortMode: String, CaseIterable, Identifiable {
        case number
        case surname
        case firstName
        case dynamic

        var id: String { rawValue }

        var title: String {
            switch self {
            case .number:
                return "Number"
            case .surname:
                return "Surname"
            case .firstName:
                return "First Name"
            case .dynamic:
                return "Dynamic"
            }
        }

        var systemImage: String {
            switch self {
            case .number:
                return "number"
            case .surname:
                return "textformat"
            case .firstName:
                return "textformat.abc"
            case .dynamic:
                return "bolt.horizontal"
            }
        }
    }

    private var ourSelections: [StatsInviteSelection] {
        selections.filter { $0.side == .ourClub }
    }

    private var oppositionSelections: [StatsInviteSelection] {
        selections.filter { $0.side == .opposition }
    }

    private var syncStatus: LiveStatsSyncStatus? {
        guard syncSessionDescriptor != nil else { return nil }
        if let sessionID,
           let cloudSessionState,
           cloudSessionState.sessionID == sessionID,
           Date().timeIntervalSince(cloudSessionState.updatedAt) <= liveSessionActivityTimeout,
           tallySyncError == nil {
            return LiveStatsSyncStatus(
                state: .green,
                issues: [],
                canManuallySyncGameAndStats: false,
                isGameAndStatsLinked: true
            )
        }
        if let tallySyncError {
            return LiveStatsSyncStatus(
                state: .red,
                issues: [LiveStatsSyncIssue(tallySyncError)],
                canManuallySyncGameAndStats: false,
                isGameAndStatsLinked: false
            )
        }
        return navigationState.liveStatsSyncStatus
    }

    private var syncStatusIconName: String {
        guard let syncStatus else { return "dot.radiowaves.left.and.right" }
        switch syncStatus.state {
        case .green, .red:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .orange:
            return "arrow.triangle.2.circlepath.circle"
        }
    }

    private var syncStatusTint: Color {
        guard let syncStatus else {
            return sessionID != nil && tallySyncError == nil ? .green : .secondary
        }
        switch syncStatus.state {
        case .green:
            return .green
        case .red:
            return .red
        case .orange:
            return .orange
        }
    }

    private var syncStatusAccessibilityLabel: String {
        guard let syncStatus else { return "Live Stats" }
        switch syncStatus.state {
        case .green:
            return "Live session is synced"
        case .red:
            return "User sync issues detected"
        case .orange:
            return "User view waiting for the same live session"
        }
    }

    private var syncIssuesMessage: String {
        syncStatus?.issues.map(\.message).joined(separator: "\n") ?? ""
    }

    private var hasUndoableSelection: Bool {
        !recentEnteredSelections.isEmpty
    }

    private var sortedAvailablePlayers: [Player] {
        availablePlayers.sorted(by: invitePlayerSortComparator)
    }

    private var combinedInvitePlayerEvents: [CloudStatsInvitePlayerEvent] {
        Array(persistedPlayerEventsByID.values) + Array(pendingCreatedPlayerEventsByID.values)
    }

    private var possessionStatTypeIDsForInviteSort: Set<UUID> {
        Set(
            statTypes
                .filter { type in
                    let normalized = type.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return normalized == "kick" || normalized == "handball"
                }
                .map(\.id)
        )
    }

    private var invitePlayerPossessionCounts: [UUID: Int] {
        guard !possessionStatTypeIDsForInviteSort.isEmpty else { return [:] }
        return combinedInvitePlayerEvents.reduce(into: [:]) { counts, event in
            guard event.sideRawValue == StatsInviteTeamSide.ourClub.rawValue,
                  possessionStatTypeIDsForInviteSort.contains(event.statTypeID) else {
                return
            }
            counts[event.playerID, default: 0] += 1
        }
    }

    private func invitePlayerSortComparator(lhs: Player, rhs: Player) -> Bool {
        switch invitePlayerSortMode {
        case .number:
            let leftNumber = lhs.number ?? Int.max
            let rightNumber = rhs.number ?? Int.max
            if leftNumber != rightNumber {
                return leftNumber < rightNumber
            }
        case .surname:
            let surnameOrder = compareInvitePlayerText(lhs.lastName, rhs.lastName)
            if let surnameOrder {
                return surnameOrder
            }
        case .firstName:
            let firstNameOrder = compareInvitePlayerText(lhs.displayFirstName, rhs.displayFirstName)
            if let firstNameOrder {
                return firstNameOrder
            }
        case .dynamic:
            let leftPossessions = invitePlayerPossessionCounts[lhs.id, default: 0]
            let rightPossessions = invitePlayerPossessionCounts[rhs.id, default: 0]
            if leftPossessions != rightPossessions {
                return leftPossessions > rightPossessions
            }
            let leftNumber = lhs.number ?? Int.max
            let rightNumber = rhs.number ?? Int.max
            if leftNumber != rightNumber {
                return leftNumber < rightNumber
            }
        }

        let surnameOrder = compareInvitePlayerText(lhs.lastName, rhs.lastName)
        if let surnameOrder {
            return surnameOrder
        }
        let firstNameOrder = compareInvitePlayerText(lhs.displayFirstName, rhs.displayFirstName)
        if let firstNameOrder {
            return firstNameOrder
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func compareInvitePlayerText(_ lhs: String, _ rhs: String) -> Bool? {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty != right.isEmpty {
            return !left.isEmpty
        }
        let comparison = left.localizedCaseInsensitiveCompare(right)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return nil
    }

    private func invitePlayerRowTitle(for player: Player) -> String {
        player.number.map { "\($0) \(player.name)" } ?? player.name
    }

    private var liveStatsSnapshotForHeader: LiveStatsInviteSnapshot? {
        if let cloudSessionState {
            return LiveStatsInviteSnapshot(
                sessionID: cloudSessionState.sessionID,
                currentQuarter: cloudSessionState.currentQuarter,
                remainingSeconds: cloudSessionState.remainingSeconds,
                isTimerRunning: cloudSessionState.isTimerRunning,
                ourPoints: cloudSessionState.ourPoints,
                theirPoints: cloudSessionState.theirPoints
            )
        }
        guard let snapshot = navigationState.activeLiveStatsInviteSnapshot else { return nil }
        if let syncSessionDescriptor {
            return snapshot.sessionID == syncSessionDescriptor.sessionID ? snapshot : nil
        }
        if let sessionID {
            return snapshot.sessionID == sessionID ? snapshot : nil
        }
        return snapshot
    }

    private var liveSnapshotForHeader: LiveGameSyncSnapshot? {
        guard let syncSessionDescriptor,
              navigationState.syncedStatsSessionID == syncSessionDescriptor.sessionID,
              let snapshot = navigationState.activeLiveGameSnapshot else {
            return nil
        }
        return snapshot
    }

    private var headerQuarterLabel: String {
        if let liveStatsSnapshotForHeader {
            return liveStatsSnapshotForHeader.currentQuarter
        }
        return liveSnapshotForHeader?.currentQuarter ?? "Q-"
    }

    private func headerCountdownLabel(at date: Date) -> String {
        guard let remaining = headerRemainingSeconds(at: date) else {
            return "--:--"
        }
        let absolute = abs(remaining)
        let sign = remaining < 0 ? "-" : ""
        return sign + String(format: "%02d:%02d", absolute / 60, absolute % 60)
    }

    private func headerRemainingSeconds(at date: Date) -> Int? {
        if let cloudSessionState {
            let elapsed = cloudSessionState.isTimerRunning
                ? max(0, Int(date.timeIntervalSince(cloudSessionState.updatedAt)))
                : 0
            return cloudSessionState.remainingSeconds - elapsed
        }
        if let liveStatsSnapshotForHeader {
            return liveStatsSnapshotForHeader.remainingSeconds
        }
        if let snapshot = liveSnapshotForHeader {
            return snapshot.syncedRemainingSeconds(at: date)
        }
        return nil
    }

    private func isHeaderTimerRunning(at date: Date) -> Bool {
        if let cloudSessionState {
            return cloudSessionState.isTimerRunning
        }
        if let liveStatsSnapshotForHeader {
            return liveStatsSnapshotForHeader.isTimerRunning
        }
        if let snapshot = liveSnapshotForHeader {
            return snapshot.isTimerActive(at: date)
        }
        return false
    }

    private func headerCountdownTint(at date: Date) -> Color {
        guard let remaining = headerRemainingSeconds(at: date) else {
            return .secondary
        }
        guard isHeaderTimerRunning(at: date) else {
            return .secondary
        }
        return remaining <= (2 * 60) ? .white : .green
    }

    private var headerOurScoreText: String {
        if let snapshot = liveSnapshotForHeader {
            return "\(snapshot.ourGoals).\(snapshot.ourBehinds) (\(snapshot.ourPoints))"
        }
        if let liveStatsSnapshotForHeader {
            return "\(liveStatsSnapshotForHeader.ourPoints)"
        }
        return "-"
    }

    private var headerOppositionScoreText: String {
        if let snapshot = liveSnapshotForHeader {
            return "\(snapshot.theirGoals).\(snapshot.theirBehinds) (\(snapshot.theirPoints))"
        }
        if let liveStatsSnapshotForHeader {
            return "\(liveStatsSnapshotForHeader.theirPoints)"
        }
        return "-"
    }

    private var headerTeamPillWidth: CGFloat {
        let font = UIFont.systemFont(ofSize: 18, weight: .bold)
        let longestName = max(clubName.count, oppositionName.count) == clubName.count ? clubName : oppositionName
        let measured = (longestName as NSString).size(withAttributes: [.font: font]).width
        return min(max(measured + 32, 120), 280)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                headerCountdownBadge(
                                    headerCountdownLabel(at: context.date),
                                    tint: headerCountdownTint(at: context.date),
                                    background: headerCountdownBackground(at: context.date)
                                )
                            }
                            Spacer(minLength: 0)
                            headerQuarterBadge(headerQuarterLabel)
                        }

                        headerTeamScorePill(
                            name: clubName,
                            score: headerOurScoreText,
                            teamStyle: style(for: clubName)
                        )

                        headerTeamScorePill(
                            name: oppositionName,
                            score: headerOppositionScoreText,
                            teamStyle: style(for: oppositionName)
                        )

                        if let tallySyncError {
                            Label(tallySyncError, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    if selections.isEmpty {
                        ContentUnavailableView(
                            "No Stats Selected",
                            systemImage: "rectangle.grid.2x2",
                            description: Text("Choose some stats first to preview the invite screen.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                    } else {
                        if !ourSelections.isEmpty {
                            previewStatsSection(
                                title: clubName,
                                selections: ourSelections,
                                availableWidth: proxy.size.width
                            )
                        }
                        if !oppositionSelections.isEmpty {
                            previewStatsSection(
                                title: oppositionName,
                                selections: oppositionSelections,
                                availableWidth: proxy.size.width
                            )
                        }
                    }
                }
                .padding(20)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: clubConfiguration.clubTeam.primaryColorHex, fallback: .blue).opacity(0.16),
                        Color(.systemBackground),
                        Color(.secondarySystemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .navigationTitle(gradeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: sessionID?.uuidString) {
            await monitorPersistedTallies()
        }
        .onAppear {
            if let syncSessionDescriptor {
                navigationState.setActiveUserStatsSession(syncSessionDescriptor)
            }
        }
        .onChange(of: syncSessionDescriptor) { _, newValue in
            navigationState.setActiveUserStatsSession(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .statsTalliesDidChange)) { notification in
            guard let sessionID else { return }
            if let tally = CloudKitStatsInviteService.tally(from: notification),
               tally.sessionID == sessionID {
                applyPersistedTallyUpdate(tally)
            } else {
                Task {
                    await refreshPersistedTallies()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .statsPlayerEventsDidChange)) { notification in
            guard let sessionID else { return }
            if let event = CloudKitStatsInviteService.playerEvent(from: notification),
               event.sessionID == sessionID {
                persistedPlayerEventsByID[event.id] = event
                lastPersistedPlayerEventUpdateAt = max(
                    lastPersistedPlayerEventUpdateAt ?? .distantPast,
                    event.updatedAt
                )
            } else {
                Task {
                    await refreshPersistedPlayerEvents(sessionID: sessionID, forceFullRefresh: true)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .statsSessionStateDidChange)) { notification in
            guard let sessionID else { return }
            if let state = CloudKitStatsInviteService.sessionState(from: notification),
               state.sessionID == sessionID {
                cloudSessionState = state
            } else {
                Task {
                    await refreshCloudSessionState()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    guard hasUndoableSelection else { return }
                    showUndoLastStatPrompt = true
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!hasUndoableSelection)
                .accessibilityLabel("Undo last stat")
            }
            ToolbarItem(placement: .topBarTrailing) {
                syncStatusToolbarButton
            }
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Sync Issues", isPresented: $showSyncIssues) {
            if syncStatus?.state == .orange && syncStatus?.canManuallySyncGameAndStats == true {
                Button("Sync") {
                    if let syncSessionDescriptor {
                        navigationState.syncActiveLiveGame(toStatsSessionID: syncSessionDescriptor.sessionID)
                    }
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(syncIssuesMessage)
        }
        .alert("Undo last stat?", isPresented: $showUndoLastStatPrompt) {
            Button("Cancel", role: .cancel) {}
            Button("Undo", role: .destructive) {
                undoLastEnteredSelection()
            }
        } message: {
            Text(undoPromptMessage)
        }
        .alert("No Players Available", isPresented: $showMissingPlayersAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add active players to this grade before recording individual stats from the stat taker view.")
        }
        .sheet(item: $selectedIndividualSelection) { selection in
            NavigationStack {
                Form {
                    Section("Player") {
                        ForEach(sortedAvailablePlayers) { player in
                            HStack(spacing: 12) {
                                Text(invitePlayerRowTitle(for: player))
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                                if invitePlayerSortMode == .dynamic {
                                    let possessions = invitePlayerPossessionCounts[player.id, default: 0]
                                    if possessions > 0 {
                                        Text("\(possessions)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        highlightedInvitePlayerID == player.id
                                        ? Color.blue
                                        : Color.clear
                                    )
                            )
                            .contentShape(Rectangle())
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .onTapGesture {
                                guard highlightedInvitePlayerID == nil else { return }
                                handleInvitePlayerSelection(selection, playerID: player.id)
                            }
                        }
                    }
                }
                .navigationTitle(statName(for: selection))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            selectedIndividualSelection = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Menu {
                            Picker("Sort Players", selection: $invitePlayerSortMode) {
                                ForEach(InvitePlayerSortMode.allCases) { mode in
                                    Label(mode.title, systemImage: mode.systemImage)
                                        .tag(mode)
                                }
                            }
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down")
                        }
                    }
                }
            }
        }
        .onDisappear {
            highlightedInvitePlayerTask?.cancel()
            statusBannerTask?.cancel()
            navigationState.clearActiveUserStatsSession(id: syncSessionDescriptor?.sessionID)
        }
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

    private func previewStatsSection(title: String, selections: [StatsInviteSelection], availableWidth: CGFloat) -> some View {
        let groups = selections.chunked(into: 4)
        return VStack(alignment: .leading, spacing: 16) {
            ScorePill(title, style: style(for: title))

            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                previewButtonGroupCard(
                    selections: group,
                    availableWidth: availableWidth,
                    sectionTitle: groups.count > 1 ? "Section \(index + 1)" : nil
                )
            }
        }
    }

    private func headerTeamScorePill(name: String, score: String, teamStyle: ClubStyle.Style) -> some View {
        HStack(spacing: 12) {
            Text(name)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .frame(width: headerTeamPillWidth)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(teamStyle.background)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(teamStyle.border.opacity(0.95), lineWidth: 1.5)
                )

            Spacer(minLength: 0)

            Text(score)
                .font(.system(size: 46, weight: .black, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(teamStyle.text)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func previewButtonGroupCard(
        selections: [StatsInviteSelection],
        availableWidth: CGFloat,
        sectionTitle: String?
    ) -> some View {
        let columnCount = availableWidth > 900 ? 3 : 2
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: max(1, min(columnCount, selections.count)))

        return VStack(alignment: .leading, spacing: 14) {
            if let sectionTitle {
                Text(sectionTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(selections) { selection in
                    previewButton(for: selection)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func previewButton(for selection: StatsInviteSelection) -> some View {
        let count = displayCount(for: selection)
        return Button {
            handleSelectionTap(selection)
        } label: {
            ZStack(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(statName(for: selection))
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    Text("\(count)")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if isIndividualSelection(selection) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 13, weight: .bold))
                        .padding(8)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(buttonBackground(for: selection), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .onLongPressGesture {
            guard hasUndoableSelection else { return }
            showUndoLastStatPrompt = true
        }
    }

    private func style(for title: String) -> ClubStyle.Style {
        ClubStyle.style(for: title, configuration: clubConfiguration)
    }

    private func buttonBackground(for selection: StatsInviteSelection) -> LinearGradient {
        switch selection.side {
        case .ourClub:
            let primary = Color(hex: clubConfiguration.clubTeam.primaryColorHex, fallback: .blue)
            let secondary = Color(hex: clubConfiguration.clubTeam.secondaryColorHex ?? clubConfiguration.clubTeam.primaryColorHex, fallback: .blue)
            return LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .opposition:
            let style = ClubStyle.style(for: oppositionName, configuration: clubConfiguration)
            return LinearGradient(colors: [style.background, style.border], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func statName(for selection: StatsInviteSelection) -> String {
        if let displayName = selectionDisplayNamesByRawValue[selection.rawValue] {
            return displayName.replacingOccurrences(of: "\(selection.side.selectionPrefix) ", with: "")
        }
        return statTypes.first(where: { $0.id == selection.statTypeID })?.name ?? "Stat"
    }

    private func isIndividualSelection(_ selection: StatsInviteSelection) -> Bool {
        if let rawValue = selectionCollectionModeByRawValue[selection.rawValue] {
            return SessionStatCollectionMode(rawValue: rawValue) == .individual
        }
        let defaultName = statTypes.first(where: { $0.id == selection.statTypeID })?.name ?? ""
        return defaultSessionStatCollectionMode(for: defaultName) == .individual
    }

    @MainActor
    private func handleSelectionTap(_ selection: StatsInviteSelection) {
        if isIndividualSelection(selection), selection.side == .ourClub {
            guard !sortedAvailablePlayers.isEmpty else {
                showMissingPlayersAlert = true
                return
            }
            selectedIndividualSelection = selection
            return
        }
        recordSelectionTap(selection)
    }

    @MainActor
    private func recordIndividualSelectionTap(_ selection: StatsInviteSelection, playerID: UUID) {
        statTapHaptic.prepare()
        statTapHaptic.impactOccurred(intensity: 1.0)

        let eventID = UUID()
        let event = CloudStatsInvitePlayerEvent(
            id: CloudKitStatsInviteService.playerEventRecordName(eventID: eventID),
            eventID: eventID,
            sessionID: sessionID ?? UUID(),
            statTypeID: selection.statTypeID,
            sideRawValue: selection.side.rawValue,
            playerID: playerID,
            quarter: resolvedQuarterLabel,
            timestamp: Date(),
            updatedAt: Date()
        )
        pendingCreatedPlayerEventsByID[event.id] = event
        recentEnteredSelections.append(
            RecentInviteSelectionEntry(selection: selection, playerEventID: event.id)
        )
        showStatusBanner(
            text: inviteSelectionSuccessBannerText(for: selection, playerID: playerID),
            isSuccess: true
        )
        if sessionID != nil {
            queuePlayerEventSync()
        }
    }

    @MainActor
    private func handleInvitePlayerSelection(_ selection: StatsInviteSelection, playerID: UUID) {
        guard highlightedInvitePlayerID == nil else { return }
        highlightedInvitePlayerTask?.cancel()
        highlightedInvitePlayerID = playerID
        recordIndividualSelectionTap(selection, playerID: playerID)
        highlightedInvitePlayerTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                highlightedInvitePlayerID = nil
                highlightedInvitePlayerTask = nil
                selectedIndividualSelection = nil
            }
        }
    }

    private func inviteSelectionSuccessBannerText(for selection: StatsInviteSelection, playerID: UUID) -> String {
        var segments = [
            inviteTeamBannerLabel(for: selection.side),
            statName(for: selection).uppercased()
        ]
        if let playerSurname = inviteIndividualPlayerBannerLabel(for: playerID) {
            segments.append(playerSurname.uppercased())
        }
        return segments.joined(separator: " - ")
    }

    private func inviteTeamBannerLabel(for side: StatsInviteTeamSide) -> String {
        switch side {
        case .ourClub:
            return clubName.uppercased()
        case .opposition:
            return oppositionName.uppercased()
        }
    }

    private func inviteIndividualPlayerBannerLabel(for playerID: UUID) -> String? {
        guard let player = availablePlayers.first(where: { $0.id == playerID }) else { return nil }
        return player.lastName.isEmpty ? player.name : player.lastName
    }

    private var resolvedQuarterLabel: String {
        let label = headerQuarterLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty || label == "Q-" ? "Q1" : label
    }

    @MainActor
    private func loadPersistedTallies() async {
        guard let sessionID else { return }
        do {
            let tallies = try await CloudKitStatsInviteService.shared.fetchTallies(
                sessionID: sessionID,
                statTypeIDs: Array(Set(selections.map(\.statTypeID))),
                sideRawValues: Array(Set(selections.map(\.side.rawValue)))
            )
            persistedCountsBySelectionID = Dictionary(
                uniqueKeysWithValues: tallies.map {
                    ("\($0.statTypeID.uuidString)|\($0.sideRawValue)", $0.count)
                }
            )
            await refreshPersistedPlayerEvents(sessionID: sessionID, forceFullRefresh: true)
            lastPersistedTallyUpdateAt = tallies.map(\.updatedAt).max()
            tallySyncError = nil
        } catch {
            tallySyncError = "CloudKit read failed: \(error.localizedDescription)"
            return
        }
    }

    private func monitorPersistedTallies() async {
        await loadPersistedTallies()
        await loadCloudSessionState()
        guard sessionID != nil else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: invitePollIntervalNanoseconds)
            guard !Task.isCancelled else { return }
            await refreshPersistedTallies()
            if let sessionID {
                await refreshPersistedPlayerEvents(sessionID: sessionID, forceFullRefresh: false)
            }
            await refreshCloudSessionState()
        }
    }

    @MainActor
    private func refreshPersistedTallies() async {
        guard let sessionID else { return }
        let statTypeIDs = Array(Set(selections.map(\.statTypeID)))
        let sideRawValues = Array(Set(selections.map(\.side.rawValue)))
        guard !statTypeIDs.isEmpty, !sideRawValues.isEmpty else { return }

        do {
            let tallies: [CloudStatsInviteTally]
            if let lastPersistedTallyUpdateAt {
                tallies = try await CloudKitStatsInviteService.shared.fetchTallies(
                    sessionID: sessionID,
                    statTypeIDs: statTypeIDs,
                    sideRawValues: sideRawValues,
                    updatedAfter: lastPersistedTallyUpdateAt
                )
            } else {
                tallies = try await CloudKitStatsInviteService.shared.fetchTallies(
                    sessionID: sessionID,
                    statTypeIDs: statTypeIDs,
                    sideRawValues: sideRawValues
                )
            }

            guard !tallies.isEmpty else { return }
            for tally in tallies {
                applyPersistedTallyUpdate(tally)
            }
            tallySyncError = nil
        } catch {
            tallySyncError = "CloudKit read failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func refreshPersistedPlayerEvents(sessionID: UUID, forceFullRefresh: Bool) async {
        do {
            let playerEvents: [CloudStatsInvitePlayerEvent]
            if forceFullRefresh || lastPersistedPlayerEventUpdateAt == nil {
                playerEvents = try await CloudKitStatsInviteService.shared.fetchPlayerEvents(sessionID: sessionID)
                persistedPlayerEventsByID = Dictionary(
                    uniqueKeysWithValues: playerEvents
                        .filter { !pendingCreatedPlayerEventsByID.keys.contains($0.id) && !pendingDeletedPlayerEventIDs.contains($0.id) }
                        .map { ($0.id, $0) }
                )
            } else if let lastPersistedPlayerEventUpdateAt {
                playerEvents = try await CloudKitStatsInviteService.shared.fetchPlayerEvents(
                    sessionID: sessionID,
                    updatedAfter: lastPersistedPlayerEventUpdateAt
                )
                for event in playerEvents
                where !pendingCreatedPlayerEventsByID.keys.contains(event.id) && !pendingDeletedPlayerEventIDs.contains(event.id) {
                    persistedPlayerEventsByID[event.id] = event
                }
            } else {
                playerEvents = []
            }

            if forceFullRefresh, playerEvents.isEmpty {
                lastPersistedPlayerEventUpdateAt = nil
            } else if let latestUpdatedAt = playerEvents.map(\.updatedAt).max() {
                lastPersistedPlayerEventUpdateAt = max(
                    lastPersistedPlayerEventUpdateAt ?? .distantPast,
                    latestUpdatedAt
                )
            }
        } catch {
            if error.localizedDescription.contains("Did not find record type: StatsPlayerEvent") {
                persistedPlayerEventsByID = [:]
                lastPersistedPlayerEventUpdateAt = nil
                return
            }
            tallySyncError = "CloudKit read failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadCloudSessionState() async {
        guard let sessionID else { return }
        do {
            cloudSessionState = try await CloudKitStatsInviteService.shared.fetchSessionState(sessionID: sessionID)
        } catch {
            return
        }
    }

    @MainActor
    private func refreshCloudSessionState() async {
        guard let sessionID else { return }
        do {
            if let state = try await CloudKitStatsInviteService.shared.fetchSessionState(sessionID: sessionID) {
                cloudSessionState = state
            }
        } catch {
            return
        }
    }

    @MainActor
    private func queueTallySync(for sessionID: UUID) {
        guard tallySyncTask == nil else { return }
        tallySyncTask = Task {
            defer {
                Task { @MainActor in
                    tallySyncTask = nil
                    if !pendingSyncDeltasBySelectionID.isEmpty {
                        queueTallySync(for: sessionID)
                    }
                }
            }
            await flushPendingTallies(sessionID: sessionID)
        }
    }

    private func flushPendingTallies(sessionID: UUID) async {
        while !Task.isCancelled {
            guard let next = nextPendingSelectionForSync() else { return }
            do {
                let tally = try await CloudKitStatsInviteService.shared.incrementTally(
                    sessionID: sessionID,
                    statTypeID: next.selection.statTypeID,
                    sideRawValue: next.selection.side.rawValue,
                    amount: next.amount
                )
                await MainActor.run {
                    inFlightSyncDeltasBySelectionID[next.selection.id, default: 0] -= next.amount
                    if inFlightSyncDeltasBySelectionID[next.selection.id] == 0 {
                        inFlightSyncDeltasBySelectionID[next.selection.id] = nil
                    }
                    applyPersistedTallyUpdate(tally)
                    tallySyncError = nil
                }
            } catch {
                await MainActor.run {
                    inFlightSyncDeltasBySelectionID[next.selection.id, default: 0] -= next.amount
                    if inFlightSyncDeltasBySelectionID[next.selection.id] == 0 {
                        inFlightSyncDeltasBySelectionID[next.selection.id] = nil
                    }
                    pendingSyncDeltasBySelectionID[next.selection.id, default: 0] += next.amount
                    tallySyncError = "CloudKit write failed: \(error.localizedDescription)"
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    @MainActor
    private func nextPendingSelectionForSync() -> (selection: StatsInviteSelection, amount: Int)? {
        guard let entry = pendingSyncDeltasBySelectionID.first(where: { $0.value != 0 }),
              let selection = StatsInviteSelection(rawValue: entry.key) else {
            return nil
        }
        pendingSyncDeltasBySelectionID[entry.key] = nil
        inFlightSyncDeltasBySelectionID[entry.key, default: 0] += entry.value
        if inFlightSyncDeltasBySelectionID[entry.key] == 0 {
            inFlightSyncDeltasBySelectionID[entry.key] = nil
        }
        return (selection, entry.value)
    }

    @MainActor
    private func applyPersistedTallyUpdate(_ tally: CloudStatsInviteTally) {
        let selectionID = "\(tally.statTypeID.uuidString)|\(tally.sideRawValue)"
        persistedCountsBySelectionID[selectionID] = tally.count
        lastPersistedTallyUpdateAt = max(lastPersistedTallyUpdateAt ?? .distantPast, tally.updatedAt)
    }

    @MainActor
    private func recordSelectionTap(_ selection: StatsInviteSelection) {
        statTapHaptic.prepare()
        statTapHaptic.impactOccurred(intensity: 1.0)
        adjustSelection(selection, delta: 1)
        recentEnteredSelections.append(RecentInviteSelectionEntry(selection: selection, playerEventID: nil))
    }

    @MainActor
    private func undoLastEnteredSelection() {
        while let last = recentEnteredSelections.popLast() {
            if let playerEventID = last.playerEventID {
                undoPlayerEvent(id: playerEventID)
                return
            }
            guard displayCount(for: last.selection) > 0 else { continue }
            adjustSelection(last.selection, delta: -1)
            return
        }
    }

    @MainActor
    private func adjustSelection(_ selection: StatsInviteSelection, delta: Int) {
        guard delta != 0 else { return }
        let currentCount = displayCount(for: selection)
        let nextCount = max(0, currentCount + delta)
        guard nextCount != currentCount else { return }

        let appliedDelta = nextCount - currentCount
        pendingSyncDeltasBySelectionID[selection.id, default: 0] += appliedDelta
        if pendingSyncDeltasBySelectionID[selection.id] == 0 {
            pendingSyncDeltasBySelectionID[selection.id] = nil
        }

        if let sessionID {
            queueTallySync(for: sessionID)
        }
    }

    @MainActor
    private func undoPlayerEvent(id: String) {
        if pendingCreatedPlayerEventsByID.removeValue(forKey: id) != nil {
            return
        }
        guard let persisted = persistedPlayerEventsByID.removeValue(forKey: id) else { return }
        pendingDeletedPlayerEventIDs.insert(id)
        if sessionID != nil {
            queuePlayerEventSync()
        } else {
            pendingDeletedPlayerEventIDs.remove(id)
            persistedPlayerEventsByID[id] = persisted
        }
    }

    @MainActor
    private func queuePlayerEventSync() {
        guard playerEventSyncTask == nil else { return }
        playerEventSyncTask = Task {
            defer {
                Task { @MainActor in
                    playerEventSyncTask = nil
                    if !pendingCreatedPlayerEventsByID.isEmpty || !pendingDeletedPlayerEventIDs.isEmpty {
                        queuePlayerEventSync()
                    }
                }
            }
            await flushPendingPlayerEvents()
        }
    }

    private func flushPendingPlayerEvents() async {
        while !Task.isCancelled {
            let nextCreate: CloudStatsInvitePlayerEvent? = await MainActor.run {
                nextPendingPlayerEventCreate()
            }
            if let nextCreate {
                do {
                    let savedEvent = try await CloudKitStatsInviteService.shared.savePlayerEvent(
                        eventID: nextCreate.eventID,
                        sessionID: nextCreate.sessionID,
                        statTypeID: nextCreate.statTypeID,
                        sideRawValue: nextCreate.sideRawValue,
                        playerID: nextCreate.playerID,
                        quarter: nextCreate.quarter,
                        timestamp: nextCreate.timestamp
                    )
                    await MainActor.run {
                        if pendingCreatedPlayerEventsByID.removeValue(forKey: savedEvent.id) != nil {
                            persistedPlayerEventsByID[savedEvent.id] = savedEvent
                        } else {
                            persistedPlayerEventsByID[savedEvent.id] = savedEvent
                            pendingDeletedPlayerEventIDs.insert(savedEvent.id)
                            queuePlayerEventSync()
                        }
                        tallySyncError = nil
                    }
                    continue
                } catch {
                    await MainActor.run {
                        pendingCreatedPlayerEventsByID[nextCreate.id] = nextCreate
                        tallySyncError = "CloudKit write failed: \(error.localizedDescription)"
                    }
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    continue
                }
            }

            let nextDelete: String? = await MainActor.run {
                nextPendingPlayerEventDeletion()
            }
            if let nextDelete {
                do {
                    try await CloudKitStatsInviteService.shared.deletePlayerEvent(recordName: nextDelete)
                    await MainActor.run {
                        pendingDeletedPlayerEventIDs.remove(nextDelete)
                        persistedPlayerEventsByID.removeValue(forKey: nextDelete)
                        tallySyncError = nil
                    }
                    continue
                } catch {
                    await MainActor.run {
                        pendingDeletedPlayerEventIDs.insert(nextDelete)
                        tallySyncError = "CloudKit write failed: \(error.localizedDescription)"
                    }
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    continue
                }
            }

            return
        }
    }

    @MainActor
    private func nextPendingPlayerEventCreate() -> CloudStatsInvitePlayerEvent? {
        pendingCreatedPlayerEventsByID.values.sorted { lhs, rhs in
            lhs.timestamp < rhs.timestamp
        }.first
    }

    @MainActor
    private func nextPendingPlayerEventDeletion() -> String? {
        pendingDeletedPlayerEventIDs.sorted().first
    }

    private func displayCount(for selection: StatsInviteSelection) -> Int {
        if isIndividualSelection(selection), selection.side == .ourClub {
            let persisted = persistedPlayerEventsByID.values.reduce(0) { partialResult, event in
                guard event.statTypeID == selection.statTypeID, event.sideRawValue == selection.side.rawValue else {
                    return partialResult
                }
                return partialResult + 1
            }
            let pending = pendingCreatedPlayerEventsByID.values.reduce(0) { partialResult, event in
                guard event.statTypeID == selection.statTypeID, event.sideRawValue == selection.side.rawValue else {
                    return partialResult
                }
                return partialResult + 1
            }
            return persisted + pending
        }
        let persisted = persistedCountsBySelectionID[selection.id, default: 0]
        let pending = pendingSyncDeltasBySelectionID[selection.id, default: 0]
        let inFlight = inFlightSyncDeltasBySelectionID[selection.id, default: 0]
        return max(0, persisted + pending + inFlight)
    }

    private var undoPromptMessage: String {
        guard let entry = recentEnteredSelections.last else {
            return "Undo the last stat entered?"
        }
        return "Undo the last \(statName(for: entry.selection)) stat entered?"
    }

    @ViewBuilder
    private var syncStatusToolbarButton: some View {
        if let syncStatus {
            Button {
                guard syncStatus.state != .green else { return }
                showSyncIssues = true
            } label: {
                Image(systemName: syncStatusIconName)
                    .foregroundStyle(syncStatusTint)
            }
            .accessibilityLabel(syncStatusAccessibilityLabel)
            .disabled(syncStatus.state == .green)
        } else {
            Image(systemName: syncStatusIconName)
                .foregroundStyle(syncStatusTint)
                .accessibilityLabel("Sync status")
        }
    }

    private func headerQuarterBadge(_ label: String) -> some View {
        Text(label)
            .font(.caption.weight(.black))
            .foregroundStyle(headerQuarterBadgeTint)
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .background(headerQuarterBadgeBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    private func headerCountdownBadge(_ label: String, tint: Color, background: AnyShapeStyle) -> some View {
        Text(label)
            .font(.caption.weight(.black))
            .monospacedDigit()
            .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
        .background(background, in: RoundedRectangle(cornerRadius: 10))
    }

    private var headerQuarterBadgeBackground: AnyShapeStyle {
        isHeaderMatchStateActive(at: Date())
            ? AnyShapeStyle(Color.green.opacity(0.22))
            : AnyShapeStyle(.ultraThinMaterial)
    }

    private func headerCountdownBackground(at date: Date) -> AnyShapeStyle {
        if isHeaderMatchStateActive(at: date) {
            if let remaining = headerRemainingSeconds(at: date), remaining <= (2 * 60) {
                return AnyShapeStyle(Color.red)
            }
            return AnyShapeStyle(headerCountdownTint(at: date).opacity(0.22))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private var headerQuarterBadgeTint: Color {
        isHeaderMatchStateActive(at: Date()) ? .green : .primary
    }

    private func isHeaderMatchStateActive(at date: Date) -> Bool {
        isHeaderTimerRunning(at: date)
    }
}

private struct LiveStatsSessionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StatType.sortOrder) private var allStatTypes: [StatType]

    let session: StatsSession

    @State private var enabledStatTypeIDs: Set<UUID> = []
    @State private var collectionModesByStatTypeID: [UUID: SessionStatCollectionMode] = [:]

    private var availableStatTypes: [StatType] {
        allStatTypes
            .filter(\.isEnabled)
            .sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    private var groupedStatTypes: [(title: String, items: [StatType])] {
        let sections: [(String, [String])] = [
            ("Ball Movement", ["Kick", "Handball", "Mark", "Tackle"]),
            ("Scoring", ["Goal", "Behind"]),
            ("Team Metrics", ["Inside 50", "Clearance", "Hit Out", "Free Kick", "Turnover", "Intercept"]),
            ("Derived", ["Disposal Efficiency", "Contested Possession"])
        ]

        var grouped: [(String, [StatType])] = sections.compactMap { title, names in
            let items = names.compactMap { name in
                availableStatTypes.first(where: {
                    $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame
                })
            }
            return items.isEmpty ? nil : (title, items)
        }

        let consumedIDs = Set(grouped.flatMap { $0.1.map(\.id) })
        let extras = availableStatTypes.filter { !consumedIDs.contains($0.id) }
        if !extras.isEmpty {
            grouped.append(("Extra Stats", extras))
        }
        return grouped
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Session Stats")
                            .font(.headline)
                        Text("Turn stats on or off for this live session only. Changes apply immediately to the Live Stats view.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                ForEach(groupedStatTypes, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.items) { statType in
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle(isOn: binding(for: statType.id)) {
                                    HStack(spacing: 10) {
                                        Text(statType.name)
                                        Spacer()
                                        if isDerivedStat(statType.name) {
                                            Text("Derived")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                if enabledStatTypeIDs.contains(statType.id) && supportsCollectionModePicker(for: statType) {
                                    Picker("Collection Mode", selection: modeBinding(for: statType.id, defaultName: statType.name)) {
                                        ForEach(SessionStatCollectionMode.allCases) { mode in
                                            Text(mode.rawValue).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Session Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Select All") {
                        enabledStatTypeIDs = Set(availableStatTypes.map(\.id))
                        persistEnabledStatTypeIDs()
                    }
                }
            }
            .onAppear {
                enabledStatTypeIDs = resolvedEnabledStatTypeIDs(for: session, allStatTypes: availableStatTypes)
                collectionModesByStatTypeID = session.statCollectionModes
            }
        }
    }

    private func binding(for statTypeID: UUID) -> Binding<Bool> {
        Binding(
            get: { enabledStatTypeIDs.contains(statTypeID) },
            set: { isEnabled in
                if isEnabled {
                    enabledStatTypeIDs.insert(statTypeID)
                } else {
                    enabledStatTypeIDs.remove(statTypeID)
                }
                persistEnabledStatTypeIDs()
            }
        )
    }

    private func persistEnabledStatTypeIDs() {
        let orderedIDs = availableStatTypes
            .map(\.id)
            .filter { enabledStatTypeIDs.contains($0) }
        session.setEnabledStatTypeIDs(orderedIDs)
        let validModes = collectionModesByStatTypeID.filter { enabledStatTypeIDs.contains($0.key) }
        session.setStatCollectionModes(validModes)
        try? modelContext.save()
    }

    private func isDerivedStat(_ name: String) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedName == "disposal efficiency" || normalizedName == "contested possession"
    }

    private func supportsCollectionModePicker(for statType: StatType) -> Bool {
        !isDerivedStat(statType.name)
    }

    private func modeBinding(for statTypeID: UUID, defaultName: String) -> Binding<SessionStatCollectionMode> {
        Binding(
            get: { collectionModesByStatTypeID[statTypeID] ?? defaultSessionStatCollectionMode(for: defaultName) },
            set: { mode in
                collectionModesByStatTypeID[statTypeID] = mode
                persistEnabledStatTypeIDs()
            }
        )
    }
}

@MainActor
struct StatTakerStatsView: View {
    @EnvironmentObject private var authCoordinator: AuthenticationCoordinator
    @EnvironmentObject private var navigationState: AppNavigationState
    @Query(sort: \Grade.displayOrder) private var grades: [Grade]
    @Query(sort: \Player.name) private var players: [Player]
    @Query(sort: \StatType.sortOrder) private var allStatTypes: [StatType]
    @State private var cloudAssignments: [CloudStatsInviteAssignment] = []
    @State private var cloudSessionStatesBySessionID: [UUID: CloudStatsInviteSessionState] = [:]
    @State private var loadError: String?
    @State private var isLoadingAssignments = false
    @State private var selectedAssignment: CloudStatsInviteAssignment?
    private let liveSessionActivityTimeout: TimeInterval = 5
    private let staleSessionCleanupTimeout: TimeInterval = 15 * 60

    private var clubConfiguration: ClubConfiguration {
        ClubConfigurationStore.load()
    }

    private var clubName: String {
        let trimmed = clubConfiguration.clubTeam.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Min Man" : trimmed
    }

    private var enabledStatTypes: [StatType] {
        allStatTypes.filter(\.isEnabled).sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    private var visibleAssignments: [CloudStatsInviteAssignment] {
        cloudAssignments.filter { hasUsableLiveSessionState(for: $0) }
    }

    private var orderedAssignments: [CloudStatsInviteAssignment] {
        visibleAssignments.sorted { left, right in
            let leftStatus = sessionAvailability(for: left)
            let rightStatus = sessionAvailability(for: right)

            if left.sessionID == navigationState.pendingStatsInviteSessionID,
               right.sessionID != navigationState.pendingStatsInviteSessionID {
                return true
            }
            if right.sessionID == navigationState.pendingStatsInviteSessionID,
               left.sessionID != navigationState.pendingStatsInviteSessionID {
                return false
            }
            if leftStatus.sortPriority != rightStatus.sortPriority {
                return leftStatus.sortPriority < rightStatus.sortPriority
            }
            if left.sessionDate != right.sessionDate {
                return left.sessionDate > right.sessionDate
            }
            return left.gradeName.localizedCaseInsensitiveCompare(right.gradeName) == .orderedAscending
        }
    }

    private func selections(for assignment: CloudStatsInviteAssignment) -> [StatsInviteSelection] {
        let selections = assignment.assignedSelectionRawValues.compactMap(StatsInviteSelection.init(rawValue:))
        let sortOrderByID = Dictionary(uniqueKeysWithValues: enabledStatTypes.map { ($0.id, $0.sortOrder) })
        return selections.sorted {
            let leftOrder = sortOrderByID[$0.statTypeID] ?? 0
            let rightOrder = sortOrderByID[$1.statTypeID] ?? 0
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            if $0.side != $1.side {
                return $0.side == .ourClub
            }
            return false
        }
    }

    private func availablePlayers(for assignment: CloudStatsInviteAssignment) -> [Player] {
        let rosterPlayers = cloudSessionStatesBySessionID[assignment.sessionID]?.availablePlayers ?? assignment.availablePlayers
        let syncedPlayers = rosterPlayers.map { player in
            Player(id: player.id, name: player.name, number: player.number, gradeIDs: [], isActive: true)
        }
        if !syncedPlayers.isEmpty {
            return syncedPlayers
        }

        guard let gradeID = grades.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(assignment.gradeName.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
        })?.id else {
            return []
        }

        return players.filter { $0.isActive && $0.gradeIDs.contains(gradeID) }
    }

    private func syncDescriptor(for assignment: CloudStatsInviteAssignment) -> LiveStatsSyncSessionDescriptor? {
        let normalizedGradeName = assignment.gradeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedGradeID = grades.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(normalizedGradeName) == .orderedSame
        })?.id ?? {
            guard let activeDescriptor = navigationState.activeLiveStatsSessionDescriptor,
                  activeDescriptor.sessionID == assignment.sessionID else {
                return nil
            }
            return activeDescriptor.gradeID
        }()

        guard let gradeID = resolvedGradeID else {
            return nil
        }

        return LiveStatsSyncSessionDescriptor(
            sessionID: assignment.sessionID,
            gradeID: gradeID,
            opposition: assignment.oppositionName,
            date: assignment.sessionDate
        )
    }

    private func liveSessionState(for assignment: CloudStatsInviteAssignment) -> CloudStatsInviteSessionState? {
        guard let state = cloudSessionStatesBySessionID[assignment.sessionID],
              state.sessionID == assignment.sessionID else {
            return nil
        }
        return state
    }

    private func hasUsableLiveSessionState(for assignment: CloudStatsInviteAssignment) -> Bool {
        guard let state = liveSessionState(for: assignment) else { return false }
        return Date().timeIntervalSince(state.updatedAt) <= staleSessionCleanupTimeout
    }

    private func hasFreshLiveSessionState(for assignment: CloudStatsInviteAssignment) -> Bool {
        guard let state = liveSessionState(for: assignment) else { return false }
        return Date().timeIntervalSince(state.updatedAt) <= liveSessionActivityTimeout
    }

    private func sessionAvailability(for assignment: CloudStatsInviteAssignment) -> StatTakerSessionAvailability {
        if hasUsableLiveSessionState(for: assignment) {
            return .active
        }
        if Calendar.current.compare(assignment.sessionDate, to: Date(), toGranularity: .day) == .orderedAscending {
            return .complete
        }
        return .joinable
    }

    var body: some View {
        NavigationStack {
            if isLoadingAssignments && cloudAssignments.isEmpty {
                LoadingFootballView("Loading assignments…")
                    .navigationTitle("Stats View")
            } else if let loadError {
                ContentUnavailableView(
                    "Unable to Load Assignments",
                    systemImage: "icloud.slash",
                    description: Text(loadError)
                )
                .navigationTitle("Stats View")
            } else if orderedAssignments.isEmpty {
                ContentUnavailableView(
                    "No live stat sessions",
                    systemImage: "rectangle.grid.2x2",
                    description: Text("This view only shows sessions with an active live feed. When one is running, it will appear here with a green Join button.")
                )
                .navigationTitle("Stats View")
            } else {
                List {
                    Section("Available Stat Sessions") {
                        ForEach(orderedAssignments) { assignment in
                            Button {
                                selectedAssignment = assignment
                            } label: {
                                statSessionRow(for: assignment)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .navigationTitle("Stats View")
                .navigationDestination(item: $selectedAssignment) { assignment in
                    statsDetailView(for: assignment)
                }
            }
        }
        .task(id: statsRefreshTaskID) {
            await monitorAssignments()
        }
        .refreshable {
            await refreshAssignments()
        }
    }

    private func monitorAssignments() async {
        await refreshAssignments()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            await refreshAssignments()
        }
    }

    @MainActor
    private func refreshAssignments() async {
        guard let email = authCoordinator.emailAddress, !email.isEmpty else {
            cloudAssignments = []
            cloudSessionStatesBySessionID = [:]
            return
        }

        isLoadingAssignments = true
        defer { isLoadingAssignments = false }

        do {
            let assignments = try await CloudKitStatsInviteService.shared.markAssignmentsConnected(for: email)
            let datePrunedAssignments = await pruneExpiredAssignments(assignments)
            let validationResult = await validateAssignments(datePrunedAssignments)
            cloudAssignments = validationResult.assignments
            cloudSessionStatesBySessionID = validationResult.sessionStates
            if let pendingSessionID = navigationState.pendingStatsInviteSessionID,
               validationResult.assignments.contains(where: { $0.sessionID == pendingSessionID }) {
                navigationState.clearPendingStatsInvite()
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func pruneExpiredAssignments(
        _ assignments: [CloudStatsInviteAssignment]
    ) async -> [CloudStatsInviteAssignment] {
        let calendar = Calendar.current
        let expiredAssignments = assignments.filter {
            calendar.compare($0.sessionDate, to: Date(), toGranularity: .day) == .orderedAscending
        }

        guard !expiredAssignments.isEmpty else { return assignments }

        let expiredSessionIDs = Set(expiredAssignments.map(\.sessionID))
        Task {
            for sessionID in expiredSessionIDs {
                await CloudKitStatsInviteService.shared.deleteSessionArtifacts(sessionID: sessionID)
            }
        }

        return assignments.filter { !expiredSessionIDs.contains($0.sessionID) }
    }

    private func validateAssignments(
        _ assignments: [CloudStatsInviteAssignment]
    ) async -> (assignments: [CloudStatsInviteAssignment], sessionStates: [UUID: CloudStatsInviteSessionState]) {
        await withTaskGroup(
            of: (
                assignment: CloudStatsInviteAssignment,
                state: CloudStatsInviteSessionState?,
                shouldDelete: Bool
            ).self
        ) { group in
            for assignment in assignments {
                group.addTask {
                    do {
                        let state = try await CloudKitStatsInviteService.shared.fetchSessionState(sessionID: assignment.sessionID)
                        let shouldDelete = Self.shouldDeleteCloudAssignment(
                            assignment,
                            sessionState: state,
                            staleSessionCleanupTimeout: staleSessionCleanupTimeout
                        )
                        return (
                            assignment: assignment,
                            state: state,
                            shouldDelete: shouldDelete
                        )
                    } catch {
                        return (
                            assignment: assignment,
                            state: nil,
                            shouldDelete: false
                        )
                    }
                }
            }

            var validAssignments: [CloudStatsInviteAssignment] = []
            var sessionStates: [UUID: CloudStatsInviteSessionState] = [:]
            var orphanedSessionIDs: Set<UUID> = []

            for await result in group {
                if let state = result.state {
                    sessionStates[result.assignment.sessionID] = state
                }

                if result.shouldDelete {
                    orphanedSessionIDs.insert(result.assignment.sessionID)
                } else {
                    validAssignments.append(result.assignment)
                }
            }

            if !orphanedSessionIDs.isEmpty {
                Task {
                    for sessionID in orphanedSessionIDs {
                        await CloudKitStatsInviteService.shared.deleteSessionArtifacts(sessionID: sessionID)
                    }
                }
            }

            return (
                assignments: validAssignments.sorted { $0.sessionDate > $1.sessionDate },
                sessionStates: sessionStates
            )
        }
    }

    nonisolated private static func shouldDeleteCloudAssignment(
        _ assignment: CloudStatsInviteAssignment,
        sessionState: CloudStatsInviteSessionState?,
        staleSessionCleanupTimeout: TimeInterval
    ) -> Bool {
        guard let sessionState else { return true }

        let now = Date()
        if now.timeIntervalSince(sessionState.updatedAt) > staleSessionCleanupTimeout {
            return true
        }

        if Calendar.current.compare(assignment.sessionDate, to: now, toGranularity: .day) == .orderedAscending {
            return true
        }

        return false
    }

    @ViewBuilder
    private func statsDetailView(for assignment: CloudStatsInviteAssignment) -> some View {
        let selections = selections(for: assignment)
        StatsInviteLivePreviewView(
            clubConfiguration: clubConfiguration,
            clubName: clubName,
            gradeTitle: assignment.gradeName,
            oppositionName: assignment.oppositionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Opposition" : assignment.oppositionName,
            selections: selections,
            statTypes: enabledStatTypes,
            selectionDisplayNamesByRawValue: assignment.assignedSelectionDisplayNameByRawValue,
            selectionCollectionModeByRawValue: assignment.assignedSelectionCollectionModeByRawValue,
            availablePlayers: availablePlayers(for: assignment),
            sessionID: assignment.sessionID,
            syncSessionDescriptor: syncDescriptor(for: assignment),
            showsDoneButton: false
        )
    }

    private func statSessionRow(for assignment: CloudStatsInviteAssignment) -> some View {
        let availability = sessionAvailability(for: assignment)
        let hasPendingInvite = assignment.sessionID == navigationState.pendingStatsInviteSessionID

        return HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(availability.color)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(assignment.gradeName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(assignment.oppositionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Opposition" : assignment.oppositionName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(assignment.sessionDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(availability.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(availability.color)
                if hasPendingInvite {
                    Text("New")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.14))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statsRefreshTaskID: String {
        let email = authCoordinator.emailAddress ?? ""
        let pending = navigationState.pendingStatsInviteSessionID?.uuidString ?? ""
        return "\(email)|\(pending)"
    }
}

private enum StatTakerSessionAvailability {
    case active
    case joinable
    case complete

    var color: Color {
        switch self {
        case .active:
            return .green
        case .joinable:
            return .orange
        case .complete:
            return .red
        }
    }

    var label: String {
        switch self {
        case .active:
            return "Join"
        case .joinable:
            return "Joinable"
        case .complete:
            return "Complete"
        }
    }

    var sortPriority: Int {
        switch self {
        case .active:
            return 0
        case .joinable:
            return 1
        case .complete:
            return 2
        }
    }
}

struct StatsInvitePreviewSettingsView: View {
    @Query(sort: \Grade.displayOrder) private var grades: [Grade]
    @Query(sort: \StatType.sortOrder) private var allStatTypes: [StatType]

    @AppStorage("statsInvitePreviewGradeID") private var previewGradeIDRaw = ""
    @AppStorage("statsInvitePreviewOpponentName") private var previewOpponentName = "Opposition"

    @State private var countsBySelectionID: [String: Int] = [:]

    private var clubConfiguration: ClubConfiguration {
        ClubConfigurationStore.load()
    }

    private var clubName: String {
        let trimmed = clubConfiguration.clubTeam.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Min Man" : trimmed
    }

    private var enabledStatTypes: [StatType] {
        allStatTypes.filter(\.isEnabled).sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    private var draftSelections: [StatsInviteSelection] {
        let sortOrderByID = Dictionary(uniqueKeysWithValues: enabledStatTypes.map { ($0.id, $0.sortOrder) })
        return StatsInviteDraftStore.loadSelections().sorted {
            let leftOrder = sortOrderByID[$0.statTypeID] ?? 0
            let rightOrder = sortOrderByID[$1.statTypeID] ?? 0
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            if $0.side != $1.side {
                return $0.side == .ourClub
            }
            return false
        }
    }

    private var selectedGrade: Grade? {
        guard let id = UUID(uuidString: previewGradeIDRaw) else {
            return grades.first
        }
        return grades.first(where: { $0.id == id }) ?? grades.first
    }

    private var gradeTitle: String {
        selectedGrade?.name ?? "Grade"
    }

    private var oppositionName: String {
        let trimmed = previewOpponentName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Opposition" : trimmed
    }

    private var ourSelections: [StatsInviteSelection] {
        draftSelections.filter { $0.side == .ourClub }
    }

    private var oppositionSelections: [StatsInviteSelection] {
        draftSelections.filter { $0.side == .opposition }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    previewHeader
                    previewControls

                    if draftSelections.isEmpty {
                        ContentUnavailableView(
                            "No Stats Selected",
                            systemImage: "rectangle.grid.2x2",
                            description: Text("Start a New Stats Session and turn stats on in the wizard to populate this preview.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                    } else {
                        if !ourSelections.isEmpty {
                            statsSection(
                                title: clubName,
                                selections: ourSelections,
                                availableWidth: proxy.size.width
                            )
                        }
                        if !oppositionSelections.isEmpty {
                            statsSection(
                                title: oppositionName,
                                selections: oppositionSelections,
                                availableWidth: proxy.size.width
                            )
                        }
                    }
                }
                .padding(20)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: clubConfiguration.clubTeam.primaryColorHex, fallback: .blue).opacity(0.16),
                        Color(.systemBackground),
                        Color(.secondarySystemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .navigationTitle("Stats View")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if previewGradeIDRaw.isEmpty, let firstGrade = grades.first {
                previewGradeIDRaw = firstGrade.id.uuidString
            }
            if previewOpponentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                previewOpponentName = clubConfiguration.sortedOppositions.first?.name ?? "Opposition"
            }
        }
    }

    private var previewHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Invited User Preview")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("\(clubName) vs \(oppositionName)")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            HStack(spacing: 10) {
                Label(gradeTitle, systemImage: "person.3.fill")
                Label("Live Stats", systemImage: "dot.radiowaves.left.and.right")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var previewControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preview Setup")
                .font(.headline)

            if !grades.isEmpty {
                Picker("Grade", selection: $previewGradeIDRaw) {
                    ForEach(grades) { grade in
                        Text(grade.name).tag(grade.id.uuidString)
                    }
                }
                .pickerStyle(.menu)
            }

            TextField("Opposition", text: $previewOpponentName)
                .textFieldStyle(.roundedBorder)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func statsSection(title: String, selections: [StatsInviteSelection], availableWidth: CGFloat) -> some View {
        let groups = selections.chunked(into: 4)
        return VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.black))

            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                buttonGroupCard(
                    selections: group,
                    availableWidth: availableWidth,
                    sectionTitle: groups.count > 1 ? "Section \(index + 1)" : nil
                )
            }
        }
    }

    private func buttonGroupCard(
        selections: [StatsInviteSelection],
        availableWidth: CGFloat,
        sectionTitle: String?
    ) -> some View {
        let columnCount = availableWidth > 900 ? 3 : 2
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: max(1, min(columnCount, selections.count)))

        return VStack(alignment: .leading, spacing: 14) {
            if let sectionTitle {
                Text(sectionTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(selections) { selection in
                    previewButton(for: selection)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func previewButton(for selection: StatsInviteSelection) -> some View {
        let count = countsBySelectionID[selection.id, default: 0]
        return Button {
            countsBySelectionID[selection.id, default: 0] += 1
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                Text(selection.side.title.uppercased())
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)

                Text(statName(for: selection))
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Text("\(count)")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .background(buttonBackground(for: selection), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func buttonBackground(for selection: StatsInviteSelection) -> LinearGradient {
        switch selection.side {
        case .ourClub:
            let primary = Color(hex: clubConfiguration.clubTeam.primaryColorHex, fallback: .blue)
            let secondary = Color(hex: clubConfiguration.clubTeam.secondaryColorHex ?? clubConfiguration.clubTeam.primaryColorHex, fallback: .blue)
            return LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .opposition:
            return LinearGradient(colors: [Color(red: 0.58, green: 0.14, blue: 0.14), Color(red: 0.87, green: 0.36, blue: 0.23)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func statName(for selection: StatsInviteSelection) -> String {
        enabledStatTypes.first(where: { $0.id == selection.statTypeID })?.name ?? "Stat"
    }
}

private struct StatsInviteRecipient: Identifiable, Equatable {
    let email: String
    let displayName: String
    let mobileNumber: String

    init(email: String, displayName: String, mobileNumber: String = "") {
        self.email = email
        self.displayName = displayName
        self.mobileNumber = mobileNumber.formattedMobileNumber
    }

    var id: String { email }
    var name: String { title }
    var phoneNumber: String { mobileNumber.formattedMobileNumber }
    var canSendTextInvite: Bool { !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var title: String {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? email : trimmedName
    }

    var subtitle: String {
        let trimmedMobile = phoneNumber.formattedMobileNumber
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMobile.isEmpty && !trimmedEmail.isEmpty {
            return "\(trimmedMobile) • \(trimmedEmail)"
        }
        if !trimmedMobile.isEmpty {
            return trimmedMobile
        }
        return trimmedEmail
    }
}

private typealias PhoneInviteContact = StatsInviteRecipient

private struct ShareDraft: Identifiable {
    let id = UUID()
    let text: String
}

private func buildStatsInviteMessage(
    recipient: StatsInviteRecipient,
    sessionID: UUID,
    recordName: String,
    sessionLine: String,
    assignedNames: String,
    testFlightURL: String
) -> String {
    let trimmedInstallURL = testFlightURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let appLink = StatsInviteLinking.appURL(
        sessionID: sessionID,
        recordName: recordName,
        inviteeEmail: recipient.email
    )?.absoluteString ?? ""
    let installLine = trimmedInstallURL.isEmpty
        ? "Install ClubResults from your assigned TestFlight build, then return to this text."
        : "Install ClubResults from TestFlight: \(trimmedInstallURL)"
    let openLine = appLink.isEmpty
        ? ""
        : "Open in ClubResults: \(appLink)\n"

    return """
    \(recipient.title), you're invited as a ClubResults Stat Taker.

    Session: \(sessionLine)

    Assigned stats: \(assignedNames)

    \(openLine)\(installLine)
    If ClubResults is not installed yet, install it first, then come back to this text and tap the ClubResults link.
    Sign in with Apple using \(recipient.email).
    After sign-in, your assigned stats will sync automatically in the Stat Taker tab via CloudKit.
    """
}

private struct StatsInviteMessageDraft: Identifiable {
    let id = UUID()
    let recipients: [String]
    let body: String
}

private struct StatsInviteMessageComposer: UIViewControllerRepresentable {
    let draft: StatsInviteMessageDraft

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = draft.recipients
        controller.body = draft.body
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true)
        }
    }
}

private struct StatsInviteManagementSheet: View {
    let assignment: StatsInviteAssignment
    let allStatTypes: [StatType]
    let onSave: ([StatsInviteSelection]) -> Void
    let onReinvite: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSelections: Set<StatsInviteSelection> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Assigned Stat Types") {
                    ForEach(allStatTypes) { type in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(type.name)
                                .font(.headline)
                            HStack(spacing: 12) {
                                Toggle("Us", isOn: selectionBinding(for: type, side: .ourClub))
                                Toggle("Opposition", isOn: selectionBinding(for: type, side: .opposition))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section("Actions") {
                    Button("Re-invite") {
                        onReinvite()
                    }
                }
            }
            .navigationTitle("Manage Invite")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(orderedSelections)
                        dismiss()
                    }
                }
            }
            .onAppear {
                selectedSelections = Set(assignment.assignedSelections)
            }
        }
    }

    private func selectionBinding(for type: StatType, side: StatsInviteTeamSide) -> Binding<Bool> {
        let selection = StatsInviteSelection(statTypeID: type.id, side: side)
        return Binding(
            get: { selectedSelections.contains(selection) },
            set: { isOn in
                if isOn {
                    selectedSelections.insert(selection)
                } else {
                    selectedSelections.remove(selection)
                }
            }
        )
    }

    private var orderedSelections: [StatsInviteSelection] {
        Array(selectedSelections).sorted { lhs, rhs in
            if lhs.side != rhs.side {
                return lhs.side == .ourClub
            }
            let leftName = allStatTypes.first(where: { $0.id == lhs.statTypeID })?.name ?? ""
            let rightName = allStatTypes.first(where: { $0.id == rhs.statTypeID })?.name ?? ""
            return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
        }
    }
}

private struct InviteStatWebInterfaceView: View {
    let assignment: StatsInviteAssignment
    let statTypes: [StatType]
    let contactName: String
    let onRecord: (StatsInviteSelection) -> Void
    let onConnectionChanged: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    private var assignedSelections: [StatsInviteSelection] {
        let sortOrderByID = Dictionary(uniqueKeysWithValues: statTypes.map { ($0.id, $0.sortOrder) })
        return assignment.assignedSelections.sorted {
            let leftOrder = sortOrderByID[$0.statTypeID] ?? 0
            let rightOrder = sortOrderByID[$1.statTypeID] ?? 0
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            if $0.side != $1.side {
                return $0.side == .ourClub
            }
            return false
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Web Stats UI")
                    .font(.title.weight(.bold))
                Text("\(contactName) sees only assigned stat buttons.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                    ForEach(assignedSelections) { selection in
                        Button(selectionName(for: selection)) {
                            onRecord(selection)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.top, 8)
                Spacer()
            }
            .padding()
            .navigationTitle("Invite Link View")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onConnectionChanged(false)
                        dismiss()
                    }
                }
            }
            .onAppear { onConnectionChanged(true) }
        }
    }

    private func selectionName(for selection: StatsInviteSelection) -> String {
        let statName = statTypes.first(where: { $0.id == selection.statTypeID })?.name ?? "Stat"
        return "\(selection.side.selectionPrefix) \(statName)"
    }
}
