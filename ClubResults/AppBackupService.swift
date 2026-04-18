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
    let lastStaffSelections: Int
    let draftResumeFlags: Int
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
    let appSettings: AppSettingsRecord
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
    let allowsLiveGameView: Bool
    let quarterLengthMinutes: Int

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
        allowsLiveGameView = grade.allowsLiveGameView
        quarterLengthMinutes = grade.quarterLengthMinutes
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
        goalKickers = game.goalKickers.map(GameGoalKickerRecord.init)
        bestPlayersRanked = game.bestPlayersRanked
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
    let includeBestPlayers: Bool
    let includePlayerGrades: Bool
    let includeGoalKickers: Bool
    let includeGuernseyNumbers: Bool
    let includeBestAndFairestVotes: Bool
    let includeStaffRoles: Bool
    let includeTrainers: Bool
    let includeMatchNotes: Bool
    let includeOnlyActiveGrades: Bool
    let minimumGamesPlayed: Int
    let groupingModeRawValue: Int

    init(_ template: CustomReportTemplate) {
        id = template.id
        name = template.name
        gradeIDs = template.gradeIDs
        includeBestPlayers = template.includeBestPlayers
        includePlayerGrades = template.includePlayerGrades
        includeGoalKickers = template.includeGoalKickers
        includeGuernseyNumbers = template.includeGuernseyNumbers
        includeBestAndFairestVotes = template.includeBestAndFairestVotes
        includeStaffRoles = template.includeStaffRoles
        includeTrainers = template.includeTrainers
        includeMatchNotes = template.includeMatchNotes
        includeOnlyActiveGrades = template.includeOnlyActiveGrades
        minimumGamesPlayed = template.minimumGamesPlayed
        groupingModeRawValue = template.groupingModeRawValue
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

struct AppSettingsRecord: Codable {
    let appAppearanceRawValue: String
    let clubConfiguration: ClubConfiguration
    let boundaryUmpireGradeMappings: [String: [UUID]]
    let lastStaffSelections: [String: String]
    let draftResumeOpenLiveFlags: [String: Bool]
    let legacyGradesBackup: [GradeBackup]
    let legacyContactsBackup: [ContactBackup]
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

    static func createFullBackupFile(modelContext: ModelContext) throws -> FullBackupExportResult {
        let grades = try modelContext.fetch(FetchDescriptor<Grade>())
        let players = try modelContext.fetch(FetchDescriptor<Player>())
        let games = try modelContext.fetch(FetchDescriptor<Game>())
        let contacts = try modelContext.fetch(FetchDescriptor<Contact>())
        let reportRecipients = try modelContext.fetch(FetchDescriptor<ReportRecipient>())
        let customReportTemplates = try modelContext.fetch(FetchDescriptor<CustomReportTemplate>())
        let staffMembers = try modelContext.fetch(FetchDescriptor<StaffMember>())
        let staffDefaults = try modelContext.fetch(FetchDescriptor<StaffDefault>())

        let settings = exportSettings()
        let payload = AppBackupPayload(
            grades: grades.map(GradeRecord.init),
            players: players.map(PlayerRecord.init),
            games: games.map(GameRecord.init),
            contacts: contacts.map(ContactRecord.init),
            reportRecipients: reportRecipients.map(ReportRecipientRecord.init),
            customReportTemplates: customReportTemplates.map(CustomReportTemplateRecord.init),
            staffMembers: staffMembers.map(StaffMemberRecord.init),
            staffDefaults: staffDefaults.map(StaffDefaultRecord.init),
            appSettings: settings
        )

        let counts = AppBackupItemCounts(
            grades: payload.grades.count,
            players: payload.players.count,
            games: payload.games.count,
            contacts: payload.contacts.count,
            reportRecipients: payload.reportRecipients.count,
            customReportTemplates: payload.customReportTemplates.count,
            staffMembers: payload.staffMembers.count,
            staffDefaults: payload.staffDefaults.count,
            lastStaffSelections: payload.appSettings.lastStaffSelections.count,
            draftResumeFlags: payload.appSettings.draftResumeOpenLiveFlags.count
        )

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
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(makeFilename(exportedAt: now))
        try data.write(to: fileURL, options: .atomic)

        guard let fileSize = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64 else {
            throw AppBackupExportError.failedToReadFileSize
        }

        return FullBackupExportResult(fileURL: fileURL, itemCounts: counts, exportedAt: now, fileSizeBytes: fileSize)
    }

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
        return envelope
    }

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
    }

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
                    includeBestPlayers: $0.includeBestPlayers,
                    includePlayerGrades: $0.includePlayerGrades,
                    includeGoalKickers: $0.includeGoalKickers,
                    includeGuernseyNumbers: $0.includeGuernseyNumbers,
                    includeBestAndFairestVotes: $0.includeBestAndFairestVotes,
                    includeStaffRoles: $0.includeStaffRoles,
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
    }

    private static func applySettings(_ settings: AppSettingsRecord) {
        UserDefaults.standard.set(settings.appAppearanceRawValue, forKey: "appAppearance")
        ClubConfigurationStore.save(settings.clubConfiguration)

        let boundaryMappings = Dictionary(
            uniqueKeysWithValues: settings.boundaryUmpireGradeMappings.compactMap { key, value in
                guard let id = UUID(uuidString: key) else { return nil }
                return (id, value)
            }
        )
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

    private static var platformDescription: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    private static func makeFilename(exportedAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"

        let stamp = formatter.string(from: exportedAt)
        return "\(safeFileName(appName))-FullBackup-\(stamp).json"
    }

    private static func safeFileName(_ input: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return input
            .components(separatedBy: bad)
            .joined(separator: "-")
            .replacingOccurrences(of: " ", with: "")
    }
}
