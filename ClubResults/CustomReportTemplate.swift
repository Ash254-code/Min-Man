import Foundation
import SwiftData

@Model
final class CustomReportTemplate {
    @Attribute(.unique) var id: UUID
    var name: String

    // Stored as JSON [UUID] to avoid fragile SwiftData transformables.
    var gradeIDsData: Data

    // Core sections
    var includeBestPlayers: Bool
    var includePlayerGrades: Bool
    var includeGoalKickers: Bool
    var includeGuernseyNumbers: Bool
    var includeBestAndFairestVotes: Bool
    var includeStaffRoles: Bool
    var includeOfficials: Bool
    var includeUmpires: Bool
    var includeTrainers: Bool
    var includeMatchNotes: Bool

    // Filters
    var includeOnlyActiveGrades: Bool
    var minimumGamesPlayed: Int
    var groupingModeRawValue: Int
    var dateRangeQuickPickRawValue: String
    var customDateRangeStart: Date
    var customDateRangeEnd: Date

    init(
        id: UUID = UUID(),
        name: String,
        gradeIDs: [UUID] = [],
        includeBestPlayers: Bool = true,
        includePlayerGrades: Bool = true,
        includeGoalKickers: Bool = true,
        includeGuernseyNumbers: Bool = true,
        includeBestAndFairestVotes: Bool = true,
        includeStaffRoles: Bool = true,
        includeOfficials: Bool = true,
        includeUmpires: Bool = true,
        includeTrainers: Bool = true,
        includeMatchNotes: Bool = false,
        includeOnlyActiveGrades: Bool = true,
        minimumGamesPlayed: Int = 0,
        groupingModeRawValue: Int = 0,
        dateRangeQuickPickRawValue: String = "Most Recent Game",
        customDateRangeStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
        customDateRangeEnd: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.gradeIDsData = (try? JSONEncoder().encode(gradeIDs)) ?? Data()
        self.includeBestPlayers = includeBestPlayers
        self.includePlayerGrades = includePlayerGrades
        self.includeGoalKickers = includeGoalKickers
        self.includeGuernseyNumbers = includeGuernseyNumbers
        self.includeBestAndFairestVotes = includeBestAndFairestVotes
        self.includeStaffRoles = includeStaffRoles
        self.includeOfficials = includeOfficials
        self.includeUmpires = includeUmpires
        self.includeTrainers = includeTrainers
        self.includeMatchNotes = includeMatchNotes
        self.includeOnlyActiveGrades = includeOnlyActiveGrades
        self.minimumGamesPlayed = max(0, minimumGamesPlayed)
        self.groupingModeRawValue = groupingModeRawValue
        self.dateRangeQuickPickRawValue = dateRangeQuickPickRawValue
        self.customDateRangeStart = customDateRangeStart
        self.customDateRangeEnd = customDateRangeEnd
    }

    var gradeIDs: [UUID] {
        get {
            (try? JSONDecoder().decode([UUID].self, from: gradeIDsData)) ?? []
        }
        set {
            gradeIDsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
}
