import Foundation
import SwiftData

@Model
final class ReportRouting {
    @Attribute(.unique) var gradeID: UUID
    var emails: [String]
    var mobileNumbers: [String]

    init(
        gradeID: UUID,
        emails: [String] = [],
        mobileNumbers: [String] = []
    ) {
        self.gradeID = gradeID
        self.emails = emails
        self.mobileNumbers = mobileNumbers
    }
}

