import Foundation
import SwiftData
import UIKit
import UniformTypeIdentifiers

struct AppBackupEnvelope: Codable {
    let appName: String
    let backupFormatVersion: Int
    let exportedAt: Date
    let appVersion: String
    let buildNumber: String
    let platform: String
    let schemaVersion: Int
    let itemCounts: AppBackupItemCounts
    let payload: AppBackupPayload

    private enum CodingKeys: String, CodingKey {
        case appName, backupFormatVersion, exportedAt, appVersion, buildNumber, platform, schemaVersion, itemCounts, payload
    }

    init(
        appName: String,
        backupFormatVersion: Int,
        exportedAt: Date,
        appVersion: String,
        buildNumber: String,
        platform: String,
        schemaVersion: Int,
        itemCounts: AppBackupItemCounts,
        payload: AppBackupPayload
    ) {
        self.appName = appName
        self.backupFormatVersion = backupFormatVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.platform = platform
        self.schemaVersion = schemaVersion
        self.itemCounts = itemCounts
        self.payload = payload
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appName = try c.decodeIfPresent(String.self, forKey: .appName) ?? "ClubResults"
        backupFormatVersion = try c.decodeIfPresent(Int.self, forKey: .backupFormatVersion) ?? 1
        exportedAt = try c.decode(Date.self, forKey: .exportedAt)
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion) ?? "unknown"
        buildNumber = try c.decodeIfPresent(String.self, forKey: .buildNumber) ?? "unknown"
        platform = try c.decodeIfPresent(String.self, forKey: .platform) ?? "unknown"
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? backupFormatVersion
        itemCounts = try c.decode(AppBackupItemCounts.self, forKey: .itemCounts)
        payload = try c.decode(AppBackupPayload.self, forKey: .payload)
    }
}

struct AppBackupItemCounts: Codable {
    let grades: Int
    let players: Int
    let games: Int
    let contacts: Int
    let reportRecipients: Int
    let customReportTemplates: Int
    let staffMembers: Int
    let staffDefaults: Int
    let contactGroups: Int
    let contactGroupMemberships: Int
    let contactSectionMemberships: Int
    let reportRecipientGroups: Int
    let customReportRecipientSections: Int
    let customReportRecipientGroups: Int
    let customReportRecipientContacts: Int
    let lastStaffSelections: Int
    let draftResumeFlags: Int

    private enum CodingKeys: String, CodingKey {
        case grades, players, games, contacts, reportRecipients, customReportTemplates, staffMembers, staffDefaults
        case contactGroups, contactGroupMemberships, contactSectionMemberships
        case reportRecipientGroups, customReportRecipientSections, customReportRecipientGroups, customReportRecipientContacts
        case lastStaffSelections, draftResumeFlags
    }

    init(
        grades: Int,
        players: Int,
        games: Int,
        contacts: Int,
        reportRecipients: Int,
        customReportTemplates: Int,
        staffMembers: Int,
        staffDefaults: Int,
        contactGroups: Int,
        contactGroupMemberships: Int,
        contactSectionMemberships: Int,
        reportRecipientGroups: Int,
        customReportRecipientSections: Int,
        customReportRecipientGroups: Int,
        customReportRecipientContacts: Int,
        lastStaffSelections: Int,
        draftResumeFlags: Int
    ) {
        self.grades = grades
        self.players = players
        self.games = games
        self.contacts = contacts
        self.reportRecipients = reportRecipients
        self.customReportTemplates = customReportTemplates
        self.staffMembers = staffMembers
        self.staffDefaults = staffDefaults
        self.contactGroups = contactGroups
        self.contactGroupMemberships = contactGroupMemberships
        self.contactSectionMemberships = contactSectionMemberships
        self.reportRecipientGroups = reportRecipientGroups
        self.customReportRecipientSections = customReportRecipientSections
        self.customReportRecipientGroups = customReportRecipientGroups
        self.customReportRecipientContacts = customReportRecipientContacts
        self.lastStaffSelections = lastStaffSelections
        self.draftResumeFlags = draftResumeFlags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        grades = try c.decodeIfPresent(Int.self, forKey: .grades) ?? 0
        players = try c.decodeIfPresent(Int.self, forKey: .players) ?? 0
        games = try c.decodeIfPresent(Int.self, forKey: .games) ?? 0
        contacts = try c.decodeIfPresent(Int.self, forKey: .contacts) ?? 0
        reportRecipients = try c.decodeIfPresent(Int.self, forKey: .reportRecipients) ?? 0
        customReportTemplates = try c.decodeIfPresent(Int.self, forKey: .customReportTemplates) ?? 0
        staffMembers = try c.decodeIfPresent(Int.self, forKey: .staffMembers) ?? 0
        staffDefaults = try c.decodeIfPresent(Int.self, forKey: .staffDefaults) ?? 0
        contactGroups = try c.decodeIfPresent(Int.self, forKey: .contactGroups) ?? 0
        contactGroupMemberships = try c.decodeIfPresent(Int.self, forKey: .contactGroupMemberships) ?? 0
        contactSectionMemberships = try c.decodeIfPresent(Int.self, forKey: .contactSectionMemberships) ?? 0
        reportRecipientGroups = try c.decodeIfPresent(Int.self, forKey: .reportRecipientGroups) ?? 0
        customReportRecipientSections = try c.decodeIfPresent(Int.self, forKey: .customReportRecipientSections) ?? 0
        customReportRecipientGroups = try c.decodeIfPresent(Int.self, forKey: .customReportRecipientGroups) ?? 0
        customReportRecipientContacts = try c.decodeIfPresent(Int.self, forKey: .customReportRecipientContacts) ?? 0
        lastStaffSelections = try c.decodeIfPresent(Int.self, forKey: .lastStaffSelections) ?? 0
        draftResumeFlags = try c.decodeIfPresent(Int.self, forKey: .draftResumeFlags) ?? 0
    }

    static func fromPayload(_ payload: AppBackupPayload) -> AppBackupItemCounts {
        AppBackupItemCounts(
            grades: payload.grades.count,
            players: payload.players.count,
            games: payload.games.count,
            contacts: payload.contacts.count,
            reportRecipients: payload.reportRecipients.count,
            customReportTemplates: payload.customReportTemplates.count,
            staffMembers: payload.staffMembers.count,
            staffDefaults: payload.staffDefaults.count,
            contactGroups: payload.contactGroups.count,
            contactGroupMemberships: payload.contactGroupMemberships.count,
            contactSectionMemberships: payload.contactSectionMemberships.count,
            reportRecipientGroups: payload.reportRecipientGroups.count,
            customReportRecipientSections: payload.customReportRecipientSections.count,
            customReportRecipientGroups: payload.customReportRecipientGroups.count,
            customReportRecipientContacts: payload.customReportRecipientContacts.count,
            lastStaffSelections: payload.appSettings.lastStaffSelections.count,
            draftResumeFlags: payload.appSettings.draftResumeOpenLiveFlags.count
        )
    }
}

