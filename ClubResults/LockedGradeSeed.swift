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

        let existingByNormalizedName = Dictionary(uniqueKeysWithValues: existing.map { (Self.norm($0.name), $0) })
        var didChange = false

        for (index, name) in orderedGradeNames.enumerated() {
            let normalizedName = Self.norm(name)
            if let grade = existingByNormalizedName[normalizedName] {
                didChange = applyDefaultPromptSettings(to: grade) || didChange
                continue
            }

            modelContext.insert(makeDefaultGrade(name: name, displayOrder: index))
            didChange = true
        }

        if didChange {
            try? modelContext.save()
        }
    }

    private static func makeDefaultGrade(name: String, displayOrder: Int) -> Grade {
        let grade = Grade(
            name: name,
            isActive: true,
            displayOrder: displayOrder,
            asksTimeKeeper: Grade.defaultAsksTimeKeeper(for: name)
        )
        _ = applyDefaultPromptSettings(to: grade)
        return grade
    }

    @discardableResult
    private static func applyDefaultPromptSettings(to grade: Grade) -> Bool {
        switch norm(grade.name) {
        case norm("Under 9's"), norm("Under 12's"):
            return update(grade) {
                $0.asksHeadCoach = true
                $0.asksAssistantCoach = false
                $0.asksTeamManager = false
                $0.asksRunner = false
                $0.asksGoalUmpire = false
                $0.asksTimeKeeper = false
                $0.asksFieldUmpire = true
                $0.asksBoundaryUmpire1 = false
                $0.asksBoundaryUmpire2 = false
                $0.asksWaterBoy1 = false
                $0.asksWaterBoy2 = false
                $0.asksWaterBoy3 = false
                $0.asksWaterBoy4 = false
                $0.asksTrainer1 = false
                $0.asksTrainer2 = false
                $0.asksTrainer3 = false
                $0.asksTrainer4 = false
                $0.asksTrainers = false
            }
        case norm("Under 14's"), norm("Under 17's"), norm("B Grade"), norm("A Grade"):
            return update(grade) {
                $0.asksFieldUmpire = false
                $0.asksWaterBoy3 = false
                $0.asksWaterBoy4 = false
                $0.asksTrainer4 = false
                $0.asksTrainers = $0.asksTrainer1 || $0.asksTrainer2 || $0.asksTrainer3 || $0.asksTrainer4
            }
        default:
            return false
        }
    }

    @discardableResult
    private static func update(_ grade: Grade, apply: (Grade) -> Void) -> Bool {
        let snapshot = GradePromptSnapshot(grade: grade)
        apply(grade)
        return snapshot != GradePromptSnapshot(grade: grade)
    }
}

private struct GradePromptSnapshot: Equatable {
    let asksHeadCoach: Bool
    let asksAssistantCoach: Bool
    let asksTeamManager: Bool
    let asksRunner: Bool
    let asksGoalUmpire: Bool
    let asksTimeKeeper: Bool
    let asksFieldUmpire: Bool
    let asksBoundaryUmpire1: Bool
    let asksBoundaryUmpire2: Bool
    let asksWaterBoy1: Bool
    let asksWaterBoy2: Bool
    let asksWaterBoy3: Bool
    let asksWaterBoy4: Bool
    let asksTrainers: Bool
    let asksTrainer1: Bool
    let asksTrainer2: Bool
    let asksTrainer3: Bool
    let asksTrainer4: Bool

    init(grade: Grade) {
        asksHeadCoach = grade.asksHeadCoach
        asksAssistantCoach = grade.asksAssistantCoach
        asksTeamManager = grade.asksTeamManager
        asksRunner = grade.asksRunner
        asksGoalUmpire = grade.asksGoalUmpire
        asksTimeKeeper = grade.asksTimeKeeper
        asksFieldUmpire = grade.asksFieldUmpire
        asksBoundaryUmpire1 = grade.asksBoundaryUmpire1
        asksBoundaryUmpire2 = grade.asksBoundaryUmpire2
        asksWaterBoy1 = grade.asksWaterBoy1
        asksWaterBoy2 = grade.asksWaterBoy2
        asksWaterBoy3 = grade.asksWaterBoy3
        asksWaterBoy4 = grade.asksWaterBoy4
        asksTrainers = grade.asksTrainers
        asksTrainer1 = grade.asksTrainer1
        asksTrainer2 = grade.asksTrainer2
        asksTrainer3 = grade.asksTrainer3
        asksTrainer4 = grade.asksTrainer4
    }
}
