import Foundation
import SwiftData

extension String {
    var formattedMobileNumber: String {
        let digits = filter(\.isNumber)
        guard !digits.isEmpty else {
            return trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if digits.count <= 4 {
            return digits
        }
        if digits.count <= 7 {
            return "\(digits.prefix(4)) \(digits.dropFirst(4))"
        }
        if digits.count <= 10 {
            return "\(digits.prefix(4)) \(digits.dropFirst(4).prefix(3)) \(digits.dropFirst(7))"
        }

        let prefix = "\(digits.prefix(4)) \(digits.dropFirst(4).prefix(3)) \(digits.dropFirst(7).prefix(3))"
        let remainder = digits.dropFirst(10)
        return remainder.isEmpty ? prefix : "\(prefix) \(remainder)"
    }
}

@Model
final class Contact {
    var id: UUID
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
        self.mobile = mobile.formattedMobileNumber
        self.email = email
    }
}