struct AppBackupPayload: Codable {
    let grades: [GradeRecord]
    let players: [PlayerRecord]
    let games: [GameRecord]
    let contacts: [ContactRecord]
    let reportRecipients: [ReportRecipientRecord]
    let customReportTemplates: [CustomReportTemplateRecord]
    let staffMembers: [StaffMemberRecord]
    let staffDefaults: [StaffDefaultRecord]
    let contactGroups: [ContactGroupRecord]
    let contactGroupMemberships: [ContactGroupMembershipRecord]
    let contactSectionMemberships: [ContactSectionMembershipRecord]
    let reportRecipientGroups: [ReportRecipientGroupRecord]
    let customReportRecipientSections: [CustomReportRecipientSectionRecord]
    let customReportRecipientGroups: [CustomReportRecipientGroupRecord]
    let customReportRecipientContacts: [CustomReportRecipientContactRecord]
    let appSettings: AppSettingsRecord

    init(
        grades: [GradeRecord],
        players: [PlayerRecord],
        games: [GameRecord],
        contacts: [ContactRecord],
        reportRecipients: [ReportRecipientRecord],
        customReportTemplates: [CustomReportTemplateRecord],
        staffMembers: [StaffMemberRecord],
        staffDefaults: [StaffDefaultRecord],
        contactGroups: [ContactGroupRecord],
        contactGroupMemberships: [ContactGroupMembershipRecord],
        contactSectionMemberships: [ContactSectionMembershipRecord],
        reportRecipientGroups: [ReportRecipientGroupRecord],
        customReportRecipientSections: [CustomReportRecipientSectionRecord],
        customReportRecipientGroups: [CustomReportRecipientGroupRecord],
        customReportRecipientContacts: [CustomReportRecipientContactRecord],
        appSettings: AppSettingsRecord
    ) {
        self.grades = grades
        self.players = players
        self.games = games
        self.contacts = contacts
        self.reportRecipients = reportRecipients
        self.customReportTemplates = customReportTemplates
        self.staffMembers = staffMembers
        self.staffDefaults = staffDefaults
        self.contactGroups = contactGroups
        self.contactGroupMemberships = contactGroupMemberships
        self.contactSectionMemberships = contactSectionMemberships
        self.reportRecipientGroups = reportRecipientGroups
        self.customReportRecipientSections = customReportRecipientSections
        self.customReportRecipientGroups = customReportRecipientGroups
        self.customReportRecipientContacts = customReportRecipientContacts
        self.appSettings = appSettings
    }

    private enum CodingKeys: String, CodingKey {
        case grades, players, games, contacts, reportRecipients, customReportTemplates
        case staffMembers, staffDefaults
        case contactGroups, contactGroupMemberships, contactSectionMemberships
        case reportRecipientGroups, customReportRecipientSections, customReportRecipientGroups, customReportRecipientContacts
        case appSettings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        grades = try c.decodeIfPresent([GradeRecord].self, forKey: .grades) ?? []
        players = try c.decodeIfPresent([PlayerRecord].self, forKey: .players) ?? []
        games = try c.decodeIfPresent([GameRecord].self, forKey: .games) ?? []
        contacts = try c.decodeIfPresent([ContactRecord].self, forKey: .contacts) ?? []
        reportRecipients = try c.decodeIfPresent([ReportRecipientRecord].self, forKey: .reportRecipients) ?? []
        customReportTemplates = try c.decodeIfPresent([CustomReportTemplateRecord].self, forKey: .customReportTemplates) ?? []
        staffMembers = try c.decodeIfPresent([StaffMemberRecord].self, forKey: .staffMembers) ?? []
        staffDefaults = try c.decodeIfPresent([StaffDefaultRecord].self, forKey: .staffDefaults) ?? []
        contactGroups = try c.decodeIfPresent([ContactGroupRecord].self, forKey: .contactGroups) ?? []
        contactGroupMemberships = try c.decodeIfPresent([ContactGroupMembershipRecord].self, forKey: .contactGroupMemberships) ?? []
        contactSectionMemberships = try c.decodeIfPresent([ContactSectionMembershipRecord].self, forKey: .contactSectionMemberships) ?? []
        reportRecipientGroups = try c.decodeIfPresent([ReportRecipientGroupRecord].self, forKey: .reportRecipientGroups) ?? []
        customReportRecipientSections = try c.decodeIfPresent([CustomReportRecipientSectionRecord].self, forKey: .customReportRecipientSections) ?? []
        customReportRecipientGroups = try c.decodeIfPresent([CustomReportRecipientGroupRecord].self, forKey: .customReportRecipientGroups) ?? []
        customReportRecipientContacts = try c.decodeIfPresent([CustomReportRecipientContactRecord].self, forKey: .customReportRecipientContacts) ?? []
        appSettings = try c.decodeIfPresent(AppSettingsRecord.self, forKey: .appSettings) ?? AppSettingsRecord.defaults
    }
}

struct GradeRecord: Codable {
    let id: UUID
    let name: String
    let isActive: Bool
    let displayOrder: Int
    let asksHeadCoach: Bool
    let asksAssistantCoach: Bool
    let asksTeamManager: Bool
    let asksRunner: Bool
    let asksGoalUmpire: Bool
    let asksFieldUmpire: Bool
    let asksBoundaryUmpire1: Bool
    let asksBoundaryUmpire2: Bool
    let asksTrainers: Bool
    let asksTrainer1: Bool
    let asksTrainer2: Bool
    let asksTrainer3: Bool
    let asksTrainer4: Bool
    let asksNotes: Bool
    let asksScore: Bool
    let asksLiveGameView: Bool
    let asksGoalKickers: Bool
    let bestPlayersCount: Int
    let asksGuestBestFairestVotesScan: Bool
    let guestBestPlayersCount: Int
    let allowsLiveGameView: Bool
    let quarterLengthMinutes: Int

    private enum CodingKeys: String, CodingKey {
        case id, name, isActive, displayOrder
        case asksHeadCoach, asksAssistantCoach, asksTeamManager, asksRunner
        case asksGoalUmpire, asksFieldUmpire, asksBoundaryUmpire1, asksBoundaryUmpire2
        case asksTrainers, asksTrainer1, asksTrainer2, asksTrainer3, asksTrainer4
        case asksNotes, asksScore, asksLiveGameView, asksGoalKickers
        case bestPlayersCount, guestBestPlayersCount
        case asksGuestBestFairestVotesScan, allowsLiveGameView, quarterLengthMinutes
    }

