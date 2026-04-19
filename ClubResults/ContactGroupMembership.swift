import Foundation
import SwiftData

@Model
final class ContactGroupMembership {
    @Attribute(.unique) var id: UUID
    var contactID: UUID
    var groupID: UUID

    init(
        id: UUID = UUID(),
        contactID: UUID,
        groupID: UUID
    ) {
        self.id = id
        self.contactID = contactID
        self.groupID = groupID
    }
}
