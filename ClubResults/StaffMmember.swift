import Foundation
import SwiftData

enum StaffRole: String, Codable, CaseIterable {
    case headCoach
    case assistantCoach
    case teamManager
    case runner
    case goalUmpire
    case timeKeeper
    case fieldUmpire
    case boundaryUmpire
    case waterBoy
    case trainer
}

@Model
final class StaffMember: Identifiable {
    var id: UUID
    var name: String
    var roleRawValue: String
    var gradeID: UUID

    init(
        id: UUID = UUID(),
        name: String,
        role: StaffRole,
        gradeID: UUID
    ) {
        self.id = id
        self.name = name
        self.roleRawValue = role.rawValue
        self.gradeID = gradeID
    }

    var role: StaffRole {
        get { StaffRole(rawValue: roleRawValue) ?? .teamManager }
        set { roleRawValue = newValue.rawValue }
    }
}
