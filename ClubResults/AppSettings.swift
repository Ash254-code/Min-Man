import Foundation

struct GradeBackup: Codable {
    let id: UUID
    let name: String
    let isActive: Bool
    let displayOrder: Int
<<<<<<< HEAD

    let showHeadCoach: Bool
    let showAssistantCoach: Bool
    let showTeamManager: Bool
    let showRunner: Bool
    let showFieldUmpire: Bool
    let showGoalUmpire: Bool
    let showBoundaryUmpire1: Bool
    let showBoundaryUmpire2: Bool
    let showTrainer1: Bool
    let showTrainer2: Bool
    let showTrainer3: Bool
    let showTrainer4: Bool
    let showGuestBestAndFairestVotes: Bool
    let showGoalKickers: Bool
    let numberOfBestPlayers: Int
=======
    let asksHeadCoach: Bool
    let asksAssistantCoach: Bool
    let asksTeamManager: Bool
    let asksRunner: Bool
    let asksGoalUmpire: Bool
    let asksBoundaryUmpires: Bool
    let asksTrainers: Bool
    let asksNotes: Bool
    let asksGoalKickers: Bool
    let asksBestPlayers: Bool
    let asksGuestBestFairestVotesScan: Bool
>>>>>>> redesign-new-game-wizard-with-toggles

