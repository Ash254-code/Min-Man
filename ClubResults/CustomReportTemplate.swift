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
    var bestPlayersLimit: Int
    var includePlayerGrades: Bool
    var guestVotesLimit: Int
    var includeGoalKickers: Bool
    var goalKickersLimit: Int
    var includeGuernseyNumbers: Bool
    var includeBestAndFairestVotes: Bool
    var bestAndFairestLimit: Int
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
        bestPlayersLimit: Int = 0,
        includePlayerGrades: Bool = true,
        guestVotesLimit: Int = 0,
        includeGoalKickers: Bool = true,
        goalKickersLimit: Int = 0,
        includeGuernseyNumbers: Bool = true,
        includeBestAndFairestVotes: Bool = true,
        bestAndFairestLimit: Int = 5,
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
        self.bestPlayersLimit = max(0, min(bestPlayersLimit, 10))
        self.includePlayerGrades = includePlayerGrades
        self.guestVotesLimit = max(0, min(guestVotesLimit, 10))
        self.includeGoalKickers = includeGoalKickers
        self.goalKickersLimit = max(0, min(goalKickersLimit, 10))
        self.includeGuernseyNumbers = includeGuernseyNumbers
        self.includeBestAndFairestVotes = includeBestAndFairestVotes
        self.bestAndFairestLimit = max(0, min(bestAndFairestLimit, 10))
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
