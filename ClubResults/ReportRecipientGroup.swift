import Foundation
import SwiftData

@Model
final class ReportRecipientGroup {
    @Attribute(.unique) var id: UUID
    var gradeID: UUID
    var groupID: UUID
    var sendEmail: Bool
    var sendText: Bool

    init(
        id: UUID = UUID(),
        gradeID: UUID,
        groupID: UUID,
        sendEmail: Bool = true,
        sendText: Bool = true
    ) {
        self.id = id
        self.gradeID = gradeID
        self.groupID = groupID
        self.sendEmail = sendEmail
        self.sendText = sendText
    }
}
