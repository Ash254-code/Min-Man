import Foundation
import SwiftData

@Model
final class CustomReportTemplate {
    static let defaultIncludeSectionOrder: [String] = [
        "scores",
        "bestPlayers",
        "guestVotes",
        "goalKickers",
        "bestAndFairest",
        "coachingStaff",
        "officials",
        "trainers",
        "matchNotes"
    ]

    @Attribute(.unique) var id: UUID
    var name: String

    // Stored as JSON [UUID] to avoid fragile SwiftData transformables.
    var gradeIDsData: Data

    // Core sections
    var includeScores: Bool
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
    var includeSectionOrderData: Data
    var reportColumnCount: Int
    var includeSectionColumnAssignmentsData: Data

    // Filters
    var sendReportOnGameSave: Bool
    var includeOnlyActiveGrades: Bool
    var includePlayersOnly: Bool
    var minimumGamesPlayed: Int
    var groupingModeRawValue: Int
    var dateRangeQuickPickRawValue: String
    var customDateRangeStart: Date
    var customDateRangeEnd: Date

    init(
        id: UUID = UUID(),
        name: String,
        gradeIDs: [UUID] = [],
        includeScores: Bool = true,
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
        includeSectionOrder: [String] = CustomReportTemplate.defaultIncludeSectionOrder,
        reportColumnCount: Int = 2,
        includeSectionColumnAssignments: [String: Int] = [:],
        sendReportOnGameSave: Bool = false,
        includeOnlyActiveGrades: Bool = true,
        includePlayersOnly: Bool = false,
        minimumGamesPlayed: Int = 0,
        groupingModeRawValue: Int = 0,
        dateRangeQuickPickRawValue: String = "Most Recent Game",
        customDateRangeStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
        customDateRangeEnd: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.gradeIDsData = (try? JSONEncoder().encode(gradeIDs)) ?? Data()
        self.includeScores = includeScores
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
        self.includeSectionOrderData = (try? JSONEncoder().encode(includeSectionOrder)) ?? Data()
        self.reportColumnCount = max(1, min(reportColumnCount, 3))
        self.includeSectionColumnAssignmentsData = (try? JSONEncoder().encode(includeSectionColumnAssignments)) ?? Data()
        self.sendReportOnGameSave = sendReportOnGameSave
        self.includeOnlyActiveGrades = includeOnlyActiveGrades
        self.includePlayersOnly = includePlayersOnly
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

    var includeSectionOrder: [String] {
        get {
            let decoded = (try? JSONDecoder().decode([String].self, from: includeSectionOrderData)) ?? []
            if decoded.isEmpty {
                return Self.defaultIncludeSectionOrder
            }

            var normalized: [String] = []
            for key in decoded where Self.defaultIncludeSectionOrder.contains(key) && !normalized.contains(key) {
                normalized.append(key)
            }
            for key in Self.defaultIncludeSectionOrder where !normalized.contains(key) {
                normalized.append(key)
            }
            return normalized
        }
        set {
            var normalized: [String] = []
            for key in newValue where Self.defaultIncludeSectionOrder.contains(key) && !normalized.contains(key) {
                normalized.append(key)
            }
            for key in Self.defaultIncludeSectionOrder where !normalized.contains(key) {
                normalized.append(key)
            }
            includeSectionOrderData = (try? JSONEncoder().encode(normalized)) ?? Data()
        }
    }

    var normalizedReportColumnCount: Int {
        max(1, min(reportColumnCount, 3))
    }

    var includeSectionColumnAssignments: [String: Int] {
        get {
            let decoded = (try? JSONDecoder().decode([String: Int].self, from: includeSectionColumnAssignmentsData)) ?? [:]
            var normalized: [String: Int] = [:]
            for key in Self.defaultIncludeSectionOrder {
                let assigned = decoded[key] ?? 0
                normalized[key] = max(0, min(assigned, normalizedReportColumnCount - 1))
            }
            return normalized
        }
        set {
            var normalized: [String: Int] = [:]
            let columnCount = normalizedReportColumnCount
            for key in Self.defaultIncludeSectionOrder {
                let assigned = newValue[key] ?? 0
                normalized[key] = max(0, min(assigned, columnCount - 1))
            }
            includeSectionColumnAssignmentsData = (try? JSONEncoder().encode(normalized)) ?? Data()
        }
    }
}
