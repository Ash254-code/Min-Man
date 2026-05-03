import Foundation
import CloudKit

extension Notification.Name {
    static let statsTalliesDidChange = Notification.Name("statsTalliesDidChange")
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
}

struct CloudStatsInviteTally: Identifiable, Hashable {
    let id: String
    let sessionID: UUID
    let statTypeID: UUID
    let sideRawValue: String
    let count: Int
    let updatedAt: Date
}

actor CloudKitStatsInviteService {
    private enum SubscriptionKeys {
        static let statsTallyChanges = "stats-tally-changes"
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
        static let lastInvitedAt = "lastInvitedAt"
        static let lastConnectedAt = "lastConnectedAt"
        static let statTypeID = "statTypeID"
        static let sideRawValue = "sideRawValue"
        static let count = "count"
        static let updatedAt = "updatedAt"
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

    func ensureTallySubscription() async throws {
        if try await subscriptionExists(id: SubscriptionKeys.statsTallyChanges) {
            return
        }

        let subscription = CKQuerySubscription(
            recordType: "StatsTally",
            predicate: NSPredicate(value: true),
            subscriptionID: SubscriptionKeys.statsTallyChanges,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        _ = try await save(subscription: subscription)
    }

    nonisolated func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              notification.subscriptionID == SubscriptionKeys.statsTallyChanges else {
            return
        }

        Task { @MainActor in
            NotificationCenter.default.post(name: .statsTalliesDidChange, object: nil)
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
        assignedSelectionDisplayNames: [String]
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
        for recordName in recordNames where !recordName.isEmpty {
            let recordID = CKRecord.ID(recordName: recordName)
            if let record = try await fetch(recordID: recordID) {
                assignments.append(try assignment(from: record))
            }
        }
        return assignments
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
        var tallies: [CloudStatsInviteTally] = []
        let uniqueStatTypeIDs = Array(Set(statTypeIDs))
        let uniqueSideRawValues = Array(Set(sideRawValues))

        for statTypeID in uniqueStatTypeIDs {
            for sideRawValue in uniqueSideRawValues {
                let recordID = CKRecord.ID(
                    recordName: Self.tallyRecordName(
                        sessionID: sessionID,
                        statTypeID: statTypeID,
                        sideRawValue: sideRawValue
                    )
                )
                if let record = try await fetch(recordID: recordID) {
                    tallies.append(try tally(from: record))
                }
            }
        }

        return tallies.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
    }

    func incrementTally(
        sessionID: UUID,
        statTypeID: UUID,
        sideRawValue: String
    ) async throws -> CloudStatsInviteTally {
        let recordID = CKRecord.ID(
            recordName: Self.tallyRecordName(
                sessionID: sessionID,
                statTypeID: statTypeID,
                sideRawValue: sideRawValue
            )
        )
        return try await incrementTally(recordID: recordID, sessionID: sessionID, statTypeID: statTypeID, sideRawValue: sideRawValue)
    }

    private func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func incrementTally(
        recordID: CKRecord.ID,
        sessionID: UUID,
        statTypeID: UUID,
        sideRawValue: String,
        attempt: Int = 0
    ) async throws -> CloudStatsInviteTally {
        let record = try await fetch(recordID: recordID) ?? CKRecord(recordType: "StatsTally", recordID: recordID)
        let currentCount = record[FieldKeys.count] as? Int ?? 0
        record[FieldKeys.sessionID] = sessionID.uuidString.lowercased() as CKRecordValue
        record[FieldKeys.statTypeID] = statTypeID.uuidString.lowercased() as CKRecordValue
        record[FieldKeys.sideRawValue] = sideRawValue as CKRecordValue
        record[FieldKeys.count] = (currentCount + 1) as CKRecordValue
        record[FieldKeys.updatedAt] = Date() as CKRecordValue

        do {
            let savedRecord = try await save(record)
            return try tally(from: savedRecord)
        } catch let error as CKError
            where error.code == .serverRecordChanged && attempt < 3 {
            return try await incrementTally(
                recordID: recordID,
                sessionID: sessionID,
                statTypeID: statTypeID,
                sideRawValue: sideRawValue,
                attempt: attempt + 1
            )
        }
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
}
