import Foundation
import SwiftData

enum LockedGradeSeed {
    /// Normalizes grade names for comparison (case/whitespace-insensitive)
    static func norm(_ s: String) -> String {
        return s
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }

    /// EXACT order you want everywhere
    static let orderedGradeNames: [String] = [
        "A Grade",
        "B Grade",
        "Under 17's",
        "Under 14's",
        "Under 12's",
        "Under 9's"
    ]

    /// Safe to call on every launch
    static func ensureGradesExist(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Grade>()
        let existing = (try? modelContext.fetch(descriptor)) ?? []

        let existingNorm = Set(existing.map { Self.norm($0.name) })

        for name in orderedGradeNames where !existingNorm.contains(Self.norm(name)) {
            modelContext.insert(Grade(name: name, isActive: true))
        }
    }
}