    init(_ grade: Grade) {
        id = grade.id
        name = grade.name
        isActive = grade.isActive
        displayOrder = grade.displayOrder
        asksHeadCoach = grade.asksHeadCoach
        asksAssistantCoach = grade.asksAssistantCoach
        asksTeamManager = grade.asksTeamManager
        asksRunner = grade.asksRunner
        asksGoalUmpire = grade.asksGoalUmpire
        asksFieldUmpire = grade.asksFieldUmpire
        asksBoundaryUmpire1 = grade.asksBoundaryUmpire1
        asksBoundaryUmpire2 = grade.asksBoundaryUmpire2
        asksTrainers = grade.asksTrainers
        asksTrainer1 = grade.asksTrainer1
        asksTrainer2 = grade.asksTrainer2
        asksTrainer3 = grade.asksTrainer3
        asksTrainer4 = grade.asksTrainer4
        asksNotes = grade.asksNotes
        asksScore = grade.asksScore
        asksLiveGameView = grade.asksLiveGameView
        asksGoalKickers = grade.asksGoalKickers
        bestPlayersCount = grade.bestPlayersCount
        asksGuestBestFairestVotesScan = grade.asksGuestBestFairestVotesScan
        guestBestPlayersCount = grade.guestBestPlayersCount
        allowsLiveGameView = grade.allowsLiveGameView
        quarterLengthMinutes = grade.quarterLengthMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        displayOrder = try c.decodeIfPresent(Int.self, forKey: .displayOrder) ?? 0
        asksHeadCoach = try c.decodeIfPresent(Bool.self, forKey: .asksHeadCoach) ?? true
        asksAssistantCoach = try c.decodeIfPresent(Bool.self, forKey: .asksAssistantCoach) ?? true
        asksTeamManager = try c.decodeIfPresent(Bool.self, forKey: .asksTeamManager) ?? true
        asksRunner = try c.decodeIfPresent(Bool.self, forKey: .asksRunner) ?? true
        asksGoalUmpire = try c.decodeIfPresent(Bool.self, forKey: .asksGoalUmpire) ?? true
        asksFieldUmpire = try c.decodeIfPresent(Bool.self, forKey: .asksFieldUmpire) ?? true
        asksBoundaryUmpire1 = try c.decodeIfPresent(Bool.self, forKey: .asksBoundaryUmpire1) ?? true
        asksBoundaryUmpire2 = try c.decodeIfPresent(Bool.self, forKey: .asksBoundaryUmpire2) ?? true
        asksTrainers = try c.decodeIfPresent(Bool.self, forKey: .asksTrainers) ?? true
        asksTrainer1 = try c.decodeIfPresent(Bool.self, forKey: .asksTrainer1) ?? asksTrainers
        asksTrainer2 = try c.decodeIfPresent(Bool.self, forKey: .asksTrainer2) ?? asksTrainers
        asksTrainer3 = try c.decodeIfPresent(Bool.self, forKey: .asksTrainer3) ?? asksTrainers
        asksTrainer4 = try c.decodeIfPresent(Bool.self, forKey: .asksTrainer4) ?? asksTrainers
        asksNotes = try c.decodeIfPresent(Bool.self, forKey: .asksNotes) ?? true
        asksScore = try c.decodeIfPresent(Bool.self, forKey: .asksScore) ?? true
        asksLiveGameView = try c.decodeIfPresent(Bool.self, forKey: .asksLiveGameView) ?? true
        asksGoalKickers = try c.decodeIfPresent(Bool.self, forKey: .asksGoalKickers) ?? true
        bestPlayersCount = try c.decodeIfPresent(Int.self, forKey: .bestPlayersCount) ?? 6
        guestBestPlayersCount = try c.decodeIfPresent(Int.self, forKey: .guestBestPlayersCount) ?? 3
        asksGuestBestFairestVotesScan = try c.decodeIfPresent(Bool.self, forKey: .asksGuestBestFairestVotesScan) ?? false
        allowsLiveGameView = try c.decodeIfPresent(Bool.self, forKey: .allowsLiveGameView) ?? false
        quarterLengthMinutes = try c.decodeIfPresent(Int.self, forKey: .quarterLengthMinutes) ?? 20
    }
}

struct PlayerRecord: Codable {
    let id: UUID
    let firstName: String
    let lastName: String
    let name: String
    let number: Int?
    let gradeIDs: [UUID]
    let isActive: Bool

    init(_ player: Player) {
        id = player.id
        firstName = player.firstName
        lastName = player.lastName
        name = player.name
        number = player.number
        gradeIDs = player.gradeIDs
        isActive = player.isActive
    }
}

struct GameGoalKickerRecord: Codable {
    let id: UUID
    let playerID: UUID?
    let goals: Int

    init(_ item: GameGoalKickerEntry) {
        id = item.id
        playerID = item.playerID
        goals = item.goals
    }
}

struct GameRecord: Codable {
    let id: UUID
    let gradeID: UUID
    let date: Date
    let opponent: String
    let venue: String
    let ourGoals: Int
    let ourBehinds: Int
    let theirGoals: Int
    let theirBehinds: Int
    let goalKickers: [GameGoalKickerRecord]
    let bestPlayersRanked: [UUID]
    let guestVotesRanked: [GameGuestVoteEntry]
    let headCoachName: String
    let assistantCoachName: String
    let teamManagerName: String
    let runnerName: String
    let goalUmpireName: String
    let fieldUmpireName: String
    let boundaryUmpire1Name: String
    let boundaryUmpire2Name: String
    let trainers: [String]
    let notes: String
    let guestBestFairestVotesScanPDF: Data?
    let isDraft: Bool

    private enum CodingKeys: String, CodingKey {
        case id, gradeID, date, opponent, venue
        case ourGoals, ourBehinds, theirGoals, theirBehinds
        case goalKickers, bestPlayersRanked, guestVotesRanked
        case headCoachName, assistantCoachName, teamManagerName, runnerName
        case goalUmpireName, fieldUmpireName, boundaryUmpire1Name, boundaryUmpire2Name
        case trainers, notes, guestBestFairestVotesScanPDF, isDraft
    }

