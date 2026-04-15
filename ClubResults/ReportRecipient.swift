import Foundation
import SwiftData

@Model
final class ReportRecipient {
    @Attribute(.unique) var id: UUID
    var gradeID: UUID
    var contactID: UUID
    var sendEmail: Bool
    var sendText: Bool

    init(
        id: UUID = UUID(),
        gradeID: UUID,
        contactID: UUID,
        sendEmail: Bool = true,
        sendText: Bool = true
    ) {
        self.id = id
        self.gradeID = gradeID
        self.contactID = contactID
        self.sendEmail = sendEmail
        self.sendText = sendText
    }
}
