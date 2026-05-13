import Foundation
import CloudKit
import SwiftData

@Model
final class CloudSyncedPreference {
    @Attribute(.unique) var key: String
    var data: Data
    var updatedAt: Date

    init(key: String, data: Data, updatedAt: Date = Date()) {
        self.key = key
        self.data = data
        self.updatedAt = updatedAt
    }
}

enum CloudSyncedPreferenceKeys {
    static let clubConfiguration = "settings.clubConfiguration.v1"
    static let boundaryUmpireMappings = "settings.boundaryUmpires.gradeMappings.v1"
    static let gradesBackup = "settings.backup.grades.v1"
    static let contactsBackup = "settings.backup.contacts.v1"
    static let fullBackup = "settings.fullBackup.v1"
    static let deletedPlayerIDs = "cloud.deletedPlayerIDs.v1"

    static let appAppearance = "appAppearance"
    static let reportsTemplateOrder = "reports.templateOrder.v1"
    static let speechSetupCustomSections = "speech_setup_custom_sections"
    static let speechSetupDetectedWords = "speech_setup_detected_words"
    static let contactSectionCustomTitles = "contactSectionCustomTitles"
    static let contactSectionCustomGroups = "contactSectionCustomGroups"
    static let contactSectionHiddenGroups = "contactSectionHiddenGroups"
    static let statsLayout = "statsLayout"
    static let statsInvitePreviewGradeID = "statsInvitePreviewGradeID"
    static let statsInvitePreviewOpponentName = "statsInvitePreviewOpponentName"
    static let appTestFlightURL = "app.testFlightURL"

    static let trackDisposalEfficiency = "trackDisposalEfficiency"
    static let trackContestedPossessions = "trackContestedPossessions"
    static let trackIndividualTracking = "trackIndividualTracking"
    static let oppTrackPossessions = "oppTrackPossessions"
    static let oppTrackDisposalEfficiency = "oppTrackDisposalEfficiency"
    static let oppTrackContestedPossessions = "oppTrackContestedPossessions"

    static let dataKeys: [String] = [
        clubConfiguration,
        boundaryUmpireMappings,
        gradesBackup,
        contactsBackup,
        deletedPlayerIDs
    ]

    static let stringKeys: [String] = [
        appAppearance,
        reportsTemplateOrder,
        speechSetupCustomSections,
        speechSetupDetectedWords,
        contactSectionCustomTitles,
        contactSectionCustomGroups,
        contactSectionHiddenGroups,
        statsLayout,
        statsInvitePreviewGradeID,
        statsInvitePreviewOpponentName,
        appTestFlightURL
    ]

    static let boolKeys: [String] = [
        trackDisposalEfficiency,
        trackContestedPossessions,
        trackIndividualTracking,
        oppTrackPossessions,
        oppTrackDisposalEfficiency,
        oppTrackContestedPossessions
    ]
}

struct CloudSyncedPreferencesDiagnostics {
    let dataKeysInCloud: Int
    let stringKeysInCloud: Int
    let boolKeysInCloud: Int
    let hasFullBackupInCloud: Bool

    var totalKeysInCloud: Int {
        dataKeysInCloud + stringKeysInCloud + boolKeysInCloud + (hasFullBackupInCloud ? 1 : 0)
    }
}

enum CloudDeletedRecordStore {
    private static let deletedPlayerIDsKey = CloudSyncedPreferenceKeys.deletedPlayerIDs

    static func recordDeletedPlayerID(_ id: UUID) {
        var ids = deletedPlayerIDs()
        ids.insert(id)
        persistDeletedPlayerIDs(ids)
    }

    static func deletedPlayerIDs() -> Set<UUID> {
        if let data = UserDefaults.standard.data(forKey: deletedPlayerIDsKey),
           let storedIDs = try? JSONDecoder().decode([String].self, from: data) {
            return Set(storedIDs.compactMap(UUID.init(uuidString:)))
        }

        let legacyStoredIDs = UserDefaults.standard.stringArray(forKey: deletedPlayerIDsKey) ?? []
        let ids = Set(legacyStoredIDs.compactMap(UUID.init(uuidString:)))
        if !ids.isEmpty {
            persistDeletedPlayerIDs(ids)
        }
        return ids
    }

    private static func persistDeletedPlayerIDs(_ ids: Set<UUID>) {
        let storedIDs = ids
            .map(\.uuidString)
            .sorted()
        guard let data = try? JSONEncoder().encode(storedIDs) else { return }
        UserDefaults.standard.set(data, forKey: deletedPlayerIDsKey)
    }
}

@MainActor
enum CloudSyncedPreferencesStore {
    private static var configuredContext: ModelContext?