    init(_ game: Game) {
        id = game.id
        gradeID = game.gradeID
        date = game.date
        opponent = game.opponent
        venue = game.venue
        ourGoals = game.ourGoals
        ourBehinds = game.ourBehinds
        theirGoals = game.theirGoals
        theirBehinds = game.theirBehinds
        goalKickers = game.goalKickers.map { GameGoalKickerRecord($0) }
        bestPlayersRanked = game.bestPlayersRanked
        guestVotesRanked = game.guestVotesRanked
        headCoachName = game.headCoachName
        assistantCoachName = game.assistantCoachName
        teamManagerName = game.teamManagerName
        runnerName = game.runnerName
        goalUmpireName = game.goalUmpireName
        fieldUmpireName = game.fieldUmpireName
        boundaryUmpire1Name = game.boundaryUmpire1Name
        boundaryUmpire2Name = game.boundaryUmpire2Name
        trainers = game.trainers
        notes = game.notes
        guestBestFairestVotesScanPDF = game.guestBestFairestVotesScanPDF
        isDraft = game.isDraft
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        gradeID = try c.decode(UUID.self, forKey: .gradeID)
        date = try c.decode(Date.self, forKey: .date)
        opponent = try c.decode(String.self, forKey: .opponent)
        venue = try c.decodeIfPresent(String.self, forKey: .venue) ?? ""
        ourGoals = try c.decode(Int.self, forKey: .ourGoals)
        ourBehinds = try c.decode(Int.self, forKey: .ourBehinds)
        theirGoals = try c.decode(Int.self, forKey: .theirGoals)
        theirBehinds = try c.decode(Int.self, forKey: .theirBehinds)
        goalKickers = try c.decodeIfPresent([GameGoalKickerRecord].self, forKey: .goalKickers) ?? []
        bestPlayersRanked = try c.decodeIfPresent([UUID].self, forKey: .bestPlayersRanked) ?? []
        guestVotesRanked = try c.decodeIfPresent([GameGuestVoteEntry].self, forKey: .guestVotesRanked) ?? []
        headCoachName = try c.decodeIfPresent(String.self, forKey: .headCoachName) ?? ""
        assistantCoachName = try c.decodeIfPresent(String.self, forKey: .assistantCoachName) ?? ""
        teamManagerName = try c.decodeIfPresent(String.self, forKey: .teamManagerName) ?? ""
        runnerName = try c.decodeIfPresent(String.self, forKey: .runnerName) ?? ""
        goalUmpireName = try c.decodeIfPresent(String.self, forKey: .goalUmpireName) ?? ""
        fieldUmpireName = try c.decodeIfPresent(String.self, forKey: .fieldUmpireName) ?? ""
        boundaryUmpire1Name = try c.decodeIfPresent(String.self, forKey: .boundaryUmpire1Name) ?? ""
        boundaryUmpire2Name = try c.decodeIfPresent(String.self, forKey: .boundaryUmpire2Name) ?? ""
        trainers = try c.decodeIfPresent([String].self, forKey: .trainers) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        guestBestFairestVotesScanPDF = try c.decodeIfPresent(Data.self, forKey: .guestBestFairestVotesScanPDF)
        isDraft = try c.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
    }
}

struct ContactRecord: Codable {
    let id: UUID
    let name: String
    let mobile: String
    let email: String

    init(_ contact: Contact) {
        id = contact.id
        name = contact.name
        mobile = contact.mobile
        email = contact.email
    }
}

struct ReportRecipientRecord: Codable {
    let id: UUID
    let gradeID: UUID
    let contactID: UUID
    let sendEmail: Bool
    let sendText: Bool

    init(_ recipient: ReportRecipient) {
        id = recipient.id
        gradeID = recipient.gradeID
        contactID = recipient.contactID
        sendEmail = recipient.sendEmail
        sendText = recipient.sendText
    }
}

struct CustomReportTemplateRecord: Codable {
    let id: UUID
    let name: String
    let gradeIDs: [UUID]
    let includeScores: Bool
    let includeBestPlayers: Bool
    let bestPlayersLimit: Int
    let includePlayerGrades: Bool
    let guestVotesLimit: Int
    let includeGoalKickers: Bool
    let goalKickersLimit: Int
    let includeGuernseyNumbers: Bool
    let includeBestAndFairestVotes: Bool
    let bestAndFairestLimit: Int
    let includeStaffRoles: Bool
    let includeOfficials: Bool
    let includeUmpires: Bool
    let includeTrainers: Bool
    let includeMatchNotes: Bool
    let includeOnlyActiveGrades: Bool
    let minimumGamesPlayed: Int
    let groupingModeRawValue: Int

    init(_ template: CustomReportTemplate) {
        id = template.id
        name = template.name
        gradeIDs = template.gradeIDs
        includeScores = template.includeScores
        includeBestPlayers = template.includeBestPlayers
        bestPlayersLimit = template.bestPlayersLimit
        includePlayerGrades = template.includePlayerGrades
        guestVotesLimit = template.guestVotesLimit
        includeGoalKickers = template.includeGoalKickers
        goalKickersLimit = template.goalKickersLimit
        includeGuernseyNumbers = template.includeGuernseyNumbers
        includeBestAndFairestVotes = template.includeBestAndFairestVotes
        bestAndFairestLimit = template.bestAndFairestLimit
        includeStaffRoles = template.includeStaffRoles
        includeOfficials = template.includeOfficials
        includeUmpires = template.includeUmpires
        includeTrainers = template.includeTrainers
        includeMatchNotes = template.includeMatchNotes
        includeOnlyActiveGrades = template.includeOnlyActiveGrades
        minimumGamesPlayed = template.minimumGamesPlayed
        groupingModeRawValue = template.groupingModeRawValue
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, gradeIDs, includeScores, includeBestPlayers, bestPlayersLimit, includePlayerGrades, guestVotesLimit
        case includeGoalKickers, goalKickersLimit, includeGuernseyNumbers, includeBestAndFairestVotes
        case bestAndFairestLimit, includeStaffRoles, includeOfficials
        case includeUmpires, includeTrainers, includeMatchNotes, includeOnlyActiveGrades
        case minimumGamesPlayed, groupingModeRawValue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        gradeIDs = try c.decodeIfPresent([UUID].self, forKey: .gradeIDs) ?? []
        includeScores = try c.decodeIfPresent(Bool.self, forKey: .includeScores) ?? true
        includeBestPlayers = try c.decodeIfPresent(Bool.self, forKey: .includeBestPlayers) ?? true
        bestPlayersLimit = try c.decodeIfPresent(Int.self, forKey: .bestPlayersLimit) ?? 0
        includePlayerGrades = try c.decodeIfPresent(Bool.self, forKey: .includePlayerGrades) ?? true
        guestVotesLimit = try c.decodeIfPresent(Int.self, forKey: .guestVotesLimit) ?? 0
        includeGoalKickers = try c.decodeIfPresent(Bool.self, forKey: .includeGoalKickers) ?? true
        goalKickersLimit = try c.decodeIfPresent(Int.self, forKey: .goalKickersLimit) ?? 0
        includeGuernseyNumbers = try c.decodeIfPresent(Bool.self, forKey: .includeGuernseyNumbers) ?? true
        includeBestAndFairestVotes = try c.decodeIfPresent(Bool.self, forKey: .includeBestAndFairestVotes) ?? true
        bestAndFairestLimit = try c.decodeIfPresent(Int.self, forKey: .bestAndFairestLimit) ?? 5
        includeStaffRoles = try c.decodeIfPresent(Bool.self, forKey: .includeStaffRoles) ?? true
        includeOfficials = try c.decodeIfPresent(Bool.self, forKey: .includeOfficials) ?? true
        includeUmpires = try c.decodeIfPresent(Bool.self, forKey: .includeUmpires) ?? true
        includeTrainers = try c.decodeIfPresent(Bool.self, forKey: .includeTrainers) ?? true
        includeMatchNotes = try c.decodeIfPresent(Bool.self, forKey: .includeMatchNotes) ?? false
        includeOnlyActiveGrades = try c.decodeIfPresent(Bool.self, forKey: .includeOnlyActiveGrades) ?? true
        minimumGamesPlayed = try c.decodeIfPresent(Int.self, forKey: .minimumGamesPlayed) ?? 0
        groupingModeRawValue = try c.decodeIfPresent(Int.self, forKey: .groupingModeRawValue) ?? 0
    }
}

