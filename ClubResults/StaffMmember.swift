import Foundation
import SwiftData

enum StaffRole: String, Codable, CaseIterable {
    case headCoach
    case assistantCoach
    case teamManager
    case runner
    case goalUmpire
    case boundaryUmpire
    case trainer
}

@Model
final class StaffMember: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var role: StaffRole
    var gradeID: UUID

    init(
        id: UUID = UUID(),
        name: String,
        role: StaffRole,
        gradeID: UUID
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.gradeID = gradeID
    }
}