    static func configure(modelContext: ModelContext) {
        configuredContext = modelContext

        for key in CloudSyncedPreferenceKeys.dataKeys {
            syncDataFromCloudToLocalIfAvailable(forKey: key)
            migrateLocalDataToCloudIfNeeded(forKey: key)
        }

        for key in CloudSyncedPreferenceKeys.stringKeys {
            syncStringFromCloudToLocalIfAvailable(forKey: key)
            migrateLocalStringToCloudIfNeeded(forKey: key)
        }

        for key in CloudSyncedPreferenceKeys.boolKeys {
            syncBoolFromCloudToLocalIfAvailable(forKey: key)
            migrateLocalBoolToCloudIfNeeded(forKey: key)
        }
    }

    static func syncedData(forKey key: String) -> Data? {
        rawRecordData(forKey: key)
    }

    static func persist(_ data: Data, forKey key: String) {
        upsert(data, forKey: key)
    }

    static func fullBackupData() -> Data? {
        rawRecordData(forKey: CloudSyncedPreferenceKeys.fullBackup)
    }

    static func persistFullBackupData(_ data: Data) {
        upsert(data, forKey: CloudSyncedPreferenceKeys.fullBackup)
    }

    static func pushAllLocalPreferencesToCloud() {
        for key in CloudSyncedPreferenceKeys.dataKeys {
            guard let localData = UserDefaults.standard.data(forKey: key) else { continue }
            persist(localData, forKey: key)
        }

        for key in CloudSyncedPreferenceKeys.stringKeys {
            guard let localValue = UserDefaults.standard.string(forKey: key) else { continue }
            persistString(localValue, forKey: key)
        }

        for key in CloudSyncedPreferenceKeys.boolKeys {
            guard UserDefaults.standard.object(forKey: key) != nil else { continue }
            persistBool(UserDefaults.standard.bool(forKey: key), forKey: key)
        }
    }

    static func diagnostics() -> CloudSyncedPreferencesDiagnostics {
        let dataCount = CloudSyncedPreferenceKeys.dataKeys.filter { rawRecordData(forKey: $0) != nil }.count
        let stringCount = CloudSyncedPreferenceKeys.stringKeys.filter { rawRecordData(forKey: $0) != nil }.count
        let boolCount = CloudSyncedPreferenceKeys.boolKeys.filter { rawRecordData(forKey: $0) != nil }.count
        return CloudSyncedPreferencesDiagnostics(
            dataKeysInCloud: dataCount,
            stringKeysInCloud: stringCount,
            boolKeysInCloud: boolCount,
            hasFullBackupInCloud: rawRecordData(forKey: CloudSyncedPreferenceKeys.fullBackup) != nil
        )
    }

    private static func syncedString(forKey key: String) -> String? {
        guard let data = rawRecordData(forKey: key),
              let value = try? JSONDecoder().decode(String.self, from: data) else {
            return nil
        }
        return value
    }

    private static func persistString(_ value: String, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        upsert(data, forKey: key)
    }

    private static func syncedBool(forKey key: String) -> Bool? {
        guard let data = rawRecordData(forKey: key),
              let value = try? JSONDecoder().decode(Bool.self, from: data) else {
            return nil
        }
        return value
    }

    private static func persistBool(_ value: Bool, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        upsert(data, forKey: key)
    }

    private static func rawRecordData(forKey key: String) -> Data? {
        guard let configuredContext else { return nil }
        let descriptor = FetchDescriptor<CloudSyncedPreference>(
            predicate: #Predicate { $0.key == key }
        )
        return try? configuredContext.fetch(descriptor).first?.data
    }

    private static func upsert(_ data: Data, forKey key: String) {
        guard let configuredContext else { return }
        let descriptor = FetchDescriptor<CloudSyncedPreference>(
            predicate: #Predicate { $0.key == key }
        )
        let existing = try? configuredContext.fetch(descriptor).first
        if let existing {
            existing.data = data
            existing.updatedAt = Date()
        } else {
            configuredContext.insert(CloudSyncedPreference(key: key, data: data))
        }
        try? configuredContext.save()
    }

    private static func syncDataFromCloudToLocalIfAvailable(forKey key: String) {
        guard let synced = syncedData(forKey: key) else { return }

        if key == CloudSyncedPreferenceKeys.deletedPlayerIDs {
            let localIDs = CloudDeletedRecordStore.deletedPlayerIDs()
            let syncedIDs = deletedPlayerIDs(from: synced)
            let mergedIDs = localIDs.union(syncedIDs)
            guard let mergedData = deletedPlayerIDsData(from: mergedIDs) else { return }
            UserDefaults.standard.set(mergedData, forKey: key)
            if mergedIDs != syncedIDs {
                upsert(mergedData, forKey: key)
            }
            return
        }

        UserDefaults.standard.set(synced, forKey: key)
    }

    private static func migrateLocalDataToCloudIfNeeded(forKey key: String) {
        guard syncedData(forKey: key) == nil,
              let localData = UserDefaults.standard.data(forKey: key) else { return }
        persist(localData, forKey: key)
    }