struct StaffMemberRecord: Codable {
    let id: UUID
    let name: String
    let role: String
    let gradeID: UUID

    init(_ staff: StaffMember) {
        id = staff.id
        name = staff.name
        role = staff.role.rawValue
        gradeID = staff.gradeID
    }
}

struct StaffDefaultRecord: Codable {
    let id: UUID
    let gradeID: UUID
    let role: String
    let name: String

    init(_ item: StaffDefault) {
        id = item.id
        gradeID = item.gradeID
        role = item.role.rawValue
        name = item.name
    }
}

struct ContactGroupRecord: Codable {
    let id: UUID
    let name: String

    init(_ item: ContactGroup) {
        id = item.id
        name = item.name
    }
}

struct ContactGroupMembershipRecord: Codable {
    let id: UUID
    let contactID: UUID
    let groupID: UUID

    init(_ item: ContactGroupMembership) {
        id = item.id
        contactID = item.contactID
        groupID = item.groupID
    }
}

struct ContactSectionMembershipRecord: Codable {
    let id: UUID
    let contactID: UUID
    let sectionKey: String

    init(_ item: ContactSectionMembership) {
        id = item.id
        contactID = item.contactID
        sectionKey = item.sectionKey
    }
}

struct ReportRecipientGroupRecord: Codable {
    let id: UUID
    let gradeID: UUID
    let groupID: UUID
    let sendEmail: Bool
    let sendText: Bool

    init(_ item: ReportRecipientGroup) {
        id = item.id
        gradeID = item.gradeID
        groupID = item.groupID
        sendEmail = item.sendEmail
        sendText = item.sendText
    }
}

struct CustomReportRecipientSectionRecord: Codable {
    let id: UUID
    let templateID: UUID
    let sectionKey: String

    init(_ item: CustomReportRecipientSection) {
        id = item.id
        templateID = item.templateID
        sectionKey = item.sectionKey
    }
}

struct CustomReportRecipientGroupRecord: Codable {
    let id: UUID
    let templateID: UUID
    let groupID: UUID

    init(_ item: CustomReportRecipientGroup) {
        id = item.id
        templateID = item.templateID
        groupID = item.groupID
    }
}

struct CustomReportRecipientContactRecord: Codable {
    let id: UUID
    let templateID: UUID
    let contactID: UUID

    init(_ item: CustomReportRecipientContact) {
        id = item.id
        templateID = item.templateID
        contactID = item.contactID
    }
}

struct AppSettingsRecord: Codable {
    let appAppearanceRawValue: String
    let clubConfiguration: ClubConfiguration
    let boundaryUmpireGradeMappings: [String: [UUID]]
    let lastStaffSelections: [String: String]
    let draftResumeOpenLiveFlags: [String: Bool]
    let legacyGradesBackup: [GradeBackup]
    let legacyContactsBackup: [ContactBackup]

    private enum CodingKeys: String, CodingKey {
        case appAppearanceRawValue, clubConfiguration, boundaryUmpireGradeMappings
        case lastStaffSelections, draftResumeOpenLiveFlags
        case legacyGradesBackup, legacyContactsBackup
    }

    init(
        appAppearanceRawValue: String,
        clubConfiguration: ClubConfiguration,
        boundaryUmpireGradeMappings: [String: [UUID]],
        lastStaffSelections: [String: String],
        draftResumeOpenLiveFlags: [String: Bool],
        legacyGradesBackup: [GradeBackup],
        legacyContactsBackup: [ContactBackup]
    ) {
        self.appAppearanceRawValue = appAppearanceRawValue
        self.clubConfiguration = clubConfiguration
        self.boundaryUmpireGradeMappings = boundaryUmpireGradeMappings
        self.lastStaffSelections = lastStaffSelections
        self.draftResumeOpenLiveFlags = draftResumeOpenLiveFlags
        self.legacyGradesBackup = legacyGradesBackup
        self.legacyContactsBackup = legacyContactsBackup
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appAppearanceRawValue = try c.decodeIfPresent(String.self, forKey: .appAppearanceRawValue) ?? AppAppearance.system.rawValue
        clubConfiguration = try c.decodeIfPresent(ClubConfiguration.self, forKey: .clubConfiguration) ?? ClubConfigurationStore.defaults
        boundaryUmpireGradeMappings = try c.decodeIfPresent([String: [UUID]].self, forKey: .boundaryUmpireGradeMappings) ?? [:]
        lastStaffSelections = try c.decodeIfPresent([String: String].self, forKey: .lastStaffSelections) ?? [:]
        draftResumeOpenLiveFlags = try c.decodeIfPresent([String: Bool].self, forKey: .draftResumeOpenLiveFlags) ?? [:]
        legacyGradesBackup = try c.decodeIfPresent([GradeBackup].self, forKey: .legacyGradesBackup) ?? []
        legacyContactsBackup = try c.decodeIfPresent([ContactBackup].self, forKey: .legacyContactsBackup) ?? []
    }

