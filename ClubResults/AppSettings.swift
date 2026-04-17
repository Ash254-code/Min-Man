import Foundation

struct GradeBackup: Codable {
    let id: UUID
    let name: String
    let isActive: Bool
    let displayOrder: Int
    let asksHeadCoach: Bool
    let asksAssistantCoach: Bool
    let asksTeamManager: Bool
    let asksRunner: Bool
    let asksGoalUmpire: Bool
    let asksFieldUmpire: Bool
    let asksBoundaryUmpire1: Bool
    let asksBoundaryUmpire2: Bool
    let asksTrainers: Bool
    let asksTrainer1: Bool
    let asksTrainer2: Bool
    let asksTrainer3: Bool
    let asksTrainer4: Bool
    let asksNotes: Bool
    let asksScore: Bool
    let asksLiveGameView: Bool
    let asksGoalKickers: Bool
    let bestPlayersCount: Int
    let asksGuestBestFairestVotesScan: Bool
    let quarterLengthMinutes: Int

    init(
        id: UUID,
        name: String,
        isActive: Bool,
        displayOrder: Int,
        asksHeadCoach: Bool = true,
        asksAssistantCoach: Bool = true,
        asksTeamManager: Bool = true,
        asksRunner: Bool = true,
        asksGoalUmpire: Bool = true,
        asksFieldUmpire: Bool = true,
        asksBoundaryUmpire1: Bool = true,
        asksBoundaryUmpire2: Bool = true,
        asksTrainers: Bool = true,
        asksTrainer1: Bool = true,
        asksTrainer2: Bool = true,
        asksTrainer3: Bool = true,
        asksTrainer4: Bool = true,
        asksNotes: Bool = true,
        asksScore: Bool = true,
        asksLiveGameView: Bool = true,
        asksGoalKickers: Bool = true,
        bestPlayersCount: Int = 6,
        asksGuestBestFairestVotesScan: Bool = false,
        quarterLengthMinutes: Int = 20
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.displayOrder = displayOrder
        self.asksHeadCoach = asksHeadCoach
        self.asksAssistantCoach = asksAssistantCoach
        self.asksTeamManager = asksTeamManager
        self.asksRunner = asksRunner
        self.asksGoalUmpire = asksGoalUmpire
        self.asksFieldUmpire = asksFieldUmpire
        self.asksBoundaryUmpire1 = asksBoundaryUmpire1
        self.asksBoundaryUmpire2 = asksBoundaryUmpire2
        self.asksTrainers = asksTrainers
        self.asksTrainer1 = asksTrainer1
        self.asksTrainer2 = asksTrainer2
        self.asksTrainer3 = asksTrainer3
        self.asksTrainer4 = asksTrainer4
        self.asksNotes = asksNotes
        self.asksScore = asksScore
        self.asksLiveGameView = asksLiveGameView
        self.asksGoalKickers = asksGoalKickers
        self.bestPlayersCount = min(max(bestPlayersCount, 0), 10)
        self.asksGuestBestFairestVotesScan = asksGuestBestFairestVotesScan
        self.quarterLengthMinutes = min(max(quarterLengthMinutes, 10), 30)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, isActive, displayOrder
        case asksHeadCoach, asksAssistantCoach, asksTeamManager, asksRunner, asksGoalUmpire
        case asksFieldUmpire
        case asksBoundaryUmpire1, asksBoundaryUmpire2, asksBoundaryUmpires
        case asksTrainers, asksTrainer1, asksTrainer2, asksTrainer3, asksTrainer4
        case asksNotes, asksScore, asksLiveGameView, asksGoalKickers
        case bestPlayersCount, asksBestPlayers
        case asksGuestBestFairestVotesScan, quarterLengthMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isActive = try c.decode(Bool.self, forKey: .isActive)
        displayOrder = try c.decode(Int.self, forKey: .displayOrder)
        asksHeadCoach = try c.decodeIfPresent(Bool.self, forKey: .asksHeadCoach) ?? true
        asksAssistantCoach = try c.decodeIfPresent(Bool.self, forKey: .asksAssistantCoach) ?? true
        asksTeamManager = try c.decodeIfPresent(Bool.self, forKey: .asksTeamManager) ?? true
        asksRunner = try c.decodeIfPresent(Bool.self, forKey: .asksRunner) ?? true
        asksGoalUmpire = try c.decodeIfPresent(Bool.self, forKey: .asksGoalUmpire) ?? true
        asksFieldUmpire = try c.decodeIfPresent(Bool.self, forKey: .asksFieldUmpire) ?? true
        let legacyAsksBoundaryUmpires = try c.decodeIfPresent(Bool.self, forKey: .asksBoundaryUmpires) ?? true
        asksBoundaryUmpire1 = try c.decodeIfPresent(Bool.self, forKey: .asksBoundaryUmpire1) ?? legacyAsksBoundaryUmpires
        asksBoundaryUmpire2 = try c.decodeIfPresent(Bool.self, forKey: .asksBoundaryUmpire2) ?? legacyAsksBoundaryUmpires
        let legacyAsksTrainers = try c.decodeIfPresent(Bool.self, forKey: .asksTrainers) ?? true
        asksTrainer1 = try c.decodeIfPresent(Bool.self, forKey: .asksTrainer1) ?? legacyAsksTrainers
        asksTrainer2 = try c.decodeIfPresent(Bool.self, forKey: .asksTrainer2) ?? legacyAsksTrainers
        asksTrainer3 = try c.decodeIfPresent(Bool.self, forKey: .asksTrainer3) ?? legacyAsksTrainers
        asksTrainer4 = try c.decodeIfPresent(Bool.self, forKey: .asksTrainer4) ?? legacyAsksTrainers
        asksTrainers = asksTrainer1 || asksTrainer2 || asksTrainer3 || asksTrainer4
        asksNotes = try c.decodeIfPresent(Bool.self, forKey: .asksNotes) ?? true
        asksScore = try c.decodeIfPresent(Bool.self, forKey: .asksScore) ?? true
        asksLiveGameView = try c.decodeIfPresent(Bool.self, forKey: .asksLiveGameView) ?? true
        asksGoalKickers = try c.decodeIfPresent(Bool.self, forKey: .asksGoalKickers) ?? true
        if let decodedCount = try c.decodeIfPresent(Int.self, forKey: .bestPlayersCount) {
            bestPlayersCount = min(max(decodedCount, 0), 10)
        } else {
            let legacyAsksBestPlayers = try c.decodeIfPresent(Bool.self, forKey: .asksBestPlayers) ?? true
            bestPlayersCount = legacyAsksBestPlayers ? 6 : 0
        }
        asksGuestBestFairestVotesScan = try c.decodeIfPresent(Bool.self, forKey: .asksGuestBestFairestVotesScan) ?? false
        quarterLengthMinutes = min(max(try c.decodeIfPresent(Int.self, forKey: .quarterLengthMinutes) ?? 20, 10), 30)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(isActive, forKey: .isActive)
        try c.encode(displayOrder, forKey: .displayOrder)
        try c.encode(asksHeadCoach, forKey: .asksHeadCoach)
        try c.encode(asksAssistantCoach, forKey: .asksAssistantCoach)
        try c.encode(asksTeamManager, forKey: .asksTeamManager)
        try c.encode(asksRunner, forKey: .asksRunner)
        try c.encode(asksGoalUmpire, forKey: .asksGoalUmpire)
        try c.encode(asksFieldUmpire, forKey: .asksFieldUmpire)
        try c.encode(asksBoundaryUmpire1, forKey: .asksBoundaryUmpire1)
        try c.encode(asksBoundaryUmpire2, forKey: .asksBoundaryUmpire2)
        try c.encode(asksTrainers, forKey: .asksTrainers)
        try c.encode(asksTrainer1, forKey: .asksTrainer1)
        try c.encode(asksTrainer2, forKey: .asksTrainer2)
        try c.encode(asksTrainer3, forKey: .asksTrainer3)
        try c.encode(asksTrainer4, forKey: .asksTrainer4)
        try c.encode(asksNotes, forKey: .asksNotes)
        try c.encode(asksScore, forKey: .asksScore)
        try c.encode(asksLiveGameView, forKey: .asksLiveGameView)
        try c.encode(asksGoalKickers, forKey: .asksGoalKickers)
        try c.encode(bestPlayersCount, forKey: .bestPlayersCount)
        try c.encode(asksGuestBestFairestVotesScan, forKey: .asksGuestBestFairestVotesScan)
        try c.encode(quarterLengthMinutes, forKey: .quarterLengthMinutes)
    }
}