    private static func deletedPlayerIDs(from data: Data) -> Set<UUID> {
        guard let storedIDs = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(storedIDs.compactMap(UUID.init(uuidString:)))
    }

    private static func deletedPlayerIDsData(from ids: Set<UUID>) -> Data? {
        let storedIDs = ids
            .map(\.uuidString)
            .sorted()
        return try? JSONEncoder().encode(storedIDs)
    }

    private static func syncStringFromCloudToLocalIfAvailable(forKey key: String) {
        guard let synced = syncedString(forKey: key) else { return }
        UserDefaults.standard.set(synced, forKey: key)
    }

    private static func migrateLocalStringToCloudIfNeeded(forKey key: String) {
        guard syncedString(forKey: key) == nil,
              let localValue = UserDefaults.standard.string(forKey: key) else { return }
        persistString(localValue, forKey: key)
    }

    private static func syncBoolFromCloudToLocalIfAvailable(forKey key: String) {
        guard let synced = syncedBool(forKey: key) else { return }
        UserDefaults.standard.set(synced, forKey: key)
    }

    private static func migrateLocalBoolToCloudIfNeeded(forKey key: String) {
        guard syncedBool(forKey: key) == nil,
              UserDefaults.standard.object(forKey: key) != nil else { return }
        persistBool(UserDefaults.standard.bool(forKey: key), forKey: key)
    }
}

@MainActor
enum CloudFullBackupSyncService {
    enum SyncAction {
        case restored
        case uploaded
        case unchanged
        case noCloudBackup
    }

    struct FullBackupSyncResult {
        let action: SyncAction
        let itemCounts: AppBackupItemCounts?
    }

    private static let lastSyncedFingerprintKey = "cloud.fullBackup.lastSyncedFingerprint.v1"

    static func pullFullBackupIfLocalUserDataIsEmpty(modelContext: ModelContext) async throws -> FullBackupImportResult? {
        guard localUserDataCount(modelContext: modelContext) == 0,
              let data = try await latestFullBackupData() else {
            return nil
        }
        let result = try AppBackupService.importFullBackupData(data, modelContext: modelContext)
        try removeLocallyDeletedPlayers(from: modelContext)
        return result
    }

    static func syncFullBackupSnapshot(modelContext: ModelContext) async throws -> FullBackupSyncResult {
        try modelContext.save()
        try removeLocallyDeletedPlayers(from: modelContext)

        let localUserDataCount = localUserDataCount(modelContext: modelContext)
        let localFingerprint = try AppBackupService.createFullBackupFingerprint(modelContext: modelContext)
        let lastSyncedFingerprint = UserDefaults.standard.string(forKey: lastSyncedFingerprintKey)
        let cloudData = try await latestFullBackupData()
        let cloudEnvelope = try cloudData.map { try AppBackupService.decodeBackupData($0) }
        let cloudFingerprint = try cloudData.map { try AppBackupService.fingerprint(forBackupData: $0) }

        if localUserDataCount == 0 {
            guard let cloudData else {
                return FullBackupSyncResult(action: .noCloudBackup, itemCounts: nil)
            }

            let result = try AppBackupService.importFullBackupData(cloudData, modelContext: modelContext)
            try removeLocallyDeletedPlayers(from: modelContext)
            let backup = try await pushFullBackupSnapshot(modelContext: modelContext)
            let pushedFingerprint = try AppBackupService.fingerprint(forBackupData: backup.data)
            UserDefaults.standard.set(pushedFingerprint, forKey: lastSyncedFingerprintKey)
            return FullBackupSyncResult(action: .restored, itemCounts: result.itemCounts)
        }

        if let lastSyncedFingerprint, localFingerprint == lastSyncedFingerprint {
            guard let cloudData, let cloudFingerprint, cloudFingerprint != lastSyncedFingerprint else {
                return FullBackupSyncResult(action: .unchanged, itemCounts: cloudEnvelope?.itemCounts)
            }

            let result = try AppBackupService.importFullBackupData(cloudData, modelContext: modelContext)
            try removeLocallyDeletedPlayers(from: modelContext)
            let backup = try await pushFullBackupSnapshot(modelContext: modelContext)
            let pushedFingerprint = try AppBackupService.fingerprint(forBackupData: backup.data)
            UserDefaults.standard.set(pushedFingerprint, forKey: lastSyncedFingerprintKey)
            return FullBackupSyncResult(action: .restored, itemCounts: result.itemCounts)
        }

        let backup = try await pushFullBackupSnapshot(modelContext: modelContext)
        let pushedFingerprint = try AppBackupService.fingerprint(forBackupData: backup.data)
        UserDefaults.standard.set(pushedFingerprint, forKey: lastSyncedFingerprintKey)
        return FullBackupSyncResult(action: .uploaded, itemCounts: backup.itemCounts)
    }

