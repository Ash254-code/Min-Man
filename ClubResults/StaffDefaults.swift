import Foundation
import SwiftData

@Model
final class StaffDefault {

    @Attribute(.unique) var id: UUID
    var gradeID: UUID
    var role: StaffRole
    var name: String

    init(
        id: UUID = UUID(),
        gradeID: UUID,
        role: StaffRole,
        name: String
    ) {
        self.id = id
        self.gradeID = gradeID
        self.role = role
        self.name = name
    }
}