struct ContactBackup: Codable {
    let id: UUID
    let name: String
    let mobile: String
    let email: String
}

struct BoundaryUmpireGradeLink: Codable {
    let gameGradeID: UUID
    let boundaryGradeID: UUID
}

struct BoundaryUmpireGradeLinks: Codable {
    let gameGradeID: UUID
    let boundaryGradeIDs: [UUID]
}

enum SettingsBackupStore {
    static let gradesKey = "settings.backup.grades.v1"
    static let contactsKey = "settings.backup.contacts.v1"
    static let boundaryUmpireMappingsKey = "settings.boundaryUmpires.gradeMappings.v1"

    static func saveGrades(_ grades: [Grade]) {
        let payload = grades.map {
            GradeBackup(
                id: $0.id,
                name: $0.name,
                isActive: $0.isActive,
                displayOrder: $0.displayOrder,
                asksHeadCoach: $0.asksHeadCoach,
                asksAssistantCoach: $0.asksAssistantCoach,
                asksTeamManager: $0.asksTeamManager,
                asksRunner: $0.asksRunner,
                asksGoalUmpire: $0.asksGoalUmpire,
                asksFieldUmpire: $0.asksFieldUmpire,
                asksBoundaryUmpire1: $0.asksBoundaryUmpire1,
                asksBoundaryUmpire2: $0.asksBoundaryUmpire2,
                asksTrainers: $0.asksTrainers,
                asksTrainer1: $0.asksTrainer1,
                asksTrainer2: $0.asksTrainer2,
                asksTrainer3: $0.asksTrainer3,
                asksTrainer4: $0.asksTrainer4,
                asksNotes: $0.asksNotes,
                asksScore: $0.asksScore,
                asksLiveGameView: $0.asksLiveGameView,
                asksGoalKickers: $0.asksGoalKickers,
                bestPlayersCount: $0.bestPlayersCount,
                asksGuestBestFairestVotesScan: $0.asksGuestBestFairestVotesScan,
                quarterLengthMinutes: $0.quarterLengthMinutes
            )
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: gradesKey)
    }

