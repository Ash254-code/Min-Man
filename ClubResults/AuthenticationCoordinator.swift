import SwiftUI
import AuthenticationServices
import CloudKit
internal import Combine

struct CloudUserProfile {
    let email: String
    let role: AppRole
    let displayName: String
    let lastSignedInAt: Date?
}

struct InvitedUserAccount: Identifiable {
    let email: String
    let role: AppRole
    let displayName: String
    let lastSignedInAt: Date?

    var id: String { email }

    var hasSignedIn: Bool {
        lastSignedInAt != nil
    }
}

enum CloudUserAccessError: LocalizedError {
    case missingEmail
    case invalidRole

    var errorDescription: String? {
        switch self {
        case .missingEmail:
            return "This Apple ID did not provide an email address. Revoke the app in Sign in with Apple settings, then sign in again."
        case .invalidRole:
            return "The CloudKit user role is invalid."
        }
    }
}

actor CloudKitUserAccessService {
    private enum StorageKeys {
        static let bootstrapAdminAssigned = "cloudkit.bootstrapAdminAssigned"
    }

    private enum RecordNames {
        static let invitedUserDirectory = "user-directory"
    }

    private enum DirectoryValues {
        static let email = "__invited-user-directory__@clubresults.local"
        static let role = AppRole.supporter
    }

    static let shared = CloudKitUserAccessService()

    private let container = CKContainer(identifier: "iCloud.MINMAN.ClubResults")

    private var database: CKDatabase {
        container.publicCloudDatabase
    }

    func resolveProfile(email: String, displayName: String) async throws -> CloudUserProfile {
        let normalizedEmail = normalized(email)

        if let record = try await fetchUserRecord(email: normalizedEmail) {
            let existingDisplayName = (record["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let resolvedDisplayName = displayName.isEmpty ? existingDisplayName : displayName
            let now = Date()
            if !resolvedDisplayName.isEmpty && existingDisplayName != resolvedDisplayName {
                record["displayName"] = resolvedDisplayName as CKRecordValue
            }
            record["lastSignedInAt"] = now as CKRecordValue
            let savedRecord = try await save(record)
            try await addEmailToDirectory(normalizedEmail)
            return try profile(from: savedRecord)
        }

        let bootstrapRole: AppRole = bootstrapRoleForNewUser()
        let newRecord = CKRecord(recordType: "User", recordID: CKRecord.ID(recordName: recordName(for: normalizedEmail)))
        newRecord["email"] = normalizedEmail as CKRecordValue
        newRecord["role"] = bootstrapRole.rawValue as CKRecordValue
        newRecord["displayName"] = displayName as CKRecordValue
        newRecord["lastSignedInAt"] = Date() as CKRecordValue
        let savedRecord = try await save(newRecord)
        try await addEmailToDirectory(normalizedEmail)
        markBootstrapAdminAssignedIfNeeded(for: bootstrapRole)

        return try profile(from: savedRecord)
    }

    func inviteUser(email: String, role: AppRole) async throws -> CloudUserProfile {
        let normalizedEmail = normalized(email)
        let record = try await fetchUserRecord(email: normalizedEmail) ?? CKRecord(
            recordType: "User",
            recordID: CKRecord.ID(recordName: recordName(for: normalizedEmail))
        )

        let existingDisplayName = (record["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        record["email"] = normalizedEmail as CKRecordValue
        record["role"] = role.rawValue as CKRecordValue
        record["displayName"] = (existingDisplayName.isEmpty ? pendingDisplayName(for: normalizedEmail) : existingDisplayName) as CKRecordValue

        let savedRecord = try await save(record)
        try await addEmailToDirectory(normalizedEmail)
        return try profile(from: savedRecord)
    }

    func fetchInvitedUsers() async throws -> [InvitedUserAccount] {
        let emails = try await fetchInvitedUserEmails()
        let records = try await fetchUserRecords(emails: emails)
        return try records
            .compactMap { record in
                let email = (record["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !email.isEmpty else { return nil }
                return try invitedUserAccount(from: record)
            }
            .sorted { lhs, rhs in
                lhs.email.localizedCaseInsensitiveCompare(rhs.email) == .orderedAscending
            }
    }

    func updateUserRole(email: String, role: AppRole) async throws -> InvitedUserAccount {
        let normalizedEmail = normalized(email)
        guard let record = try await fetchUserRecord(email: normalizedEmail) else {
            throw CKError(.unknownItem)
        }

        record["role"] = role.rawValue as CKRecordValue
        let savedRecord = try await save(record)
        return try invitedUserAccount(from: savedRecord)
    }

    func removeUser(email: String) async throws {
        let normalizedEmail = normalized(email)
        try await delete(recordID: CKRecord.ID(recordName: recordName(for: normalizedEmail)))
        try await removeEmailFromDirectory(normalizedEmail)
    }

    private func role(from record: CKRecord) throws -> AppRole {
        guard let rawValue = record["role"] as? String,
              let role = AppRole(rawValue: rawValue) else {
            throw CloudUserAccessError.invalidRole
        }
        return role
    }

    private func fetchUserRecord(email: String) async throws -> CKRecord? {
        let recordID = CKRecord.ID(recordName: recordName(for: email))

        do {
            return try await fetch(recordID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func fetch(recordID: CKRecord.ID) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withRecordID: recordID) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let record else {
                    continuation.resume(throwing: CKError(.unknownItem))
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

    private func delete(recordID: CKRecord.ID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            database.delete(withRecordID: recordID) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: ())
            }
        }
    }

    private func fetchUserRecords(emails: [String]) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        for email in emails {
            if let record = try await fetchUserRecord(email: email) {
                records.append(record)
            }
        }
        return records
    }

    private func fetchInvitedUserEmails() async throws -> [String] {
        let record = try await fetchInvitedUserDirectoryRecord()
        return directoryEmails(from: record)
    }

    private func fetchInvitedUserDirectoryRecord() async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: RecordNames.invitedUserDirectory)

        do {
            return try await fetch(recordID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            let record = CKRecord(recordType: "User", recordID: recordID)
            record["email"] = DirectoryValues.email as CKRecordValue
            record["role"] = DirectoryValues.role.rawValue as CKRecordValue
            record["displayName"] = "" as CKRecordValue
            return try await save(record)
        }
    }

    private func addEmailToDirectory(_ email: String) async throws {
        let normalizedEmail = normalized(email)
        guard !normalizedEmail.isEmpty else { return }

        let record = try await fetchInvitedUserDirectoryRecord()
        var emails = directoryEmails(from: record)
        if !emails.contains(normalizedEmail) {
            emails.append(normalizedEmail)
            record["displayName"] = serializeDirectoryEmails(emails) as CKRecordValue
            _ = try await save(record)
        }
    }

    private func removeEmailFromDirectory(_ email: String) async throws {
        let normalizedEmail = normalized(email)
        let record = try await fetchInvitedUserDirectoryRecord()
        let currentEmails = directoryEmails(from: record)
        let updatedEmails = currentEmails.filter { $0 != normalizedEmail }
        guard updatedEmails != currentEmails else { return }
        record["displayName"] = serializeDirectoryEmails(updatedEmails) as CKRecordValue
        _ = try await save(record)
    }

    private func directoryEmails(from record: CKRecord) -> [String] {
        ((record["displayName"] as? String) ?? "")
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map(normalized)
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
    }

    private func serializeDirectoryEmails(_ emails: [String]) -> String {
        emails
            .map(normalized)
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            .joined(separator: "\n")
    }

    private func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func recordName(for email: String) -> String {
        let safeValue = email.map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "-"
        }
        return "user-\(String(safeValue))"
    }

    private func pendingDisplayName(for email: String) -> String {
        let localPart = email.split(separator: "@").first.map(String.init) ?? email
        return localPart.replacingOccurrences(of: ".", with: " ").capitalized
    }

    private func profile(from record: CKRecord) throws -> CloudUserProfile {
        CloudUserProfile(
            email: (record["email"] as? String) ?? "",
            role: try role(from: record),
            displayName: (record["displayName"] as? String) ?? "",
            lastSignedInAt: record["lastSignedInAt"] as? Date
        )
    }

    private func invitedUserAccount(from record: CKRecord) throws -> InvitedUserAccount {
        InvitedUserAccount(
            email: (record["email"] as? String) ?? "",
            role: try role(from: record),
            displayName: (record["displayName"] as? String) ?? "",
            lastSignedInAt: record["lastSignedInAt"] as? Date
        )
    }

    private func bootstrapRoleForNewUser() -> AppRole {
        let hasAssignedBootstrapAdmin = UserDefaults.standard.bool(forKey: StorageKeys.bootstrapAdminAssigned)
        return hasAssignedBootstrapAdmin ? .supporter : .admin
    }

    private func markBootstrapAdminAssignedIfNeeded(for role: AppRole) {
        guard role == .admin else { return }
        UserDefaults.standard.set(true, forKey: StorageKeys.bootstrapAdminAssigned)
    }
}

@MainActor
final class AuthenticationCoordinator: ObservableObject {
    private enum StorageKeys {
        static let appleUserID = "auth.appleUserID"
        static let email = "auth.email"
        static let displayName = "auth.displayName"
        static let forceAdminOnNextSignIn = "auth.forceAdminOnNextSignIn"
    }

    @Published private(set) var isAuthenticated = false
    @Published private(set) var isRestoringSession = false
    @Published private(set) var isSigningIn = false
    @Published private(set) var emailAddress: String?
    @Published private(set) var displayName = ""
    @Published private(set) var currentRole: AppRole?
    @Published var errorMessage: String?
    @Published var pendingAppleUserID: String?
    @Published var pendingDisplayName = ""
    @Published var requiresManualEmailEntry = false

    private var hasAttemptedRestore = false

    init() {
        UserDefaults.standard.register(defaults: [StorageKeys.forceAdminOnNextSignIn: true])
    }

    func restoreSessionIfNeeded(navigationState: AppNavigationState) async {
        guard !hasAttemptedRestore else { return }
        hasAttemptedRestore = true
        isRestoringSession = true
        defer { isRestoringSession = false }

        guard let appleUserID = UserDefaults.standard.string(forKey: StorageKeys.appleUserID) else {
            navigationState.clearAuthenticatedRole()
            return
        }

        let storedCredentialState: ASAuthorizationAppleIDProvider.CredentialState
        do {
            storedCredentialState = try await credentialState(for: appleUserID)
        } catch {
            errorMessage = error.localizedDescription
            navigationState.clearAuthenticatedRole()
            return
        }

        guard storedCredentialState == .authorized else {
            signOut(navigationState: navigationState)
            return
        }

        guard let storedEmail = UserDefaults.standard.string(forKey: StorageKeys.email), !storedEmail.isEmpty else {
            errorMessage = CloudUserAccessError.missingEmail.errorDescription
            signOut(navigationState: navigationState)
            return
        }

        let storedDisplayName = UserDefaults.standard.string(forKey: StorageKeys.displayName) ?? ""
        await applyAuthenticatedUser(
            appleUserID: appleUserID,
            email: storedEmail,
            displayName: storedDisplayName,
            navigationState: navigationState
        )
    }

    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.email, .fullName]
    }

    func handleCompletion(_ result: Result<ASAuthorization, Error>, navigationState: AppNavigationState) {
        switch result {
        case let .failure(error):
            errorMessage = error.localizedDescription
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Unable to read the Apple sign-in credential."
                return
            }

            let formatter = PersonNameComponentsFormatter()
            let resolvedEmail = credential.email ?? UserDefaults.standard.string(forKey: StorageKeys.email) ?? ""
            let resolvedDisplayName = formatter.string(from: credential.fullName ?? PersonNameComponents())
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nonEmpty(or: UserDefaults.standard.string(forKey: StorageKeys.displayName) ?? "")

            guard !resolvedEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                pendingAppleUserID = credential.user
                pendingDisplayName = resolvedDisplayName
                requiresManualEmailEntry = true
                errorMessage = "Apple did not provide an email on this sign-in. Enter the invited email address to continue."
                return
            }

            Task {
                isSigningIn = true
                await applyAuthenticatedUser(
                    appleUserID: credential.user,
                    email: resolvedEmail,
                    displayName: resolvedDisplayName,
                    navigationState: navigationState
                )
                isSigningIn = false
            }
        }
    }

    func sendInvite(email: String, role: AppRole) async throws -> CloudUserProfile {
        try await CloudKitUserAccessService.shared.inviteUser(email: email, role: role)
    }

    func fetchInvitedUsers() async throws -> [InvitedUserAccount] {
        try await CloudKitUserAccessService.shared.fetchInvitedUsers()
    }

    func updateInvitedUserRole(email: String, role: AppRole) async throws -> InvitedUserAccount {
        try await CloudKitUserAccessService.shared.updateUserRole(email: email, role: role)
    }

    func removeInvitedUser(email: String) async throws {
        try await CloudKitUserAccessService.shared.removeUser(email: email)
    }

    func signOut(navigationState: AppNavigationState) {
        UserDefaults.standard.removeObject(forKey: StorageKeys.appleUserID)
        UserDefaults.standard.removeObject(forKey: StorageKeys.email)
        UserDefaults.standard.removeObject(forKey: StorageKeys.displayName)

        isAuthenticated = false
        isSigningIn = false
        emailAddress = nil
        displayName = ""
        currentRole = nil
        errorMessage = nil
        pendingAppleUserID = nil
        pendingDisplayName = ""
        requiresManualEmailEntry = false

        navigationState.clearAuthenticatedRole()
    }

    func continueWithManualEmail(_ email: String, navigationState: AppNavigationState) {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let pendingAppleUserID, !normalizedEmail.isEmpty else {
            errorMessage = CloudUserAccessError.missingEmail.errorDescription
            return
        }

        requiresManualEmailEntry = false
        errorMessage = nil

        Task {
            isSigningIn = true
            await applyAuthenticatedUser(
                appleUserID: pendingAppleUserID,
                email: normalizedEmail,
                displayName: pendingDisplayName,
                navigationState: navigationState
            )
            isSigningIn = false
        }
    }

    func continueWithoutAppleSignIn(navigationState: AppNavigationState) {
        isAuthenticated = true
        isSigningIn = false
        isRestoringSession = false
        emailAddress = nil
        displayName = "Offline User"
        currentRole = .admin
        errorMessage = nil
        pendingAppleUserID = nil
        pendingDisplayName = ""
        requiresManualEmailEntry = false
        navigationState.setAuthenticatedRole(.admin)
    }

    func enableAdminRecoveryOnNextSignIn(navigationState: AppNavigationState) {
        UserDefaults.standard.set(true, forKey: StorageKeys.forceAdminOnNextSignIn)
        signOut(navigationState: navigationState)
    }

    private func applyAuthenticatedUser(
        appleUserID: String,
        email: String,
        displayName: String,
        navigationState: AppNavigationState
    ) async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty else {
            errorMessage = CloudUserAccessError.missingEmail.errorDescription
            return
        }

        do {
            let resolvedProfile = try await CloudKitUserAccessService.shared.resolveProfile(
                email: normalizedEmail,
                displayName: displayName
            )
            let shouldForceAdmin = UserDefaults.standard.bool(forKey: StorageKeys.forceAdminOnNextSignIn)
            let profile: CloudUserProfile
            if shouldForceAdmin, resolvedProfile.role != .admin {
                let updatedUser = try await CloudKitUserAccessService.shared.updateUserRole(
                    email: normalizedEmail,
                    role: .admin
                )
                profile = CloudUserProfile(
                    email: updatedUser.email,
                    role: updatedUser.role,
                    displayName: updatedUser.displayName,
                    lastSignedInAt: updatedUser.lastSignedInAt
                )
            } else {
                profile = resolvedProfile
            }
            if shouldForceAdmin {
                UserDefaults.standard.set(false, forKey: StorageKeys.forceAdminOnNextSignIn)
            }

            UserDefaults.standard.set(appleUserID, forKey: StorageKeys.appleUserID)
            UserDefaults.standard.set(profile.email, forKey: StorageKeys.email)
            UserDefaults.standard.set(profile.displayName, forKey: StorageKeys.displayName)

            isAuthenticated = true
            emailAddress = profile.email
            self.displayName = profile.displayName
            currentRole = profile.role
            errorMessage = nil
            pendingAppleUserID = nil
            pendingDisplayName = ""
            requiresManualEmailEntry = false

            navigationState.setAuthenticatedRole(profile.role)
        } catch {
            errorMessage = error.localizedDescription
            navigationState.clearAuthenticatedRole()
        }
    }

    private func credentialState(for userID: String) async throws -> ASAuthorizationAppleIDProvider.CredentialState {
        try await withCheckedThrowingContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: state)
                }
            }
        }
    }
}