    init(
        id: UUID,
        name: String,
        isActive: Bool,
        displayOrder: Int,
<<<<<<< HEAD
        showHeadCoach: Bool = true,
        showAssistantCoach: Bool = true,
        showTeamManager: Bool = true,
        showRunner: Bool = true,
        showFieldUmpire: Bool = true,
        showGoalUmpire: Bool = true,
        showBoundaryUmpire1: Bool = true,
        showBoundaryUmpire2: Bool = true,
        showTrainer1: Bool = true,
        showTrainer2: Bool = true,
        showTrainer3: Bool = true,
        showTrainer4: Bool = true,
        showGuestBestAndFairestVotes: Bool = true,
        showGoalKickers: Bool = true,
        numberOfBestPlayers: Int = 6
=======
        asksHeadCoach: Bool = true,
        asksAssistantCoach: Bool = true,
        asksTeamManager: Bool = true,
        asksRunner: Bool = true,
        asksGoalUmpire: Bool = true,
        asksBoundaryUmpires: Bool = true,
        asksTrainers: Bool = true,
        asksNotes: Bool = true,
        asksGoalKickers: Bool = true,
        asksBestPlayers: Bool = true,
        asksGuestBestFairestVotesScan: Bool = false
>>>>>>> redesign-new-game-wizard-with-toggles
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.displayOrder = displayOrder
<<<<<<< HEAD
        self.showHeadCoach = showHeadCoach
        self.showAssistantCoach = showAssistantCoach
        self.showTeamManager = showTeamManager
        self.showRunner = showRunner
        self.showFieldUmpire = showFieldUmpire
        self.showGoalUmpire = showGoalUmpire
        self.showBoundaryUmpire1 = showBoundaryUmpire1
        self.showBoundaryUmpire2 = showBoundaryUmpire2
        self.showTrainer1 = showTrainer1
        self.showTrainer2 = showTrainer2
        self.showTrainer3 = showTrainer3
        self.showTrainer4 = showTrainer4
        self.showGuestBestAndFairestVotes = showGuestBestAndFairestVotes
        self.showGoalKickers = showGoalKickers
        self.numberOfBestPlayers = max(1, min(10, numberOfBestPlayers))
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isActive
        case displayOrder
        case showHeadCoach
        case showAssistantCoach
        case showTeamManager
        case showRunner
        case showFieldUmpire
        case showGoalUmpire
        case showBoundaryUmpire1
        case showBoundaryUmpire2
        case showTrainer1
        case showTrainer2
        case showTrainer3
        case showTrainer4
        case showGuestBestAndFairestVotes
        case showGoalKickers
        case numberOfBestPlayers
=======
        self.asksHeadCoach = asksHeadCoach
        self.asksAssistantCoach = asksAssistantCoach
        self.asksTeamManager = asksTeamManager
        self.asksRunner = asksRunner
        self.asksGoalUmpire = asksGoalUmpire
        self.asksBoundaryUmpires = asksBoundaryUmpires
        self.asksTrainers = asksTrainers
        self.asksNotes = asksNotes
        self.asksGoalKickers = asksGoalKickers
        self.asksBestPlayers = asksBestPlayers
        self.asksGuestBestFairestVotesScan = asksGuestBestFairestVotesScan
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, isActive, displayOrder
        case asksHeadCoach, asksAssistantCoach, asksTeamManager, asksRunner, asksGoalUmpire, asksBoundaryUmpires
        case asksTrainers, asksNotes, asksGoalKickers, asksBestPlayers, asksGuestBestFairestVotesScan
>>>>>>> redesign-new-game-wizard-with-toggles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isActive = try c.decode(Bool.self, forKey: .isActive)
        displayOrder = try c.decode(Int.self, forKey: .displayOrder)
<<<<<<< HEAD

        showHeadCoach = try c.decodeIfPresent(Bool.self, forKey: .showHeadCoach) ?? true
        showAssistantCoach = try c.decodeIfPresent(Bool.self, forKey: .showAssistantCoach) ?? true
        showTeamManager = try c.decodeIfPresent(Bool.self, forKey: .showTeamManager) ?? true
        showRunner = try c.decodeIfPresent(Bool.self, forKey: .showRunner) ?? true
        showFieldUmpire = try c.decodeIfPresent(Bool.self, forKey: .showFieldUmpire) ?? true
        showGoalUmpire = try c.decodeIfPresent(Bool.self, forKey: .showGoalUmpire) ?? true
        showBoundaryUmpire1 = try c.decodeIfPresent(Bool.self, forKey: .showBoundaryUmpire1) ?? true
        showBoundaryUmpire2 = try c.decodeIfPresent(Bool.self, forKey: .showBoundaryUmpire2) ?? true
        showTrainer1 = try c.decodeIfPresent(Bool.self, forKey: .showTrainer1) ?? true
        showTrainer2 = try c.decodeIfPresent(Bool.self, forKey: .showTrainer2) ?? true
        showTrainer3 = try c.decodeIfPresent(Bool.self, forKey: .showTrainer3) ?? true
        showTrainer4 = try c.decodeIfPresent(Bool.self, forKey: .showTrainer4) ?? true
        showGuestBestAndFairestVotes = try c.decodeIfPresent(Bool.self, forKey: .showGuestBestAndFairestVotes) ?? true
        showGoalKickers = try c.decodeIfPresent(Bool.self, forKey: .showGoalKickers) ?? true
        numberOfBestPlayers = max(1, min(10, try c.decodeIfPresent(Int.self, forKey: .numberOfBestPlayers) ?? 6))
=======
        asksHeadCoach = try c.decodeIfPresent(Bool.self, forKey: .asksHeadCoach) ?? true
        asksAssistantCoach = try c.decodeIfPresent(Bool.self, forKey: .asksAssistantCoach) ?? true
        asksTeamManager = try c.decodeIfPresent(Bool.self, forKey: .asksTeamManager) ?? true
        asksRunner = try c.decodeIfPresent(Bool.self, forKey: .asksRunner) ?? true
        asksGoalUmpire = try c.decodeIfPresent(Bool.self, forKey: .asksGoalUmpire) ?? true
        asksBoundaryUmpires = try c.decodeIfPresent(Bool.self, forKey: .asksBoundaryUmpires) ?? true
        asksTrainers = try c.decodeIfPresent(Bool.self, forKey: .asksTrainers) ?? true
        asksNotes = try c.decodeIfPresent(Bool.self, forKey: .asksNotes) ?? true
        asksGoalKickers = try c.decodeIfPresent(Bool.self, forKey: .asksGoalKickers) ?? true
        asksBestPlayers = try c.decodeIfPresent(Bool.self, forKey: .asksBestPlayers) ?? true
        asksGuestBestFairestVotesScan = try c.decodeIfPresent(Bool.self, forKey: .asksGuestBestFairestVotesScan) ?? false
>>>>>>> redesign-new-game-wizard-with-toggles
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
<<<<<<< HEAD
                showHeadCoach: $0.showHeadCoach,
                showAssistantCoach: $0.showAssistantCoach,
                showTeamManager: $0.showTeamManager,
                showRunner: $0.showRunner,
                showFieldUmpire: $0.showFieldUmpire,
                showGoalUmpire: $0.showGoalUmpire,
                showBoundaryUmpire1: $0.showBoundaryUmpire1,
                showBoundaryUmpire2: $0.showBoundaryUmpire2,
                showTrainer1: $0.showTrainer1,
                showTrainer2: $0.showTrainer2,
                showTrainer3: $0.showTrainer3,
                showTrainer4: $0.showTrainer4,
                showGuestBestAndFairestVotes: $0.showGuestBestAndFairestVotes,
                showGoalKickers: $0.showGoalKickers,
                numberOfBestPlayers: $0.numberOfBestPlayers
=======
                asksHeadCoach: $0.asksHeadCoach,
                asksAssistantCoach: $0.asksAssistantCoach,
                asksTeamManager: $0.asksTeamManager,
                asksRunner: $0.asksRunner,
                asksGoalUmpire: $0.asksGoalUmpire,
                asksBoundaryUmpires: $0.asksBoundaryUmpires,
                asksTrainers: $0.asksTrainers,
                asksNotes: $0.asksNotes,
                asksGoalKickers: $0.asksGoalKickers,
                asksBestPlayers: $0.asksBestPlayers,
                asksGuestBestFairestVotesScan: $0.asksGuestBestFairestVotesScan
>>>>>>> redesign-new-game-wizard-with-toggles
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
<<<<<<< HEAD
                showHeadCoach: backup.showHeadCoach,
                showAssistantCoach: backup.showAssistantCoach,
                showTeamManager: backup.showTeamManager,
                showRunner: backup.showRunner,
                showFieldUmpire: backup.showFieldUmpire,
                showGoalUmpire: backup.showGoalUmpire,
                showBoundaryUmpire1: backup.showBoundaryUmpire1,
                showBoundaryUmpire2: backup.showBoundaryUmpire2,
                showTrainer1: backup.showTrainer1,
                showTrainer2: backup.showTrainer2,
                showTrainer3: backup.showTrainer3,
                showTrainer4: backup.showTrainer4,
                showGuestBestAndFairestVotes: backup.showGuestBestAndFairestVotes,
                showGoalKickers: backup.showGoalKickers,
                numberOfBestPlayers: backup.numberOfBestPlayers
=======
                asksHeadCoach: backup.asksHeadCoach,
                asksAssistantCoach: backup.asksAssistantCoach,
                asksTeamManager: backup.asksTeamManager,
                asksRunner: backup.asksRunner,
                asksGoalUmpire: backup.asksGoalUmpire,
                asksBoundaryUmpires: backup.asksBoundaryUmpires,
                asksTrainers: backup.asksTrainers,
                asksNotes: backup.asksNotes,
                asksGoalKickers: backup.asksGoalKickers,
                asksBestPlayers: backup.asksBestPlayers,
                asksGuestBestFairestVotesScan: backup.asksGuestBestFairestVotesScan
>>>>>>> redesign-new-game-wizard-with-toggles
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