    static func loadGrades() -> [GradeBackup] {
        guard let data = UserDefaults.standard.data(forKey: gradesKey),
              let decoded = try? JSONDecoder().decode([GradeBackup].self, from: data) else {
            return []
        }
        return decoded
    }

    static func saveContacts(_ contacts: [Contact]) {
        let payload = contacts.map { ContactBackup(id: $0.id, name: $0.name, mobile: $0.mobile, email: $0.email) }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: contactsKey)
    }

    static func loadContacts() -> [ContactBackup] {
        guard let data = UserDefaults.standard.data(forKey: contactsKey),
              let decoded = try? JSONDecoder().decode([ContactBackup].self, from: data) else {
            return []
        }
        return decoded
    }

    static func saveBoundaryUmpireGradeMappings(_ mappings: [UUID: [UUID]]) {
        let payload = mappings.map {
            BoundaryUmpireGradeLinks(gameGradeID: $0.key, boundaryGradeIDs: $0.value)
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: boundaryUmpireMappingsKey)
    }

    static func loadBoundaryUmpireGradeMappings() -> [UUID: [UUID]] {
        guard let data = UserDefaults.standard.data(forKey: boundaryUmpireMappingsKey) else {
            return [:]
        }

        if let decoded = try? JSONDecoder().decode([BoundaryUmpireGradeLinks].self, from: data) {
            return Dictionary(uniqueKeysWithValues: decoded.map { ($0.gameGradeID, $0.boundaryGradeIDs) })
        }

        // Backwards compatibility with single-grade mappings.
        if let decodedLegacy = try? JSONDecoder().decode([BoundaryUmpireGradeLink].self, from: data) {
            return Dictionary(uniqueKeysWithValues: decodedLegacy.map { ($0.gameGradeID, [$0.boundaryGradeID]) })
        }

        return [:]
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

func resolvedConfiguredGrades(from persistedGrades: [Grade]) -> [Grade] {
    let backups = SettingsBackupStore.loadGrades()
    guard !backups.isEmpty else { return persistedGrades }

    var resolved = persistedGrades
    var seenIDs = Set(persistedGrades.map(\.id))
    var seenNames = Set(persistedGrades.map { normalizedGradeName($0.name) })

    for backup in backups {
        let normalizedName = normalizedGradeName(backup.name)
        if seenIDs.contains(backup.id) || seenNames.contains(normalizedName) {
            continue
        }

        resolved.append(
            Grade(
                id: backup.id,
                name: backup.name,
                isActive: backup.isActive,
                displayOrder: backup.displayOrder,
                asksHeadCoach: backup.asksHeadCoach,
                asksAssistantCoach: backup.asksAssistantCoach,
                asksTeamManager: backup.asksTeamManager,
                asksRunner: backup.asksRunner,
                asksGoalUmpire: backup.asksGoalUmpire,
                asksFieldUmpire: backup.asksFieldUmpire,
                asksBoundaryUmpire1: backup.asksBoundaryUmpire1,
                asksBoundaryUmpire2: backup.asksBoundaryUmpire2,
                asksTrainers: backup.asksTrainers,
                asksTrainer1: backup.asksTrainer1,
                asksTrainer2: backup.asksTrainer2,
                asksTrainer3: backup.asksTrainer3,
                asksTrainer4: backup.asksTrainer4,
                asksNotes: backup.asksNotes,
                asksScore: backup.asksScore,
                asksLiveGameView: backup.asksLiveGameView,
                asksGoalKickers: backup.asksGoalKickers,
                bestPlayersCount: backup.bestPlayersCount,
                asksGuestBestFairestVotesScan: backup.asksGuestBestFairestVotesScan,
                quarterLengthMinutes: backup.quarterLengthMinutes
            )
        )

        seenIDs.insert(backup.id)
        seenNames.insert(normalizedName)
    }

    return resolved
}

private func normalizedGradeName(_ name: String) -> String {
    name
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}
