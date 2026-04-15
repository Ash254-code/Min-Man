import Foundation
import SwiftData

@Model
final class Contact {
    @Attribute(.unique) var id: UUID
    var name: String
    var mobile: String
    var email: String

    init(
        id: UUID = UUID(),
        name: String,
        mobile: String,
        email: String
    ) {
        self.id = id
        self.name = name
        self.mobile = mobile
        self.email = email
    }
}
