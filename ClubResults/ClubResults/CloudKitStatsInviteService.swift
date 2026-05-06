import Foundation
import CloudKit

extension Notification.Name {
    static let statsTalliesDidChange = Notification.Name("statsTalliesDidChange")
    static let statsPlayerEventsDidChange = Notification.Name("statsPlayerEventsDidChange")
    static let statsSessionStateDidChange = Notification.Name("statsSessionStateDidChange")
}

private enum StatsTallyNotificationKeys {
    static let sessionID = "sessionID"
    static let statTypeID = "statTypeID"
    static let sideRawValue = "sideRawValue"
    static let count = "count"
    static let updatedAt = "updatedAt"
}

private enum StatsPlayerEventNotificationKeys {
    static let isDeleted = "isDeleted"
    static let recordName = "recordName"
    static let sessionID = "sessionID"
    static let eventID = "eventID"
    static let statTypeID = "statTypeID"
    static let sideRawValue = "sideRawValue"
    static let playerID = "playerID"
    static let quarter = "quarter"
    static let timestamp = "timestamp"
    static let updatedAt = "updatedAt"
}

private enum StatsSessionStateNotificationKeys {
    static let sessionID = "sessionID"
    static let currentQuarter = "currentQuarter"
    static let remainingSeconds = "remainingSeconds"
    static let isTimerRunning = "isTimerRunning"
    static let ourPoints = "ourPoints"
    static let theirPoints = "theirPoints"
    static let availablePlayerPayloadJSON = "availablePlayerPayloadJSON"
    static let updatedAt = "updatedAt"
}

struct CloudStatsInviteAssignment: Identifiable, Hashable {
    let id: String
    let inviteeEmail: String
    let inviteeName: String
    let sessionID: UUID
    let gradeName: String
    let oppositionName: String
    let venue: String
    let sessionDate: Date
    let assignedSelectionRawValues: [String]
    let assignedSelectionDisplayNames: [String]
    let assignedSelectionCollectionModes: [String]
    let availablePlayerPayloadJSON: String
    let lastInvitedAt: Date
    let lastConnectedAt: Date?

    var hasConnected: Bool {
        lastConnectedAt != nil
    }

    var assignedSelectionDisplayNameByRawValue: [String: String] {
        Dictionary(
            uniqueKeysWithValues: zip(assignedSelectionRawValues, assignedSelectionDisplayNames).map { ($0, $1) }
        )
    }

    var assignedSelectionCollectionModeByRawValue: [String: String] {
        Dictionary(
            uniqueKeysWithValues: zip(assignedSelectionRawValues, assignedSelectionCollectionModes).map { ($0, $1) }
        )
    }

    var availablePlayers: [CloudStatsInviteRosterPlayer] {
        guard let data = availablePlayerPayloadJSON.data(using: .utf8),
              let players = try? JSONDecoder().decode([CloudStatsInviteRosterPlayer].self, from: data) else {
            return []
        }
        return players
    }
}

struct CloudStatsInviteTally: Identifiable, Hashable {
    let id: String
    let sessionID: UUID
    let statTypeID: UUID
    let sideRawValue: String
    let count: Int
    let updatedAt: Date
}

struct CloudStatsInvitePlayerEvent: Identifiable, Hashable {
    let id: String
    let eventID: UUID
    let sessionID: UUID
    let statTypeID: UUID
    let sideRawValue: String
    let playerID: UUID
    let quarter: String
    let timestamp: Date
    let updatedAt: Date
}

struct CloudStatsInviteRosterPlayer: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let number: Int?
}

func encodeRosterPlayers(_ players: [CloudStatsInviteRosterPlayer]) -> String {
    guard let data = try? JSONEncoder().encode(players),
          let json = String(data: data, encoding: .utf8) else {
        return "[]"
    }
    return json
}

func decodeRosterPlayers(from json: String) -> [CloudStatsInviteRosterPlayer] {
    guard let data = json.data(using: .utf8),
          let players = try? JSONDecoder().decode([CloudStatsInviteRosterPlayer].self, from: data) else {
        return []
    }
    return players
}

struct CloudStatsInviteSessionState: Identifiable, Hashable {
    let id: String
    let sessionID: UUID
    let currentQuarter: String
    let remainingSeconds: Int
    let isTimerRunning: Bool
    let ourPoints: Int
    let theirPoints: Int
    let availablePlayerPayloadJSON: String
    let updatedAt: Date

    var availablePlayers: [CloudStatsInviteRosterPlayer] {
        guard let data = availablePlayerPayloadJSON.data(using: .utf8),
              let players = try? JSONDecoder().decode([CloudStatsInviteRosterPlayer].self, from: data) else {
            return []
        }
        return players
    }
}

struct CloudStatsInviteSessionRoster: Identifiable, Hashable {
    let id: String
    let sessionID: UUID
    let players: [CloudStatsInviteRosterPlayer]
    let updatedAt: Date
}

