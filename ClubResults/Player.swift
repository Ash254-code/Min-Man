import Foundation
import SwiftData

@Model
final class Player: Identifiable {
    var id: UUID
    var firstName: String = ""
    var lastName: String = ""
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
        self.name = Player.combineName(first: parts.first, last: parts.last)
        self.number = number
        self.gradeIDs = gradeIDs
        self.isActive = isActive
    }

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        number: Int? = nil,
        gradeIDs: [UUID] = [],
        isActive: Bool = true
    ) {
        let cleanedFirst = firstName.cleanedName
        let cleanedLast = lastName.cleanedName
        self.id = id
        self.firstName = cleanedFirst
        self.lastName = cleanedLast
        self.name = Player.combineName(first: cleanedFirst, last: cleanedLast)
        self.number = number
        self.gradeIDs = gradeIDs
        self.isActive = isActive
    }

    func setName(firstName: String, lastName: String) {
        let cleanedFirst = firstName.cleanedName
        let cleanedLast = lastName.cleanedName
        self.firstName = cleanedFirst
        self.lastName = cleanedLast
        self.name = Player.combineName(first: cleanedFirst, last: cleanedLast)
    }

    static func combineName(first: String, last: String) -> String {
        [first.cleanedName, last.cleanedName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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
