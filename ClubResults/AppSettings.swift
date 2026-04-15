import Foundation

struct GradeBackup: Codable {
    let id: UUID
    let name: String
    let isActive: Bool
    let displayOrder: Int
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

    init(
        id: UUID,
        name: String,
        isActive: Bool,
        displayOrder: Int,
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
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.displayOrder = displayOrder
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
        case asksAssistantCoach, asksTeamManager, asksRunner, asksGoalUmpire, asksBoundaryUmpires
        case asksTrainers, asksNotes, asksGoalKickers, asksBestPlayers, asksGuestBestFairestVotesScan
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isActive = try c.decode(Bool.self, forKey: .isActive)
        displayOrder = try c.decode(Int.self, forKey: .displayOrder)
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
    }
}

struct ContactBackup: Codable {
    let id: UUID
    let name: String
    let mobile: String
    let email: String
}

enum SettingsBackupStore {
    static let gradesKey = "settings.backup.grades.v1"
    static let contactsKey = "settings.backup.contacts.v1"

    static func saveGrades(_ grades: [Grade]) {
        let payload = grades.map {
            GradeBackup(
                id: $0.id,
                name: $0.name,
                isActive: $0.isActive,
                displayOrder: $0.displayOrder,
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
