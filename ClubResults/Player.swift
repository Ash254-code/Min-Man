import Foundation
import SwiftData

@Model
final class Player: Identifiable {
    var id: UUID
    var name: String
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
        self.id = id
        self.name = name
        self.number = number
        self.gradeIDs = gradeIDs
        self.isActive = isActive
    }
}