    static func pushFullBackupSnapshot(modelContext: ModelContext) async throws -> FullBackupDataResult {
        let backup = try AppBackupService.createFullBackupData(modelContext: modelContext)
        CloudSyncedPreferencesStore.persistFullBackupData(backup.data)
        try await DirectCloudFullBackupStore.saveFullBackupData(backup.data)
        try modelContext.save()
        return backup
    }

    static func localUserDataCount(modelContext: ModelContext) -> Int {
        let players = (try? modelContext.fetch(FetchDescriptor<Player>()))?.count ?? 0
        let games = (try? modelContext.fetch(FetchDescriptor<Game>()))?.count ?? 0
        let contacts = (try? modelContext.fetch(FetchDescriptor<Contact>()))?.count ?? 0
        let reportRecipients = (try? modelContext.fetch(FetchDescriptor<ReportRecipient>()))?.count ?? 0
        let reportRecipientGroups = (try? modelContext.fetch(FetchDescriptor<ReportRecipientGroup>()))?.count ?? 0
        let customReportTemplates = (try? modelContext.fetch(FetchDescriptor<CustomReportTemplate>()))?.count ?? 0
        let staffMembers = (try? modelContext.fetch(FetchDescriptor<StaffMember>()))?.count ?? 0
        let staffDefaults = (try? modelContext.fetch(FetchDescriptor<StaffDefault>()))?.count ?? 0
        let contactGroups = (try? modelContext.fetch(FetchDescriptor<ContactGroup>()))?.count ?? 0
        let statsSessions = (try? modelContext.fetch(FetchDescriptor<StatsSession>()))?.count ?? 0
        let statEvents = (try? modelContext.fetch(FetchDescriptor<StatEvent>()))?.count ?? 0

        return players + games + contacts + reportRecipients + reportRecipientGroups + customReportTemplates + staffMembers + staffDefaults + contactGroups + statsSessions + statEvents
    }

    private static func latestFullBackupData() async throws -> Data? {
        if let directCloudData = try await DirectCloudFullBackupStore.fetchFullBackupData() {
            CloudSyncedPreferencesStore.persistFullBackupData(directCloudData)
            return directCloudData
        }

        return CloudSyncedPreferencesStore.fullBackupData()
    }

    @discardableResult
    private static func removeLocallyDeletedPlayers(from modelContext: ModelContext) throws -> Int {
        let deletedPlayerIDs = CloudDeletedRecordStore.deletedPlayerIDs()
        guard !deletedPlayerIDs.isEmpty else { return 0 }

        let players = try modelContext.fetch(FetchDescriptor<Player>())
        var removedCount = 0
        for player in players where deletedPlayerIDs.contains(player.id) {
            modelContext.delete(player)
            removedCount += 1
        }

        if removedCount > 0 {
            try modelContext.save()
        }
        return removedCount
    }
}

enum DirectCloudFullBackupStore {
    private static let containerIdentifier = "iCloud.MINMAN.ClubResults"
    private static let recordType = "AppFullBackupSnapshot"
    private static let recordName = "settings-full-backup-v1"
    private static let backupAssetField = "backupAsset"
    private static let updatedAtField = "updatedAt"
    private static let byteCountField = "byteCount"

    private static var database: CKDatabase {
        CKContainer(identifier: containerIdentifier).privateCloudDatabase
    }

    static func fetchFullBackupData() async throws -> Data? {
        let recordID = CKRecord.ID(recordName: recordName)
        let record = try await fetch(recordID: recordID)
        guard let asset = record?[backupAssetField] as? CKAsset,
              let fileURL = asset.fileURL else {
            return nil
        }

        return try Data(contentsOf: fileURL)
    }

    static func saveFullBackupData(_ data: Data) async throws {
        let recordID = CKRecord.ID(recordName: recordName)
        let record = try await fetch(recordID: recordID) ?? CKRecord(recordType: recordType, recordID: recordID)
        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: "ClubResultsFullBackup-\(UUID().uuidString).json")

        try data.write(to: temporaryURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        record[backupAssetField] = CKAsset(fileURL: temporaryURL)
        record[updatedAtField] = Date() as CKRecordValue
        record[byteCountField] = data.count as CKRecordValue

        _ = try await save(record)
    }

    private static func fetch(recordID: CKRecord.ID) async throws -> CKRecord? {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withRecordID: recordID) { record, error in
                if let ckError = error as? CKError, ckError.code == .unknownItem {
                    continuation.resume(returning: nil)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: record)
            }
        }
    }

    private static func save(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.save(record) { savedRecord, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let savedRecord else {
                    continuation.resume(throwing: CKError(.internalError))
                    return
                }

                continuation.resume(returning: savedRecord)
            }
        }
    }
}
