import Foundation

struct GradeBackup: Codable {
    let id: UUID
    let name: String
    let isActive: Bool
    let displayOrder: Int
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

enum SettingsBackupStore {
    static let gradesKey = "settings.backup.grades.v1"
    static let contactsKey = "settings.backup.contacts.v1"
    static let boundaryUmpireMappingsKey = "settings.boundaryUmpires.gradeMappings.v1"

    static func saveGrades(_ grades: [Grade]) {
        let payload = grades.map { GradeBackup(id: $0.id, name: $0.name, isActive: $0.isActive, displayOrder: $0.displayOrder) }
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

    static func saveBoundaryUmpireGradeMappings(_ mappings: [UUID: UUID]) {
        let payload = mappings.map {
            BoundaryUmpireGradeLink(gameGradeID: $0.key, boundaryGradeID: $0.value)
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: boundaryUmpireMappingsKey)
    }

    static func loadBoundaryUmpireGradeMappings() -> [UUID: UUID] {
        guard let data = UserDefaults.standard.data(forKey: boundaryUmpireMappingsKey),
              let decoded = try? JSONDecoder().decode([BoundaryUmpireGradeLink].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: decoded.map { ($0.gameGradeID, $0.boundaryGradeID) })
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
                displayOrder: backup.displayOrder
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
