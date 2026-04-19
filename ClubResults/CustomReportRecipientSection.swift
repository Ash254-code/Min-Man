import Foundation
import SwiftData

@Model
final class CustomReportRecipientSection {
    @Attribute(.unique) var id: UUID
    var templateID: UUID
    var sectionKey: String

    init(
        id: UUID = UUID(),
        templateID: UUID,
        sectionKey: String
    ) {
        self.id = id
        self.templateID = templateID
        self.sectionKey = sectionKey
    }
}

@Model
final class CustomReportRecipientGroup {
    @Attribute(.unique) var id: UUID
    var templateID: UUID
    var groupID: UUID

    init(
        id: UUID = UUID(),
        templateID: UUID,
        groupID: UUID
    ) {
        self.id = id
        self.templateID = templateID
        self.groupID = groupID
    }
}

@Model
final class CustomReportRecipientContact {
    @Attribute(.unique) var id: UUID
    var templateID: UUID
    var contactID: UUID

    init(
        id: UUID = UUID(),
        templateID: UUID,
        contactID: UUID
    ) {
        self.id = id
        self.templateID = templateID
        self.contactID = contactID
    }
}
