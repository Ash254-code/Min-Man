import SwiftUI
import AuthenticationServices
import CloudKit

struct CloudUserProfile {
    let email: String
    let role: AppRole
    let displayName: String
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
    static let shared = CloudKitUserAccessService()

    private let container = CKContainer(identifier: "iCloud.MINMAN.ClubResults")

    private var database: CKDatabase {
        container.publicCloudDatabase
    }

    func resolveProfile(email: String, displayName: String) async throws -> CloudUserProfile {
        let normalizedEmail = normalized(email)

        if let record = try await fetchUserRecord(email: normalizedEmail) {
            let role = try role(from: record)
            let existingDisplayName = (record["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let resolvedDisplayName = displayName.isEmpty ? existingDisplayName : displayName

            if !resolvedDisplayName.isEmpty, existingDisplayName != resolvedDisplayName {
                record["displayName"] = resolvedDisplayName as CKRecordValue
                _ = try await save(record)
            }

            return CloudUserProfile(
                email: normalizedEmail,
                role: role,
                displayName: resolvedDisplayName
            )
        }

        let bootstrapRole: AppRole = try await hasAnyUserRecords() ? .supporter : .admin
        let newRecord = CKRecord(recordType: "User", recordID: CKRecord.ID(recordName: recordName(for: normalizedEmail)))
        newRecord["email"] = normalizedEmail as CKRecordValue
        newRecord["role"] = bootstrapRole.rawValue as CKRecordValue
        newRecord["displayName"] = displayName as CKRecordValue
        _ = try await save(newRecord)

        return CloudUserProfile(
            email: normalizedEmail,
            role: bootstrapRole,
            displayName: displayName
        )
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
        return CloudUserProfile(
            email: normalizedEmail,
            role: try self.role(from: savedRecord),
            displayName: (savedRecord["displayName"] as? String) ?? ""
        )
    }

    private func role(from record: CKRecord) throws -> AppRole {
        guard let rawValue = record["role"] as? String,
              let role = AppRole(rawValue: rawValue) else {
            throw CloudUserAccessError.invalidRole
        }
        return role
    }

    private func hasAnyUserRecords() async throws -> Bool {
        let query = CKQuery(recordType: "User", predicate: NSPredicate(value: true))
        let records = try await performQuery(query, resultsLimit: 1)
        return !records.isEmpty
    }

    private func fetchUserRecord(email: String) async throws -> CKRecord? {
        let query = CKQuery(recordType: "User", predicate: NSPredicate(format: "email == %@", email))
        let records = try await performQuery(query, resultsLimit: 1)
        return records.first
    }

    private func performQuery(_ query: CKQuery, resultsLimit: Int) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKQueryOperation(query: query)
            operation.resultsLimit = resultsLimit
            var records: [CKRecord] = []
            var didResume = false

            func resume(_ result: Result<[CKRecord], Error>) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            operation.recordMatchedBlock = { _, result in
                switch result {
                case let .success(record):
                    records.append(record)
                case let .failure(error):
                    resume(.failure(error))
                }
            }

            operation.queryResultBlock = { result in
                switch result {
                case .success:
                    resume(.success(records))
                case let .failure(error):
                    resume(.failure(error))
                }
            }

            database.add(operation)
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
}

@MainActor
final class AuthenticationCoordinator: ObservableObject {
    private enum StorageKeys {
        static let appleUserID = "auth.appleUserID"
        static let email = "auth.email"
        static let displayName = "auth.displayName"
    }

    @Published private(set) var isAuthenticated = false
    @Published private(set) var isRestoringSession = false
    @Published private(set) var emailAddress: String?
    @Published private(set) var displayName = ""
    @Published private(set) var currentRole: AppRole?
    @Published var errorMessage: String?

    private var hasAttemptedRestore = false

    func restoreSessionIfNeeded(navigationState: AppNavigationState) async {
        guard !hasAttemptedRestore else { return }
        hasAttemptedRestore = true
        isRestoringSession = true
        defer { isRestoringSession = false }

        guard let appleUserID = UserDefaults.standard.string(forKey: StorageKeys.appleUserID) else {
            navigationState.clearAuthenticatedRole()
            return
        }

        let credentialState: ASAuthorizationAppleIDProvider.CredentialState
        do {
            credentialState = try await credentialState(for: appleUserID)
        } catch {
            errorMessage = error.localizedDescription
            navigationState.clearAuthenticatedRole()
            return
        }

        guard credentialState == .authorized else {
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

            Task {
                await applyAuthenticatedUser(
                    appleUserID: credential.user,
                    email: resolvedEmail,
                    displayName: resolvedDisplayName,
                    navigationState: navigationState
                )
            }
        }
    }

    func sendInvite(email: String, role: AppRole) async throws -> CloudUserProfile {
        try await CloudKitUserAccessService.shared.inviteUser(email: email, role: role)
    }

    func signOut(navigationState: AppNavigationState) {
        UserDefaults.standard.removeObject(forKey: StorageKeys.appleUserID)
        UserDefaults.standard.removeObject(forKey: StorageKeys.email)
        UserDefaults.standard.removeObject(forKey: StorageKeys.displayName)

        isAuthenticated = false
        emailAddress = nil
        displayName = ""
        currentRole = nil
        errorMessage = nil

        navigationState.clearAuthenticatedRole()
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
            let profile = try await CloudKitUserAccessService.shared.resolveProfile(
                email: normalizedEmail,
                displayName: displayName
            )

            UserDefaults.standard.set(appleUserID, forKey: StorageKeys.appleUserID)
            UserDefaults.standard.set(profile.email, forKey: StorageKeys.email)
            UserDefaults.standard.set(profile.displayName, forKey: StorageKeys.displayName)

            isAuthenticated = true
            emailAddress = profile.email
            self.displayName = profile.displayName
            currentRole = profile.role
            errorMessage = nil

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
                } else {
                    SignInWithAppleButton(.continue) { request in
                        authCoordinator.prepare(request)
                    } onCompletion: { result in
                        authCoordinator.handleCompletion(result, navigationState: navigationState)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
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
