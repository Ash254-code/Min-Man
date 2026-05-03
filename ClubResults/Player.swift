import Foundation
import SwiftData

@Model
final class Player: Identifiable {
    var id: UUID
    var firstName: String = ""
    var lastName: String = ""
    var preferredName: String = ""
    var name: String = ""
    var number: Int?
    var gradeIDs: [UUID]
    var isActive: Bool

    init(
        id: UUID = UUID(),
        name: String,
        number: Int? = nil,
        gradeIDs: [UUID] = [],
        isActive: Bool = true
    ) {
        let parts = Player.splitName(name)
        self.id = id
        self.firstName = parts.first
        self.lastName = parts.last
        self.preferredName = ""
        self.name = Player.combineDisplayName(first: parts.first, last: parts.last, preferred: "")
        self.number = number
        self.gradeIDs = gradeIDs
        self.isActive = isActive
    }

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        preferredName: String = "",
        number: Int? = nil,
        gradeIDs: [UUID] = [],
        isActive: Bool = true
    ) {
        let cleanedFirst = firstName.cleanedName
        let cleanedLast = lastName.cleanedName
        let cleanedPreferred = preferredName.cleanedName
        self.id = id
        self.firstName = cleanedFirst
        self.lastName = cleanedLast
        self.preferredName = cleanedPreferred
        self.name = Player.combineDisplayName(first: cleanedFirst, last: cleanedLast, preferred: cleanedPreferred)
        self.number = number
        self.gradeIDs = gradeIDs
        self.isActive = isActive
    }

    var displayFirstName: String {
        let cleanedPreferred = preferredName.cleanedName
        return cleanedPreferred.isEmpty ? firstName.cleanedName : cleanedPreferred
    }

    var fullName: String {
        Player.combineName(first: firstName, last: lastName)
    }

    var duplicateMatchKey: String {
        Self.duplicateMatchKey(firstName: firstName, lastName: lastName)
    }

    func setName(firstName: String, lastName: String, preferredName: String = "") {
        let cleanedFirst = firstName.cleanedName
        let cleanedLast = lastName.cleanedName
        let cleanedPreferred = preferredName.cleanedName
        self.firstName = cleanedFirst
        self.lastName = cleanedLast
        self.preferredName = cleanedPreferred
        self.name = Player.combineDisplayName(first: cleanedFirst, last: cleanedLast, preferred: cleanedPreferred)
    }

    @discardableResult
    func normalizeStoredNamesIfNeeded() -> Bool {
        let split = Player.splitName(name)
        let cleanedFirst = firstName.cleanedName.isEmpty ? split.first : firstName.cleanedName
        let cleanedLast = lastName.cleanedName.isEmpty ? split.last : lastName.cleanedName
        let cleanedPreferred = preferredName.cleanedName
        let displayName = Player.combineDisplayName(first: cleanedFirst, last: cleanedLast, preferred: cleanedPreferred)

        if cleanedFirst == firstName,
           cleanedLast == lastName,
           cleanedPreferred == preferredName,
           displayName == name {
            return false
        }

        firstName = cleanedFirst
        lastName = cleanedLast
        preferredName = cleanedPreferred
        name = displayName
        return true
    }

    static func combineName(first: String, last: String) -> String {
        [first.cleanedName, last.cleanedName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func combineDisplayName(first: String, last: String, preferred: String) -> String {
        let resolvedFirst = preferred.cleanedName.isEmpty ? first.cleanedName : preferred.cleanedName
        return combineName(first: resolvedFirst, last: last)
    }

    static func duplicateMatchKey(firstName: String, lastName: String) -> String {
        let normalizedLast = lastName.cleanedName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let normalizedFirst = firstName.cleanedName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return "\(normalizedLast)|\(normalizedFirst)"
    }

    static func splitName(_ fullName: String) -> (first: String, last: String) {
        let cleaned = fullName.cleanedName
        guard !cleaned.isEmpty else { return ("", "") }

        let parts = cleaned.split(separator: " ").map(String.init)
        guard let first = parts.first else { return ("", "") }
        let last = parts.dropFirst().joined(separator: " ")
        return (first, last)
    }
}
