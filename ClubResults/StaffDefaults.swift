import Foundation
import SwiftData

@Model
final class StaffDefault {

    var id: UUID
    var gradeID: UUID
    var roleRawValue: String
    var name: String

    init(
        id: UUID = UUID(),
        gradeID: UUID,
        role: StaffRole,
        name: String
    ) {
        self.id = id
        self.gradeID = gradeID
        self.roleRawValue = role.rawValue
        self.name = name
    }

    var role: StaffRole {
        get { StaffRole(rawValue: roleRawValue) ?? .teamManager }
        set { roleRawValue = newValue.rawValue }
    }
}
