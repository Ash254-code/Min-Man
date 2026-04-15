import Foundation

enum SettingsBackupStore {
    static let gradesKey = "settings.backup.grades.v1"
    static let contactsKey = "settings.backup.contacts.v1"

    private struct GradeSnapshot: Codable {
        let id: UUID
        let name: String
        let isActive: Bool
        let displayOrder: Int
    }

    private struct ContactSnapshot: Codable {
        let id: UUID
        let name: String
        let mobile: String
        let email: String
    }

    static func saveGrades(_ grades: [Grade]) {
        let payload = grades.map { GradeSnapshot(id: $0.id, name: $0.name, isActive: $0.isActive, displayOrder: $0.displayOrder) }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: gradesKey)
    }

    static func loadGrades() -> [Grade] {
        guard let data = UserDefaults.standard.data(forKey: gradesKey),
              let decoded = try? JSONDecoder().decode([GradeSnapshot].self, from: data) else {
            return []
        }
        return decoded.map {
            Grade(id: $0.id, name: $0.name, isActive: $0.isActive, displayOrder: $0.displayOrder)
        }
    }

    static func saveContacts(_ contacts: [Contact]) {
        let payload = contacts.map { ContactSnapshot(id: $0.id, name: $0.name, mobile: $0.mobile, email: $0.email) }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: contactsKey)
    }

    static func loadContacts() -> [Contact] {
        guard let data = UserDefaults.standard.data(forKey: contactsKey),
              let decoded = try? JSONDecoder().decode([ContactSnapshot].self, from: data) else {
            return []
        }
        return decoded.map {
            Contact(id: $0.id, name: $0.name, mobile: $0.mobile, email: $0.email)
        }
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