struct AuthenticationGateView<Content: View>: View {
    @EnvironmentObject private var authCoordinator: AuthenticationCoordinator
    @EnvironmentObject private var navigationState: AppNavigationState
    @State private var manualEmail = ""

    let content: () -> Content

    var body: some View {
        Group {
            if authCoordinator.isAuthenticated {
                content()
            } else {
                signInView
            }
        }
        .task {
            await authCoordinator.restoreSessionIfNeeded(navigationState: navigationState)
        }
    }

    private var signInView: some View {
        ZStack {
            ClubTheme.bgGradient
                .ignoresSafeArea()

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("ClubResults")
                        .font(.largeTitle.weight(.bold))
                    Text("Sign in with Apple to load your invited role and app access.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if authCoordinator.isRestoringSession {
                    ProgressView("Checking your access…")
                } else if authCoordinator.isSigningIn {
                    ProgressView("Signing you in…")
                } else {
                    SignInWithAppleButton(.continue) { request in
                        authCoordinator.prepare(request)
                    } onCompletion: { result in
                        authCoordinator.handleCompletion(result, navigationState: navigationState)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)

                    Button("Continue Without Apple Sign-In") {
                        authCoordinator.continueWithoutAppleSignIn(navigationState: navigationState)
                    }
                    .buttonStyle(.bordered)
                }

                if authCoordinator.requiresManualEmailEntry {
                    VStack(spacing: 12) {
                        TextField("Invited email address", text: $manualEmail)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button("Continue With Email") {
                            authCoordinator.continueWithManualEmail(manualEmail, navigationState: navigationState)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manualEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if let errorMessage = authCoordinator.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Text("Invites are matched to the exact email returned by Sign in with Apple.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding()
        }
    }
}

private extension String {
    func nonEmpty(or fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