    static var defaults: AppSettingsRecord {
        AppSettingsRecord(
            appAppearanceRawValue: AppAppearance.system.rawValue,
            clubConfiguration: ClubConfigurationStore.defaults,
            boundaryUmpireGradeMappings: [:],
            lastStaffSelections: [:],
            draftResumeOpenLiveFlags: [:],
            legacyGradesBackup: [],
            legacyContactsBackup: []
        )
    }
}

struct FullBackupExportResult {
    let fileURL: URL
    let itemCounts: AppBackupItemCounts
    let exportedAt: Date
    let fileSizeBytes: UInt64
}

struct FullBackupImportResult {
    let importedAt: Date
    let itemCounts: AppBackupItemCounts
}

enum AppBackupExportError: LocalizedError {
    case failedToReadFileSize

    var errorDescription: String? {
        switch self {
        case .failedToReadFileSize:
            return "Backup was created, but the file size could not be read."
        }
    }
}

enum AppBackupImportError: LocalizedError {
    case invalidFileType
    case unsupportedBackupFormat(version: Int)
    case unsupportedSchema(version: Int)

    var errorDescription: String? {
        switch self {
        case .invalidFileType:
            return "Please select a valid JSON backup file."
        case let .unsupportedBackupFormat(version):
            return "This backup format (\(version)) is not supported by this app version."
        case let .unsupportedSchema(version):
            return "This backup schema (\(version)) is not supported by this app version."
        }
    }
}

enum AppBackupService {
    static let backupFormatVersion = 1

