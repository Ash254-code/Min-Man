import Foundation
import SwiftData

@Model
final class ContactSectionMembership {
    var id: UUID
    var contactID: UUID
    var sectionKey: String

    init(
        id: UUID = UUID(),
        contactID: UUID,
        sectionKey: String
    ) {
        self.id = id
        self.contactID = contactID
        self.sectionKey = sectionKey
    }
}
