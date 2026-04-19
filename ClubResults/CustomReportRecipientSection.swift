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
