import Foundation
import SwiftData

@Model
final class Grade {
    var id: UUID
    var name: String
    var isActive: Bool
    var displayOrder: Int

    init(id: UUID = UUID(), name: String, isActive: Bool = true, displayOrder: Int = 0) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.displayOrder = displayOrder
    }
}
