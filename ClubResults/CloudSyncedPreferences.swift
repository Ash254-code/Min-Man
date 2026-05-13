import Foundation
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
        contactsBackup
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
        UserDefaults.standard.set(synced, forKey: key)
    }

    private static func migrateLocalDataToCloudIfNeeded(forKey key: String) {
        guard syncedData(forKey: key) == nil,
              let localData = UserDefaults.standard.data(forKey: key) else { return }
        persist(localData, forKey: key)
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