    @MainActor
    static func createFullBackupFile(modelContext: ModelContext) throws -> FullBackupExportResult {
        // Flush pending edits so export reflects what the user currently sees.
        try modelContext.save()

        let grades = try modelContext.fetch(FetchDescriptor<Grade>())
        let players = try modelContext.fetch(FetchDescriptor<Player>())
        let games = try modelContext.fetch(FetchDescriptor<Game>())
        let contacts = try modelContext.fetch(FetchDescriptor<Contact>())
        let reportRecipients = try modelContext.fetch(FetchDescriptor<ReportRecipient>())
        let customReportTemplates = try modelContext.fetch(FetchDescriptor<CustomReportTemplate>())
        let staffMembers = try modelContext.fetch(FetchDescriptor<StaffMember>())
        let staffDefaults = try modelContext.fetch(FetchDescriptor<StaffDefault>())
        let contactGroups = try modelContext.fetch(FetchDescriptor<ContactGroup>())
        let contactGroupMemberships = try modelContext.fetch(FetchDescriptor<ContactGroupMembership>())
        let contactSectionMemberships = try modelContext.fetch(FetchDescriptor<ContactSectionMembership>())
        let reportRecipientGroups = try modelContext.fetch(FetchDescriptor<ReportRecipientGroup>())
        let customReportRecipientSections = try modelContext.fetch(FetchDescriptor<CustomReportRecipientSection>())
        let customReportRecipientGroups = try modelContext.fetch(FetchDescriptor<CustomReportRecipientGroup>())
        let customReportRecipientContacts = try modelContext.fetch(FetchDescriptor<CustomReportRecipientContact>())

        let settings = exportSettings()
        let payload = AppBackupPayload(
            grades: grades.map { GradeRecord($0) },
            players: players.map { PlayerRecord($0) },
            games: games.map { GameRecord($0) },
            contacts: contacts.map { ContactRecord($0) },
            reportRecipients: reportRecipients.map { ReportRecipientRecord($0) },
            customReportTemplates: customReportTemplates.map { CustomReportTemplateRecord($0) },
            staffMembers: staffMembers.map { StaffMemberRecord($0) },
            staffDefaults: staffDefaults.map { StaffDefaultRecord($0) },
            contactGroups: contactGroups.map { ContactGroupRecord($0) },
            contactGroupMemberships: contactGroupMemberships.map { ContactGroupMembershipRecord($0) },
            contactSectionMemberships: contactSectionMemberships.map { ContactSectionMembershipRecord($0) },
            reportRecipientGroups: reportRecipientGroups.map { ReportRecipientGroupRecord($0) },
            customReportRecipientSections: customReportRecipientSections.map { CustomReportRecipientSectionRecord($0) },
            customReportRecipientGroups: customReportRecipientGroups.map { CustomReportRecipientGroupRecord($0) },
            customReportRecipientContacts: customReportRecipientContacts.map { CustomReportRecipientContactRecord($0) },
            appSettings: settings
        )

        let counts = AppBackupItemCounts.fromPayload(payload)

        let now = Date()
        let envelope = AppBackupEnvelope(
            appName: appName,
            backupFormatVersion: backupFormatVersion,
            exportedAt: now,
            appVersion: appVersion,
            buildNumber: buildNumber,
            platform: platformDescription,
            schemaVersion: backupFormatVersion,
            itemCounts: counts,
            payload: payload
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(envelope)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(makeFilename())
        try data.write(to: fileURL, options: Data.WritingOptions.atomic)

        guard let fileSize = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64 else {
            throw AppBackupExportError.failedToReadFileSize
        }

        return FullBackupExportResult(fileURL: fileURL, itemCounts: counts, exportedAt: now, fileSizeBytes: fileSize)
    }

    @MainActor
    static func previewBackupFile(url: URL) throws -> AppBackupEnvelope {
        guard url.pathExtension.lowercased() == "json"
                || UTType(filenameExtension: url.pathExtension)?.conforms(to: .json) == true else {
            throw AppBackupImportError.invalidFileType
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(AppBackupEnvelope.self, from: data)
        try validateEnvelope(envelope)

        // Trust payload as the source of truth and recompute summary counts so
        // import previews/results stay accurate even if serialized metadata is stale.
        let payloadCounts = AppBackupItemCounts.fromPayload(envelope.payload)
        return AppBackupEnvelope(
            appName: envelope.appName,
            backupFormatVersion: envelope.backupFormatVersion,
            exportedAt: envelope.exportedAt,
            appVersion: envelope.appVersion,
            buildNumber: envelope.buildNumber,
            platform: envelope.platform,
            schemaVersion: envelope.schemaVersion,
            itemCounts: payloadCounts,
            payload: envelope.payload
        )
    }

    @MainActor
    static func importFullBackupFile(url: URL, modelContext: ModelContext) throws -> FullBackupImportResult {
        let envelope = try previewBackupFile(url: url)

        clearExistingData(modelContext: modelContext)
        importPayload(envelope.payload, into: modelContext)
        applySettings(envelope.payload.appSettings)
        try modelContext.save()

        return FullBackupImportResult(importedAt: Date(), itemCounts: envelope.itemCounts)
    }

    private static func validateEnvelope(_ envelope: AppBackupEnvelope) throws {
        guard envelope.backupFormatVersion <= backupFormatVersion else {
            throw AppBackupImportError.unsupportedBackupFormat(version: envelope.backupFormatVersion)
        }
        guard envelope.schemaVersion <= backupFormatVersion else {
            throw AppBackupImportError.unsupportedSchema(version: envelope.schemaVersion)
        }
    }

    @MainActor
    private static func clearExistingData(modelContext: ModelContext) {
        let grades = (try? modelContext.fetch(FetchDescriptor<Grade>())) ?? []
        grades.forEach { modelContext.delete($0) }

        let players = (try? modelContext.fetch(FetchDescriptor<Player>())) ?? []
        players.forEach { modelContext.delete($0) }

        let games = (try? modelContext.fetch(FetchDescriptor<Game>())) ?? []
        games.forEach { modelContext.delete($0) }

        let contacts = (try? modelContext.fetch(FetchDescriptor<Contact>())) ?? []
        contacts.forEach { modelContext.delete($0) }

        let recipients = (try? modelContext.fetch(FetchDescriptor<ReportRecipient>())) ?? []
        recipients.forEach { modelContext.delete($0) }

        let templates = (try? modelContext.fetch(FetchDescriptor<CustomReportTemplate>())) ?? []
        templates.forEach { modelContext.delete($0) }

        let staffMembers = (try? modelContext.fetch(FetchDescriptor<StaffMember>())) ?? []
        staffMembers.forEach { modelContext.delete($0) }

        let staffDefaults = (try? modelContext.fetch(FetchDescriptor<StaffDefault>())) ?? []
        staffDefaults.forEach { modelContext.delete($0) }

        let contactGroups = (try? modelContext.fetch(FetchDescriptor<ContactGroup>())) ?? []
        contactGroups.forEach { modelContext.delete($0) }

        let contactGroupMemberships = (try? modelContext.fetch(FetchDescriptor<ContactGroupMembership>())) ?? []
        contactGroupMemberships.forEach { modelContext.delete($0) }

        let contactSectionMemberships = (try? modelContext.fetch(FetchDescriptor<ContactSectionMembership>())) ?? []
        contactSectionMemberships.forEach { modelContext.delete($0) }

        let reportRecipientGroups = (try? modelContext.fetch(FetchDescriptor<ReportRecipientGroup>())) ?? []
        reportRecipientGroups.forEach { modelContext.delete($0) }

        let customReportRecipientSections = (try? modelContext.fetch(FetchDescriptor<CustomReportRecipientSection>())) ?? []
        customReportRecipientSections.forEach { modelContext.delete($0) }

        let customReportRecipientGroups = (try? modelContext.fetch(FetchDescriptor<CustomReportRecipientGroup>())) ?? []
        customReportRecipientGroups.forEach { modelContext.delete($0) }

        let customReportRecipientContacts = (try? modelContext.fetch(FetchDescriptor<CustomReportRecipientContact>())) ?? []
        customReportRecipientContacts.forEach { modelContext.delete($0) }
    }

    @MainActor
    private static func importPayload(_ payload: AppBackupPayload, into modelContext: ModelContext) {
        payload.grades.forEach {
            modelContext.insert(
                Grade(
                    id: $0.id,
                    name: $0.name,
                    isActive: $0.isActive,
                    displayOrder: $0.displayOrder,
                    asksHeadCoach: $0.asksHeadCoach,
                    asksAssistantCoach: $0.asksAssistantCoach,
                    asksTeamManager: $0.asksTeamManager,
                    asksRunner: $0.asksRunner,
                    asksGoalUmpire: $0.asksGoalUmpire,
                    asksFieldUmpire: $0.asksFieldUmpire,
                    asksBoundaryUmpire1: $0.asksBoundaryUmpire1,
                    asksBoundaryUmpire2: $0.asksBoundaryUmpire2,
                    asksTrainers: $0.asksTrainers,
                    asksTrainer1: $0.asksTrainer1,
                    asksTrainer2: $0.asksTrainer2,
                    asksTrainer3: $0.asksTrainer3,
                    asksTrainer4: $0.asksTrainer4,
                    asksNotes: $0.asksNotes,
                    asksScore: $0.asksScore,
                    asksLiveGameView: $0.asksLiveGameView,
                    asksGoalKickers: $0.asksGoalKickers,
                    bestPlayersCount: $0.bestPlayersCount,
                    asksGuestBestFairestVotesScan: $0.asksGuestBestFairestVotesScan,
                    guestBestPlayersCount: $0.guestBestPlayersCount,
                    allowsLiveGameView: $0.allowsLiveGameView,
                    quarterLengthMinutes: $0.quarterLengthMinutes
                )
            )
        }

        payload.players.forEach {
            modelContext.insert(
                Player(
                    id: $0.id,
                    firstName: $0.firstName,
                    lastName: $0.lastName,
                    number: $0.number,
                    gradeIDs: $0.gradeIDs,
                    isActive: $0.isActive
                )
            )
        }

        payload.games.forEach {
            modelContext.insert(
                Game(
                    id: $0.id,
                    gradeID: $0.gradeID,
                    date: $0.date,
                    opponent: $0.opponent,
                    venue: $0.venue,
                    ourGoals: $0.ourGoals,
                    ourBehinds: $0.ourBehinds,
                    theirGoals: $0.theirGoals,
                    theirBehinds: $0.theirBehinds,
                    goalKickers: $0.goalKickers.map {
                        GameGoalKickerEntry(id: $0.id, playerID: $0.playerID, goals: $0.goals)
                    },
                    bestPlayersRanked: $0.bestPlayersRanked,
                    guestVotesRanked: $0.guestVotesRanked,
                    headCoachName: $0.headCoachName,
                    assistantCoachName: $0.assistantCoachName,
                    teamManagerName: $0.teamManagerName,
                    runnerName: $0.runnerName,
                    goalUmpireName: $0.goalUmpireName,
                    fieldUmpireName: $0.fieldUmpireName,
                    boundaryUmpire1Name: $0.boundaryUmpire1Name,
                    boundaryUmpire2Name: $0.boundaryUmpire2Name,
                    trainers: $0.trainers,
                    notes: $0.notes,
                    guestBestFairestVotesScanPDF: $0.guestBestFairestVotesScanPDF,
                    isDraft: $0.isDraft
                )
            )
        }

        payload.contacts.forEach {
            modelContext.insert(Contact(id: $0.id, name: $0.name, mobile: $0.mobile, email: $0.email))
        }

        payload.reportRecipients.forEach {
            modelContext.insert(
                ReportRecipient(
                    id: $0.id,
                    gradeID: $0.gradeID,
                    contactID: $0.contactID,
                    sendEmail: $0.sendEmail,
                    sendText: $0.sendText
                )
            )
        }

        payload.customReportTemplates.forEach {
            modelContext.insert(
                CustomReportTemplate(
                    id: $0.id,
                    name: $0.name,
                    gradeIDs: $0.gradeIDs,
                    includeScores: $0.includeScores,
                    includeBestPlayers: $0.includeBestPlayers,
                    bestPlayersLimit: $0.bestPlayersLimit,
                    includePlayerGrades: $0.includePlayerGrades,
                    guestVotesLimit: $0.guestVotesLimit,
                    includeGoalKickers: $0.includeGoalKickers,
                    goalKickersLimit: $0.goalKickersLimit,
                    includeGuernseyNumbers: $0.includeGuernseyNumbers,
                    includeBestAndFairestVotes: $0.includeBestAndFairestVotes,
                    bestAndFairestLimit: $0.bestAndFairestLimit,
                    includeStaffRoles: $0.includeStaffRoles,
                    includeOfficials: $0.includeOfficials,
                    includeUmpires: $0.includeUmpires,
                    includeTrainers: $0.includeTrainers,
                    includeMatchNotes: $0.includeMatchNotes,
                    includeOnlyActiveGrades: $0.includeOnlyActiveGrades,
                    minimumGamesPlayed: $0.minimumGamesPlayed,
                    groupingModeRawValue: $0.groupingModeRawValue
                )
            )
        }

        payload.staffMembers.forEach { item in
            guard let role = StaffRole(rawValue: item.role) else { return }
            modelContext.insert(StaffMember(id: item.id, name: item.name, role: role, gradeID: item.gradeID))
        }

        payload.staffDefaults.forEach { item in
            guard let role = StaffRole(rawValue: item.role) else { return }
            modelContext.insert(StaffDefault(id: item.id, gradeID: item.gradeID, role: role, name: item.name))
        }

        payload.contactGroups.forEach {
            modelContext.insert(ContactGroup(id: $0.id, name: $0.name))
        }

        payload.contactGroupMemberships.forEach {
            modelContext.insert(ContactGroupMembership(id: $0.id, contactID: $0.contactID, groupID: $0.groupID))
        }

        payload.contactSectionMemberships.forEach {
            modelContext.insert(ContactSectionMembership(id: $0.id, contactID: $0.contactID, sectionKey: $0.sectionKey))
        }

        payload.reportRecipientGroups.forEach {
            modelContext.insert(
                ReportRecipientGroup(
                    id: $0.id,
                    gradeID: $0.gradeID,
                    groupID: $0.groupID,
                    sendEmail: $0.sendEmail,
                    sendText: $0.sendText
                )
            )
        }

        payload.customReportRecipientSections.forEach {
            modelContext.insert(CustomReportRecipientSection(id: $0.id, templateID: $0.templateID, sectionKey: $0.sectionKey))
        }

        payload.customReportRecipientGroups.forEach {
            modelContext.insert(CustomReportRecipientGroup(id: $0.id, templateID: $0.templateID, groupID: $0.groupID))
        }

        payload.customReportRecipientContacts.forEach {
            modelContext.insert(CustomReportRecipientContact(id: $0.id, templateID: $0.templateID, contactID: $0.contactID))
        }
    }

    @MainActor
    private static func applySettings(_ settings: AppSettingsRecord) {
        UserDefaults.standard.set(settings.appAppearanceRawValue, forKey: "appAppearance")
        ClubConfigurationStore.save(settings.clubConfiguration)

        let boundaryMappingPairs: [(UUID, [UUID])] = settings.boundaryUmpireGradeMappings.compactMap { item in
                guard let id = UUID(uuidString: item.key) else { return nil }
                return (id, item.value)
            }
        let boundaryMappings = Dictionary(uniqueKeysWithValues: boundaryMappingPairs)
        SettingsBackupStore.saveBoundaryUmpireGradeMappings(boundaryMappings)

        UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("lastStaffSelection.") || $0.hasPrefix("resume.openLive.") }
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }

        settings.lastStaffSelections.forEach {
            UserDefaults.standard.set($0.value, forKey: $0.key)
        }
        settings.draftResumeOpenLiveFlags.forEach {
            UserDefaults.standard.set($0.value, forKey: $0.key)
        }

        if let gradesData = try? JSONEncoder().encode(settings.legacyGradesBackup) {
            UserDefaults.standard.set(gradesData, forKey: SettingsBackupStore.gradesKey)
        }
        if let contactsData = try? JSONEncoder().encode(settings.legacyContactsBackup) {
            UserDefaults.standard.set(contactsData, forKey: SettingsBackupStore.contactsKey)
        }
    }

