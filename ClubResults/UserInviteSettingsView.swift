import SwiftUI

struct UserInviteSettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var authCoordinator: AuthenticationCoordinator
    @EnvironmentObject private var navigationState: AppNavigationState

    @State private var email = ""
    @State private var selectedRole: AppRole = .supporter
    @State private var isSendingInvite = false
    @State private var confirmationMessage: String?
    @State private var errorMessage: String?
    @State private var invitedUsers: [InvitedUserAccount] = []
    @State private var isLoadingUsers = false
    @State private var editingUser: InvitedUserAccount?
    @State private var deletingUser: InvitedUserAccount?

    private var isAdminRole: Bool {
        navigationState.currentRole == .admin
    }

    var body: some View {
        Form {
            Section("Invite Details") {
                TextField("email@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Picker("Role", selection: $selectedRole) {
                    ForEach(AppRole.allCases) { role in
                        Text(role.title).tag(role)
                    }
                }
            }

            Section {
                Button {
                    sendInvite()
                } label: {
                    HStack {
                        if isSendingInvite {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                        Text(isSendingInvite ? "Sending Invite…" : "Send Invite")
                    }
                }
                .disabled(isSendingInvite || normalizedEmail.isEmpty)
            } footer: {
                Text("This creates or updates a CloudKit `User` record, then opens a prefilled email invite.")
                    .foregroundStyle(.secondary)
            }

            if isAdminRole {
                invitedUsersSection
            }

            if let confirmationMessage {
                Section("Status") {
                    Text(confirmationMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("User Invites")
        .task {
            guard isAdminRole else { return }
            await loadInvitedUsers()
        }
        .refreshable {
            guard isAdminRole else { return }
            await loadInvitedUsers()
        }
        .sheet(item: $editingUser) { user in
            NavigationStack {
                InvitedUserEditView(user: user) { selectedRole in
                    await updateRole(for: user, role: selectedRole)
                }
            }
        }
        .alert(
            "Invite Failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .alert(
            "Remove User?",
            isPresented: Binding(
                get: { deletingUser != nil },
                set: { if !$0 { deletingUser = nil } }
            ),
            presenting: deletingUser
        ) { user in
            Button("Remove", role: .destructive) {
                remove(user: user)
            }
            Button("Cancel", role: .cancel) {
                deletingUser = nil
            }
        } message: { user in
            Text("Remove \(user.email) from invited users?")
        }
    }

    @ViewBuilder
    private var invitedUsersSection: some View {
        Section {
            if isLoadingUsers && invitedUsers.isEmpty {
                HStack {
                    ProgressView()
                    Text("Loading invited users…")
                        .foregroundStyle(.secondary)
                }
            } else if invitedUsers.isEmpty {
                ContentUnavailableView(
                    "No invited users",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Invited users will appear here once you send an invite.")
                )
            } else {
                ForEach(invitedUsers) { user in
                    HStack(spacing: 12) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(user.hasSignedIn ? .green : .orange)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.email)
                            Text(userDetailText(for: user))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingUser = user
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) {
                            deletingUser = user
                        }

                        Button("Edit") {
                            editingUser = user
                        }
                        .tint(.blue)
                    }
                }
            }
        } header: {
            Text("Invited Users")
        } footer: {
            Text("Green means the user has signed in. Orange means they have been invited but have not signed in yet.")
                .foregroundStyle(.secondary)
        }
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func userDetailText(for user: InvitedUserAccount) -> String {
        let displayName = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let signedInText: String
        if let lastSignedInAt = user.lastSignedInAt {
            signedInText = "Signed in \(lastSignedInAt.formatted(date: .abbreviated, time: .shortened))"
        } else {
            signedInText = "Invited, not signed in"
        }

        if displayName.isEmpty {
            return "\(user.role.title) • \(signedInText)"
        }

        return "\(displayName) • \(user.role.title) • \(signedInText)"
    }

    private func sendInvite() {
        guard !normalizedEmail.isEmpty else { return }
        isSendingInvite = true
        confirmationMessage = nil

        Task {
            defer { isSendingInvite = false }

            do {
                let profile = try await authCoordinator.sendInvite(email: normalizedEmail, role: selectedRole)
                let body = """
                You have been invited to ClubResults as \(profile.role.title).

                Sign in with Apple using \(profile.email) to load your access role.
                """
                openMailInvite(to: profile.email, body: body)
                confirmationMessage = "Invite saved for \(profile.email) as \(profile.role.title)."
                email = ""
                selectedRole = .supporter
                if isAdminRole {
                    await loadInvitedUsers()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func loadInvitedUsers() async {
        isLoadingUsers = true
        defer { isLoadingUsers = false }

        do {
            invitedUsers = try await authCoordinator.fetchInvitedUsers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateRole(for user: InvitedUserAccount, role: AppRole) async {
        do {
            let updatedUser = try await authCoordinator.updateInvitedUserRole(email: user.email, role: role)
            await MainActor.run {
                if let index = invitedUsers.firstIndex(where: { $0.id == updatedUser.id }) {
                    invitedUsers[index] = updatedUser
                }
                confirmationMessage = "Updated \(updatedUser.email) to \(updatedUser.role.title)."
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func remove(user: InvitedUserAccount) {
        deletingUser = nil

        Task {
            do {
                try await authCoordinator.removeInvitedUser(email: user.email)
                await MainActor.run {
                    invitedUsers.removeAll { $0.id == user.id }
                    confirmationMessage = "Removed \(user.email)."
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func openMailInvite(to recipient: String, body: String) {
        let subject = "ClubResults Invite"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        let encodedRecipient = recipient.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? recipient

        guard let url = URL(string: "mailto:\(encodedRecipient)?subject=\(encodedSubject)&body=\(encodedBody)") else {
            return
        }

        openURL(url)
    }
}

private struct InvitedUserEditView: View {
    @Environment(\.dismiss) private var dismiss

    let user: InvitedUserAccount
    let onSave: (AppRole) async -> Void

    @State private var selectedRole: AppRole
    @State private var isSaving = false

    init(user: InvitedUserAccount, onSave: @escaping (AppRole) async -> Void) {
        self.user = user
        self.onSave = onSave
        _selectedRole = State(initialValue: user.role)
    }

    var body: some View {
        Form {
            Section("User") {
                Text(user.email)
                if !user.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(user.displayName)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Role") {
                Picker("Role", selection: $selectedRole) {
                    ForEach(AppRole.allCases) { role in
                        Text(role.title).tag(role)
                    }
                }
                .pickerStyle(.inline)
            }
        }
        .navigationTitle("Edit User")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    isSaving = true
                    Task {
                        await onSave(selectedRole)
                        await MainActor.run {
                            isSaving = false
                            dismiss()
                        }
                    }
                }
                .disabled(isSaving || selectedRole == user.role)
            }
        }
    }
}