actor CloudKitStatsInviteService {
    private enum SubscriptionKeys {
        static let statsTallyChanges = "stats-tally-changes"
        static let statsPlayerEventChanges = "stats-player-event-changes"
        static let statsSessionStateChanges = "stats-session-state-changes"
    }

    private enum FieldKeys {
        static let inviteeEmail = "inviteeEmail"
        static let inviteeName = "inviteeName"
        static let sessionID = "sessionID"
        static let gradeName = "gradeName"
        static let oppositionName = "oppositionName"
        static let venue = "venue"
        static let sessionDate = "sessionDate"
        static let assignedSelectionRawValues = "assignedSelectionRawValues"
        static let assignedSelectionDisplayNames = "assignedSelectionDisplayNames"
        static let assignedSelectionCollectionModes = "assignedSelectionCollectionModes"
        static let availablePlayerPayloadJSON = "availablePlayerPayloadJSON"
        static let lastInvitedAt = "lastInvitedAt"
        static let lastConnectedAt = "lastConnectedAt"
        static let eventID = "eventID"
        static let statTypeID = "statTypeID"
        static let sideRawValue = "sideRawValue"
        static let playerID = "playerID"
        static let quarter = "quarter"
        static let timestamp = "timestamp"
        static let count = "count"
        static let updatedAt = "updatedAt"
        static let currentQuarter = "currentQuarter"
        static let remainingSeconds = "remainingSeconds"
        static let isTimerRunning = "isTimerRunning"
        static let ourPoints = "ourPoints"
        static let theirPoints = "theirPoints"
    }

    static let shared = CloudKitStatsInviteService()

    private let container = CKContainer(identifier: "iCloud.MINMAN.ClubResults")

    private var database: CKDatabase {
        container.publicCloudDatabase
    }

    nonisolated static func recordName(sessionID: UUID, inviteeEmail: String) -> String {
        let normalizedEmail = inviteeEmail
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let safeEmail = normalizedEmail.map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "-"
        }
        return "stats-assignment-\(sessionID.uuidString.lowercased())-\(String(safeEmail))"
    }

    nonisolated static func tallyRecordName(sessionID: UUID, statTypeID: UUID, sideRawValue: String) -> String {
        "stats-tally-\(sessionID.uuidString.lowercased())-\(statTypeID.uuidString.lowercased())-\(sideRawValue)"
    }

    nonisolated static func sessionStateRecordName(sessionID: UUID) -> String {
        "stats-session-state-\(sessionID.uuidString.lowercased())"
    }

    nonisolated static func sessionRosterRecordName(sessionID: UUID) -> String {
        "stats-session-roster-\(sessionID.uuidString.lowercased())"
    }

    nonisolated static func playerEventRecordName(eventID: UUID) -> String {
        "stats-player-event-\(eventID.uuidString.lowercased())"
    }

    nonisolated static func tally(from notification: Notification) -> CloudStatsInviteTally? {
        guard
            let userInfo = notification.userInfo,
            let sessionIDRaw = userInfo["sessionID"] as? String,
            let sessionID = UUID(uuidString: sessionIDRaw),
            let statTypeIDRaw = userInfo["statTypeID"] as? String,
            let statTypeID = UUID(uuidString: statTypeIDRaw),
            let sideRawValue = userInfo["sideRawValue"] as? String,
            let count = userInfo["count"] as? Int,
            let updatedAt = userInfo["updatedAt"] as? Date
        else {
            return nil
        }

        return CloudStatsInviteTally(
            id: Self.tallyRecordName(sessionID: sessionID, statTypeID: statTypeID, sideRawValue: sideRawValue),
            sessionID: sessionID,
            statTypeID: statTypeID,
            sideRawValue: sideRawValue,
            count: count,
            updatedAt: updatedAt
        )
    }

    nonisolated static func playerEvent(from notification: Notification) -> CloudStatsInvitePlayerEvent? {
        guard
            let userInfo = notification.userInfo,
            (userInfo["isDeleted"] as? Bool) != true,
            let recordName = userInfo["recordName"] as? String,
            let eventIDRaw = userInfo["eventID"] as? String,
            let eventID = UUID(uuidString: eventIDRaw),
            let sessionIDRaw = userInfo["sessionID"] as? String,
            let sessionID = UUID(uuidString: sessionIDRaw),
            let statTypeIDRaw = userInfo["statTypeID"] as? String,
            let statTypeID = UUID(uuidString: statTypeIDRaw),
            let sideRawValue = userInfo["sideRawValue"] as? String,
            let playerIDRaw = userInfo["playerID"] as? String,
            let playerID = UUID(uuidString: playerIDRaw),
            let quarter = userInfo["quarter"] as? String,
            let timestamp = userInfo["timestamp"] as? Date,
            let updatedAt = userInfo["updatedAt"] as? Date
        else {
            return nil
        }

        return CloudStatsInvitePlayerEvent(
            id: recordName,
            eventID: eventID,
            sessionID: sessionID,
            statTypeID: statTypeID,
            sideRawValue: sideRawValue,
            playerID: playerID,
            quarter: quarter,
            timestamp: timestamp,
            updatedAt: updatedAt
        )
    }

    nonisolated static func playerEventWasDeleted(from notification: Notification) -> Bool {
        (notification.userInfo?["isDeleted"] as? Bool) == true
    }

    nonisolated static func sessionState(from notification: Notification) -> CloudStatsInviteSessionState? {
        guard
            let userInfo = notification.userInfo,
            let sessionIDRaw = userInfo["sessionID"] as? String,
            let sessionID = UUID(uuidString: sessionIDRaw),
            let currentQuarter = userInfo["currentQuarter"] as? String,
            let remainingSeconds = userInfo["remainingSeconds"] as? Int,
            let isTimerRunning = userInfo["isTimerRunning"] as? Bool,
            let ourPoints = userInfo["ourPoints"] as? Int,
            let theirPoints = userInfo["theirPoints"] as? Int,
            let availablePlayerPayloadJSON = userInfo["availablePlayerPayloadJSON"] as? String,
            let updatedAt = userInfo["updatedAt"] as? Date
        else {
            return nil
        }

        return CloudStatsInviteSessionState(
            id: Self.sessionStateRecordName(sessionID: sessionID),
            sessionID: sessionID,
            currentQuarter: currentQuarter,
            remainingSeconds: remainingSeconds,
            isTimerRunning: isTimerRunning,
            ourPoints: ourPoints,
            theirPoints: theirPoints,
            availablePlayerPayloadJSON: availablePlayerPayloadJSON,
            updatedAt: updatedAt
        )
    }

    func ensureTallySubscription() async throws {
        try await ensureSubscription(
            id: SubscriptionKeys.statsTallyChanges,
            recordType: "StatsTally",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        try await ensureSubscription(
            id: SubscriptionKeys.statsPlayerEventChanges,
            recordType: "StatsPlayerEvent",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        try await ensureSubscription(
            id: SubscriptionKeys.statsSessionStateChanges,
            recordType: "StatsSessionState",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
    }

    nonisolated func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            return
        }

        Task {
            await handleRemoteNotification(notification)
        }
    }

    func saveAssignment(
        inviteeEmail: String,
        inviteeName: String,
        sessionID: UUID,
        gradeName: String,
        oppositionName: String,
        venue: String,
        sessionDate: Date,
        assignedSelectionRawValues: [String],
        assignedSelectionDisplayNames: [String],
        assignedSelectionCollectionModes: [String],
        availablePlayerPayloadJSON: String
    ) async throws -> CloudStatsInviteAssignment {
        let normalizedEmail = normalized(inviteeEmail)
        let recordID = CKRecord.ID(recordName: Self.recordName(sessionID: sessionID, inviteeEmail: normalizedEmail))
        let record = try await fetch(recordID: recordID) ?? CKRecord(recordType: "StatsAssignment", recordID: recordID)

        record[FieldKeys.inviteeEmail] = normalizedEmail as CKRecordValue
        record[FieldKeys.inviteeName] = inviteeName.trimmingCharacters(in: .whitespacesAndNewlines) as CKRecordValue
        record[FieldKeys.sessionID] = sessionID.uuidString.lowercased() as CKRecordValue
        record[FieldKeys.gradeName] = gradeName as CKRecordValue
        record[FieldKeys.oppositionName] = oppositionName as CKRecordValue
        record[FieldKeys.venue] = venue as CKRecordValue
        record[FieldKeys.sessionDate] = sessionDate as CKRecordValue
        record[FieldKeys.assignedSelectionRawValues] = assignedSelectionRawValues as CKRecordValue
        record[FieldKeys.assignedSelectionDisplayNames] = assignedSelectionDisplayNames as CKRecordValue
        record[FieldKeys.assignedSelectionCollectionModes] = assignedSelectionCollectionModes as CKRecordValue
        record[FieldKeys.availablePlayerPayloadJSON] = availablePlayerPayloadJSON as CKRecordValue
        record[FieldKeys.lastInvitedAt] = Date() as CKRecordValue

        let savedRecord = try await save(record)
        return try assignment(from: savedRecord)
    }

    func fetchAssignments(for inviteeEmail: String) async throws -> [CloudStatsInviteAssignment] {
        let normalizedEmail = normalized(inviteeEmail)
        guard !normalizedEmail.isEmpty else { return [] }

        let predicate = NSPredicate(format: "%K == %@", FieldKeys.inviteeEmail, normalizedEmail)
        let query = CKQuery(recordType: "StatsAssignment", predicate: predicate)
        let records = try await performQuery(query)

        return try records
            .map(assignment(from:))
            .sorted { lhs, rhs in
                lhs.sessionDate > rhs.sessionDate
            }
    }

    func markAssignmentsConnected(for inviteeEmail: String) async throws -> [CloudStatsInviteAssignment] {
        let assignments = try await fetchAssignments(for: inviteeEmail)
        let now = Date()
        var updated: [CloudStatsInviteAssignment] = []

        for existingAssignment in assignments {
            let recordID = CKRecord.ID(recordName: existingAssignment.id)
            guard let record = try await fetch(recordID: recordID) else { continue }
            record[FieldKeys.lastConnectedAt] = now as CKRecordValue
            let savedRecord = try await save(record)
            updated.append(try assignment(from: savedRecord))
        }

        return updated.sorted { lhs, rhs in
            lhs.sessionDate > rhs.sessionDate
        }
    }

    func fetchAssignments(recordNames: [String]) async throws -> [CloudStatsInviteAssignment] {
        var assignments: [CloudStatsInviteAssignment] = []
        for recordName in Set(recordNames).sorted() where !recordName.isEmpty {
            let recordID = CKRecord.ID(recordName: recordName)
            if let record = try await fetch(recordID: recordID) {
                assignments.append(try assignment(from: record))
            }
        }
        return assignments
    }

    func deleteAssignments(recordNames: [String]) async {
        for recordName in recordNames where !recordName.isEmpty {
            await deleteRecordIfExists(recordName: recordName)
        }
    }

    func deleteSessionArtifacts(sessionID: UUID) async {
        let sessionPredicate = NSPredicate(format: "%K == %@", FieldKeys.sessionID, sessionID.uuidString.lowercased())
        await deleteRecords(recordType: "StatsAssignment", predicate: sessionPredicate)
        await deleteRecords(recordType: "StatsTally", predicate: sessionPredicate)
        await deleteRecords(recordType: "StatsPlayerEvent", predicate: sessionPredicate)
        await deleteRecordIfExists(recordName: Self.sessionStateRecordName(sessionID: sessionID))
    }

    func fetchTallies(sessionID: UUID) async throws -> [CloudStatsInviteTally] {
        let predicate = NSPredicate(format: "%K == %@", FieldKeys.sessionID, sessionID.uuidString.lowercased())
        let query = CKQuery(recordType: "StatsTally", predicate: predicate)
        let records = try await performQuery(query)

        return try records
            .map(tally(from:))
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
    }

    func fetchTallies(
        sessionID: UUID,
        statTypeIDs: [UUID],
        sideRawValues: [String]
    ) async throws -> [CloudStatsInviteTally] {
        let uniqueStatTypeIDs = Array(Set(statTypeIDs))
        let uniqueSideRawValues = Array(Set(sideRawValues))
        let recordIDs = uniqueStatTypeIDs.flatMap { statTypeID in
            uniqueSideRawValues.map { sideRawValue in
                CKRecord.ID(
                    recordName: Self.tallyRecordName(
                        sessionID: sessionID,
                        statTypeID: statTypeID,
                        sideRawValue: sideRawValue
                    )
                )
            }
        }
        let records = try await fetch(recordIDs: recordIDs)

        return try records
            .map(tally(from:))
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
    }

    func fetchTallies(
        sessionID: UUID,
        statTypeIDs: [UUID],
        sideRawValues: [String],
        updatedAfter: Date
    ) async throws -> [CloudStatsInviteTally] {
        let normalizedStatTypeIDs = Array(Set(statTypeIDs.map { $0.uuidString.lowercased() }))
        let normalizedSideRawValues = Array(Set(sideRawValues))
        guard !normalizedStatTypeIDs.isEmpty, !normalizedSideRawValues.isEmpty else { return [] }

        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "%K == %@", FieldKeys.sessionID, sessionID.uuidString.lowercased()),
            NSPredicate(format: "%K IN %@", FieldKeys.statTypeID, normalizedStatTypeIDs),
            NSPredicate(format: "%K IN %@", FieldKeys.sideRawValue, normalizedSideRawValues),
            NSPredicate(format: "%K > %@", FieldKeys.updatedAt, updatedAfter as NSDate)
        ])
        let query = CKQuery(recordType: "StatsTally", predicate: predicate)
        let records = try await performQuery(query)

        return try records
            .map(tally(from:))
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
    }

    func incrementTally(
        sessionID: UUID,
        statTypeID: UUID,
        sideRawValue: String,
        amount: Int = 1
    ) async throws -> CloudStatsInviteTally {
        let recordID = CKRecord.ID(
            recordName: Self.tallyRecordName(
                sessionID: sessionID,
                statTypeID: statTypeID,
                sideRawValue: sideRawValue
            )
        )
        return try await incrementTally(
            recordID: recordID,
            sessionID: sessionID,
            statTypeID: statTypeID,
            sideRawValue: sideRawValue,
            amount: amount
        )
    }

    func savePlayerEvent(
        eventID: UUID,
        sessionID: UUID,
        statTypeID: UUID,
        sideRawValue: String,
        playerID: UUID,
        quarter: String,
        timestamp: Date = Date()
    ) async throws -> CloudStatsInvitePlayerEvent {
        let recordID = CKRecord.ID(recordName: Self.playerEventRecordName(eventID: eventID))
        let record = try await fetch(recordID: recordID) ?? CKRecord(recordType: "StatsPlayerEvent", recordID: recordID)
        record[FieldKeys.eventID] = eventID.uuidString.lowercased() as CKRecordValue
        record[FieldKeys.sessionID] = sessionID.uuidString.lowercased() as CKRecordValue
        record[FieldKeys.statTypeID] = statTypeID.uuidString.lowercased() as CKRecordValue
        record[FieldKeys.sideRawValue] = sideRawValue as CKRecordValue
        record[FieldKeys.playerID] = playerID.uuidString.lowercased() as CKRecordValue
        record[FieldKeys.quarter] = quarter as CKRecordValue
        record[FieldKeys.timestamp] = timestamp as CKRecordValue
        record[FieldKeys.updatedAt] = Date() as CKRecordValue

        let savedRecord = try await save(record)
        let savedEvent = try playerEvent(from: savedRecord)
        await postPlayerEventDidChange(savedEvent)
        return savedEvent
    }

    func saveSessionRoster(
        sessionID: UUID,
        players: [CloudStatsInviteRosterPlayer]
    ) async throws -> CloudStatsInviteSessionState {
        let recordID = CKRecord.ID(recordName: Self.sessionStateRecordName(sessionID: sessionID))
        let record = try await fetch(recordID: recordID) ?? CKRecord(recordType: "StatsSessionState", recordID: recordID)
        record[FieldKeys.sessionID] = sessionID.uuidString.lowercased() as CKRecordValue
        let playerPayloadJSON: String
        if let data = try? JSONEncoder().encode(players),
           let json = String(data: data, encoding: .utf8) {
            playerPayloadJSON = json
        } else {
            playerPayloadJSON = "[]"
        }
        record[FieldKeys.availablePlayerPayloadJSON] = playerPayloadJSON as CKRecordValue
        record[FieldKeys.updatedAt] = Date() as CKRecordValue

        let savedRecord = try await save(record)
        let savedState = try sessionState(from: savedRecord)
        await postSessionStateDidChange(savedState)
        return savedState
    }

    func fetchSessionRoster(sessionID: UUID) async throws -> CloudStatsInviteSessionRoster? {
        let recordID = CKRecord.ID(recordName: Self.sessionStateRecordName(sessionID: sessionID))
        guard let record = try await fetch(recordID: recordID) else { return nil }
        return try sessionRoster(from: record)
    }

    func fetchPlayerEvents(sessionID: UUID) async throws -> [CloudStatsInvitePlayerEvent] {
        let predicate = NSPredicate(format: "%K == %@", FieldKeys.sessionID, sessionID.uuidString.lowercased())
        let query = CKQuery(recordType: "StatsPlayerEvent", predicate: predicate)
        let records = try await performQuery(query)

        return try records
            .map(playerEvent(from:))
            .sorted { lhs, rhs in
                lhs.timestamp > rhs.timestamp
            }
    }

    func fetchPlayerEvents(sessionID: UUID, updatedAfter: Date) async throws -> [CloudStatsInvitePlayerEvent] {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "%K == %@", FieldKeys.sessionID, sessionID.uuidString.lowercased()),
            NSPredicate(format: "%K > %@", FieldKeys.updatedAt, updatedAfter as NSDate)
        ])
        let query = CKQuery(recordType: "StatsPlayerEvent", predicate: predicate)
        let records = try await performQuery(query)

        return try records
            .map(playerEvent(from:))
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
    }

    func deletePlayerEvent(recordName: String) async throws {
        let recordID = CKRecord.ID(recordName: recordName)
        _ = try await delete(recordID: recordID)
        await postGenericPlayerEventChange()
    }

    func saveSessionState(
        sessionID: UUID,
        currentQuarter: String,
        remainingSeconds: Int,
        isTimerRunning: Bool,
        ourPoints: Int,
        theirPoints: Int
    ) async throws -> CloudStatsInviteSessionState {
        let recordID = CKRecord.ID(recordName: Self.sessionStateRecordName(sessionID: sessionID))
        let record = try await fetch(recordID: recordID) ?? CKRecord(recordType: "StatsSessionState", recordID: recordID)
        record[FieldKeys.sessionID] = sessionID.uuidString.lowercased() as CKRecordValue
        record[FieldKeys.currentQuarter] = currentQuarter as CKRecordValue
        record[FieldKeys.remainingSeconds] = remainingSeconds as CKRecordValue
        record[FieldKeys.isTimerRunning] = isTimerRunning as CKRecordValue
        record[FieldKeys.ourPoints] = ourPoints as CKRecordValue
        record[FieldKeys.theirPoints] = theirPoints as CKRecordValue
        record[FieldKeys.updatedAt] = Date() as CKRecordValue

        let savedRecord = try await save(record)
        let savedState = try sessionState(from: savedRecord)
        await postSessionStateDidChange(savedState)
        return savedState
    }

    func fetchSessionState(sessionID: UUID) async throws -> CloudStatsInviteSessionState? {
        let recordID = CKRecord.ID(recordName: Self.sessionStateRecordName(sessionID: sessionID))
        guard let record = try await fetch(recordID: recordID) else { return nil }
        return try sessionState(from: record)
    }

    private func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func incrementTally(
        recordID: CKRecord.ID,
        sessionID: UUID,
        statTypeID: UUID,
        sideRawValue: String,
        amount: Int,
        attempt: Int = 0
    ) async throws -> CloudStatsInviteTally {
        let record = try await fetch(recordID: recordID) ?? CKRecord(recordType: "StatsTally", recordID: recordID)
        let currentCount = record[FieldKeys.count] as? Int ?? 0
        record[FieldKeys.sessionID] = sessionID.uuidString.lowercased() as CKRecordValue
        record[FieldKeys.statTypeID] = statTypeID.uuidString.lowercased() as CKRecordValue
        record[FieldKeys.sideRawValue] = sideRawValue as CKRecordValue
        record[FieldKeys.count] = (currentCount + amount) as CKRecordValue
        record[FieldKeys.updatedAt] = Date() as CKRecordValue

        do {
            let savedRecord = try await save(record)
            let savedTally = try tally(from: savedRecord)
            await postTallyDidChange(savedTally)
            return savedTally
        } catch let error as CKError
            where error.code == .serverRecordChanged && attempt < 3 {
            return try await incrementTally(
                recordID: recordID,
                sessionID: sessionID,
                statTypeID: statTypeID,
                sideRawValue: sideRawValue,
                amount: amount,
                attempt: attempt + 1
            )
        }
    }

    private func fetchTally(recordID: CKRecord.ID) async throws -> CloudStatsInviteTally? {
        guard let record = try await fetch(recordID: recordID) else { return nil }
        return try tally(from: record)
    }

    private func fetch(recordID: CKRecord.ID) async throws -> CKRecord? {
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

    private func save(_ record: CKRecord) async throws -> CKRecord {
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

    private func fetch(recordIDs: [CKRecord.ID]) async throws -> [CKRecord] {
        guard !recordIDs.isEmpty else { return [] }

        return try await withCheckedThrowingContinuation { continuation in
            var matches: [CKRecord.ID: CKRecord] = [:]
            let operation = CKFetchRecordsOperation(recordIDs: recordIDs)
            operation.perRecordResultBlock = { recordID, result in
                if case let .success(record) = result {
                    matches[recordID] = record
                }
            }
            operation.fetchRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: recordIDs.compactMap { matches[$0] })
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func delete(recordID: CKRecord.ID) async throws -> CKRecord.ID {
        try await withCheckedThrowingContinuation { continuation in
            database.delete(withRecordID: recordID) { deletedRecordID, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let deletedRecordID else {
                    continuation.resume(throwing: CKError(.internalError))
                    return
                }
                continuation.resume(returning: deletedRecordID)
            }
        }
    }

    private func deleteRecords(recordType: String, predicate: NSPredicate) async {
        do {
            let records = try await performQuery(CKQuery(recordType: recordType, predicate: predicate))
            for record in records {
                _ = try? await delete(recordID: record.recordID)
            }
        } catch {
            // Ignore missing/undeployed record types so cleanup can proceed for the rest.
            if error.localizedDescription.localizedCaseInsensitiveContains("record type") {
                return
            }
        }
    }

    private func deleteRecordIfExists(recordName: String) async {
        do {
            _ = try await delete(recordID: CKRecord.ID(recordName: recordName))
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                return
            }
        }
    }

    private func subscriptionExists(id: String) async throws -> Bool {
        let subscription: CKSubscription? = try await withCheckedThrowingContinuation { continuation in
            database.fetch(withSubscriptionID: id) { subscription, error in
                if let ckError = error as? CKError, ckError.code == .unknownItem {
                    continuation.resume(returning: nil)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: subscription)
            }
        }
        return subscription != nil
    }

    private func ensureSubscription(
        id: String,
        recordType: String,
        options: CKQuerySubscription.Options
    ) async throws {
        if try await subscriptionExists(id: id) {
            return
        }

        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: id,
            options: options
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        _ = try await save(subscription: subscription)
    }

    private func save(subscription: CKSubscription) async throws -> CKSubscription {
        try await withCheckedThrowingContinuation { continuation in
            database.save(subscription) { savedSubscription, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let savedSubscription else {
                    continuation.resume(throwing: CKError(.internalError))
                    return
                }
                continuation.resume(returning: savedSubscription)
            }
        }
    }

    private func performQuery(_ query: CKQuery) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            var matches: [CKRecord] = []
            let operation = CKQueryOperation(query: query)
            operation.recordMatchedBlock = { _, result in
                if case let .success(record) = result {
                    matches.append(record)
                }
            }
            operation.queryResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: matches)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func assignment(from record: CKRecord) throws -> CloudStatsInviteAssignment {
        guard
            let sessionIDRaw = record[FieldKeys.sessionID] as? String,
            let sessionID = UUID(uuidString: sessionIDRaw)
        else {
            throw CKError(.partialFailure)
        }

        return CloudStatsInviteAssignment(
            id: record.recordID.recordName,
            inviteeEmail: (record[FieldKeys.inviteeEmail] as? String) ?? "",
            inviteeName: (record[FieldKeys.inviteeName] as? String) ?? "",
            sessionID: sessionID,
            gradeName: (record[FieldKeys.gradeName] as? String) ?? "Grade",
            oppositionName: (record[FieldKeys.oppositionName] as? String) ?? "Opposition",
            venue: (record[FieldKeys.venue] as? String) ?? "",
            sessionDate: (record[FieldKeys.sessionDate] as? Date) ?? .distantPast,
            assignedSelectionRawValues: (record[FieldKeys.assignedSelectionRawValues] as? [String]) ?? [],
            assignedSelectionDisplayNames: (record[FieldKeys.assignedSelectionDisplayNames] as? [String]) ?? [],
            assignedSelectionCollectionModes: (record[FieldKeys.assignedSelectionCollectionModes] as? [String]) ?? [],
            availablePlayerPayloadJSON: (record[FieldKeys.availablePlayerPayloadJSON] as? String) ?? "[]",
            lastInvitedAt: (record[FieldKeys.lastInvitedAt] as? Date) ?? .distantPast,
            lastConnectedAt: record[FieldKeys.lastConnectedAt] as? Date
        )
    }

    private func tally(from record: CKRecord) throws -> CloudStatsInviteTally {
        guard
            let sessionIDRaw = record[FieldKeys.sessionID] as? String,
            let sessionID = UUID(uuidString: sessionIDRaw),
            let statTypeIDRaw = record[FieldKeys.statTypeID] as? String,
            let statTypeID = UUID(uuidString: statTypeIDRaw)
        else {
            throw CKError(.partialFailure)
        }

        return CloudStatsInviteTally(
            id: record.recordID.recordName,
            sessionID: sessionID,
            statTypeID: statTypeID,
            sideRawValue: (record[FieldKeys.sideRawValue] as? String) ?? "",
            count: record[FieldKeys.count] as? Int ?? 0,
            updatedAt: (record[FieldKeys.updatedAt] as? Date) ?? .distantPast
        )
    }

    private func playerEvent(from record: CKRecord) throws -> CloudStatsInvitePlayerEvent {
        guard
            let eventIDRaw = record[FieldKeys.eventID] as? String,
            let eventID = UUID(uuidString: eventIDRaw),
            let sessionIDRaw = record[FieldKeys.sessionID] as? String,
            let sessionID = UUID(uuidString: sessionIDRaw),
            let statTypeIDRaw = record[FieldKeys.statTypeID] as? String,
            let statTypeID = UUID(uuidString: statTypeIDRaw),
            let playerIDRaw = record[FieldKeys.playerID] as? String,
            let playerID = UUID(uuidString: playerIDRaw)
        else {
            throw CKError(.partialFailure)
        }

        return CloudStatsInvitePlayerEvent(
            id: record.recordID.recordName,
            eventID: eventID,
            sessionID: sessionID,
            statTypeID: statTypeID,
            sideRawValue: (record[FieldKeys.sideRawValue] as? String) ?? "",
            playerID: playerID,
            quarter: (record[FieldKeys.quarter] as? String) ?? "Q1",
            timestamp: (record[FieldKeys.timestamp] as? Date) ?? .distantPast,
            updatedAt: (record[FieldKeys.updatedAt] as? Date) ?? .distantPast
        )
    }

    private func sessionState(from record: CKRecord) throws -> CloudStatsInviteSessionState {
        guard
            let sessionIDRaw = record[FieldKeys.sessionID] as? String,
            let sessionID = UUID(uuidString: sessionIDRaw)
        else {
            throw CKError(.partialFailure)
        }

        return CloudStatsInviteSessionState(
            id: record.recordID.recordName,
            sessionID: sessionID,
            currentQuarter: (record[FieldKeys.currentQuarter] as? String) ?? "Q1",
            remainingSeconds: record[FieldKeys.remainingSeconds] as? Int ?? 0,
            isTimerRunning: record[FieldKeys.isTimerRunning] as? Bool ?? false,
            ourPoints: record[FieldKeys.ourPoints] as? Int ?? 0,
            theirPoints: record[FieldKeys.theirPoints] as? Int ?? 0,
            availablePlayerPayloadJSON: (record[FieldKeys.availablePlayerPayloadJSON] as? String) ?? "[]",
            updatedAt: (record[FieldKeys.updatedAt] as? Date) ?? .distantPast
        )
    }

    private func sessionRoster(from record: CKRecord) throws -> CloudStatsInviteSessionRoster {
        guard
            let sessionIDRaw = record[FieldKeys.sessionID] as? String,
            let sessionID = UUID(uuidString: sessionIDRaw)
        else {
            throw CKError(.partialFailure)
        }

        let payloadJSON = (record[FieldKeys.availablePlayerPayloadJSON] as? String) ?? "[]"
        let players: [CloudStatsInviteRosterPlayer]
        if let data = payloadJSON.data(using: .utf8),
           let decodedPlayers = try? JSONDecoder().decode([CloudStatsInviteRosterPlayer].self, from: data) {
            players = decodedPlayers
        } else {
            players = []
        }

        return CloudStatsInviteSessionRoster(
            id: record.recordID.recordName,
            sessionID: sessionID,
            players: players,
            updatedAt: (record[FieldKeys.updatedAt] as? Date) ?? .distantPast
        )
    }

    @MainActor
    private func postGenericTallyChange() {
        NotificationCenter.default.post(name: .statsTalliesDidChange, object: nil)
    }

    @MainActor
    private func postTallyDidChange(_ tally: CloudStatsInviteTally) {
        NotificationCenter.default.post(
            name: .statsTalliesDidChange,
            object: nil,
            userInfo: [
                StatsTallyNotificationKeys.sessionID: tally.sessionID.uuidString.lowercased(),
                StatsTallyNotificationKeys.statTypeID: tally.statTypeID.uuidString.lowercased(),
                StatsTallyNotificationKeys.sideRawValue: tally.sideRawValue,
                StatsTallyNotificationKeys.count: tally.count,
                StatsTallyNotificationKeys.updatedAt: tally.updatedAt
            ]
        )
    }

    private func handleRemoteNotification(_ notification: CKNotification) async {
        switch notification.subscriptionID {
        case SubscriptionKeys.statsTallyChanges:
            await handleTallyNotification(notification as? CKQueryNotification)
        case SubscriptionKeys.statsPlayerEventChanges:
            await handlePlayerEventNotification(notification as? CKQueryNotification)
        case SubscriptionKeys.statsSessionStateChanges:
            await handleSessionStateNotification(notification as? CKQueryNotification)
        default:
            return
        }
    }

    private func handleTallyNotification(_ queryNotification: CKQueryNotification?) async {
        if let queryNotification,
           let recordID = queryNotification.recordID,
           let tally = try? await fetchTally(recordID: recordID) {
            await postTallyDidChange(tally)
        } else {
            await postGenericTallyChange()
        }
    }

    private func handlePlayerEventNotification(_ queryNotification: CKQueryNotification?) async {
        if let queryNotification,
           queryNotification.queryNotificationReason == .recordDeleted {
            await postGenericPlayerEventChange()
            return
        }

        if let queryNotification,
           let recordID = queryNotification.recordID,
           let record = try? await fetch(recordID: recordID) {
            if let event = try? playerEvent(from: record) {
                await postPlayerEventDidChange(event)
            } else {
                await postGenericPlayerEventChange()
            }
        } else {
            await postGenericPlayerEventChange()
        }
    }

    private func handleSessionStateNotification(_ queryNotification: CKQueryNotification?) async {
        if let queryNotification,
           let recordID = queryNotification.recordID,
           let record = try? await fetch(recordID: recordID) {
            if let state = try? sessionState(from: record) {
                await postSessionStateDidChange(state)
            } else {
                await postGenericSessionStateChange()
            }
        } else {
            await postGenericSessionStateChange()
        }
    }

    @MainActor
    private func postGenericPlayerEventChange() {
        NotificationCenter.default.post(name: .statsPlayerEventsDidChange, object: nil)
    }

    @MainActor
    private func postPlayerEventDidChange(_ event: CloudStatsInvitePlayerEvent) {
        NotificationCenter.default.post(
            name: .statsPlayerEventsDidChange,
            object: nil,
            userInfo: [
                StatsPlayerEventNotificationKeys.isDeleted: false,
                StatsPlayerEventNotificationKeys.recordName: event.id,
                StatsPlayerEventNotificationKeys.sessionID: event.sessionID.uuidString.lowercased(),
                StatsPlayerEventNotificationKeys.eventID: event.eventID.uuidString.lowercased(),
                StatsPlayerEventNotificationKeys.statTypeID: event.statTypeID.uuidString.lowercased(),
                StatsPlayerEventNotificationKeys.sideRawValue: event.sideRawValue,
                StatsPlayerEventNotificationKeys.playerID: event.playerID.uuidString.lowercased(),
                StatsPlayerEventNotificationKeys.quarter: event.quarter,
                StatsPlayerEventNotificationKeys.timestamp: event.timestamp,
                StatsPlayerEventNotificationKeys.updatedAt: event.updatedAt
            ]
        )
    }

    @MainActor
    private func postGenericSessionStateChange() {
        NotificationCenter.default.post(name: .statsSessionStateDidChange, object: nil)
    }

    @MainActor
    private func postSessionStateDidChange(_ state: CloudStatsInviteSessionState) {
        NotificationCenter.default.post(
            name: .statsSessionStateDidChange,
            object: nil,
            userInfo: [
                StatsSessionStateNotificationKeys.sessionID: state.sessionID.uuidString.lowercased(),
                StatsSessionStateNotificationKeys.currentQuarter: state.currentQuarter,
                StatsSessionStateNotificationKeys.remainingSeconds: state.remainingSeconds,
                StatsSessionStateNotificationKeys.isTimerRunning: state.isTimerRunning,
                StatsSessionStateNotificationKeys.ourPoints: state.ourPoints,
                StatsSessionStateNotificationKeys.theirPoints: state.theirPoints,
                StatsSessionStateNotificationKeys.availablePlayerPayloadJSON: state.availablePlayerPayloadJSON,
                StatsSessionStateNotificationKeys.updatedAt: state.updatedAt
            ]
        )
    }
}