    private static func exportSettings() -> AppSettingsRecord {
        let defaults = UserDefaults.standard
        let allDefaults = defaults.dictionaryRepresentation()

        let lastStaffSelections = allDefaults
            .compactMapValues { $0 as? String }
            .filter { $0.key.hasPrefix("lastStaffSelection.") }

        let draftResumeFlags = allDefaults
            .compactMapValues { $0 as? Bool }
            .filter { $0.key.hasPrefix("resume.openLive.") }

        let rawMappings = SettingsBackupStore.loadBoundaryUmpireGradeMappings()
        let serializedMappings = Dictionary(
            uniqueKeysWithValues: rawMappings.map { ($0.key.uuidString, $0.value) }
        )

        return AppSettingsRecord(
            appAppearanceRawValue: defaults.string(forKey: "appAppearance") ?? AppAppearance.system.rawValue,
            clubConfiguration: ClubConfigurationStore.load(),
            boundaryUmpireGradeMappings: serializedMappings,
            lastStaffSelections: lastStaffSelections,
            draftResumeOpenLiveFlags: draftResumeFlags,
            legacyGradesBackup: SettingsBackupStore.loadGrades(),
            legacyContactsBackup: SettingsBackupStore.loadContacts()
        )
    }

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "ClubResults"
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    @MainActor
    private static var platformDescription: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    private static func makeFilename() -> String {
        "\(safeFileName(appName))-FullBackup.json"
    }

    private static func safeFileName(_ input: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return input
            .components(separatedBy: bad)
            .joined(separator: "-")
            .replacingOccurrences(of: " ", with: "")
    }
}
