import SwiftUI
import SwiftData
import PDFKit
import MessageUI
import UIKit
import UniformTypeIdentifiers
import CloudKit

struct SettingsView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext
    @EnvironmentObject private var navigationState: AppNavigationState
    @EnvironmentObject private var authCoordinator: AuthenticationCoordinator
    @AppStorage("settings.open.contacts") private var shouldOpenContacts = false
    @State private var saveErrorMessage: String?
    @State private var showContactsSettings = false
    @State private var showProfileSheet = false
    @State private var showCloudSyncSheet = false
    var resetToken: UUID = UUID()

    var body: some View {
        NavigationStack {
            List {
                settingsSection

                if !navigationState.currentRole.showsSupporterSettingsOnly &&
                    !navigationState.currentRole.showsTeamManagerSettingsOnly &&
                    !navigationState.currentRole.showsCoachSettingsOnly {
                    adminSection
                }
            }
            .clubGlassBackground()
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("Settings")
            .iPhoneTransparentTopChrome()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    profileButton
                }

                if navigationState.canPreviewRoles {
                    ToolbarItem(placement: .topBarTrailing) {
                        viewAsMenu
                    }
                }
            }
            .navigationDestination(isPresented: $showContactsSettings) {
                ContactsSettingsView()
                    .clubGlassBackground()
            }
            .sheet(isPresented: $showProfileSheet) {
                NavigationStack {
                    ProfileSheetView()
                }
                .clubGlassBackground()
            }
            .sheet(isPresented: $showCloudSyncSheet) {
                NavigationStack {
                    CloudSyncSheet()
                }
            }
            .task {
                seedInitialGradesIfNeeded()
                seedDefaultStatTypesIfNeeded()
            }
            .onAppear {
                guard shouldOpenContacts else { return }
                shouldOpenContacts = false
                showContactsSettings = true
            }
            .alert(
                "Save Error",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    saveErrorMessage = nil
                }
            } message: {
                Text(saveErrorMessage ?? "An unknown error occurred.")
            }
        }
        .toolbarBackground(UIDevice.current.userInterfaceIdiom == .phone ? .hidden : .automatic, for: .navigationBar)
        .id(resetToken)
    }


    private var settingsSection: some View {
        Section("Settings") {
            if navigationState.currentRole.showsSupporterSettingsOnly {
                settingsLink("App Appearance", icon: "circle.lefthalf.filled", destination: AnyView(AppAppearanceSettingsView()))
            } else if navigationState.currentRole.showsTeamManagerSettingsOnly {
                settingsLink("Players", icon: "person.3", destination: AnyView(PlayersView()))
                settingsLink("App Appearance", icon: "circle.lefthalf.filled", destination: AnyView(AppAppearanceSettingsView()))
            } else if navigationState.currentRole.showsCoachSettingsOnly {
                settingsLink("App Appearance", icon: "circle.lefthalf.filled", destination: AnyView(AppAppearanceSettingsView()))
            } else {
                settingsLink("Club Grades", icon: "person.3.fill", destination: AnyView(ClubGradesSettingsView()))
                settingsLink("Players", icon: "person.3", destination: AnyView(PlayersView()))
                if !navigationState.currentRole.hasRestrictedAdminSettings {
                    settingsLink("Stats Settings", icon: "chart.xyaxis.line", destination: AnyView(StatsTypesSettingsView()))
                }
                settingsLink("Stats View", icon: "rectangle.grid.2x2.fill", destination: AnyView(StatsInvitePreviewSettingsView()))
                settingsLink("Umpires", icon: "flag.pattern.checkered", destination: AnyView(UmpiresSettingsView()))
                settingsLink("App Appearance", icon: "circle.lefthalf.filled", destination: AnyView(AppAppearanceSettingsView()))
                settingsLink("Teams & Venues", icon: "flag.2.crossed", destination: AnyView(TeamsAndVenuesSettingsView()))
                settingsLink("Contacts", icon: "person.crop.circle.badge.checkmark", destination: AnyView(ContactsSettingsView()))
                settingsLink("Groups", icon: "person.3.sequence", destination: AnyView(GroupsSettingsView()))
                settingsLink(
                    "Reports",
                    icon: "doc.text",
                    destination: AnyView(ReportsSettingsView {
                        shouldOpenContacts = true
                    })
                )
                if !navigationState.currentRole.hasRestrictedAdminSettings {
                    settingsLink("AI Master of Ceremonies", icon: "waveform.badge.mic", destination: AnyView(AIMasterOfCeremoniesSettingsView()))
                }
            }
        }
    }

    private var adminSection: some View {
        Section("Admin") {
            settingsLink("Roles", icon: "person.crop.rectangle.stack.fill", destination: AnyView(RolesSettingsView()))
            if navigationState.currentRole.canManageInvites {
                settingsLink("User Invites", icon: "person.badge.plus", destination: AnyView(UserInviteSettingsView()))
            }
            if !navigationState.currentRole.hasRestrictedAdminSettings {
                Button {
                    showCloudSyncSheet = true
                } label: {
                    HStack(spacing: 12) {
                        settingsRow(title: "Cloud Sync", icon: "arrow.triangle.2.circlepath.icloud")
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                settingsLink("Clear Saved Picker Names", icon: "trash", destination: AnyView(AdminNameResetView()))
                settingsLink("Backup & Restore", icon: "externaldrive.badge.icloud", destination: AnyView(BackupAndRestoreSettingsView()))
                settingsLink("PIN Code", icon: "number.square", destination: AnyView(PinCodeSettingsView()))
            }
        }
    }

    private var profileButton: some View {
        Button {
            showProfileSheet = true
        } label: {
            Image(systemName: "person.crop.circle")
        }
        .accessibilityLabel("Profile")
    }

    private func settingsLink(
        _ title: String,
        icon: String,
        destination: AnyView
    ) -> some View {
        NavigationLink {
            destination
                .clubGlassBackground()
        } label: {
            settingsRow(title: title, icon: icon)
        }
    }

    private let settingsIconColumnWidth: CGFloat = 40

    @ViewBuilder
    private func settingsRow(title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: settingsIconColumnWidth, alignment: .leading)
            Text(title)
        }
    }

    private var viewAsMenu: some View {
        Menu {
            ForEach(AppRole.allCases) { role in
                Button {
                    navigationState.setPreviewRole(role)
                } label: {
                    if role == navigationState.currentRole {
                        Label(role.title, systemImage: "checkmark")
                    } else {
                        Text(role.title)
                    }
                }
            }
        } label: {
            Label(navigationState.currentRole.title, systemImage: navigationState.currentRole.icon)
                .labelStyle(.titleAndIcon)
        }
    }

    private func seedInitialGradesIfNeeded() {
        LockedGradeSeed.ensureGradesExist(modelContext: dataContext)
    }
    private func seedDefaultStatTypesIfNeeded() {
        let existing = (try? dataContext.fetch(FetchDescriptor<StatType>())) ?? []
        guard existing.isEmpty else { return }

        for (index, name) in ["Kick", "Handball", "Mark", "Tackle", "Goal", "Behind"].enumerated() {
            dataContext.insert(StatType(name: name, isEnabled: true, sortOrder: index))
        }

        do {
            try dataContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}

private struct CloudSyncSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("cloud.sync.lastDate") private var cloudSyncLastDateInterval: Double = 0
    @State private var isSyncing = false
    @State private var syncMessage: String?
    @State private var syncSummary: String?
    @State private var accountStatus: CKAccountStatus = .couldNotDetermine
    @State private var diagnostics = CloudSyncedPreferencesDiagnostics(
        dataKeysInCloud: 0,
        stringKeysInCloud: 0,
        boolKeysInCloud: 0,
        hasFullBackupInCloud: false
    )
    @State private var showSyncProgressPopup = false
    @State private var syncPhaseMessage = "Preparing sync..."
    @State private var showSyncSummaryPopup = false
    @State private var syncSummaryPopupBody = ""

    private var lastSyncDate: Date? {
        guard cloudSyncLastDateInterval > 0 else { return nil }
        return Date(timeIntervalSince1970: cloudSyncLastDateInterval)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("iCloud Account") {
                    Text(accountStatusText)
                        .foregroundStyle(accountStatusColor)
                }
                LabeledContent("Environment") {
                    Text(cloudEnvironmentLabel)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Last Sync") {
                    Text(lastSyncDate?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                        .foregroundStyle(.secondary)
                }

            } header: {
                Text("CloudKit")
            } footer: {
                Text(syncMessage ?? "Forces a local save and CloudKit refresh for account sync.")
                    .foregroundStyle(.secondary)
                if let syncSummary {
                    Text(syncSummary)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sync Diagnostics") {
                LabeledContent("Data Keys in Cloud") {
                    Text("\(diagnostics.dataKeysInCloud)/\(CloudSyncedPreferenceKeys.dataKeys.count)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("String Keys in Cloud") {
                    Text("\(diagnostics.stringKeysInCloud)/\(CloudSyncedPreferenceKeys.stringKeys.count)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Bool Keys in Cloud") {
                    Text("\(diagnostics.boolKeysInCloud)/\(CloudSyncedPreferenceKeys.boolKeys.count)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Full Backup Snapshot") {
                    Text(diagnostics.hasFullBackupInCloud ? "Available" : "Missing")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Total Keys in Cloud") {
                    Text("\(diagnostics.totalKeysInCloud)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            await refreshCloudAccountStatus()
            refreshDiagnostics()
        }
        .refreshable {
            await refreshCloudAccountStatus()
            refreshDiagnostics()
        }
        .navigationTitle("Cloud Sync")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSyncing ? "Syncing..." : "Sync Now") {
                    forceSyncNow()
                }
                .disabled(isSyncing)
            }
        }
        .overlay {
            if showSyncProgressPopup {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        LoadingFootballView(size: 42)
                        Text("Syncing Cloud Data")
                            .font(.headline)
                        Text(syncPhaseMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .frame(maxWidth: 320)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .alert("Sync Complete", isPresented: $showSyncSummaryPopup) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(syncSummaryPopupBody)
        }
    }

    private var accountStatusText: String {
        switch accountStatus {
        case .available:
            return "Connected"
        case .noAccount:
            return "Not Signed In"
        case .restricted:
            return "Restricted"
        case .temporarilyUnavailable:
            return "Temporarily Unavailable"
        case .couldNotDetermine:
            return "Unknown"
        @unknown default:
            return "Unknown"
        }
    }

    private var accountStatusColor: Color {
        switch accountStatus {
        case .available:
            return .green
        case .noAccount, .restricted, .temporarilyUnavailable:
            return .orange
        case .couldNotDetermine:
            return .secondary
        @unknown default:
            return .secondary
        }
    }

    private var cloudEnvironmentLabel: String {
#if DEBUG
        return "Development"
#else
        return "Production"
#endif
    }

    private struct SyncSnapshot {
        let players: Int
        let games: Int
        let grades: Int
        let contacts: Int
        let reports: Int
        let statTypes: Int
        let sessions: Int
        let events: Int

        var description: String {
            "Players \(players), Games \(games), Grades \(grades), Contacts \(contacts), Reports \(reports), Stat Types \(statTypes), Sessions \(sessions), Events \(events)"
        }
    }

    private func captureSnapshot() -> SyncSnapshot {
        let players = (try? modelContext.fetch(FetchDescriptor<Player>()))?.count ?? 0
        let games = (try? modelContext.fetch(FetchDescriptor<Game>()))?.count ?? 0
        let grades = (try? modelContext.fetch(FetchDescriptor<Grade>()))?.count ?? 0
        let contacts = (try? modelContext.fetch(FetchDescriptor<Contact>()))?.count ?? 0
        let reports = (try? modelContext.fetch(FetchDescriptor<CustomReportTemplate>()))?.count ?? 0
        let statTypes = (try? modelContext.fetch(FetchDescriptor<StatType>()))?.count ?? 0
        let sessions = (try? modelContext.fetch(FetchDescriptor<StatsSession>()))?.count ?? 0
        let events = (try? modelContext.fetch(FetchDescriptor<StatEvent>()))?.count ?? 0
        return SyncSnapshot(
            players: players,
            games: games,
            grades: grades,
            contacts: contacts,
            reports: reports,
            statTypes: statTypes,
            sessions: sessions,
            events: events
        )
    }

    private func refreshCloudAccountStatus() async {
        accountStatus = await CloudKitStatsInviteService.shared.accountStatus()
    }

    private func refreshDiagnostics() {
        diagnostics = CloudSyncedPreferencesStore.diagnostics()
    }

    private func importSummary(before: SyncSnapshot, pulled: SyncSnapshot, after: SyncSnapshot) -> String {
        let beforeEntityTotal = before.players + before.games + before.contacts + before.reports + before.sessions + before.events
        let afterEntityTotal = after.players + after.games + after.contacts + after.reports + after.sessions + after.events

        if afterEntityTotal > beforeEntityTotal {
            let delta = afterEntityTotal - beforeEntityTotal
            return "Entity import: +\(delta) records pulled from cloud."
        }

        if afterEntityTotal == 0 && pulled.players == 0 && pulled.games == 0 && pulled.contacts == 0 && pulled.reports == 0 && pulled.sessions == 0 && pulled.events == 0 {
            return "Entity import: no cloud entity data received. Check iCloud account, CloudKit environment (Development/Production), and whether this environment has uploaded entity records."
        }

        return "Entity import: no new entity changes detected during this sync window."
    }

    private func forceSyncNow() {
        guard !isSyncing else { return }
        isSyncing = true
        showSyncProgressPopup = true
        syncPhaseMessage = "Pulling latest CloudKit changes..."
        syncMessage = "Pulling latest CloudKit changes..."
        syncSummary = nil

        let before = captureSnapshot()

        Task { @MainActor in
            do {
                // Pull phase: wait for inbound sync windows, then restore or merge the cloud backup snapshot.
                try modelContext.save()
                try await CloudKitStatsInviteService.shared.ensureTallySubscription()
                await refreshCloudAccountStatus()
                try await Task.sleep(nanoseconds: 1_500_000_000)
                try modelContext.save()
                let fullBackupSyncResult = try await CloudFullBackupSyncService.syncFullBackupSnapshot(modelContext: modelContext)
                let pulled = await MainActor.run { captureSnapshot() }
                let hasLocalUserData = CloudFullBackupSyncService.localUserDataCount(modelContext: modelContext) > 0
                let pushResult: String

                // Push phase: upload settings plus a full backup snapshot when local user data exists.
                await MainActor.run {
                    syncPhaseMessage = "Uploading full backup snapshot..."
                }
                if hasLocalUserData {
                    CloudSyncedPreferencesStore.pushAllLocalPreferencesToCloud()
                    pushResult = "Preference upload: completed."
                    try modelContext.save()
                } else {
                    pushResult = "Preference upload: skipped because this device has no user data."
                }

                await MainActor.run {
                    syncPhaseMessage = "Finalizing sync summary..."
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
                try modelContext.save()

                let after = await MainActor.run { captureSnapshot() }
                let now = Date()
                await MainActor.run {
                    cloudSyncLastDateInterval = now.timeIntervalSince1970
                    let restoreSummary: String
                    switch fullBackupSyncResult.action {
                    case .restored:
                        let counts = fullBackupSyncResult.itemCounts
                        restoreSummary = "Full app restore from cloud: completed (\(counts?.players ?? 0) players, \(counts?.games ?? 0) games, \(counts?.grades ?? 0) grades)."
                    case .uploaded:
                        let counts = fullBackupSyncResult.itemCounts
                        restoreSummary = "Full app upload to cloud: completed (\(counts?.players ?? 0) players, \(counts?.games ?? 0) games, \(counts?.grades ?? 0) grades)."
                    case .unchanged:
                        restoreSummary = "Full app sync: no new changes detected."
                    case .noCloudBackup:
                        restoreSummary = "Full app sync: no cloud backup available."
                    }
                    let entityImportResult = importSummary(before: before, pulled: pulled, after: after)
                    syncMessage = "Synced \(now.formatted(date: .abbreviated, time: .shortened))"
                    syncSummary = "\(restoreSummary)\n\(entityImportResult)\n\(pushResult)\n\nBefore: \(before.description)\nPulled/Restored: \(pulled.description)\nAfter: \(after.description)"
                    syncSummaryPopupBody = "\(restoreSummary)\n\(entityImportResult)\n\(pushResult)\n\nEnvironment: \(cloudEnvironmentLabel)\n\nBefore:\n\(before.description)\n\nAfter:\n\(after.description)"
                    refreshDiagnostics()
                    showSyncProgressPopup = false
                    showSyncSummaryPopup = true
                    isSyncing = false
                }
            } catch {
                await MainActor.run {
                    syncMessage = "Sync failed: \(error.localizedDescription)"
                    syncSummaryPopupBody = "Sync failed.\n\n\(error.localizedDescription)"
                    refreshDiagnostics()
                    showSyncProgressPopup = false
                    showSyncSummaryPopup = true
                    isSyncing = false
                }
            }
        }
    }
}

private struct ProfileSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigationState: AppNavigationState
    @EnvironmentObject private var authCoordinator: AuthenticationCoordinator

    var body: some View {
        List {
            Section {
                LabeledContent("Signed In") {
                    Text(authCoordinator.emailAddress ?? "No")
                        .foregroundStyle(.secondary)
                }

                if let role = authCoordinator.currentRole {
                    LabeledContent("Role") {
                        Text(role.title)
                            .foregroundStyle(.secondary)
                    }
                }

                if authCoordinator.isAuthenticated {
                    Button("Sign Out", role: .destructive) {
                        authCoordinator.signOut(navigationState: navigationState)
                        dismiss()
                    }
                }

                if authCoordinator.isAuthenticated, authCoordinator.currentRole != .admin {
                    Button("Recover Admin Access") {
                        authCoordinator.enableAdminRecoveryOnNextSignIn(navigationState: navigationState)
                        dismiss()
                    }
                }
            } header: {
                Text("Access")
            } footer: {
                Text("Invites must use the same email address returned by Sign in with Apple.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Profile")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

private struct RolesSettingsView: View {
    @EnvironmentObject private var navigationState: AppNavigationState

    var body: some View {
        List {
            Section {
                ForEach(AppRole.allCases) { role in
                    Button {
                        navigationState.setPreviewRole(role)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: role.icon)
                                .foregroundStyle(.tint)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(role.title)
                                Text(role.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if role == navigationState.currentRole {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
            } header: {
                Text("View As")
            } footer: {
                Text("Use this to preview the app as each role.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Roles")
    }
}

private struct BackupAndRestoreSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var shareURL: URL?
    @State private var exportSuccessMessage: String?
    @State private var exportErrorMessage: String?
    @State private var isExporting = false
    @State private var isImportPickerPresented = false
    @State private var pendingImportURL: URL?
    @State private var pendingImportEnvelope: AppBackupEnvelope?
    @State private var importSuccessMessage: String?
    @State private var importErrorMessage: String?
    @State private var isImporting = false

    private var isShareSheetPresented: Binding<Bool> {
        Binding(
            get: { shareURL != nil },
            set: { shouldPresent in
                if !shouldPresent {
                    shareURL = nil
                }
            }
        )
    }

    private var isExportErrorPresented: Binding<Bool> {
        Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )
    }

    private var isReplaceDataConfirmPresented: Binding<Bool> {
        Binding(
            get: { pendingImportEnvelope != nil && pendingImportURL != nil },
            set: { shouldPresent in
                if !shouldPresent {
                    pendingImportEnvelope = nil
                    pendingImportURL = nil
                }
            }
        )
    }

    private var isImportErrorPresented: Binding<Bool> {
        Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )
    }

    var body: some View {
        Form {
            Section {
                Text("Creates a full backup file of all saved data so it can be stored safely before updates or major changes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    exportAllData()
                } label: {
                    HStack {
                        if isExporting {
                            LoadingFootballView(size: 18)
                        }
                        Text(isExporting ? "Creating Backup…" : "Export All Data")
                    }
                }
                .disabled(isExporting)

                Button(role: .destructive) {
                    isImportPickerPresented = true
                } label: {
                    HStack {
                        if isImporting {
                            LoadingFootballView(size: 18)
                        }
                        Text(isImporting ? "Importing…" : "Import Backup File")
                    }
                }
                .disabled(isImporting || isExporting)
            } header: {
                Text("Data Safety")
            } footer: {
                if let exportSuccessMessage {
                    Text(exportSuccessMessage)
                        .foregroundStyle(.secondary)
                } else if let importSuccessMessage {
                    Text(importSuccessMessage)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Export creates a full JSON backup. Import restores a backup and replaces all current app data.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Backup & Restore")
        .fileImporter(
            isPresented: $isImportPickerPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportSelection(result)
        }
        .sheet(isPresented: isShareSheetPresented) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
        .alert(
            "Export Failed",
            isPresented: isExportErrorPresented
        ) {
            Button("OK", role: .cancel) {
                exportErrorMessage = nil
            }
        } message: {
            Text(exportErrorMessage ?? "An unknown error occurred.")
        }
        .alert(
            "Replace Existing Data?",
            isPresented: isReplaceDataConfirmPresented
        ) {
            Button("Cancel", role: .cancel) {
                pendingImportEnvelope = nil
                pendingImportURL = nil
            }
            Button("Import", role: .destructive) {
                confirmImport()
            }
        } message: {
            if let envelope = pendingImportEnvelope {
                Text(
                    """
                    This will replace all current data with the selected backup.

                    Players: \(envelope.itemCounts.players)
                    Games: \(envelope.itemCounts.games)
                    Grades: \(envelope.itemCounts.grades)
                    Contacts: \(envelope.itemCounts.contacts)
                    Contact Groups: \(envelope.itemCounts.contactGroups)
                    Contact Group Links: \(envelope.itemCounts.contactGroupMemberships)
                    Contact Sections: \(envelope.itemCounts.contactSectionMemberships)
                    Report Recipients: \(envelope.itemCounts.reportRecipients)
                    Report Recipient Groups: \(envelope.itemCounts.reportRecipientGroups)
                    Custom Report Templates: \(envelope.itemCounts.customReportTemplates)
                    Custom Report Sections: \(envelope.itemCounts.customReportRecipientSections)
                    Custom Report Groups: \(envelope.itemCounts.customReportRecipientGroups)
                    Custom Report Contacts: \(envelope.itemCounts.customReportRecipientContacts)
                    Staff Members: \(envelope.itemCounts.staffMembers)
                    Staff Defaults: \(envelope.itemCounts.staffDefaults)
                    Opposition Clubs: \(envelope.itemCounts.oppositionClubs)
                    NES Stats Sessions: \(envelope.itemCounts.statsSessions)
                    NES Stat Events: \(envelope.itemCounts.statEvents)
                    Exported: \(envelope.exportedAt.formatted(date: .abbreviated, time: .shortened))
                    """
                )
            }
        }
        .alert(
            "Import Failed",
            isPresented: isImportErrorPresented
        ) {
            Button("OK", role: .cancel) {
                importErrorMessage = nil
            }
        } message: {
            Text(importErrorMessage ?? "An unknown error occurred.")
        }
    }

    private func exportAllData() {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }

        do {
            let result = try AppBackupService.createFullBackupFile(modelContext: modelContext)
            shareURL = result.fileURL
            exportSuccessMessage = """
            Backup ready: \(result.fileURL.lastPathComponent)
            \(ByteCountFormatter.string(fromByteCount: Int64(result.fileSizeBytes), countStyle: .file)) • \
            \(result.itemCounts.players) players • \(result.itemCounts.games) games • \(result.itemCounts.grades) grades • \
            \(result.itemCounts.contacts) contacts • \(result.itemCounts.contactGroups) groups • \
            \(result.itemCounts.statsSessions) NES sessions • \(result.itemCounts.statEvents) NES events
            """
            importSuccessMessage = nil
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            do {
                guard url.startAccessingSecurityScopedResource() else {
                    throw AppBackupImportError.invalidFileType
                }
                defer { url.stopAccessingSecurityScopedResource() }
                pendingImportEnvelope = try AppBackupService.previewBackupFile(url: url)
                pendingImportURL = url
            } catch {
                importErrorMessage = error.localizedDescription
            }
        case let .failure(error):
            importErrorMessage = error.localizedDescription
        }
    }

    private func confirmImport() {
        guard let url = pendingImportURL else { return }
        pendingImportEnvelope = nil
        pendingImportURL = nil

        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        do {
            guard url.startAccessingSecurityScopedResource() else {
                throw AppBackupImportError.invalidFileType
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let result = try AppBackupService.importFullBackupFile(url: url, modelContext: modelContext)
            importSuccessMessage = """
            Backup imported on \(result.importedAt.formatted(date: .abbreviated, time: .shortened))
            \(result.itemCounts.players) players • \(result.itemCounts.games) games • \(result.itemCounts.grades) grades • \
            \(result.itemCounts.contacts) contacts • \(result.itemCounts.contactGroups) groups • \
            \(result.itemCounts.statsSessions) NES sessions • \(result.itemCounts.statEvents) NES events
            """
            exportSuccessMessage = nil
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }
}

private struct AdminNameResetView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext
    @Query private var grades: [Grade]
    @Query private var staffMembers: [StaffMember]

    @State private var selectedGradeIDs: Set<UUID> = []
    @State private var selectedPickerTypes: Set<AdminPickerType> = Set(AdminPickerType.allCases)
    @State private var showConfirmClear = false
    @State private var clearFeedbackMessage: String?

    private var orderedGrades: [Grade] {
        orderedGradesForDisplay(resolvedConfiguredGrades(from: grades), includeInactive: true)
    }

    private var canClear: Bool {
        !selectedGradeIDs.isEmpty && !selectedPickerTypes.isEmpty
    }

    var body: some View {
        List {
            Section {
                if orderedGrades.isEmpty {
                    Text("No grades available.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(orderedGrades) { grade in
                        Button {
                            toggleGrade(grade.id)
                        } label: {
                            checkboxRow(
                                title: grade.name,
                                isSelected: selectedGradeIDs.contains(grade.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Grades")
            } footer: {
                if !orderedGrades.isEmpty {
                    sectionBulkSelectionControls(
                        onSelectAll: selectAllGrades,
                        onUnselectAll: unselectAllGrades
                    )
                }
            }

            Section {
                ForEach(AdminPickerType.allCases) { pickerType in
                    Button {
                        togglePickerType(pickerType)
                    } label: {
                        checkboxRow(
                            title: pickerType.title,
                            isSelected: selectedPickerTypes.contains(pickerType)
                        )
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Pickers")
            } footer: {
                sectionBulkSelectionControls(
                    onSelectAll: selectAllPickerTypes,
                    onUnselectAll: unselectAllPickerTypes
                )
            }

            Section {
                Button("Clear Selected Names", role: .destructive) {
                    showConfirmClear = true
                }
                .disabled(!canClear)
            } footer: {
                if let clearFeedbackMessage {
                    Text(clearFeedbackMessage)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Select one or more grades and picker types, then clear.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Admin")
        .alert("Clear Saved Names?", isPresented: $showConfirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearSelections()
            }
        } message: {
            Text("This will remove saved picker names for the selected grades and picker types.")
        }
        .onAppear {
            if selectedGradeIDs.isEmpty {
                selectedGradeIDs = Set(orderedGrades.map(\.id))
            }
        }
    }

    private func toggleGrade(_ gradeID: UUID) {
        if selectedGradeIDs.contains(gradeID) {
            selectedGradeIDs.remove(gradeID)
        } else {
            selectedGradeIDs.insert(gradeID)
        }
    }

    private func togglePickerType(_ pickerType: AdminPickerType) {
        if selectedPickerTypes.contains(pickerType) {
            selectedPickerTypes.remove(pickerType)
        } else {
            selectedPickerTypes.insert(pickerType)
        }
    }

    private func selectAllGrades() {
        selectedGradeIDs = Set(orderedGrades.map(\.id))
    }

    private func unselectAllGrades() {
        selectedGradeIDs.removeAll()
    }

    private func selectAllPickerTypes() {
        selectedPickerTypes = Set(AdminPickerType.allCases)
    }

    private func unselectAllPickerTypes() {
        selectedPickerTypes.removeAll()
    }

    private func clearSelections() {
        guard canClear else { return }

        let selectedRoles = Set(selectedPickerTypes.map(\.role))
        let selectedLastSelectionFields: [String] = selectedPickerTypes.reduce(into: []) { result, pickerType in
            result.append(contentsOf: pickerType.lastSelectionFieldKeys)
        }
        let selectedGradeIDs = self.selectedGradeIDs

        let matchingStaffMembers = staffMembers.filter {
            selectedGradeIDs.contains($0.gradeID) && selectedRoles.contains($0.role)
        }

        for staffMember in matchingStaffMembers {
            dataContext.delete(staffMember)
        }

        for gradeID in selectedGradeIDs {
            for role in selectedRoles {
                let key = "staffPickerNames.\(gradeID.uuidString).\(role.rawValue)"
                UserDefaults.standard.removeObject(forKey: key)
            }
            for fieldKey in selectedLastSelectionFields {
                let key = "lastStaffSelection.\(gradeID.uuidString).\(fieldKey)"
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        do {
            try dataContext.save()
            let removedCount = matchingStaffMembers.count
            clearFeedbackMessage = "Cleared \(removedCount) saved name\(removedCount == 1 ? "" : "s")."
        } catch {
            clearFeedbackMessage = "Could not clear names: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func checkboxRow(title: String, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func sectionBulkSelectionControls(
        onSelectAll: @escaping () -> Void,
        onUnselectAll: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            Button("Select All", action: onSelectAll)
                .buttonStyle(.plain)
            Button("Unselect All", action: onUnselectAll)
                .buttonStyle(.plain)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.top, 8)
    }
}

private enum AdminPickerType: String, CaseIterable, Identifiable, Hashable {
    case headCoach
    case assistantCoach
    case teamManager
    case runner
    case goalUmpire
    case fieldUmpire
    case waterBoy
    case trainer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .headCoach: return "Head Coach"
        case .assistantCoach: return "Assistant Coach"
        case .teamManager: return "Team Manager"
        case .runner: return "Runner"
        case .goalUmpire: return "Goal Umpire"
        case .fieldUmpire: return "Field Umpire"
        case .waterBoy: return "Water"
        case .trainer: return "Trainers"
        }
    }

    var role: StaffRole {
        switch self {
        case .headCoach: return .headCoach
        case .assistantCoach: return .assistantCoach
        case .teamManager: return .teamManager
        case .runner: return .runner
        case .goalUmpire: return .goalUmpire
        case .fieldUmpire: return .fieldUmpire
        case .waterBoy: return .waterBoy
        case .trainer: return .trainer
        }
    }

    var lastSelectionFieldKeys: [String] {
        switch self {
        case .headCoach: return ["headCoach"]
        case .assistantCoach: return ["assistantCoach"]
        case .teamManager: return ["teamManager"]
        case .runner: return ["runner"]
        case .goalUmpire: return ["goalUmpire"]
        case .fieldUmpire: return ["fieldUmpire"]
        case .waterBoy: return ["waterBoy1", "waterBoy2", "waterBoy3", "waterBoy4"]
        case .trainer: return ["trainer1", "trainer2", "trainer3", "trainer4"]
        }
    }
}

private struct UmpiresSettingsView: View {
    @Query private var grades: [Grade]
    @State private var mappings: [UUID: [UUID]] = [:]

    private var orderedGrades: [Grade] {
        orderedGradesForDisplay(resolvedConfiguredGrades(from: grades), includeInactive: true)
    }

    var body: some View {
        List {
            Section {
                Text("Choose which grade lists provide names in the umpire duties picker. These selections control the names shown for Boundary Umpire 1, Boundary Umpire 2, Field Umpire, and Water 1-4.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(orderedGrades) { grade in
                NavigationLink {
                    boundaryGradeSelectionView(for: grade)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(grade.name)

                        Text(mappingSummary(for: grade.id))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Umpires")
        .task {
            mappings = SettingsBackupStore.loadBoundaryUmpireGradeMappings()
            ensureMissingMappingsDefaultToSelf()
            SettingsBackupStore.saveBoundaryUmpireGradeMappings(mappings)
        }
    }

    @ViewBuilder
    private func boundaryGradeSelectionView(for gameGrade: Grade) -> some View {
        List {
            ForEach(orderedGrades) { option in
                Button {
                    toggleBoundaryGrade(option.id, for: gameGrade.id)
                } label: {
                    HStack {
                        StandardListIcon(systemName: "person.3.fill")
                        Text(option.name)
                        Spacer()
                        if selectedBoundaryGradeIDs(for: gameGrade.id).contains(option.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .navigationTitle(gameGrade.name)
    }

    private func selectedBoundaryGradeIDs(for gameGradeID: UUID) -> [UUID] {
        let selected = mappings[gameGradeID] ?? [gameGradeID]
        if selected.isEmpty {
            return [gameGradeID]
        }
        return selected
    }

    private func toggleBoundaryGrade(_ boundaryGradeID: UUID, for gameGradeID: UUID) {
        var selected = selectedBoundaryGradeIDs(for: gameGradeID)
        if let index = selected.firstIndex(of: boundaryGradeID) {
            selected.remove(at: index)
        } else {
            selected.append(boundaryGradeID)
        }

        if selected.isEmpty {
            selected = [gameGradeID]
        }

        mappings[gameGradeID] = selected
        SettingsBackupStore.saveBoundaryUmpireGradeMappings(mappings)
    }

    private func mappingSummary(for gameGradeID: UUID) -> String {
        let selectedIDs = selectedBoundaryGradeIDs(for: gameGradeID)
        let selectedNames = orderedGrades
            .filter { selectedIDs.contains($0.id) }
            .map(\.name)

        if selectedNames.isEmpty {
            return "Umpires from: \(orderedGrades.first(where: { $0.id == gameGradeID })?.name ?? "This grade")"
        }

        return "Umpires from: \(selectedNames.joined(separator: ", "))"
    }

    private func ensureMissingMappingsDefaultToSelf() {
        for grade in orderedGrades {
            let selected = mappings[grade.id] ?? []
            mappings[grade.id] = selected.isEmpty ? [grade.id] : selected
        }
    }
}

private struct ClubGradesSettingsView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext

    @State private var grades: [Grade] = []
    @Query private var players: [Player]
    @Query private var games: [Game]
    @Query private var reportRecipients: [ReportRecipient]

    @State private var showAddGrade = false
    @State private var newGradeDraft = NewGradeDraft()

    @State private var gradeEditing: Grade?
    @State private var editGradeDraft = EditGradeDraft()
    @State private var showDiscardChangesAlert = false

    @State private var deletionErrorMessage: String?
    @State private var showDeletionError = false
    @State private var saveErrorMessage: String?

    private var sortedGrades: [Grade] {
        orderedGradesForDisplay(grades, includeInactive: true)
    }

    var body: some View {
        List {
            Section {
                ForEach(sortedGrades) { grade in
                    HStack {
                        StandardListIcon(systemName: "person.3.fill")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(grade.name)
                            if !grade.isActive {
                                Text("Inactive")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        gradeEditing = grade
                        editGradeDraft = EditGradeDraft(grade: grade)
                    }
                }
                .onMove(perform: moveGrades)

                Button {
                    newGradeDraft = NewGradeDraft()
                    showAddGrade = true
                } label: {
                    Label("Add Grade", systemImage: "plus")
                }
            } header: {
                Text("Grades")
            } footer: {
                Text("Grades are used in players, games and reports. Reorder to control display order.")
            }
        }
        .navigationTitle("Club Grades")
        .toolbar { EditButton() }
        .alert("Delete Error", isPresented: $showDeletionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deletionErrorMessage ?? "Unable to delete this grade.")
        }
        .alert(
            "Save Error",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
        .sheet(isPresented: $showAddGrade) {
            AddGradeWizardView(draft: $newGradeDraft) { draft in
                if addGrade(using: draft) {
                    showAddGrade = false
                }
            } onCancel: {
                showAddGrade = false
            }
            .appPopupStyle()
        }
        .sheet(item: $gradeEditing) { grade in
            NavigationStack {
                Form {
                    TextField("Grade name", text: $editGradeDraft.name)
                        .textInputAutocapitalization(.words)

                    Section {
                        Label("Coaching Staff", systemImage: "person.2.fill")
                            .font(.subheadline.weight(.semibold))
                        Toggle("Head Coach", isOn: bind(\.asksHeadCoach))
                        Toggle("Assistant Coach", isOn: bind(\.asksAssistantCoach))
                        Toggle("Team Manager", isOn: bind(\.asksTeamManager))
                        Toggle("Runner", isOn: bind(\.asksRunner))
                    } header: {
                        Text("New Game Wizard Fields")
                    }

                    Section {
                        Label("Officials", systemImage: "flag.fill")
                            .font(.subheadline.weight(.semibold))
                        Toggle("Goal Umpire", isOn: bind(\.asksGoalUmpire))
                        Toggle("Time Keeper", isOn: bind(\.asksTimeKeeper))
                        Toggle("Field Umpire", isOn: bind(\.asksFieldUmpire))
                        Toggle("Boundary Umpire 1", isOn: bind(\.asksBoundaryUmpire1))
                        Toggle("Boundary Umpire 2", isOn: bind(\.asksBoundaryUmpire2))
                        Toggle("Water 1", isOn: bind(\.asksWaterBoy1))
                        Toggle("Water 2", isOn: bind(\.asksWaterBoy2))
                        Toggle("Water 3", isOn: bind(\.asksWaterBoy3))
                        Toggle("Water 4", isOn: bind(\.asksWaterBoy4))
                    }

                    Section {
                        Label("Trainers", systemImage: "cross.case.fill")
                            .font(.subheadline.weight(.semibold))
                        Toggle("Trainer 1", isOn: bind(\.asksTrainer1))
                        Toggle("Trainer 2", isOn: bind(\.asksTrainer2))
                        Toggle("Trainer 3", isOn: bind(\.asksTrainer3))
                        Toggle("Trainer 4", isOn: bind(\.asksTrainer4))
                    }

                    Section {
                        let bestPlayersCountBinding = bind(\.bestPlayersCount)
                        let guestBestPlayersCountBinding = bind(\.guestBestPlayersCount)

                        Label("Awards", systemImage: "rosette")
                            .font(.subheadline.weight(.semibold))
                        Toggle("Score", isOn: bind(\.asksScore))
                        Toggle("Goal Kickers", isOn: bind(\.asksGoalKickers))
                        oneToTenPicker("Best Players", selection: bestPlayersCountBinding)
                        Toggle("Guest Best Players", isOn: bind(\.asksGuestBestFairestVotesScan))
                        if editGradeDraft.asksGuestBestFairestVotesScan {
                            oneToTenPicker("Guest Best Players Quantity", selection: guestBestPlayersCountBinding)
                        }
                    }

                    Section {
                        let bestPlayersCountBinding = bind(\.bestPlayersCount)
                        let guestBestPlayersCountBinding = bind(\.guestBestPlayersCount)
                        let bestPlayersVotesBinding = bind(\.bestPlayersVotes)
                        let guestBestPlayersVotesBinding = bind(\.guestBestPlayersVotes)

                        NavigationLink {
                            VoteAllocationEditorView(
                                bestPlayersCount: bestPlayersCountBinding,
                                guestBestPlayersCount: guestBestPlayersCountBinding,
                                bestPlayersVotes: bestPlayersVotesBinding,
                                guestBestPlayersVotes: guestBestPlayersVotesBinding
                            )
                        } label: {
                            Label("Best & Fairest", systemImage: "list.number")
                        }
                    }

                    editGradeSettingsSection()

                    Section {
                        Button(role: .destructive) {
                            if deleteGrade(grade) {
                                gradeEditing = nil
                            }
                        } label: {
                            Label("Delete Grade", systemImage: "trash")
                        }
                    }
                }
                .navigationTitle("Edit Grade")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            if hasUnsavedEditGradeChanges {
                                showDiscardChangesAlert = true
                            } else {
                                gradeEditing = nil
                            }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if saveEditedGrade() {
                                gradeEditing = nil
                            }
                        }
                        .saveButtonBehavior(isEnabled: !isEditGradeSaveDisabled)
                    }
                }
                .alert("Discard changes?", isPresented: $showDiscardChangesAlert) {
                    Button("Keep Editing", role: .cancel) {}
                    Button("Discard Changes", role: .destructive) {
                        gradeEditing = nil
                    }
                } message: {
                    Text("You have unsaved changes. If you cancel now, your edits will be lost.")
                }
            }
            .appPopupStyle()
        }
        .task {
            reloadGrades()
        }
    }

    private func bind(_ keyPath: WritableKeyPath<EditGradeDraft, Bool>) -> Binding<Bool> {
        Binding(
            get: { editGradeDraft[keyPath: keyPath] },
            set: { editGradeDraft[keyPath: keyPath] = $0 }
        )
    }

    private func bind(_ keyPath: WritableKeyPath<EditGradeDraft, Int>) -> Binding<Int> {
        Binding(
            get: { editGradeDraft[keyPath: keyPath] },
            set: {
                if keyPath == \.quarterLengthMinutes {
                    editGradeDraft[keyPath: keyPath] = min(max($0, 10), 30)
                } else if keyPath == \.playersPerTeam {
                    editGradeDraft[keyPath: keyPath] = min(max($0, 1), 60)
                } else {
                    editGradeDraft[keyPath: keyPath] = min(max($0, 1), 10)
                }
            }
        )
    }

    private func bind(_ keyPath: WritableKeyPath<EditGradeDraft, [Int]>) -> Binding<[Int]> {
        Binding(
            get: { editGradeDraft[keyPath: keyPath] },
            set: { editGradeDraft[keyPath: keyPath] = $0 }
        )
    }

    @ViewBuilder
    private func oneToTenPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            Text("1").tag(1)
            Text("2").tag(2)
            Text("3").tag(3)
            Text("4").tag(4)
            Text("5").tag(5)
            Text("6").tag(6)
            Text("7").tag(7)
            Text("8").tag(8)
            Text("9").tag(9)
            Text("10").tag(10)
        }
    }

    @ViewBuilder
    private func editGradeSettingsSection() -> some View {
        let playersPerTeamBinding = bind(\.playersPerTeam)
        let quarterLengthBinding = bind(\.quarterLengthMinutes)

        Section {
            Label("Settings", systemImage: "gearshape.fill")
                .font(.subheadline.weight(.semibold))
            Toggle("Track players per team", isOn: bind(\.tracksPlayersPerTeam))
            if editGradeDraft.tracksPlayersPerTeam {
                Stepper("Players per team: \(editGradeDraft.playersPerTeam)", value: playersPerTeamBinding, in: 1...60)
            }
            Toggle("Player Swaps", isOn: bind(\.playerSwapsEnabled))
            Toggle("Notes", isOn: bind(\.asksNotes))
            Toggle("Live Game View", isOn: bind(\.allowsLiveGameView))
            Picker("Length of Quarters", selection: quarterLengthBinding) {
                ForEach(10...30, id: \.self) { minute in
                    Text("\(minute) min").tag(minute)
                }
            }
            Toggle("Time on", isOn: bind(\.timeOnEnabled))
        }
    }

    private func addGrade(using draft: NewGradeDraft) -> Bool {
        let name = clean(draft.name)
        guard !name.isEmpty else { return false }
        guard !grades.contains(where: { clean($0.name).lowercased() == name.lowercased() }) else { return false }

        let nextOrder = (grades.map(\.displayOrder).max() ?? -1) + 1
        let newGrade = Grade(
            name: name,
            isActive: true,
            displayOrder: nextOrder,
            asksHeadCoach: draft.asksHeadCoach,
            asksAssistantCoach: draft.asksAssistantCoach,
            asksTeamManager: draft.asksTeamManager,
            asksRunner: draft.asksRunner,
            asksGoalUmpire: draft.asksGoalUmpire,
            asksTimeKeeper: draft.asksTimeKeeper,
            asksFieldUmpire: draft.asksFieldUmpire,
            asksBoundaryUmpire1: draft.asksBoundaryUmpire1,
            asksBoundaryUmpire2: draft.asksBoundaryUmpire2,
            asksWaterBoy1: draft.asksWaterBoy1,
            asksWaterBoy2: draft.asksWaterBoy2,
            asksWaterBoy3: draft.asksWaterBoy3,
            asksWaterBoy4: draft.asksWaterBoy4,
            asksTrainers: draft.hasAnyTrainerEnabled,
            asksTrainer1: draft.asksTrainer1,
            asksTrainer2: draft.asksTrainer2,
            asksTrainer3: draft.asksTrainer3,
            asksTrainer4: draft.asksTrainer4,
            asksNotes: draft.asksNotes,
            asksGoalKickers: draft.asksGoalKickers,
            tracksPlayersPerTeam: draft.tracksPlayersPerTeam,
            playersPerTeam: draft.playersPerTeam,
            playerSwapsEnabled: draft.playerSwapsEnabled,
            bestPlayersCount: draft.bestPlayersCount,
            asksGuestBestFairestVotesScan: draft.asksGuestBestFairestVotesScan,
            guestBestPlayersCount: draft.guestBestPlayersCount,
            bestPlayersVotes: draft.bestPlayersVotes,
            guestBestPlayersVotes: draft.guestBestPlayersVotes,
            allowsLiveGameView: draft.allowsLiveGameView,
            quarterLengthMinutes: draft.quarterLengthMinutes,
            timeOnEnabled: draft.timeOnEnabled
        )
        dataContext.insert(newGrade)
        grades.append(newGrade)

        SettingsBackupStore.saveGrades(grades)
        saveContext()
        reloadGrades()
        return true
    }

    private func saveEditedGrade() -> Bool {
        guard let gradeEditing else { return false }

        let name = clean(editGradeDraft.name)
        guard !name.isEmpty else { return false }
        guard !grades.contains(where: { $0.id != gradeEditing.id && clean($0.name).lowercased() == name.lowercased() }) else { return false }

        gradeEditing.name = name
        gradeEditing.asksHeadCoach = editGradeDraft.asksHeadCoach
        gradeEditing.asksAssistantCoach = editGradeDraft.asksAssistantCoach
        gradeEditing.asksTeamManager = editGradeDraft.asksTeamManager
        gradeEditing.asksRunner = editGradeDraft.asksRunner
        gradeEditing.asksGoalUmpire = editGradeDraft.asksGoalUmpire
        gradeEditing.asksTimeKeeper = editGradeDraft.asksTimeKeeper
        gradeEditing.asksFieldUmpire = editGradeDraft.asksFieldUmpire
        gradeEditing.asksBoundaryUmpire1 = editGradeDraft.asksBoundaryUmpire1
        gradeEditing.asksBoundaryUmpire2 = editGradeDraft.asksBoundaryUmpire2
        gradeEditing.asksWaterBoy1 = editGradeDraft.asksWaterBoy1
        gradeEditing.asksWaterBoy2 = editGradeDraft.asksWaterBoy2
        gradeEditing.asksWaterBoy3 = editGradeDraft.asksWaterBoy3
        gradeEditing.asksWaterBoy4 = editGradeDraft.asksWaterBoy4
        gradeEditing.asksTrainer1 = editGradeDraft.asksTrainer1
        gradeEditing.asksTrainer2 = editGradeDraft.asksTrainer2
        gradeEditing.asksTrainer3 = editGradeDraft.asksTrainer3
        gradeEditing.asksTrainer4 = editGradeDraft.asksTrainer4
        gradeEditing.asksTrainers = editGradeDraft.hasAnyTrainerEnabled
        gradeEditing.asksScore = editGradeDraft.asksScore
        gradeEditing.asksGoalKickers = editGradeDraft.asksGoalKickers
        gradeEditing.tracksPlayersPerTeam = editGradeDraft.tracksPlayersPerTeam
        gradeEditing.playersPerTeam = editGradeDraft.playersPerTeam
        gradeEditing.playerSwapsEnabled = editGradeDraft.playerSwapsEnabled
        gradeEditing.bestPlayersCount = editGradeDraft.bestPlayersCount
        gradeEditing.asksGuestBestFairestVotesScan = editGradeDraft.asksGuestBestFairestVotesScan
        gradeEditing.guestBestPlayersCount = editGradeDraft.guestBestPlayersCount
        gradeEditing.bestPlayersVotes = Grade.normalizedVotes(editGradeDraft.bestPlayersVotes, count: editGradeDraft.bestPlayersCount)
        gradeEditing.guestBestPlayersVotes = Grade.normalizedGuestVotes(editGradeDraft.guestBestPlayersVotes, count: editGradeDraft.guestBestPlayersCount)
        gradeEditing.asksNotes = editGradeDraft.asksNotes
        gradeEditing.allowsLiveGameView = editGradeDraft.allowsLiveGameView
        gradeEditing.quarterLengthMinutes = editGradeDraft.quarterLengthMinutes
        gradeEditing.timeOnEnabled = editGradeDraft.timeOnEnabled
        SettingsBackupStore.saveGrades(grades)
        saveContext()
        reloadGrades()
        return true
    }

    private var isEditGradeSaveDisabled: Bool {
        guard let gradeEditing else { return true }
        let name = clean(editGradeDraft.name)
        guard !name.isEmpty else { return true }
        let hasDuplicateName = grades.contains(where: { $0.id != gradeEditing.id && clean($0.name).lowercased() == name.lowercased() })
        return hasDuplicateName || !hasUnsavedEditGradeChanges
    }

    private var hasUnsavedEditGradeChanges: Bool {
        guard let gradeEditing else { return false }
        let normalizedDraft = editGradeDraft.normalizedName(clean)
        let normalizedGradeName = clean(gradeEditing.name)
        return normalizedDraft != normalizedGradeName
            || editGradeDraft.asksHeadCoach != gradeEditing.asksHeadCoach
            || editGradeDraft.asksAssistantCoach != gradeEditing.asksAssistantCoach
            || editGradeDraft.asksTeamManager != gradeEditing.asksTeamManager
            || editGradeDraft.asksRunner != gradeEditing.asksRunner
            || editGradeDraft.asksGoalUmpire != gradeEditing.asksGoalUmpire
            || editGradeDraft.asksFieldUmpire != gradeEditing.asksFieldUmpire
            || editGradeDraft.asksBoundaryUmpire1 != gradeEditing.asksBoundaryUmpire1
            || editGradeDraft.asksBoundaryUmpire2 != gradeEditing.asksBoundaryUmpire2
            || editGradeDraft.asksWaterBoy1 != gradeEditing.asksWaterBoy1
            || editGradeDraft.asksWaterBoy2 != gradeEditing.asksWaterBoy2
            || editGradeDraft.asksWaterBoy3 != gradeEditing.asksWaterBoy3
            || editGradeDraft.asksWaterBoy4 != gradeEditing.asksWaterBoy4
            || editGradeDraft.asksTrainer1 != gradeEditing.asksTrainer1
            || editGradeDraft.asksTrainer2 != gradeEditing.asksTrainer2
            || editGradeDraft.asksTrainer3 != gradeEditing.asksTrainer3
            || editGradeDraft.asksTrainer4 != gradeEditing.asksTrainer4
            || editGradeDraft.asksScore != gradeEditing.asksScore
            || editGradeDraft.asksGoalKickers != gradeEditing.asksGoalKickers
            || editGradeDraft.tracksPlayersPerTeam != gradeEditing.tracksPlayersPerTeam
            || editGradeDraft.playersPerTeam != gradeEditing.playersPerTeam
            || editGradeDraft.playerSwapsEnabled != gradeEditing.playerSwapsEnabled
            || editGradeDraft.bestPlayersCount != gradeEditing.bestPlayersCount
            || editGradeDraft.asksGuestBestFairestVotesScan != gradeEditing.asksGuestBestFairestVotesScan
            || editGradeDraft.guestBestPlayersCount != gradeEditing.guestBestPlayersCount
            || Grade.normalizedVotes(editGradeDraft.bestPlayersVotes, count: editGradeDraft.bestPlayersCount) != gradeEditing.bestPlayersVotes
            || Grade.normalizedGuestVotes(editGradeDraft.guestBestPlayersVotes, count: editGradeDraft.guestBestPlayersCount) != gradeEditing.guestBestPlayersVotes
            || editGradeDraft.asksNotes != gradeEditing.asksNotes
            || editGradeDraft.allowsLiveGameView != gradeEditing.allowsLiveGameView
            || editGradeDraft.quarterLengthMinutes != gradeEditing.quarterLengthMinutes
            || editGradeDraft.timeOnEnabled != gradeEditing.timeOnEnabled
    }

    private func moveGrades(from source: IndexSet, to destination: Int) {
        var reordered = sortedGrades
        reordered.move(fromOffsets: source, toOffset: destination)

        for (index, grade) in reordered.enumerated() {
            grade.displayOrder = index
        }

        SettingsBackupStore.saveGrades(reordered)
        saveContext()
        reloadGrades()
    }

    private func deleteGrade(_ grade: Grade) -> Bool {
        if games.contains(where: { $0.gradeID == grade.id }) {
            deletionErrorMessage = "This grade has games attached. Reassign or remove those games first."
            showDeletionError = true
            return false
        }

        if players.contains(where: { $0.gradeIDs.contains(grade.id) }) {
            deletionErrorMessage = "This grade has players attached. Remove the grade from players first."
            showDeletionError = true
            return false
        }

        for recipient in reportRecipients where recipient.gradeID == grade.id {
            dataContext.delete(recipient)
        }

        dataContext.delete(grade)

        let remaining = orderedGradesForDisplay(
            grades.filter { $0.id != grade.id },
            includeInactive: true
        )

        for (index, item) in remaining.enumerated() {
            item.displayOrder = index
        }

        SettingsBackupStore.saveGrades(remaining)
        saveContext()
        reloadGrades()
        return true
    }

    private func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveContext() {
        do {
            try dataContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func reloadGrades() {
        do {
            let descriptor = FetchDescriptor<Grade>(
                sortBy: [
                    SortDescriptor(\Grade.displayOrder),
                    SortDescriptor(\Grade.name)
                ]
            )
            let fetched = try dataContext.fetch(descriptor)

            if fetched.isEmpty {
                let backups = SettingsBackupStore.loadGrades()
                if !backups.isEmpty {
                    grades = backups.map {
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
                            asksTimeKeeper: $0.asksTimeKeeper,
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
                            playersPerTeam: $0.playersPerTeam,
                            playerSwapsEnabled: $0.playerSwapsEnabled,
                            bestPlayersCount: $0.bestPlayersCount,
                            asksGuestBestFairestVotesScan: $0.asksGuestBestFairestVotesScan,
                            guestBestPlayersCount: $0.guestBestPlayersCount,
                            bestPlayersVotes: $0.bestPlayersVotes,
                            guestBestPlayersVotes: $0.guestBestPlayersVotes,
                            allowsLiveGameView: $0.allowsLiveGameView,
                            quarterLengthMinutes: $0.quarterLengthMinutes
                        )
                    }

                    for item in backups {
                        dataContext.insert(
                            Grade(
                                id: item.id,
                                name: item.name,
                                isActive: item.isActive,
                                displayOrder: item.displayOrder,
                                asksHeadCoach: item.asksHeadCoach,
                                asksAssistantCoach: item.asksAssistantCoach,
                                asksTeamManager: item.asksTeamManager,
                                asksRunner: item.asksRunner,
                                asksGoalUmpire: item.asksGoalUmpire,
                                asksTimeKeeper: item.asksTimeKeeper,
                                asksFieldUmpire: item.asksFieldUmpire,
                                asksBoundaryUmpire1: item.asksBoundaryUmpire1,
                                asksBoundaryUmpire2: item.asksBoundaryUmpire2,
                                asksWaterBoy1: item.asksWaterBoy1,
                                asksWaterBoy2: item.asksWaterBoy2,
                                asksWaterBoy3: item.asksWaterBoy3,
                                asksWaterBoy4: item.asksWaterBoy4,
                                asksTrainers: item.asksTrainers,
                                asksTrainer1: item.asksTrainer1,
                                asksTrainer2: item.asksTrainer2,
                                asksTrainer3: item.asksTrainer3,
                                asksTrainer4: item.asksTrainer4,
                                asksNotes: item.asksNotes,
                                asksScore: item.asksScore,
                                asksLiveGameView: item.asksLiveGameView,
                                asksGoalKickers: item.asksGoalKickers,
                                playersPerTeam: item.playersPerTeam,
                                playerSwapsEnabled: item.playerSwapsEnabled,
                                bestPlayersCount: item.bestPlayersCount,
                                asksGuestBestFairestVotesScan: item.asksGuestBestFairestVotesScan,
                                guestBestPlayersCount: item.guestBestPlayersCount,
                                bestPlayersVotes: item.bestPlayersVotes,
                                guestBestPlayersVotes: item.guestBestPlayersVotes,
                                allowsLiveGameView: item.allowsLiveGameView,
                                quarterLengthMinutes: item.quarterLengthMinutes
                            )
                        )
                    }

                    try? dataContext.save()

                    let afterRestore = (try? dataContext.fetch(descriptor)) ?? []
                    if !afterRestore.isEmpty {
                        grades = afterRestore
                    }
                    return
                }
            }

            grades = fetched
            SettingsBackupStore.saveGrades(grades)
        } catch {
            saveErrorMessage = error.localizedDescription
            let backups = SettingsBackupStore.loadGrades()
            grades = backups.map {
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
                    asksTimeKeeper: $0.asksTimeKeeper,
                    asksFieldUmpire: $0.asksFieldUmpire,
                    asksBoundaryUmpire1: $0.asksBoundaryUmpire1,
                    asksBoundaryUmpire2: $0.asksBoundaryUmpire2,
                    asksWaterBoy1: $0.asksWaterBoy1,
                    asksWaterBoy2: $0.asksWaterBoy2,
                    asksWaterBoy3: $0.asksWaterBoy3,
                    asksWaterBoy4: $0.asksWaterBoy4,
                    asksTrainers: $0.asksTrainers,
                    asksTrainer1: $0.asksTrainer1,
                    asksTrainer2: $0.asksTrainer2,
                    asksTrainer3: $0.asksTrainer3,
                    asksTrainer4: $0.asksTrainer4,
                    asksNotes: $0.asksNotes,
                    asksScore: $0.asksScore,
                    asksLiveGameView: $0.asksLiveGameView,
                    asksGoalKickers: $0.asksGoalKickers,
                    playerSwapsEnabled: $0.playerSwapsEnabled,
                    bestPlayersCount: $0.bestPlayersCount,
                    asksGuestBestFairestVotesScan: $0.asksGuestBestFairestVotesScan,
                    guestBestPlayersCount: $0.guestBestPlayersCount,
                    bestPlayersVotes: $0.bestPlayersVotes,
                    guestBestPlayersVotes: $0.guestBestPlayersVotes,
                    allowsLiveGameView: $0.allowsLiveGameView,
                    quarterLengthMinutes: $0.quarterLengthMinutes
                )
            }
        }
    }
}

private struct AppAppearanceSettingsView: View {
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $appAppearance) {
                    ForEach(AppAppearance.allCases) { item in
                        Text(item.title).tag(item.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("App Appearance")
            }
        }
        .navigationTitle("App Appearance")
    }
}

private struct VoteAllocationEditorView: View {
    @Binding var bestPlayersCount: Int
    @Binding var guestBestPlayersCount: Int
    @Binding var bestPlayersVotes: [Int]
    @Binding var guestBestPlayersVotes: [Int]

    var body: some View {
        Form {
            Section {
                Text("Choose how many Best & Fairest votes each ranked player receives.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(0..<bestPlayersCount, id: \.self) { index in
                    Stepper(value: bestVoteBinding(index), in: 0...20) {
                        VoteAllocationRow(
                            rank: index + 1,
                            votes: bestVotes(for: index),
                            description: "Player ranked #\(index + 1) gets \(bestVotes(for: index)) vote\(bestVotes(for: index) == 1 ? "" : "s")."
                        )
                    }
                }
            } header: {
                Text("Best Players Votes")
            }
            Section {
                Text("Set the vote weighting used when collecting guest best players.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(0..<guestBestPlayersCount, id: \.self) { index in
                    Stepper(value: guestVoteBinding(index), in: 0...20) {
                        VoteAllocationRow(
                            rank: index + 1,
                            votes: guestVotes(for: index),
                            description: "Guest player ranked #\(index + 1) gets \(guestVotes(for: index)) vote\(guestVotes(for: index) == 1 ? "" : "s")."
                        )
                    }
                }
            } header: {
                Text("Guest Best Players Votes")
            }
        }
        .navigationTitle("Best & Fairest")
        .onAppear(perform: normalizeArrays)
        .onChange(of: bestPlayersCount) { _, _ in normalizeArrays() }
        .onChange(of: guestBestPlayersCount) { _, _ in normalizeArrays() }
    }

    private func normalizeArrays() {
        bestPlayersVotes = Grade.normalizedVotes(bestPlayersVotes, count: bestPlayersCount)
        guestBestPlayersVotes = Grade.normalizedGuestVotes(guestBestPlayersVotes, count: guestBestPlayersCount)
    }

    private func bestVotes(for index: Int) -> Int {
        Grade.normalizedVotes(bestPlayersVotes, count: bestPlayersCount)[index]
    }

    private func guestVotes(for index: Int) -> Int {
        Grade.normalizedGuestVotes(guestBestPlayersVotes, count: guestBestPlayersCount)[index]
    }

    private func bestVoteBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { bestVotes(for: index) },
            set: { newValue in
                var values = Grade.normalizedVotes(bestPlayersVotes, count: bestPlayersCount)
                values[index] = max(0, newValue)
                bestPlayersVotes = values
            }
        )
    }

    private func guestVoteBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { guestVotes(for: index) },
            set: { newValue in
                var values = Grade.normalizedGuestVotes(guestBestPlayersVotes, count: guestBestPlayersCount)
                values[index] = max(0, newValue)
                guestBestPlayersVotes = values
            }
        )
    }
}

private struct VoteAllocationRow: View {
    let rank: Int
    let votes: Int
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Rank \(rank): \(votes)")
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct EditGradeDraft {
    var name = ""
    var asksHeadCoach = true
    var asksAssistantCoach = true
    var asksTeamManager = true
    var asksRunner = true
    var asksGoalUmpire = true
    var asksTimeKeeper = true
    var asksFieldUmpire = true
    var asksBoundaryUmpire1 = true
    var asksBoundaryUmpire2 = true
    var asksWaterBoy1 = false
    var asksWaterBoy2 = false
    var asksWaterBoy3 = false
    var asksWaterBoy4 = false
    var asksTrainer1 = true
    var asksTrainer2 = true
    var asksTrainer3 = true
    var asksTrainer4 = true
    var asksScore = true
    var asksGoalKickers = true
    var tracksPlayersPerTeam = true
    var playersPerTeam = 22
    var playerSwapsEnabled = true
    var bestPlayersCount = 6
    var asksGuestBestFairestVotesScan = true
    var guestBestPlayersCount = 3
    var bestPlayersVotes = Grade.normalizedVotes(nil, count: 6)
    var guestBestPlayersVotes = Grade.normalizedGuestVotes(nil, count: 3)
    var asksNotes = true
    var allowsLiveGameView = true
    var quarterLengthMinutes = 20
    var timeOnEnabled = false

    init() {}

    init(grade: Grade) {
        name = grade.name
        asksHeadCoach = grade.asksHeadCoach
        asksAssistantCoach = grade.asksAssistantCoach
        asksTeamManager = grade.asksTeamManager
        asksRunner = grade.asksRunner
        asksGoalUmpire = grade.asksGoalUmpire
        asksTimeKeeper = grade.asksTimeKeeper
        asksFieldUmpire = grade.asksFieldUmpire
        asksBoundaryUmpire1 = grade.asksBoundaryUmpire1
        asksBoundaryUmpire2 = grade.asksBoundaryUmpire2
        asksWaterBoy1 = grade.asksWaterBoy1
        asksWaterBoy2 = grade.asksWaterBoy2
        asksWaterBoy3 = grade.asksWaterBoy3
        asksWaterBoy4 = grade.asksWaterBoy4
        asksTrainer1 = grade.asksTrainer1
        asksTrainer2 = grade.asksTrainer2
        asksTrainer3 = grade.asksTrainer3
        asksTrainer4 = grade.asksTrainer4
        asksScore = grade.asksScore
        asksGoalKickers = grade.asksGoalKickers
        tracksPlayersPerTeam = grade.tracksPlayersPerTeam
        playersPerTeam = grade.playersPerTeam
        playerSwapsEnabled = grade.playerSwapsEnabled
        bestPlayersCount = grade.bestPlayersCount
        asksGuestBestFairestVotesScan = grade.asksGuestBestFairestVotesScan
        guestBestPlayersCount = grade.guestBestPlayersCount
        bestPlayersVotes = Grade.normalizedVotes(grade.bestPlayersVotes, count: grade.bestPlayersCount)
        guestBestPlayersVotes = Grade.normalizedGuestVotes(grade.guestBestPlayersVotes, count: grade.guestBestPlayersCount)
        asksNotes = grade.asksNotes
        allowsLiveGameView = grade.allowsLiveGameView
        quarterLengthMinutes = grade.quarterLengthMinutes
        timeOnEnabled = grade.timeOnEnabled
    }

    var hasAnyTrainerEnabled: Bool {
        asksTrainer1 || asksTrainer2 || asksTrainer3 || asksTrainer4
    }

    func normalizedName(_ cleaner: (String) -> String) -> String {
        cleaner(name)
    }
}

private struct NewGradeDraft {
    var name = ""
    var asksHeadCoach = true
    var asksAssistantCoach = true
    var asksTeamManager = true
    var asksRunner = true
    var asksGoalUmpire = true
    var asksTimeKeeper = true
    var asksFieldUmpire = true
    var asksBoundaryUmpire1 = true
    var asksBoundaryUmpire2 = true
    var asksWaterBoy1 = false
    var asksWaterBoy2 = false
    var asksWaterBoy3 = false
    var asksWaterBoy4 = false
    var asksTrainer1 = true
    var asksTrainer2 = true
    var asksTrainer3 = true
    var asksTrainer4 = true
    var asksNotes = true
    var asksGoalKickers = true
    var tracksPlayersPerTeam = true
    var playersPerTeam = 22
    var playerSwapsEnabled = true
    var bestPlayersCount = 6
    var asksGuestBestFairestVotesScan = true
    var guestBestPlayersCount = 3
    var bestPlayersVotes = Grade.normalizedVotes(nil, count: 6)
    var guestBestPlayersVotes = Grade.normalizedGuestVotes(nil, count: 3)
    var allowsLiveGameView = true
    var quarterLengthMinutes = 20
    var timeOnEnabled = false

    var hasAnyTrainerEnabled: Bool {
        asksTrainer1 || asksTrainer2 || asksTrainer3 || asksTrainer4
    }
}

private struct AddGradeWizardView: View {
    enum Step: Int {
        case gradeName
        case coaches
        case officials
        case trainers
        case awards
        case settings
    }

    @Binding var draft: NewGradeDraft
    let onSave: (NewGradeDraft) -> Void
    let onCancel: () -> Void

    @State private var step: Step = .gradeName

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .gradeName:
                    Section {
                        TextField("Grade name", text: $draft.name)
                            .textInputAutocapitalization(.words)
                            .onChange(of: draft.name) { _, newName in
                                draft.tracksPlayersPerTeam = Grade.defaultTracksPlayersPerTeam(for: newName)
                                draft.playersPerTeam = Grade.defaultPlayersPerTeam(for: newName)
                                draft.playerSwapsEnabled = Grade.defaultPlayerSwapsEnabled(for: newName)
                            }
                    } header: {
                        Text("Grade")
                    }
                case .coaches:
                    Section {
                        Toggle("Head Coach", isOn: $draft.asksHeadCoach)
                        Toggle("Assistant Coach", isOn: $draft.asksAssistantCoach)
                        Toggle("Team Manager", isOn: $draft.asksTeamManager)
                        Toggle("Runner", isOn: $draft.asksRunner)
                    } header: {
                        Text("Coaching Staff")
                    }
                case .officials:
                    Section {
                        Toggle("Goal Umpire", isOn: $draft.asksGoalUmpire)
                        Toggle("Time Keeper", isOn: $draft.asksTimeKeeper)
                        Toggle("Field Umpire", isOn: $draft.asksFieldUmpire)
                        Toggle("Boundary Umpire 1", isOn: $draft.asksBoundaryUmpire1)
                        Toggle("Boundary Umpire 2", isOn: $draft.asksBoundaryUmpire2)
                        Toggle("Water 1", isOn: $draft.asksWaterBoy1)
                        Toggle("Water 2", isOn: $draft.asksWaterBoy2)
                        Toggle("Water 3", isOn: $draft.asksWaterBoy3)
                        Toggle("Water 4", isOn: $draft.asksWaterBoy4)
                    } header: {
                        Text("Officials")
                    }
                case .trainers:
                    Section {
                        Toggle("Trainer 1", isOn: $draft.asksTrainer1)
                        Toggle("Trainer 2", isOn: $draft.asksTrainer2)
                        Toggle("Trainer 3", isOn: $draft.asksTrainer3)
                        Toggle("Trainer 4", isOn: $draft.asksTrainer4)
                    } header: {
                        Text("Trainers")
                    }
                case .awards:
                    Section {
                        Toggle("Goal Kickers", isOn: $draft.asksGoalKickers)
                        Picker("Best Players", selection: $draft.bestPlayersCount) {
                            ForEach(1...10, id: \.self) { count in
                                Text("\(count)").tag(count)
                            }
                        }
                        Toggle("Guest Best Players", isOn: $draft.asksGuestBestFairestVotesScan)
                        if draft.asksGuestBestFairestVotesScan {
                            Picker("Guest Best Players Quantity", selection: $draft.guestBestPlayersCount) {
                                ForEach(1...10, id: \.self) { count in
                                    Text("\(count)").tag(count)
                                }
                            }
                        }
                        NavigationLink {
                            VoteAllocationEditorView(
                                bestPlayersCount: $draft.bestPlayersCount,
                                guestBestPlayersCount: $draft.guestBestPlayersCount,
                                bestPlayersVotes: $draft.bestPlayersVotes,
                                guestBestPlayersVotes: $draft.guestBestPlayersVotes
                            )
                        } label: {
                            Label("Best & Fairest", systemImage: "list.number")
                        }
                    } header: {
                        Text("Awards")
                    }
                case .settings:
                    Section {
                        Toggle("Track players per team", isOn: $draft.tracksPlayersPerTeam)
                        if draft.tracksPlayersPerTeam {
                            Stepper("Players per team: \(draft.playersPerTeam)", value: $draft.playersPerTeam, in: 1...60)
                        }
                        Toggle("Player Swaps", isOn: $draft.playerSwapsEnabled)
                        Toggle("Notes", isOn: $draft.asksNotes)
                        Toggle("Live Game View", isOn: $draft.allowsLiveGameView)
                        Picker("Length of Quarters", selection: $draft.quarterLengthMinutes) {
                            ForEach(10...30, id: \.self) { minute in
                                Text("\(minute) min").tag(minute)
                            }
                        }
                    } header: {
                        Text("Settings")
                    }
                }
            }
            .navigationTitle("Add Grade")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        if step != .gradeName {
                            Button("Back") {
                                step = Step(rawValue: step.rawValue - 1) ?? .gradeName
                            }
                        }
                        Spacer()
                        if step == .settings {
                            Button("Save") { onSave(draft) }
                                .saveButtonBehavior(isEnabled: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } else {
                            Button("Next") {
                                step = Step(rawValue: step.rawValue + 1) ?? .settings
                            }
                            .disabled(step == .gradeName && draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
    }
}

private struct ContactsSettingsView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext

    @State private var contacts: [Contact] = []
    @Query private var reportRecipients: [ReportRecipient]
    @Query private var sectionMemberships: [ContactSectionMembership]

    @State private var showAddContact = false
    @State private var contactEditing: Contact?
    @State private var saveErrorMessage: String?

    var body: some View {
        List {
            Section {
                Text("Required fields: Name, Mobile, Email")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if contacts.isEmpty {
                    Text("No contacts added.")
                        .foregroundStyle(.secondary)
                }

                ForEach(contacts) { contact in
                    HStack(alignment: .top, spacing: 8) {
                        StandardListIcon(systemName: "person.crop.circle.badge.checkmark")
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(contact.name)
                                .font(.headline)

                            Text(contact.mobile.formattedMobileNumber)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text(contact.email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        contactEditing = contact
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteContact(contact)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                Button {
                    showAddContact = true
                } label: {
                    Label("Add Contact", systemImage: "plus")
                }
            } header: {
                Text("Contacts")
            } footer: {
                Text("Manage contact group assignments from Settings > Groups.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Contacts")
        .sheet(isPresented: $showAddContact) {
            ContactEditSheet(
                title: "Add Contact",
                allowsSaveAndAddAnother: false,
                onSave: { name, mobile, email in
                    let newContact = Contact(name: name, mobile: mobile, email: email)
                    dataContext.insert(newContact)
                    contacts.append(newContact)
                    contacts.sort {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    SettingsBackupStore.saveContacts(contacts)
                    saveContext()
                    reloadContacts()
                    return true
                }
            )
            .appPopupStyle()
        }
        .sheet(item: $contactEditing) { contact in
            ContactEditSheet(
                title: "Edit Contact",
                initialName: contact.name,
                initialMobile: contact.mobile.formattedMobileNumber,
                initialEmail: contact.email,
                onSave: { name, mobile, email in
                    contact.name = name
                    contact.mobile = mobile.formattedMobileNumber
                    contact.email = email
                    SettingsBackupStore.saveContacts(contacts)
                    saveContext()
                    reloadContacts()
                    return true
                },
                onDelete: {
                    deleteContact(contact)
                }
            )
            .appPopupStyle()
        }
        .alert(
            "Save Error",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
        .task {
            reloadContacts()
        }
    }

    private func deleteContact(_ contact: Contact) {
        for recipient in reportRecipients where recipient.contactID == contact.id {
            dataContext.delete(recipient)
        }

        for membership in sectionMemberships where membership.contactID == contact.id {
            dataContext.delete(membership)
        }

        dataContext.delete(contact)
        contacts.removeAll { $0.id == contact.id }

        SettingsBackupStore.saveContacts(contacts)
        saveContext()
        reloadContacts()
    }

    private func saveContext() {
        do {
            try dataContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
            let backups = SettingsBackupStore.loadContacts()
            contacts = backups
                .map {
                    Contact(
                        id: $0.id,
                        name: $0.name,
                        mobile: $0.mobile,
                        email: $0.email
                    )
                }
                .sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
        }
    }

    private func reloadContacts() {
        do {
            let descriptor = FetchDescriptor<Contact>(
                sortBy: [SortDescriptor(\Contact.name)]
            )
            let fetched = try dataContext.fetch(descriptor)

            if fetched.isEmpty {
                let backups = SettingsBackupStore.loadContacts()
                if !backups.isEmpty {
                    contacts = backups
                        .map {
                            Contact(
                                id: $0.id,
                                name: $0.name,
                                mobile: $0.mobile,
                                email: $0.email
                            )
                        }
                        .sorted {
                            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                        }

                    for item in backups {
                        dataContext.insert(
                            Contact(
                                id: item.id,
                                name: item.name,
                                mobile: item.mobile,
                                email: item.email
                            )
                        )
                    }

                    try? dataContext.save()

                    let afterRestore = (try? dataContext.fetch(descriptor)) ?? []
                    if !afterRestore.isEmpty {
                        contacts = afterRestore
                    }
                    return
                }
            }

            contacts = fetched
            SettingsBackupStore.saveContacts(contacts)
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}

private struct GroupsSettingsView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Query(sort: [SortDescriptor(\Contact.name)]) private var contacts: [Contact]
    @Query(sort: [SortDescriptor(\Grade.displayOrder), SortDescriptor(\Grade.name)]) private var grades: [Grade]
    @Query private var sectionMemberships: [ContactSectionMembership]

    @State private var addContactsSection: GroupSectionSelection?
    @State private var sectionEditing: GroupSectionSelection?
    @State private var contactEditing: Contact?
    @State private var isManagingGroups = false
    @State private var saveErrorMessage: String?
    @AppStorage("contactSectionCustomTitles") private var customSectionTitlesData: String = ""
    @AppStorage("contactSectionCustomGroups") private var customSectionKeysData: String = ""
    @AppStorage("contactSectionHiddenGroups") private var hiddenSectionKeysData: String = ""

    var body: some View {
        GeometryReader { geometry in
            List {
                if useTwoColumnLayout(in: geometry.size) {
                    twoColumnSectionsLayout
                } else {
                    singleColumnSectionsLayout
                }
            }
        }
        .navigationTitle("Groups")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isManagingGroups = true
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Manage Groups")
            }
        }
        .sheet(item: $addContactsSection) { selection in
            AddContactsToSectionSheet(
                contacts: contacts,
                assignedContactIDs: Set(
                    sectionMemberships
                        .filter { $0.sectionKey == selection.sectionKey }
                        .map(\.contactID)
                ),
                onAddExisting: { selectedIDs in
                    selectedIDs.forEach { assignContact($0, toSection: selection.sectionKey) }
                    saveContext()
                    addContactsSection = nil
                },
                onAddNew: { name, mobile, email in
                    let contact = Contact(name: name, mobile: mobile, email: email)
                    dataContext.insert(contact)
                    assignContact(contact.id, toSection: selection.sectionKey)
                    saveContext()
                }
            )
            .appPopupStyle()
        }
        .sheet(item: $contactEditing) { contact in
            ContactEditSheet(
                title: "Edit Contact",
                initialName: contact.name,
                initialMobile: contact.mobile.formattedMobileNumber,
                initialEmail: contact.email,
                onSave: { name, mobile, email in
                    contact.name = name
                    contact.mobile = mobile.formattedMobileNumber
                    contact.email = email
                    saveContext()
                    return true
                }
            )
            .appPopupStyle()
        }
        .sheet(item: $sectionEditing) { selection in
            GroupSectionEditorSheet(
                title: displayTitle(for: selection.sectionKey, fallback: selection.fallbackTitle),
                contacts: contacts,
                selectedContactIDs: Set(
                    sectionMemberships
                        .filter { $0.sectionKey == selection.sectionKey }
                        .map(\.contactID)
                ),
                onToggleContact: { contactID, isSelected in
                    if isSelected {
                        assignContact(contactID, toSection: selection.sectionKey)
                    } else {
                        removeContact(contactID, fromSection: selection.sectionKey)
                    }
                    saveContext()
                },
                onEditContact: { contact in
                    contactEditing = contact
                },
                onAddContact: { name, mobile, email in
                    let contact = Contact(name: name, mobile: mobile, email: email)
                    dataContext.insert(contact)
                    assignContact(contact.id, toSection: selection.sectionKey)
                    var updatedContacts = contacts + [contact]
                    updatedContacts.sort {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    SettingsBackupStore.saveContacts(updatedContacts)
                    saveContext()
                    return true
                }
            )
            .appPopupStyle()
        }
        .sheet(isPresented: $isManagingGroups) {
            GroupManagerSheet(initialGroups: manageableGroups) { drafts in
                applyGroupDrafts(drafts)
            }
            .appPopupStyle()
        }
        .alert(
            "Save Error",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
    }

    private var orderedGrades: [Grade] {
        orderedGradesForDisplay(resolvedConfiguredGrades(from: grades), includeInactive: true)
    }

    private var customGroupKeys: [String] {
        guard
            let data = customSectionKeysData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private var hiddenGroupKeys: Set<String> {
        guard
            let data = hiddenSectionKeysData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return Set(decoded)
    }

    private var baseSections: [GroupSectionDescriptor] {
        let primary = primarySections.map {
            GroupSectionDescriptor(section: .fixed($0), sectionKey: $0.rawValue, fallbackTitle: $0.title)
        }
        let gradeSections = orderedGrades.map {
            GroupSectionDescriptor(
                section: .coachesGrade,
                sectionKey: ContactSectionKey.coachesGrade($0.id).rawValue,
                fallbackTitle: $0.name
            )
        }
        return (primary + gradeSections).filter { !hiddenGroupKeys.contains($0.sectionKey) }
    }

    private var customSections: [GroupSectionDescriptor] {
        customGroupKeys
            .filter { !hiddenGroupKeys.contains($0) }
            .map { key in
                GroupSectionDescriptor(
                    section: .custom,
                    sectionKey: key,
                    fallbackTitle: "Custom Group"
                )
            }
    }

    private var fixedSections: [GroupSectionDescriptor] {
        baseSections.filter {
            if case .fixed = $0.section { return true }
            return false
        }
    }

    private var roleSections: [GroupSectionDescriptor] {
        fixedSections + customSections
    }

    private var coachingSections: [GroupSectionDescriptor] {
        baseSections.filter { $0.section == .coachesGrade }
    }

    private let groupMainCardSpacing: CGFloat = 14
    private let groupSubCardSpacing: CGFloat = 12
    private let groupSubCardHeight: CGFloat = 168
    private let groupMemberRowHeight: CGFloat = 28

    private var groupMemberListHeight: CGFloat {
        groupMemberRowHeight * 3
    }

    @ViewBuilder
    private var singleColumnSectionsLayout: some View {
        if !roleSections.isEmpty {
            groupMainCard(title: "Roles") {
                VStack(spacing: groupSubCardSpacing) {
                    ForEach(roleSections, id: \.sectionKey) { section in
                        sectionCardView(fallbackTitle: section.fallbackTitle, sectionKey: section.sectionKey)
                    }
                }
            }
        }

        groupMainCard(title: "Coaching Staff") {
            if orderedGrades.isEmpty {
                Text("Add club grades in Settings > Club Grades to manage coach contacts by grade.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: groupSubCardSpacing) {
                    ForEach(coachingSections, id: \.sectionKey) { section in
                        sectionCardView(fallbackTitle: section.fallbackTitle, sectionKey: section.sectionKey)
                    }
                }
            }
        }
    }

    private var allDisplayedSections: [GroupSectionDescriptor] {
        fixedSections + coachingSections + customSections
    }

    @ViewBuilder
    private var twoColumnSectionsLayout: some View {
        if !roleSections.isEmpty {
            groupMainCard(title: "Roles") {
                twoColumnGrid(for: roleSections)
            }
        }

        groupMainCard(title: "Coaching Staff") {
            if orderedGrades.isEmpty {
                Text("Add club grades in Settings > Club Grades to manage coach contacts by grade.")
                    .foregroundStyle(.secondary)
            } else {
                twoColumnGrid(for: coachingSections)
            }
        }
    }

    @ViewBuilder
    private func groupMainCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            VStack(alignment: .leading, spacing: groupMainCardSpacing) {
                Text(title)
                    .font(.title3.weight(.semibold))

                content()
            }
            .padding(14)
            .clubGlassSurface(cornerRadius: 16)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private func twoColumnGrid(for sections: [GroupSectionDescriptor]) -> some View {
        let gridColumns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(sections, id: \.sectionKey) { section in
                sectionCardView(fallbackTitle: section.fallbackTitle, sectionKey: section.sectionKey)
            }
        }
    }

    private func useTwoColumnLayout(in size: CGSize) -> Bool {
        horizontalSizeClass != .compact && size.width >= 600
    }

    private var manageableGroups: [GroupManagementDraft] {
        (baseSections + customSections).map { section in
            GroupManagementDraft(
                sectionKey: section.sectionKey,
                name: displayTitle(for: section.sectionKey, fallback: section.fallbackTitle),
                fallbackTitle: section.fallbackTitle,
                isCustom: section.section == .custom
            )
        }
    }

    private func sectionView(fallbackTitle: String, sectionKey: String) -> some View {
        Section {
            let members = contactsForSection(sectionKey)

            Button {
                sectionEditing = GroupSectionSelection(sectionKey: sectionKey, fallbackTitle: fallbackTitle)
            } label: {
                HStack {
                    if members.isEmpty {
                        Text("No contacts added.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(members.map(\.name).joined(separator: ", "))
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Edit")
                }
            }
        } header: {
            HStack {
                Text(displayTitle(for: sectionKey, fallback: fallbackTitle))
            }
        }
    }

    private func sectionCardView(fallbackTitle: String, sectionKey: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(displayTitle(for: sectionKey, fallback: fallbackTitle))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                Spacer()
                Button("Edit") {
                    sectionEditing = GroupSectionSelection(sectionKey: sectionKey, fallbackTitle: fallbackTitle)
                }
                .buttonStyle(.borderless)
            }

            let members = contactsForSection(sectionKey)
            Group {
                if members.isEmpty {
                    Text("No contacts added.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if members.count > 3 {
                    ScrollView {
                        memberRows(members)
                    }
                    .scrollIndicators(.visible)
                } else {
                    memberRows(members)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(height: groupMemberListHeight, alignment: .top)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ClubTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ClubTheme.cardOverlay)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ClubTheme.cardStroke, lineWidth: 1)
        }
        .frame(maxWidth: .infinity, minHeight: groupSubCardHeight, maxHeight: groupSubCardHeight, alignment: .topLeading)
    }

    private func memberRows(_ members: [Contact]) -> some View {
        VStack(spacing: 0) {
            ForEach(members) { contact in
                HStack {
                    StandardListIcon(systemName: "person.crop.circle.badge.checkmark")
                    Text(contact.name)
                        .lineLimit(1)
                    Spacer()
                }
                .frame(height: groupMemberRowHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    contactEditing = contact
                }
            }
        }
    }

    private func fallbackTitle(for sectionKey: String) -> String {
        if let section = allDisplayedSections.first(where: { $0.sectionKey == sectionKey }) {
            return section.fallbackTitle
        }
        return "Group"
    }

    private func contactsForSection(_ sectionKey: String) -> [Contact] {
        let ids = Set(sectionMemberships.filter { $0.sectionKey == sectionKey }.map(\.contactID))
        return contacts.filter { ids.contains($0.id) }
    }

    private func assignContact(_ contactID: UUID, toSection sectionKey: String) {
        guard !sectionMemberships.contains(where: { $0.contactID == contactID && $0.sectionKey == sectionKey }) else {
            return
        }
        dataContext.insert(ContactSectionMembership(contactID: contactID, sectionKey: sectionKey))
    }

    private func removeContact(_ contactID: UUID, fromSection sectionKey: String) {
        for membership in sectionMemberships where membership.contactID == contactID && membership.sectionKey == sectionKey {
            dataContext.delete(membership)
        }
        saveContext()
    }

    private func syncMembers(for sectionKey: String, selectedIDs: Set<UUID>) {
        let existingIDs = Set(sectionMemberships.filter { $0.sectionKey == sectionKey }.map(\.contactID))
        let idsToAdd = selectedIDs.subtracting(existingIDs)
        let idsToRemove = existingIDs.subtracting(selectedIDs)

        for contactID in idsToAdd {
            assignContact(contactID, toSection: sectionKey)
        }
        for contactID in idsToRemove {
            for membership in sectionMemberships where membership.contactID == contactID && membership.sectionKey == sectionKey {
                dataContext.delete(membership)
            }
        }
        saveContext()
    }

    private func clearGroup(_ sectionKey: String) {
        for membership in sectionMemberships where membership.sectionKey == sectionKey {
            dataContext.delete(membership)
        }
        removeCustomTitle(for: sectionKey)
        saveContext()
    }

    private func saveContext() {
        do {
            try dataContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private var primarySections: [ContactSectionKey] {
        [
            .registrar,
            .coordinatorsSenior,
            .coordinatorsJunior,
            .marketing,
            .committee,
            .other
        ]
    }

    private var customSectionTitles: [String: String] {
        guard
            let data = customSectionTitlesData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private func displayTitle(for sectionKey: String, fallback: String) -> String {
        if let custom = customSectionTitles[sectionKey], !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        return fallback
    }

    private func setCustomTitle(_ title: String, for sectionKey: String, fallback: String) {
        var updated = customSectionTitles
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned == fallback {
            updated.removeValue(forKey: sectionKey)
        } else {
            updated[sectionKey] = cleaned
        }
        if let data = try? JSONEncoder().encode(updated), let json = String(data: data, encoding: .utf8) {
            customSectionTitlesData = json
        }
    }

    private func removeCustomTitle(for sectionKey: String) {
        var updated = customSectionTitles
        updated.removeValue(forKey: sectionKey)
        if let data = try? JSONEncoder().encode(updated), let json = String(data: data, encoding: .utf8) {
            customSectionTitlesData = json
        }
    }

    private func saveCustomGroupKeys(_ keys: [String]) {
        guard let data = try? JSONEncoder().encode(keys), let json = String(data: data, encoding: .utf8) else { return }
        customSectionKeysData = json
    }

    private func saveHiddenGroupKeys(_ keys: Set<String>) {
        guard let data = try? JSONEncoder().encode(Array(keys)), let json = String(data: data, encoding: .utf8) else { return }
        hiddenSectionKeysData = json
    }

    private func applyGroupDrafts(_ drafts: [GroupManagementDraft]) {
        let existingKeys = Set(manageableGroups.map(\.sectionKey))
        let keptKeys = Set(drafts.map(\.sectionKey))
        let deletedKeys = existingKeys.subtracting(keptKeys)

        for key in deletedKeys {
            clearGroup(key)
        }

        var updatedHidden = hiddenGroupKeys
        let customKeys = drafts.filter(\.isCustom).map(\.sectionKey)
        saveCustomGroupKeys(customKeys)

        let baseKeys = Set((baseSections + customSections).filter { !$0.section.isCustom }.map(\.sectionKey))
        for key in deletedKeys where baseKeys.contains(key) {
            updatedHidden.insert(key)
        }
        saveHiddenGroupKeys(updatedHidden)

        for draft in drafts {
            setCustomTitle(draft.name, for: draft.sectionKey, fallback: draft.fallbackTitle)
        }
    }
}

private struct GroupSectionSelection: Identifiable {
    let sectionKey: String
    let fallbackTitle: String

    var id: String { sectionKey }
}

private struct GroupSectionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let contacts: [Contact]
    let selectedContactIDs: Set<UUID>
    let onToggleContact: (UUID, Bool) -> Void
    let onEditContact: (Contact) -> Void
    let onAddContact: (String, String, String) -> Bool

    @State private var showAddContact = false

    var body: some View {
        NavigationStack {
            List {
                if contacts.isEmpty {
                    Text("No contacts available.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(contacts) { contact in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(contact.name)
                                    .font(.headline)
                                if !contact.mobile.isEmpty {
                                    Text(contact.mobile.formattedMobileNumber)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if !contact.email.isEmpty {
                                    Text(contact.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button {
                                let isSelected = selectedContactIDs.contains(contact.id)
                                onToggleContact(contact.id, !isSelected)
                            } label: {
                                Image(systemName: selectedContactIDs.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                                    .imageScale(.large)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                selectedContactIDs.contains(contact.id)
                                    ? "Remove \(contact.name) from \(title)"
                                    : "Add \(contact.name) to \(title)"
                            )
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let isSelected = selectedContactIDs.contains(contact.id)
                            onToggleContact(contact.id, !isSelected)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                onEditContact(contact)
                            } label: {
                                Label("Edit Contact", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddContact = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Contact")
                }
            }
        }
        .sheet(isPresented: $showAddContact) {
            ContactEditSheet(
                title: "Add Contact",
                allowsSaveAndAddAnother: false,
                onSave: { name, mobile, email in
                    onAddContact(name, mobile, email)
                }
            )
            .appPopupStyle()
        }
    }
}

private struct GroupSectionDescriptor {
    enum SectionKind: Equatable {
        case fixed(ContactSectionKey)
        case coachesGrade
        case custom

        var isCustom: Bool {
            self == .custom
        }
    }

    let section: SectionKind
    let sectionKey: String
    let fallbackTitle: String
}

private struct PinCodeSettingsView: View {
    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        Form {
            Section("Verify Current Code") {
                SecureField("Current 4-digit code", text: $currentPIN)
                    .keyboardType(.numberPad)
            }

            Section("Set New Code") {
                SecureField("New 4-digit code", text: $newPIN)
                    .keyboardType(.numberPad)
                SecureField("Confirm new code", text: $confirmPIN)
                    .keyboardType(.numberPad)
            }

            Section {
                Button("Change Delete Code") {
                    changeCode()
                }
            }

            if let successMessage {
                Section {
                    Text(successMessage)
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("PIN Code")
        .alert(
            "Could Not Change Code",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func changeCode() {
        successMessage = nil
        let trimmedCurrent = currentPIN.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newPIN.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirm = confirmPIN.trimmingCharacters(in: .whitespacesAndNewlines)

        guard DeleteCodeStore.verify(trimmedCurrent) else {
            errorMessage = "Current code is incorrect."
            return
        }

        guard DeleteCodeStore.isValidCode(trimmedNew) else {
            errorMessage = "New code must be exactly 4 digits."
            return
        }

        guard trimmedNew == trimmedConfirm else {
            errorMessage = "New code and confirmation do not match."
            return
        }

        DeleteCodeStore.save(trimmedNew)
        currentPIN = ""
        newPIN = ""
        confirmPIN = ""
        successMessage = "Delete code updated successfully."
    }
}

private enum ContactSectionKey: Hashable, Identifiable {
    case coaches
    case coachesGrade(UUID)
    case registrar
    case coordinatorsSenior
    case coordinatorsJunior
    case marketing
    case committee
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coaches: return "Coaching Staff"
        case .coachesGrade: return "Grade"
        case .registrar: return "Registrar"
        case .coordinatorsSenior: return "Coordinators - Senior"
        case .coordinatorsJunior: return "Coordinators - Junior"
        case .marketing: return "Marketing"
        case .committee: return "Committee"
        case .other: return "Other"
        }
    }

    var rawValue: String {
        switch self {
        case .coaches:
            return "coaches"
        case let .coachesGrade(gradeID):
            return "coaches:\(gradeID.uuidString)"
        case .registrar:
            return "registrar"
        case .coordinatorsSenior:
            return "coordinators:senior"
        case .coordinatorsJunior:
            return "coordinators:junior"
        case .marketing:
            return "marketing"
        case .committee:
            return "committee"
        case .other:
            return "other"
        }
    }

    static func fromRawValue(_ value: String) -> ContactSectionKey {
        if value == ContactSectionKey.coaches.rawValue { return .coaches }
        if value == ContactSectionKey.registrar.rawValue { return .registrar }
        if value == ContactSectionKey.coordinatorsSenior.rawValue { return .coordinatorsSenior }
        if value == ContactSectionKey.coordinatorsJunior.rawValue { return .coordinatorsJunior }
        if value == ContactSectionKey.marketing.rawValue { return .marketing }
        if value == ContactSectionKey.committee.rawValue { return .committee }
        if value == ContactSectionKey.other.rawValue { return .other }
        if value.hasPrefix("coaches:"), let uuid = UUID(uuidString: String(value.dropFirst("coaches:".count))) {
            return .coachesGrade(uuid)
        }
        return .other
    }
}

private struct GroupNameEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    var initialName: String = ""
    let onSave: (String) -> Bool

    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Group name", text: $name)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if onSave(cleaned) { dismiss() }
                    }
                    .saveButtonBehavior(isEnabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                name = initialName
            }
        }
    }
}

private struct GroupMembersSheet: View {
    let group: ContactGroup
    let contacts: [Contact]
    let memberships: [ContactGroupMembership]
    let onAssign: (UUID) -> Void
    let onRemove: (UUID) -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var isRenaming = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(contacts) { contact in
                    Button {
                        if isInGroup(contact.id) {
                            onRemove(contact.id)
                        } else {
                            onAssign(contact.id)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(contact.name)
                                Text(contact.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isInGroup(contact.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle(group.name)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Rename") { isRenaming = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete", role: .destructive) { onDelete() }
                }
            }
        }
        .sheet(isPresented: $isRenaming) {
            GroupNameEditSheet(title: "Rename Group", initialName: group.name) { newName in
                guard !newName.isEmpty else { return false }
                onRename(newName)
                return true
            }
            .appPopupStyle()
        }
    }

    private func isInGroup(_ contactID: UUID) -> Bool {
        memberships.contains(where: { $0.groupID == group.id && $0.contactID == contactID })
    }
}

private struct ContactEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let initialName: String
    let initialMobile: String
    let initialEmail: String
    let allowsSaveAndAddAnother: Bool
    let onSave: (String, String, String) -> Bool
    let onDelete: (() -> Void)?

    @State private var name: String
    @State private var mobile: String
    @State private var email: String
    @State private var showDeleteConfirmation = false

    init(
        title: String,
        initialName: String = "",
        initialMobile: String = "",
        initialEmail: String = "",
        allowsSaveAndAddAnother: Bool = false,
        onSave: @escaping (String, String, String) -> Bool,
        onDelete: (() -> Void)? = nil
    ) {
        self.title = title
        self.initialName = initialName
        self.initialMobile = initialMobile
        self.initialEmail = initialEmail
        self.allowsSaveAndAddAnother = allowsSaveAndAddAnother
        self.onSave = onSave
        self.onDelete = onDelete

        _name = State(initialValue: initialName)
        _mobile = State(initialValue: initialMobile)
        _email = State(initialValue: initialEmail)
    }

    private var canSave: Bool {
        !clean(name).isEmpty &&
        !clean(mobile).isEmpty &&
        !clean(email).isEmpty
    }

    private var hasChanges: Bool {
        clean(name) != clean(initialName) ||
        clean(mobile) != clean(initialMobile) ||
        clean(email) != clean(initialEmail)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)

                TextField("Mobile", text: $mobile)
                    .keyboardType(.phonePad)

                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if onDelete != nil {
                    Section {
                        Button("Delete Contact", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveAndClose() }
                        .buttonStyle(.borderedProminent)
                        .saveButtonBehavior(isEnabled: canSave && hasChanges)
                }
                if allowsSaveAndAddAnother {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save & Add Another") {
                            saveAndAddAnother()
                        }
                        .buttonStyle(.borderedProminent)
                        .saveButtonBehavior(isEnabled: canSave)
                    }
                }
            }
        }
        .alert("Delete contact?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This contact will be permanently deleted.")
        }
    }

    private func saveAndClose() {
        guard onSave(clean(name), clean(mobile), clean(email)) else { return }
        dismiss()
    }

    private func saveAndAddAnother() {
        guard onSave(clean(name), clean(mobile), clean(email)) else { return }
        name = ""
        mobile = ""
        email = ""
    }

    private func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct AddContactsToSectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let contacts: [Contact]
    let assignedContactIDs: Set<UUID>
    let onAddExisting: (Set<UUID>) -> Void
    let onAddNew: (_ name: String, _ mobile: String, _ email: String) -> Void

    @State private var selectedContactIDs: Set<UUID> = []
    @State private var showingAddNewContact = false

    private var hasAnyContacts: Bool {
        !contacts.isEmpty
    }

    private var availableContacts: [Contact] {
        contacts.filter { !assignedContactIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if availableContacts.isEmpty {
                    Text(hasAnyContacts ? "All contacts are already in this section." : "No contacts available yet. Add a new contact below.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(availableContacts) { contact in
                        Button {
                            if selectedContactIDs.contains(contact.id) {
                                selectedContactIDs.remove(contact.id)
                            } else {
                                selectedContactIDs.insert(contact.id)
                            }
                        } label: {
                            HStack {
                                Text(contact.name)
                                Spacer()
                                if selectedContactIDs.contains(contact.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Contacts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Selected") {
                        onAddExisting(selectedContactIDs)
                        dismiss()
                    }
                    .disabled(selectedContactIDs.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        showingAddNewContact = true
                    } label: {
                        Label("Add New", systemImage: "person.badge.plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddNewContact) {
            ContactEditSheet(
                title: "Add Contact",
                allowsSaveAndAddAnother: false,
                onSave: { name, mobile, email in
                    onAddNew(name, mobile, email)
                    return true
                }
            )
            .appPopupStyle()
        }
    }
}

private struct GroupManagementDraft: Identifiable, Equatable {
    let sectionKey: String
    var name: String
    let fallbackTitle: String
    let isCustom: Bool

    var id: String { sectionKey }
}

private struct GroupManagerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: ([GroupManagementDraft]) -> Void

    @State private var draftGroups: [GroupManagementDraft]
    @State private var initialGroups: [GroupManagementDraft]
    @State private var pendingDeleteGroupID: GroupManagementDraft.ID?
    @State private var showDeleteConfirmation = false

    init(initialGroups: [GroupManagementDraft], onSave: @escaping ([GroupManagementDraft]) -> Void) {
        self.onSave = onSave
        _draftGroups = State(initialValue: initialGroups)
        _initialGroups = State(initialValue: initialGroups)
    }

    private var hasChanges: Bool {
        draftGroups != initialGroups
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach($draftGroups) { $group in
                    HStack(spacing: 12) {
                        TextField("Group Name", text: $group.name)
                            .textInputAutocapitalization(.words)

                        Button(role: .destructive) {
                            pendingDeleteGroupID = group.id
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    draftGroups.append(
                        GroupManagementDraft(
                            sectionKey: "custom:\(UUID().uuidString)",
                            name: "",
                            fallbackTitle: "Custom Group",
                            isCustom: true
                        )
                    )
                } label: {
                    Label("Add Group", systemImage: "plus")
                }
            }
            .navigationTitle("Manage Groups")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(normalizedDrafts())
                        dismiss()
                    }
                    .saveButtonBehavior(isEnabled: hasChanges)
                }
            }
        }
        .alert("Delete group?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                guard let groupID = pendingDeleteGroupID else { return }
                draftGroups.removeAll { $0.id == groupID }
                pendingDeleteGroupID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteGroupID = nil
            }
        } message: {
            Text("This removes all contacts from the group.")
        }
    }

    private func normalizedDrafts() -> [GroupManagementDraft] {
        var seen = Set<String>()
        return draftGroups.compactMap { group in
            let cleaned = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = cleaned.isEmpty ? group.fallbackTitle : cleaned
            guard !seen.contains(group.sectionKey) else { return nil }
            seen.insert(group.sectionKey)
            return GroupManagementDraft(
                sectionKey: group.sectionKey,
                name: finalName,
                fallbackTitle: group.fallbackTitle,
                isCustom: group.isCustom
            )
        }
    }
}

struct ReportsSettingsView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext
    @Query(sort: [SortDescriptor(\CustomReportTemplate.name)]) private var templates: [CustomReportTemplate]
    @Query(sort: [SortDescriptor(\Grade.displayOrder), SortDescriptor(\Grade.name)]) private var grades: [Grade]
    @Query(sort: [SortDescriptor(\Contact.name)]) private var contacts: [Contact]
    @Query(sort: [SortDescriptor(\ContactGroup.name)]) private var groups: [ContactGroup]
    @Query private var groupMemberships: [ContactGroupMembership]
    @Query private var sectionMemberships: [ContactSectionMembership]
    @Query private var customReportRecipientSections: [CustomReportRecipientSection]
    @Query private var customReportRecipientGroups: [CustomReportRecipientGroup]
    @Query private var customReportRecipientContacts: [CustomReportRecipientContact]
    @Query(sort: [SortDescriptor(\Game.date, order: .reverse)]) private var games: [Game]
    @Query(sort: [SortDescriptor(\Player.name)]) private var players: [Player]

    @State private var templateEditing: CustomReportTemplate?
    @State private var templateActioning: CustomReportTemplate?
    @State private var templatePreviewing: TemplateRunRequest?
    @State private var isCreatingTemplate = false
    @State private var saveErrorMessage: String?
    @State private var isMoveModeEnabled = false
    @State private var moveDraftOrder: [UUID] = []
    @State private var moveDraftSlots: [UUID?] = []
    @State private var moveInitialOrder: [UUID] = []
    @State private var draggingTemplateID: UUID?
    @State private var draggingTranslation: CGSize = .zero
    @State private var draggingStartSlotIndex: Int?
    @State private var isDiscardMoveChangesAlertPresented = false
    @State private var activeTemplateGridColumnCount = UIDevice.current.userInterfaceIdiom == .phone ? 1 : 4
    @AppStorage("reports.templateOrder.v1") private var templateOrderData = ""
    var onOpenContactsSettings: (() -> Void)? = nil

    private func templateGridColumnCount(for size: CGSize) -> Int {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return size.height > size.width ? 1 : 2
        }
        if UIDevice.current.userInterfaceIdiom == .pad && size.height > size.width {
            return 3
        }
        return 4
    }
    private let templateGridSpacing: CGFloat = 12
    private let templateTileHeight: CGFloat = 118

    private var displayedTemplates: [CustomReportTemplate] {
        let templateByID = Dictionary(templates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let activeOrder = activeTemplateOrderIDs()
        let orderedFromStore = activeOrder.compactMap { templateByID[$0] }
        let remaining = templates.filter { !activeOrder.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return orderedFromStore + remaining
    }

    private func templateGridColumns(columnCount: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: templateGridSpacing), count: columnCount)
    }

    private func placeholderSlotCount(columnCount: Int) -> Int {
        let minimumSlots = columnCount * 2
        let templateCount = displayedTemplates.count
        let requiredSlots = templateCount + (isMoveModeEnabled ? 0 : 1)
        let visibleSlots = max(minimumSlots, requiredSlots)
        let rowCount = Int(ceil(Double(visibleSlots) / Double(columnCount)))
        return rowCount * columnCount
    }

    private var isTemplateActionDialogPresented: Binding<Bool> {
        Binding(
            get: { templateActioning != nil },
            set: { isPresented in
                if !isPresented {
                    templateActioning = nil
                }
            }
        )
    }

    private var isSaveErrorAlertPresented: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    saveErrorMessage = nil
                }
            }
        )
    }

    private var hasMoveOrderChanges: Bool {
        moveDraftSlots.compactMap { $0 } != moveInitialOrder
    }

    var body: some View {
        GeometryReader { viewProxy in
            let columnCount = templateGridColumnCount(for: viewProxy.size)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                if isMoveModeEnabled {
                    HStack {
                        Button("Back") {
                            handleMoveModeBackTapped()
                        }
                        .font(.headline)

                        Spacer()

                        Button("Save") {
                            finishMoveModeAndSave()
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(hasMoveOrderChanges ? Color(uiColor: .systemGray) : ClubTheme.subCardFill)
                        .foregroundStyle(hasMoveOrderChanges ? Color.white : Color.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .buttonStyle(.plain)
                        .disabled(!hasMoveOrderChanges)
                    }
                    .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 12) {
                    if templates.isEmpty {
                        Text("No custom reports yet. Create one to save reusable report filters.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { proxy in
                        let tileWidth = max(
                            0,
                            (proxy.size.width - (templateGridSpacing * CGFloat(columnCount - 1)))
                            / CGFloat(columnCount)
                        )

                        LazyVGrid(columns: templateGridColumns(columnCount: columnCount), spacing: templateGridSpacing) {
                            ForEach(0..<placeholderSlotCount(columnCount: columnCount), id: \.self) { index in
                                slotTile(at: index, tileWidth: tileWidth, columnCount: columnCount)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: gridHeightEstimate(columnCount: columnCount))
                }
                .padding(14)
                .clubGlassSurface(cornerRadius: 18)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Reports")
        .onAppear {
            updateActiveTemplateGridColumnCount(columnCount)
            syncTemplateOrderWithCurrentTemplates()
        }
        .onChange(of: viewProxy.size) { _, newSize in
            updateActiveTemplateGridColumnCount(templateGridColumnCount(for: newSize))
        }
        .onChange(of: templates.map(\.id)) { _, _ in
            syncTemplateOrderWithCurrentTemplates()
            syncMoveDraftWithCurrentTemplates()
        }
        .confirmationDialog(
            "Report actions",
            isPresented: isTemplateActionDialogPresented,
            titleVisibility: .visible,
            actions: templateActionDialogActions
        )
        .sheet(isPresented: $isCreatingTemplate) {
            CustomReportEditView(
                grades: grades,
                contacts: contacts,
                sectionMemberships: sectionMemberships
            ) { draft in
                handleCreateTemplateSave(draft)
            }
            .appPopupStyle()
        }
        .sheet(item: $templatePreviewing) { request in
            CustomReportPreviewView(
                template: request.template,
                grades: grades,
                games: games,
                players: players,
                selectedDateRange: request.dateRange,
                emailRecipients: request.emailRecipients
            )
                .appPopupStyle()
        }
        .sheet(item: $templateEditing) { template in
            CustomReportEditView(
                grades: grades,
                contacts: contacts,
                sectionMemberships: sectionMemberships,
                initialName: template.name,
                initialSelectedGradeIDs: template.gradeIDs,
                initialSendReportOnGameSave: template.sendReportOnGameSave,
                initialSendReportTriggerGradeID: template.sendReportTriggerGradeID,
                initialDisplayOfficialsInListView: template.displayOfficialsInListView,
                initialIncludeScores: template.includeScores,
                initialIncludeBestPlayers: template.includeBestPlayers,
                initialBestPlayersLimit: template.bestPlayersLimit,
                initialIncludeGuestVotes: template.includePlayerGrades,
                initialGuestVotesLimit: template.guestVotesLimit,
                initialIncludeGoalKickers: template.includeGoalKickers,
                initialGoalKickersLimit: template.goalKickersLimit,
                initialIncludeBestAndFairestVotes: template.includeBestAndFairestVotes,
                initialBestAndFairestLimit: template.bestAndFairestLimit,
                initialIncludeStaffRoles: template.includeStaffRoles,
                initialIncludeOfficials: template.includeOfficials,
                initialIncludeUmpires: template.includeUmpires,
                initialIncludeTrainers: template.includeTrainers,
                initialIncludeMatchNotes: template.includeMatchNotes,
                initialIncludedDataOrder: template.includeSectionOrder,
                initialReportColumnCount: template.normalizedReportColumnCount,
                initialIncludedDataColumns: template.includeSectionColumnAssignments,
                initialIncludeOnlyActiveGrades: template.includeOnlyActiveGrades,
                initialIncludePlayersOnly: template.includePlayersOnly,
                initialPlayersOnlyGradeFilterIDs: template.playersOnlyGradeFilterIDs,
                initialMinimumGamesPlayed: template.minimumGamesPlayed,
                initialGroupingModeRawValue: template.groupingModeRawValue,
                initialDateRangeQuickPickRawValue: template.dateRangeQuickPickRawValue,
                initialCustomDateRangeStart: template.customDateRangeStart,
                initialCustomDateRangeEnd: template.customDateRangeEnd,
                initialRecipientSectionKeys: customReportRecipientSections
                    .filter { $0.templateID == template.id }
                    .map(\.sectionKey),
                initialRecipientContactIDs: customReportRecipientContacts
                    .filter { $0.templateID == template.id }
                    .map(\.contactID),
                onDelete: {
                    deleteTemplate(template)
                }
            ) { draft in
                handleEditTemplateSave(draft, template: template)
            }
            .appPopupStyle()
        }
        .alert("Save Error", isPresented: isSaveErrorAlertPresented) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
        .alert("Discard changes?", isPresented: $isDiscardMoveChangesAlertPresented) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard Changes", role: .destructive) {
                cancelMoveMode()
            }
        } message: {
            Text("You have unsaved report order changes. If you go back now, your changes will be lost.")
        }
        }
    }

    @ViewBuilder
    private func templateActionDialogActions() -> some View {
        if let template = templateActioning {
            Button("Edit") {
                templateEditing = template
            }
            Button("Duplicate") {
                duplicateTemplate(template)
            }
            Button("Preview") {
                templatePreviewing = TemplateRunRequest(
                    template: template,
                    dateRange: reportDateRange(for: template),
                    emailRecipients: recipientEmails(for: template)
                )
            }
            Button("Move") {
                beginMoveMode()
            }
            Button("Delete Report", role: .destructive) {
                deleteTemplate(template)
            }
        }
    }

    private func handleCreateTemplateSave(_ draft: CustomReportTemplateDraft) {
        let normalizedStart = min(draft.customDateRangeStart, draft.customDateRangeEnd)
        let normalizedEnd = max(draft.customDateRangeStart, draft.customDateRangeEnd)
        let template = CustomReportTemplate(
            name: draft.name,
            gradeIDs: draft.selectedGradeIDs,
            includeScores: draft.includeScores,
            includeBestPlayers: draft.includeBestPlayers,
            bestPlayersLimit: draft.bestPlayersLimit,
            includePlayerGrades: draft.includeGuestVotes,
            guestVotesLimit: draft.guestVotesLimit,
            includeGoalKickers: draft.includeGoalKickers,
            goalKickersLimit: draft.goalKickersLimit,
            includeGuernseyNumbers: false,
            includeBestAndFairestVotes: draft.includeBestAndFairestVotes,
            bestAndFairestLimit: draft.bestAndFairestLimit,
            includeStaffRoles: draft.includeStaffRoles,
            includeOfficials: draft.includeOfficials,
            displayOfficialsInListView: draft.displayOfficialsInListView,
            includeUmpires: draft.includeOfficials,
            includeTrainers: draft.includeTrainers,
            includeMatchNotes: draft.includeMatchNotes,
            includeSectionOrder: draft.includedDataOrder,
            reportColumnCount: draft.reportColumnCount,
            includeSectionColumnAssignments: draft.includedDataColumns,
            sendReportOnGameSave: draft.sendReportOnGameSave,
            sendReportTriggerGradeID: draft.sendReportTriggerGradeID,
            includeOnlyActiveGrades: draft.includeOnlyActiveGrades,
            includePlayersOnly: draft.includePlayersOnly,
            playersOnlyGradeFilterIDs: draft.playersOnlyGradeFilterIDs,
            minimumGamesPlayed: draft.minimumGamesPlayed,
            groupingModeRawValue: draft.groupingModeRawValue,
            dateRangeQuickPickRawValue: draft.selectedQuickPickRawValue,
            customDateRangeStart: normalizedStart,
            customDateRangeEnd: normalizedEnd
        )
        dataContext.insert(template)
        draft.selectedRecipientSectionKeys.forEach { sectionKey in
            dataContext.insert(CustomReportRecipientSection(templateID: template.id, sectionKey: sectionKey))
        }
        draft.selectedRecipientContactIDs.forEach { contactID in
            dataContext.insert(CustomReportRecipientContact(templateID: template.id, contactID: contactID))
        }
        saveContext()

        let selectedQuickPick = ReportRangeQuickPick(rawValue: draft.selectedQuickPickRawValue) ?? .mostRecentGame
        let selectedDateRange = buildDateRange(
            for: selectedQuickPick,
            template: template,
            games: games,
            customStartDate: normalizedStart,
            customEndDate: normalizedEnd
        )
        templatePreviewing = TemplateRunRequest(
            template: template,
            dateRange: selectedDateRange,
            emailRecipients: recipientEmails(for: template)
        )
    }

    private func handleEditTemplateSave(_ draft: CustomReportTemplateDraft, template: CustomReportTemplate) {
        let normalizedStart = min(draft.customDateRangeStart, draft.customDateRangeEnd)
        let normalizedEnd = max(draft.customDateRangeStart, draft.customDateRangeEnd)

        template.name = draft.name
        template.gradeIDs = draft.selectedGradeIDs
        template.sendReportOnGameSave = draft.sendReportOnGameSave
        template.sendReportTriggerGradeID = draft.sendReportTriggerGradeID
        template.includeScores = draft.includeScores
        template.includeBestPlayers = draft.includeBestPlayers
        template.bestPlayersLimit = draft.bestPlayersLimit
        template.includePlayerGrades = draft.includeGuestVotes
        template.guestVotesLimit = draft.guestVotesLimit
        template.includeGoalKickers = draft.includeGoalKickers
        template.goalKickersLimit = draft.goalKickersLimit
        template.includeGuernseyNumbers = false
        template.includeBestAndFairestVotes = draft.includeBestAndFairestVotes
        template.bestAndFairestLimit = draft.bestAndFairestLimit
        template.includeStaffRoles = draft.includeStaffRoles
        template.includeOfficials = draft.includeOfficials
        template.displayOfficialsInListView = draft.displayOfficialsInListView
        template.includeUmpires = draft.includeOfficials
        template.includeTrainers = draft.includeTrainers
        template.includeMatchNotes = draft.includeMatchNotes
        template.includeSectionOrder = draft.includedDataOrder
        template.reportColumnCount = draft.reportColumnCount
        template.includeSectionColumnAssignments = draft.includedDataColumns
        template.includeOnlyActiveGrades = draft.includeOnlyActiveGrades
        template.includePlayersOnly = draft.includePlayersOnly
        template.playersOnlyGradeFilterIDs = draft.playersOnlyGradeFilterIDs
        template.minimumGamesPlayed = draft.minimumGamesPlayed
        template.groupingModeRawValue = draft.groupingModeRawValue
        template.dateRangeQuickPickRawValue = draft.selectedQuickPickRawValue
        template.customDateRangeStart = normalizedStart
        template.customDateRangeEnd = normalizedEnd

        for recipientSection in customReportRecipientSections where recipientSection.templateID == template.id {
            dataContext.delete(recipientSection)
        }
        for recipientGroup in customReportRecipientGroups where recipientGroup.templateID == template.id {
            dataContext.delete(recipientGroup)
        }
        for recipientContact in customReportRecipientContacts where recipientContact.templateID == template.id {
            dataContext.delete(recipientContact)
        }
        draft.selectedRecipientSectionKeys.forEach { sectionKey in
            dataContext.insert(CustomReportRecipientSection(templateID: template.id, sectionKey: sectionKey))
        }
        draft.selectedRecipientContactIDs.forEach { contactID in
            dataContext.insert(CustomReportRecipientContact(templateID: template.id, contactID: contactID))
        }
        saveContext()
    }

    @ViewBuilder
    private func placeholderTile(at index: Int) -> some View {
        let isCreateSlot = !isMoveModeEnabled && index == displayedTemplates.count
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(ClubTheme.subCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(ClubTheme.subCardStroke, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            )
            .overlay {
                if isCreateSlot {
                    Button {
                        isCreatingTemplate = true
                    } label: {
                        Text("+")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.tint)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Create Custom Report")
                }
            }
            .frame(height: templateTileHeight)
    }

    private func saveContext() {
        do {
            try dataContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func slotTile(at index: Int, tileWidth: CGFloat, columnCount: Int) -> some View {
        if let template = templateForSlot(index) {
            let tile = reportTile(for: template, tileWidth: tileWidth, columnCount: columnCount)
            if isMoveModeEnabled {
                tile.zIndex(draggingTemplateID == template.id ? 2 : 1)
            } else {
                tile
            }
        } else {
            placeholderTile(at: index)
        }
    }

    @ViewBuilder
    private func reportTile(for template: CustomReportTemplate, tileWidth: CGFloat, columnCount: Int) -> some View {
        let baseTile = VStack(spacing: 6) {
            Text(template.name)
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(gradesSummary(for: template))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(dateRangeSummary(for: template))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            guard !isMoveModeEnabled else { return }
            templatePreviewing = TemplateRunRequest(
                template: template,
                dateRange: reportDateRange(for: template),
                emailRecipients: recipientEmails(for: template)
            )
        }
        .onLongPressGesture {
            if isMoveModeEnabled { return }
            templateActioning = template
        }
        .scaleEffect(draggingTemplateID == template.id ? 1.08 : (isMoveModeEnabled ? 1.02 : 1))
        .offset(draggingTemplateID == template.id ? draggingTranslation : .zero)
        .shadow(color: .black.opacity(draggingTemplateID == template.id ? 0.2 : 0), radius: 12, y: 8)
        .frame(maxWidth: .infinity)
        .frame(height: templateTileHeight)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ClubTheme.subCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ClubTheme.subCardStroke, lineWidth: 1)
        )

        if isMoveModeEnabled {
            baseTile
                .gesture(templateMoveGesture(for: template.id, tileWidth: tileWidth, columnCount: columnCount))
        } else {
            baseTile
        }
    }

    private func deleteTemplate(_ template: CustomReportTemplate) {
        for recipientSection in customReportRecipientSections where recipientSection.templateID == template.id {
            dataContext.delete(recipientSection)
        }
        for recipientGroup in customReportRecipientGroups where recipientGroup.templateID == template.id {
            dataContext.delete(recipientGroup)
        }
        for recipientContact in customReportRecipientContacts where recipientContact.templateID == template.id {
            dataContext.delete(recipientContact)
        }
        dataContext.delete(template)
        removeTemplateIDFromOrder(template.id)
        saveContext()
    }

    private func duplicateTemplate(_ template: CustomReportTemplate) {
        let duplicatedTemplate = CustomReportTemplate(
            name: "\(template.name) Copy",
            gradeIDs: template.gradeIDs,
            includeScores: template.includeScores,
            includeBestPlayers: template.includeBestPlayers,
            bestPlayersLimit: template.bestPlayersLimit,
            includePlayerGrades: template.includePlayerGrades,
            guestVotesLimit: template.guestVotesLimit,
            includeGoalKickers: template.includeGoalKickers,
            goalKickersLimit: template.goalKickersLimit,
            includeGuernseyNumbers: template.includeGuernseyNumbers,
            includeBestAndFairestVotes: template.includeBestAndFairestVotes,
            bestAndFairestLimit: template.bestAndFairestLimit,
            includeStaffRoles: template.includeStaffRoles,
            includeOfficials: template.includeOfficials,
            displayOfficialsInListView: template.displayOfficialsInListView,
            includeUmpires: template.includeUmpires,
            includeTrainers: template.includeTrainers,
            includeMatchNotes: template.includeMatchNotes,
            includeSectionOrder: template.includeSectionOrder,
            reportColumnCount: template.normalizedReportColumnCount,
            includeSectionColumnAssignments: template.includeSectionColumnAssignments,
            sendReportOnGameSave: template.sendReportOnGameSave,
            sendReportTriggerGradeID: template.sendReportTriggerGradeID,
            includeOnlyActiveGrades: template.includeOnlyActiveGrades,
            includePlayersOnly: template.includePlayersOnly,
            playersOnlyGradeFilterIDs: template.playersOnlyGradeFilterIDs,
            minimumGamesPlayed: template.minimumGamesPlayed,
            groupingModeRawValue: template.groupingModeRawValue,
            dateRangeQuickPickRawValue: template.dateRangeQuickPickRawValue,
            customDateRangeStart: template.customDateRangeStart,
            customDateRangeEnd: template.customDateRangeEnd
        )
        dataContext.insert(duplicatedTemplate)
        for section in customReportRecipientSections where section.templateID == template.id {
            dataContext.insert(CustomReportRecipientSection(templateID: duplicatedTemplate.id, sectionKey: section.sectionKey))
        }
        for group in customReportRecipientGroups where group.templateID == template.id {
            dataContext.insert(CustomReportRecipientGroup(templateID: duplicatedTemplate.id, groupID: group.groupID))
        }
        for contact in customReportRecipientContacts where contact.templateID == template.id {
            dataContext.insert(CustomReportRecipientContact(templateID: duplicatedTemplate.id, contactID: contact.contactID))
        }
        appendTemplateIDToOrder(duplicatedTemplate.id)
        saveContext()
        templateEditing = duplicatedTemplate
    }

    private func beginMoveMode() {
        syncTemplateOrderWithCurrentTemplates()
        moveDraftOrder = persistedTemplateOrderIDs()
        moveInitialOrder = moveDraftOrder
        moveDraftSlots = moveDraftOrder.map { Optional($0) }
        let slotCount = placeholderSlotCount(columnCount: activeTemplateGridColumnCount)
        if moveDraftSlots.count < slotCount {
            moveDraftSlots.append(contentsOf: Array(repeating: nil, count: slotCount - moveDraftSlots.count))
        }
        isMoveModeEnabled = true
    }

    private func finishMoveModeAndSave() {
        guard hasMoveOrderChanges else { return }
        moveDraftOrder = moveDraftSlots.compactMap { $0 }
        persistTemplateOrder(moveDraftOrder)
        moveInitialOrder = moveDraftOrder
        isMoveModeEnabled = false
        draggingTemplateID = nil
        draggingTranslation = .zero
        draggingStartSlotIndex = nil
    }

    private func cancelMoveMode() {
        moveDraftOrder = moveInitialOrder
        moveDraftSlots = moveInitialOrder.map { Optional($0) }
        let slotCount = placeholderSlotCount(columnCount: activeTemplateGridColumnCount)
        if moveDraftSlots.count < slotCount {
            moveDraftSlots.append(contentsOf: Array(repeating: nil, count: slotCount - moveDraftSlots.count))
        }
        isMoveModeEnabled = false
        draggingTemplateID = nil
        draggingTranslation = .zero
        draggingStartSlotIndex = nil
    }

    private func handleMoveModeBackTapped() {
        if hasMoveOrderChanges {
            isDiscardMoveChangesAlertPresented = true
        } else {
            cancelMoveMode()
        }
    }

    private func activeTemplateOrderIDs() -> [UUID] {
        isMoveModeEnabled ? moveDraftOrder : persistedTemplateOrderIDs()
    }

    private func syncMoveDraftWithCurrentTemplates() {
        let currentTemplateIDs = Set(templates.map(\.id))
        moveDraftOrder = moveDraftOrder.filter { currentTemplateIDs.contains($0) }
        let missing = templates.map(\.id).filter { !moveDraftOrder.contains($0) }
        moveDraftOrder.append(contentsOf: missing)
        moveDraftSlots = moveDraftSlots.map { slot in
            guard let slot else { return nil }
            return currentTemplateIDs.contains(slot) ? slot : nil
        }
        for id in missing where !moveDraftSlots.contains(id) {
            if let firstEmpty = moveDraftSlots.firstIndex(where: { $0 == nil }) {
                moveDraftSlots[firstEmpty] = id
            } else {
                moveDraftSlots.append(id)
            }
        }
        let slotCount = placeholderSlotCount(columnCount: activeTemplateGridColumnCount)
        if isMoveModeEnabled && moveDraftSlots.count < slotCount {
            moveDraftSlots.append(contentsOf: Array(repeating: nil, count: slotCount - moveDraftSlots.count))
        }
    }

    private func persistedTemplateOrderIDs() -> [UUID] {
        guard let data = templateOrderData.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values.compactMap(UUID.init(uuidString:))
    }

    private func persistTemplateOrder(_ order: [UUID]) {
        let values = order.map(\.uuidString)
        guard let data = try? JSONEncoder().encode(values),
              let value = String(data: data, encoding: .utf8) else { return }
        templateOrderData = value
    }

    private func syncTemplateOrderWithCurrentTemplates() {
        let currentTemplateIDs = templates.map(\.id)
        let existingOrder = persistedTemplateOrderIDs().filter { currentTemplateIDs.contains($0) }
        let missingTemplateIDs = currentTemplateIDs.filter { !existingOrder.contains($0) }
        persistTemplateOrder(existingOrder + missingTemplateIDs)
    }

    private func updateActiveTemplateGridColumnCount(_ columnCount: Int) {
        guard activeTemplateGridColumnCount != columnCount else { return }
        activeTemplateGridColumnCount = columnCount
        guard isMoveModeEnabled else { return }

        let slotCount = placeholderSlotCount(columnCount: columnCount)
        if moveDraftSlots.count < slotCount {
            moveDraftSlots.append(contentsOf: Array(repeating: nil, count: slotCount - moveDraftSlots.count))
        }
    }

    private func appendTemplateIDToOrder(_ id: UUID) {
        var order = persistedTemplateOrderIDs()
        order.removeAll { $0 == id }
        order.append(id)
        persistTemplateOrder(order)
    }

    private func removeTemplateIDFromOrder(_ id: UUID) {
        var order = persistedTemplateOrderIDs()
        order.removeAll { $0 == id }
        persistTemplateOrder(order)
    }

    private func templateMoveGesture(for templateID: UUID, tileWidth: CGFloat, columnCount: Int) -> some Gesture {
        let hold = LongPressGesture(minimumDuration: 0.2)
        let drag = DragGesture(minimumDistance: 0)

        return hold.sequenced(before: drag)
            .onChanged { value in
                guard isMoveModeEnabled else { return }
                switch value {
                case .first(true):
                    if draggingTemplateID != templateID {
                        draggingTemplateID = templateID
                        draggingStartSlotIndex = moveDraftSlots.firstIndex(of: templateID)
                    }
                case .second(true, let dragValue?):
                    if draggingTemplateID != templateID {
                        draggingTemplateID = templateID
                        draggingStartSlotIndex = moveDraftSlots.firstIndex(of: templateID)
                    }
                    draggingTranslation = dragValue.translation
                default:
                    break
                }
            }
            .onEnded { _ in
                commitDragReorder(tileWidth: tileWidth, columnCount: columnCount)
                draggingTemplateID = nil
                draggingTranslation = .zero
                draggingStartSlotIndex = nil
            }
    }

    private func nearestSlotIndex(for translation: CGSize, tileWidth: CGFloat, columnCount: Int) -> Int {
        guard let startSlotIndex = draggingStartSlotIndex else { return 0 }
        let cellWidth = max(tileWidth + templateGridSpacing, 1)
        let cellHeight = templateTileHeight + templateGridSpacing
        let horizontalShift = Int((translation.width / cellWidth).rounded())
        let verticalShift = Int((translation.height / cellHeight).rounded())
        let proposedTarget = startSlotIndex + horizontalShift + (verticalShift * columnCount)
        return min(max(0, proposedTarget), max(moveDraftSlots.count - 1, 0))
    }

    private func commitDragReorder(tileWidth: CGFloat, columnCount: Int) {
        guard let draggingTemplateID else { return }
        guard let sourceIndex = moveDraftSlots.firstIndex(of: draggingTemplateID) else { return }

        let targetIndex = nearestSlotIndex(for: draggingTranslation, tileWidth: tileWidth, columnCount: columnCount)
        guard targetIndex != sourceIndex else { return }

        var currentSlots = moveDraftSlots
        let destinationItem = currentSlots[targetIndex]
        currentSlots[targetIndex] = draggingTemplateID
        currentSlots[sourceIndex] = destinationItem
        moveDraftSlots = currentSlots
    }

    private func gridHeightEstimate(columnCount: Int) -> CGFloat {
        let rowCount: Int = {
            if isMoveModeEnabled {
                return max(1, Int(ceil(Double(placeholderSlotCount(columnCount: columnCount)) / Double(columnCount))))
            }
            return max(1, Int(ceil(Double(displayedTemplates.count + 1) / Double(columnCount))))
        }()
        return (CGFloat(rowCount) * templateTileHeight) + (CGFloat(max(0, rowCount - 1)) * templateGridSpacing)
    }

    private func templateForSlot(_ index: Int) -> CustomReportTemplate? {
        if isMoveModeEnabled {
            guard index < moveDraftSlots.count, let id = moveDraftSlots[index] else { return nil }
            return displayedTemplates.first(where: { $0.id == id })
        }
        guard index < displayedTemplates.count else { return nil }
        return displayedTemplates[index]
    }

    private func gradesSummary(for template: CustomReportTemplate) -> String {
        let selectedGradeNames = grades
            .filter { template.gradeIDs.contains($0.id) }
            .map(\.name)

        return selectedGradeNames.isEmpty ? "All grades" : selectedGradeNames.joined(separator: " • ")
    }

    private func reportDateRange(for template: CustomReportTemplate) -> ReportDateRange {
        let quickPick = ReportRangeQuickPick(rawValue: template.dateRangeQuickPickRawValue) ?? .mostRecentGame
        return buildDateRange(
            for: quickPick,
            template: template,
            games: games,
            customStartDate: template.customDateRangeStart,
            customEndDate: template.customDateRangeEnd
        )
    }

    private func dateRangeSummary(for template: CustomReportTemplate) -> String {
        let quickPick = ReportRangeQuickPick(rawValue: template.dateRangeQuickPickRawValue) ?? .mostRecentGame
        return quickPick.rawValue
    }

    private func recipientEmails(for template: CustomReportTemplate) -> [String] {
        let sectionKeys = Set(
            customReportRecipientSections
                .filter { $0.templateID == template.id }
                .map(\.sectionKey)
        )
        let sectionContactIDs = Set(
            sectionMemberships
                .filter { sectionKeys.contains($0.sectionKey) }
                .map(\.contactID)
        )

        let groupIDs = Set(
            customReportRecipientGroups
                .filter { $0.templateID == template.id }
                .map(\.groupID)
        )
        let groupContactIDs = Set(
            groupMemberships
                .filter { groupIDs.contains($0.groupID) }
                .map(\.contactID)
        )

        let individualContactIDs = Set(
            customReportRecipientContacts
                .filter { $0.templateID == template.id }
                .map(\.contactID)
        )

        let contactIDs = sectionContactIDs
            .union(groupContactIDs)
            .union(individualContactIDs)

        return contacts
            .filter { contactIDs.contains($0.id) }
            .map { $0.email.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

private struct TemplateRunRequest: Identifiable {
    let template: CustomReportTemplate
    let dateRange: ReportDateRange
    let emailRecipients: [String]

    var id: String {
        "\(template.id.uuidString)-\(dateRange.start.timeIntervalSince1970)-\(dateRange.end.timeIntervalSince1970)"
    }
}

struct ReportDateRange {
    let start: Date
    let end: Date

    func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}

enum ReportRangeQuickPick: String, CaseIterable, Identifiable {
    case mostRecentGame = "Most Recent Game"
    case previousWeek = "Previous Week"
    case previousMonth = "Previous Month"
    case currentYear = "Current Year"
    case custom = "Custom Date Range"

    var id: String { rawValue }
}

func buildDateRange(
    for quickPick: ReportRangeQuickPick,
    template: CustomReportTemplate,
    games: [Game],
    customStartDate: Date,
    customEndDate: Date
) -> ReportDateRange {
    let calendar = Calendar.current
    let today = Date()
    switch quickPick {
    case .mostRecentGame:
        let scopedGames = games
            .filter { template.gradeIDs.isEmpty || template.gradeIDs.contains($0.gradeID) }
            .filter { !$0.isDraft && $0.date <= today }
        let mostRecentGameDate = scopedGames.map(\.date).max() ?? today
        let dayStart = calendar.startOfDay(for: mostRecentGameDate)
        let dayEnd = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: dayStart) ?? mostRecentGameDate
        return ReportDateRange(start: dayStart, end: dayEnd)
    case .previousWeek:
        let dayStart = calendar.startOfDay(for: today)
        let start = calendar.date(byAdding: .day, value: -7, to: dayStart) ?? dayStart
        let end = calendar.date(byAdding: DateComponents(second: -1), to: dayStart) ?? today
        return ReportDateRange(start: start, end: end)
    case .previousMonth:
        let dayStart = calendar.startOfDay(for: today)
        let start = calendar.date(byAdding: .month, value: -1, to: dayStart) ?? dayStart
        let end = calendar.date(byAdding: DateComponents(second: -1), to: dayStart) ?? today
        return ReportDateRange(start: start, end: end)
    case .currentYear:
        let year = calendar.component(.year, from: today)
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? calendar.startOfDay(for: today)
        return ReportDateRange(start: start, end: today)
    case .custom:
        let start = min(customStartDate, customEndDate)
        let end = max(customStartDate, customEndDate)
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        return ReportDateRange(
            start: startDay,
            end: calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endDay) ?? end
        )
    }
}

private struct CustomReportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigationState: AppNavigationState

    let template: CustomReportTemplate
    let grades: [Grade]
    let games: [Game]
    let players: [Player]
    let selectedDateRange: ReportDateRange
    let emailRecipients: [String]
    @State private var pdfURL: URL?
    @State private var errorMessage: String?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if let pdfURL {
                    PDFPreviewView(url: pdfURL)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 30))
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    LoadingFootballView("Generating PDF preview…")
                }
            }
            .navigationTitle("Preview")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(pdfURL == nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let pdfURL {
                    ShareSheet(items: [pdfURL], subject: "Custom Report: \(template.name)")
                } else {
                    ShareSheet(items: [])
                }
            }
            .task {
                guard pdfURL == nil, errorMessage == nil else { return }
                do {
                    pdfURL = try makeTemplatePreviewPDF(
                        template: template,
                        grades: grades,
                        games: games,
                        players: players,
                        dateRange: selectedDateRange,
                        canViewVoteDetails: navigationState.currentRole.canViewVoteDetails
                    )
                } catch {
                    errorMessage = "Could not generate preview PDF."
                }
            }
        }
    }
}

private struct ReportMailComposeView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    let recipients: [String]
    let subject: String
    let body: String
    let attachmentURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: { dismiss() })
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        if let data = try? Data(contentsOf: attachmentURL) {
            controller.addAttachmentData(data, mimeType: "application/pdf", fileName: attachmentURL.lastPathComponent)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
            onFinish()
        }
    }
}

private struct CustomReportShareView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigationState: AppNavigationState

    let template: CustomReportTemplate
    let grades: [Grade]
    let contacts: [Contact]
    let groups: [ContactGroup]
    let memberships: [ContactGroupMembership]
    let sectionMemberships: [ContactSectionMembership]
    let selectedDateRange: ReportDateRange

    @State private var selectedContactIDs: Set<UUID> = []
    @State private var selectedGroupIDs: Set<UUID> = []
    @State private var activeGroupID: UUID?
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    private var selectedContacts: [Contact] {
        contacts.filter { selectedContactIDs.contains($0.id) }
    }

    private var selectedGroups: [ContactGroup] {
        groups.filter { selectedGroupIDs.contains($0.id) }
    }

    private var contactCountByGroupID: [UUID: Int] {
        let validContactIDs = Set(contacts.map(\.id))
        return Dictionary(
            grouping: memberships.filter { validContactIDs.contains($0.contactID) },
            by: \.groupID
        ).mapValues { Set($0.map(\.contactID)).count }
    }

    private var activeGroupMembers: [Contact] {
        guard let activeGroupID else { return [] }
        let memberIDs = Set(memberships.filter { $0.groupID == activeGroupID }.map(\.contactID))
        return contacts
            .filter { memberIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var additionalContacts: [Contact] {
        let memberIDs = Set(activeGroupMembers.map(\.id))
        return contacts
            .filter { !memberIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var shareMessage: String {
        var lines: [String] = []
        lines.append("Custom report: \(template.name)")
        lines.append(
            buildTemplateDetails(
                for: template,
                grades: grades,
                dateRange: selectedDateRange,
                canViewVoteDetails: navigationState.currentRole.canViewVoteDetails
            )
        )
        lines.append(selectedContacts.isEmpty ? "Selected contacts: none" : "Selected contacts: \(selectedContacts.map(\.name).joined(separator: ", "))")
        lines.append(selectedGroups.isEmpty ? "Selected groups: none" : "Selected groups: \(selectedGroups.map(\.name).joined(separator: ", "))")
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if groups.isEmpty {
                        Text("No groups found. Add groups in Settings > Contacts first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(groups) { group in
                            Button {
                                if selectedGroupIDs.contains(group.id) {
                                    selectedGroupIDs.remove(group.id)
                                    if activeGroupID == group.id {
                                        activeGroupID = selectedGroupIDs.first
                                    }
                                } else {
                                    selectedGroupIDs.insert(group.id)
                                    activeGroupID = group.id
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(group.name)
                                            .foregroundStyle(.primary)
                                        Text("\(contactCountByGroupID[group.id, default: 0]) contact(s)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedGroupIDs.contains(group.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    activeGroupID = group.id
                                } label: {
                                    Label("Set Active", systemImage: "scope")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                } header: {
                    Text("Recipient Groups")
                } footer: {
                    Text("Swipe a group and tap Set Active to show its members in Individuals.")
                }

                Section {
                    if activeGroupID == nil {
                        Text("Select a recipient group to view its individual contacts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if activeGroupMembers.isEmpty {
                        Text("No contacts in the selected group.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeGroupMembers) { contact in
                            Button {
                                if selectedContactIDs.contains(contact.id) { selectedContactIDs.remove(contact.id) }
                                else { selectedContactIDs.insert(contact.id) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(contact.name)
                                        Text(contact.email)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedContactIDs.contains(contact.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }

                    if contacts.isEmpty {
                        Text("No contacts found. Add contacts in Settings > Contacts first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Menu {
                            if additionalContacts.isEmpty {
                                Text("No additional contacts available")
                            } else {
                                ForEach(additionalContacts) { contact in
                                    Button {
                                        selectedContactIDs.insert(contact.id)
                                    } label: {
                                        Text(contact.name)
                                    }
                                }
                            }
                        } label: {
                            Label("Add Individual from Contact List", systemImage: "plus")
                        }
                    }
                } header: {
                    Text("Individuals")
                }
            }
            .navigationTitle("Share Report")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") {
                        shareItems = [shareMessage]
                        showShareSheet = true
                    }
                    .disabled(contacts.isEmpty && groups.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
    }
}

private func buildTemplateDetails(
    for template: CustomReportTemplate,
    grades: [Grade],
    dateRange: ReportDateRange,
    canViewVoteDetails: Bool
) -> String {
    let orderedGrades = orderedGradesForDisplay(grades, includeInactive: true)
    let gradeNames = orderedGrades
        .filter { !template.includeOnlyActiveGrades || $0.isActive }
        .filter { template.gradeIDs.isEmpty || template.gradeIDs.contains($0.id) }
        .map(\.name)

    let items: [String] = template.includeSectionOrder.compactMap { key in
        switch key {
        case "scores":
            return template.includeScores ? "Scores" : nil
        case "bestPlayers":
            return template.includeBestPlayers ? "Best players" : nil
        case "guestVotes":
            return template.includePlayerGrades && canViewVoteDetails ? "Guest Votes" : nil
        case "goalKickers":
            return template.includeGoalKickers ? "Goal kickers" : nil
        case "bestAndFairest":
            return template.includeBestAndFairestVotes && canViewVoteDetails ? "B&F votes" : nil
        case "coachingStaff":
            return template.includeStaffRoles ? "Coaching Staff" : nil
        case "officials":
            return (template.includeOfficials || template.includeUmpires) ? "Officials" : nil
        case "trainers":
            return template.includeTrainers ? "Trainers" : nil
        case "matchNotes":
            return template.includeMatchNotes ? "Match notes" : nil
        default:
            return nil
        }
    }

    let gradesText: String = {
        if gradeNames.isEmpty { return "All grades" }
        return "Grades: " + gradeNames.joined(separator: ", ")
    }()

    let grouping = ReportGroupingMode(rawValue: template.groupingModeRawValue) ?? .combinedTotals
    let filters = "Filters: min games \(template.minimumGamesPlayed), \(template.includeOnlyActiveGrades ? "active grades only" : "active + inactive"), \(template.includePlayersOnly ? "players only" : "all names"), \(grouping.filterSummary)"
    let dateRangeText = "Date range: \(formattedDate(dateRange.start)) – \(formattedDate(dateRange.end))"
    let sections = "Includes: " + (items.isEmpty ? "No sections selected" : items.joined(separator: ", "))
    return [gradesText, sections, filters, dateRangeText].joined(separator: " • ")
}

private func formattedDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

private enum ReportGroupingMode: Int, CaseIterable, Identifiable {
    case combinedTotals = 0
    case splitByGameAndGrade = 1
    case splitByGame = 2
    case splitByGrade = 3

    var id: Int { rawValue }

    var splitByGameEnabled: Bool {
        switch self {
        case .combinedTotals, .splitByGrade:
            return false
        case .splitByGameAndGrade, .splitByGame:
            return true
        }
    }

    var splitByGradeEnabled: Bool {
        switch self {
        case .combinedTotals, .splitByGame:
            return false
        case .splitByGameAndGrade, .splitByGrade:
            return true
        }
    }

    static func from(splitByGame: Bool, splitByGrade: Bool) -> ReportGroupingMode {
        switch (splitByGame, splitByGrade) {
        case (false, false):
            return .combinedTotals
        case (true, true):
            return .splitByGameAndGrade
        case (true, false):
            return .splitByGame
        case (false, true):
            return .splitByGrade
        }
    }

    var title: String {
        switch self {
        case .combinedTotals:
            return "Combine totals"
        case .splitByGame:
            return "Split by game"
        case .splitByGrade:
            return "Split by grade"
        case .splitByGameAndGrade:
            return "Split by game & grade"
        }
    }

    var filterSummary: String {
        switch self {
        case .combinedTotals:
            return "combined totals"
        case .splitByGame:
            return "split by game"
        case .splitByGrade:
            return "split by grade"
        case .splitByGameAndGrade:
            return "split by game and grade"
        }
    }
}

func makeTemplatePreviewPDF(
    template: CustomReportTemplate,
    grades: [Grade],
    games: [Game],
    players: [Player],
    dateRange: ReportDateRange,
    canViewVoteDetails: Bool = true
) throws -> URL {
    let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
    let orderedGrades = orderedGradesForDisplay(grades, includeInactive: true)
    let selectedGrades = orderedGrades
        .filter { !template.includeOnlyActiveGrades || $0.isActive }
        .filter { template.gradeIDs.isEmpty || template.gradeIDs.contains($0.id) }
    let selectedGradeIDs = Set(selectedGrades.map(\.id))
    let normalizedTemplateName = template.name
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
    let isRosterReport = normalizedTemplateName.contains("roster")
        || (template.includePlayersOnly && (normalizedTemplateName.contains("senior") || normalizedTemplateName.contains("junior")))
    let isMissingEntriesReport = normalizedTemplateName.contains("missing entries")
    let relevantGames = games
        .filter { selectedGradeIDs.isEmpty || selectedGradeIDs.contains($0.gradeID) }
        .filter { !$0.isDraft && $0.date <= Date() }
        .filter { dateRange.contains($0.date) }
        .sorted { $0.date > $1.date }
    let missingEntryGames = games
        .filter { !$0.isDraft && $0.date <= Date() }
        .sorted { $0.date > $1.date }
    let playerLookup = Dictionary(players.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let playersOnlyGradeFilterIDs = Set(template.playersOnlyGradeFilterIDs)
    let playersInPlayersOnlyScope = players.filter { player in
        guard player.isActive else { return false }
        guard playersOnlyGradeFilterIDs.isEmpty else {
            return !Set(player.gradeIDs).isDisjoint(with: playersOnlyGradeFilterIDs)
        }
        return true
    }
    let playersOnlyScopedPlayerIDs = Set(playersInPlayersOnlyScope.map(\.id))
    let normalizedPlayerNames: Set<String> = Set(
        playersInPlayersOnlyScope
            .map(\.name)
            .map {
                $0
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            }
            .filter { !$0.isEmpty }
    )
    let gradeLookup = Dictionary(grades.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    let gradeConfigLookup = Dictionary(grades.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let selectedGradeNames = selectedGrades.map(\.name)
    let gradeSummary = selectedGradeNames.isEmpty ? "All grades" : selectedGradeNames.joined(separator: ", ")
    let dateSummary: String = {
        let start = dateRange.start.formatted(date: .abbreviated, time: .omitted)
        let end = dateRange.end.formatted(date: .abbreviated, time: .omitted)
        return start == end ? start : "\(start) – \(end)"
    }()
    let reportGradeSummary = isMissingEntriesReport ? "All grades" : gradeSummary
    let reportDateSummary = isMissingEntriesReport ? "All previous games" : dateSummary
    let clubConfiguration = ClubConfigurationStore.load()
    let homeVenueNames = Set(
        clubConfiguration.clubTeam.sanitizedVenues.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    )
    var gamesByPlayer: [UUID: Int] = [:]

    func guestVotePoints(for game: Game, rank: Int) -> Int {
        guard let grade = gradeConfigLookup[game.gradeID] else {
            return Grade.normalizedGuestVotes(nil, count: 3)[rank - 1]
        }
        let votes = Grade.normalizedGuestVotes(grade.guestBestPlayersVotes, count: grade.guestBestPlayersCount)
        return votes[rank - 1]
    }

    func bestPlayerPoints(for game: Game, index: Int) -> Int {
        guard let grade = gradeConfigLookup[game.gradeID] else {
            return Grade.normalizedVotes(nil, count: 6)[index]
        }
        let votes = Grade.normalizedVotes(grade.bestPlayersVotes, count: grade.bestPlayersCount)
        return votes[index]
    }

    func includePlayerID(_ id: UUID) -> Bool {
        if id == GameGoalKickerEntry.oppositionPlayerID {
            return !template.includePlayersOnly
        }
        guard template.includePlayersOnly else { return true }
        return playersOnlyScopedPlayerIDs.contains(id)
    }

    func playerDisplayName(for id: UUID) -> String {
        if id == GameGoalKickerEntry.oppositionPlayerID {
            return GameGoalKickerEntry.oppositionPlayerName
        }
        return playerLookup[id]?.name ?? "Unknown Player"
    }

    func includeName(_ rawName: String) -> Bool {
        guard template.includePlayersOnly else { return true }
        let normalized = rawName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !normalized.isEmpty else { return false }
        return normalizedPlayerNames.contains(normalized)
    }

    func metadataSummary(for game: Game) -> String {
        var parts: [String] = []
        if template.includeStaffRoles {
            let staff = [game.headCoachName, game.assistantCoachName, game.teamManagerName, game.runnerName]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter(includeName)
            if !staff.isEmpty { parts.append("Staff: \(staff.joined(separator: ", "))") }
        }
        if template.includeOfficials || template.includeUmpires {
            var officials: [String] = []
            if template.includeOfficials {
                officials += [game.goalUmpireName, game.timeKeeperName, game.fieldUmpireName]
            }
            if template.includeUmpires {
                officials += [game.boundaryUmpire1Name, game.boundaryUmpire2Name, game.waterBoy1Name, game.waterBoy2Name, game.waterBoy3Name, game.waterBoy4Name]
            }
            officials = officials
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter(includeName)
            if !officials.isEmpty { parts.append("Officials: \(officials.joined(separator: ", "))") }
        }
        if template.includeTrainers {
            let trainers = game.trainers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter(includeName)
            if !trainers.isEmpty { parts.append("Trainers: \(trainers.joined(separator: ", "))") }
        }
        if template.includeMatchNotes {
            let notes = game.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty { parts.append("Notes: \(notes)") }
        }
        return parts.joined(separator: " • ")
    }
    for game in relevantGames {
        var seenPlayerIDs = Set<UUID>()
        if template.includeGoalKickers {
            for entry in game.goalKickers {
                if let playerID = entry.playerID {
                    seenPlayerIDs.insert(playerID)
                }
            }
        }
        if template.includeBestPlayers || template.includeBestAndFairestVotes {
            for playerID in game.bestPlayersRanked {
                seenPlayerIDs.insert(playerID)
            }
        }
        if canViewVoteDetails, (template.includePlayerGrades || template.includeBestAndFairestVotes) {
            for vote in game.guestVotesRanked {
                seenPlayerIDs.insert(vote.playerID)
            }
        }
        for playerID in seenPlayerIDs {
            gamesByPlayer[playerID, default: 0] += 1
        }
    }

    struct MissingEntryReportRound: Identifiable {
        let id: String
        let roundNumber: Int
        let opponent: String
        let date: Date
        let games: [Game]
    }

    struct MissingEntryReportRow {
        let roundID: String
        let gradeName: String
        let role: String
        let sortDate: Date
        let gradeOrder: Int
    }

    let missingEntryRounds: [MissingEntryReportRound] = {
        let sortedChronological = missingEntryGames.sorted { $0.date < $1.date }
        guard !sortedChronological.isEmpty else { return [] }

        struct RoundBucket {
            var id: String
            var opponentKey: String
            var opponentLabel: String
            var anchorDate: Date
            var games: [Game]
        }

        var buckets: [RoundBucket] = []
        let matchingWindow: TimeInterval = 60 * 60 * 24 * 3

        for game in sortedChronological {
            let opponentLabel = game.opponent.trimmingCharacters(in: .whitespacesAndNewlines)
            let opponentKey = opponentLabel.lowercased()
            if let index = buckets.firstIndex(where: { bucket in
                bucket.opponentKey == opponentKey &&
                abs(bucket.anchorDate.timeIntervalSince(game.date)) <= matchingWindow
            }) {
                buckets[index].games.append(game)
                let sortedDates = buckets[index].games.map(\.date).sorted()
                buckets[index].anchorDate = sortedDates[sortedDates.count / 2]
            } else {
                let dayKey = Calendar.current.startOfDay(for: game.date).timeIntervalSince1970
                buckets.append(
                    RoundBucket(
                        id: "\(opponentKey)|\(Int(dayKey))",
                        opponentKey: opponentKey,
                        opponentLabel: opponentLabel.isEmpty ? "Unknown Opponent" : opponentLabel,
                        anchorDate: game.date,
                        games: [game]
                    )
                )
            }
        }

        return buckets
            .map { bucket in
                (
                    id: bucket.id,
                    date: bucket.games.map(\.date).max() ?? bucket.anchorDate,
                    opponent: bucket.opponentLabel,
                    games: bucket.games.sorted { $0.date > $1.date }
                )
            }
            .sorted { $0.date < $1.date }
            .enumerated()
            .map { index, round in
                MissingEntryReportRound(
                    id: round.id,
                    roundNumber: index + 1,
                    opponent: round.opponent,
                    date: round.date,
                    games: round.games
                )
            }
    }()

    let missingEntryRoundLookup = Dictionary(uniqueKeysWithValues: missingEntryRounds.map { ($0.id, $0) })
    let missingEntryRoundIDByGameID = Dictionary(
        uniqueKeysWithValues: missingEntryRounds.flatMap { round in
            round.games.map { ($0.id, round.id) }
        }
    )
    let validPlayerIDs = Set(players.map(\.id))
    let missingEntriesGradeOrder = Dictionary(uniqueKeysWithValues: orderedGrades.enumerated().map { ($0.element.id, $0.offset) })

    func hasReportTextValue(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func reportIsHomeGame(_ game: Game) -> Bool {
        let selectedVenue = game.venue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !selectedVenue.isEmpty else { return false }
        return homeVenueNames.contains(selectedVenue)
    }

    func reportRequiresFieldUmpire(for game: Game, grade: Grade) -> Bool {
        grade.asksFieldUmpire && reportIsHomeGame(game)
    }

    func requiredReportTrainerCount(for grade: Grade) -> Int {
        [
            grade.asksTrainer1,
            grade.asksTrainer2,
            grade.asksTrainer3,
            grade.asksTrainer4
        ].filter { $0 }.count
    }

    func requiredReportBestPlayersCount(for grade: Grade) -> Int {
        min(max(grade.bestPlayersCount, 0), 10)
    }

    func requiredReportGuestVotesCount(for grade: Grade) -> Int {
        grade.asksGuestBestFairestVotesScan ? grade.guestBestPlayersCount : 0
    }

    func reportHasRequiredGoalKickers(for game: Game, grade: Grade) -> Bool {
        guard grade.asksGoalKickers else { return true }
        guard game.ourGoals > 0 else { return true }

        let validEntries = game.goalKickers.filter { entry in
            guard entry.goals > 0, let playerID = entry.playerID else { return false }
            return playerID == GameGoalKickerEntry.oppositionPlayerID || validPlayerIDs.contains(playerID)
        }
        let totalGoals = validEntries.reduce(0) { $0 + $1.goals }
        let oppositionGoals = validEntries.reduce(0) { $0 + $1.oppositionGoals }
        return totalGoals == game.ourGoals + oppositionGoals
    }

    func reportHasRequiredBestPlayers(for game: Game, grade: Grade) -> Bool {
        let requiredCount = requiredReportBestPlayersCount(for: grade)
        guard requiredCount > 0 else { return true }
        let pickedIDs = Array(game.bestPlayersRanked.prefix(requiredCount))
        guard pickedIDs.count == requiredCount else { return false }
        return Set(pickedIDs).count == requiredCount && pickedIDs.allSatisfy { validPlayerIDs.contains($0) }
    }

    func reportHasRequiredGuestVotes(for game: Game, grade: Grade) -> Bool {
        let requiredCount = requiredReportGuestVotesCount(for: grade)
        guard requiredCount > 0 else { return true }
        let votes = Array(game.guestVotesRanked.prefix(requiredCount))
        let pickedIDs = votes.map(\.playerID)
        guard pickedIDs.count == requiredCount else { return false }
        return Set(pickedIDs).count == requiredCount && pickedIDs.allSatisfy { validPlayerIDs.contains($0) }
    }

    func missingEntryGameLabel(for game: Game, grade: Grade) -> String? {
        let normalizedGradeName = grade.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        guard normalizedGradeName == "under 9's" || normalizedGradeName == "under 12's" else { return nil }

        let pairedGames = missingEntryGames
            .filter {
                $0.gradeID == game.gradeID &&
                Calendar.current.isDate($0.date, inSameDayAs: game.date) &&
                $0.opponent == game.opponent &&
                $0.venue == game.venue
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        guard pairedGames.count > 1, let gameIndex = pairedGames.firstIndex(where: { $0.id == game.id }) else { return nil }
        return "Game \(gameIndex + 1)"
    }

    func missingEntryRoles(for game: Game, grade: Grade) -> [String] {
        var roles: [String] = []

        if grade.asksHeadCoach, !hasReportTextValue(game.headCoachName) { roles.append("Head Coach") }
        if grade.asksAssistantCoach, !hasReportTextValue(game.assistantCoachName) { roles.append("Assistant Coach") }
        if grade.asksTeamManager, !hasReportTextValue(game.teamManagerName) { roles.append("Team Manager") }
        if grade.asksRunner, !hasReportTextValue(game.runnerName) { roles.append("Runner") }
        if grade.asksGoalUmpire, !hasReportTextValue(game.goalUmpireName) { roles.append("Goal Umpire") }
        if grade.asksTimeKeeper, !hasReportTextValue(game.timeKeeperName) { roles.append("Time Keeper") }
        if reportRequiresFieldUmpire(for: game, grade: grade), !hasReportTextValue(game.fieldUmpireName) { roles.append("Field Umpire") }
        if grade.asksBoundaryUmpire1, !hasReportTextValue(game.boundaryUmpire1Name) { roles.append("Boundary Umpire 1") }
        if grade.asksBoundaryUmpire2, !hasReportTextValue(game.boundaryUmpire2Name) { roles.append("Boundary Umpire 2") }
        if grade.asksWaterBoy1, !hasReportTextValue(game.waterBoy1Name) { roles.append("Water 1") }
        if grade.asksWaterBoy2, !hasReportTextValue(game.waterBoy2Name) { roles.append("Water 2") }
        if grade.asksWaterBoy3, !hasReportTextValue(game.waterBoy3Name) { roles.append("Water 3") }
        if grade.asksWaterBoy4, !hasReportTextValue(game.waterBoy4Name) { roles.append("Water 4") }

        let requiredTrainers = requiredReportTrainerCount(for: grade)
        let trainerCount = game.trainers.filter(hasReportTextValue).count
        if trainerCount < requiredTrainers {
            roles.append(requiredTrainers == 1 ? "Trainer" : "Trainers (\(requiredTrainers) required)")
        }

        if grade.asksNotes, !hasReportTextValue(game.notes) { roles.append("Notes") }
        if !reportHasRequiredGoalKickers(for: game, grade: grade) { roles.append("Goal Kickers") }

        let requiredBestPlayers = requiredReportBestPlayersCount(for: grade)
        if !reportHasRequiredBestPlayers(for: game, grade: grade) {
            roles.append("Best Players (\(requiredBestPlayers) required)")
        }

        let requiredGuestVotes = requiredReportGuestVotesCount(for: grade)
        if !reportHasRequiredGuestVotes(for: game, grade: grade) {
            roles.append("Guest Votes (\(requiredGuestVotes) required)")
        }

        return roles
    }

    let missingEntryRows: [MissingEntryReportRow] = missingEntryGames.flatMap { game in
        guard let grade = gradeConfigLookup[game.gradeID],
              let roundID = missingEntryRoundIDByGameID[game.id] else { return [MissingEntryReportRow]() }
        let gameLabel = missingEntryGameLabel(for: game, grade: grade)
        return missingEntryRoles(for: game, grade: grade).map { role in
            let displayRole = gameLabel.map { "\($0) - \(role)" } ?? role
            return MissingEntryReportRow(
                roundID: roundID,
                gradeName: grade.name,
                role: displayRole,
                sortDate: game.date,
                gradeOrder: missingEntriesGradeOrder[grade.id] ?? Int.max
            )
        }
    }
    .sorted { lhs, rhs in
        let lhsRoundNumber = missingEntryRoundLookup[lhs.roundID]?.roundNumber ?? Int.max
        let rhsRoundNumber = missingEntryRoundLookup[rhs.roundID]?.roundNumber ?? Int.max
        if lhsRoundNumber != rhsRoundNumber { return lhsRoundNumber < rhsRoundNumber }
        if lhs.gradeOrder != rhs.gradeOrder { return lhs.gradeOrder < rhs.gradeOrder }
        let gradeCompare = lhs.gradeName.localizedStandardCompare(rhs.gradeName)
        if gradeCompare != .orderedSame { return gradeCompare == .orderedAscending }
        let roleCompare = lhs.role.localizedStandardCompare(rhs.role)
        if roleCompare != .orderedSame { return roleCompare == .orderedAscending }
        return lhs.sortDate < rhs.sortDate
    }

    let data = renderer.pdfData { context in
        let horizontalInset: CGFloat = 30
        let verticalInset: CGFloat = 28
        let contentRect = pageBounds.insetBy(dx: horizontalInset, dy: verticalInset)
        var cursorY = contentRect.minY
        let bottomLimit = contentRect.maxY

        func beginNewPageIfNeeded(requiredHeight: CGFloat) {
            if cursorY + requiredHeight <= bottomLimit { return }
            context.beginPage()
            cursorY = contentRect.minY
        }

        func beginNewPage() {
            context.beginPage()
            cursorY = contentRect.minY
        }

        beginNewPage()

        let titleFont = UIFont(name: "AvenirNext-Bold", size: 22) ?? UIFont.boldSystemFont(ofSize: 22)
        let subtitleFont = UIFont(name: "AvenirNext-Medium", size: 12) ?? UIFont.systemFont(ofSize: 12, weight: .medium)
        let sectionFont = UIFont(name: "AvenirNext-DemiBold", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .semibold)
        let bodyFont = UIFont(name: "AvenirNext-Regular", size: 11) ?? UIFont.systemFont(ofSize: 11)
        let headerFont = UIFont(name: "AvenirNext-DemiBold", size: 10) ?? UIFont.systemFont(ofSize: 10, weight: .semibold)
        let scoreBannerFont = UIFont(name: "AvenirNext-Bold", size: 26) ?? UIFont.systemFont(ofSize: 26, weight: .bold)
        let scoreDetailFont = UIFont(name: "AvenirNext-DemiBold", size: 12) ?? UIFont.systemFont(ofSize: 12, weight: .semibold)

        if let logo = UIImage(named: "club_logo") {
            let logoRect = CGRect(x: contentRect.minX, y: cursorY, width: 56, height: 56)
            logo.draw(in: logoRect)
        }

        let titleX = contentRect.minX + 68
        let titleRect = CGRect(x: titleX, y: cursorY + 4, width: contentRect.width - 68, height: 28)
        NSAttributedString(
            string: template.name,
            attributes: [.font: titleFont, .foregroundColor: UIColor.black]
        ).draw(in: titleRect)

        let subtitle = "\(reportDateSummary) • \(reportGradeSummary)"
        let subtitleRect = CGRect(x: titleX, y: titleRect.maxY + 2, width: contentRect.width - 68, height: 22)
        NSAttributedString(
            string: subtitle,
            attributes: [.font: subtitleFont, .foregroundColor: UIColor.darkGray]
        ).draw(in: subtitleRect)
        cursorY += 72

        let tableColumns: [(String, CGFloat)] = [
            ("Player Name", 0.34),
            ("Guernsey", 0.11),
            ("Goals", 0.11),
            ("Best Players", 0.16),
            ("Games", 0.10),
            ("Notes", 0.18)
        ]
        let tableWidth = contentRect.width
        let columnWidths = tableColumns.map { $0.1 * tableWidth }

        func drawSectionHeader(_ text: String) {
            beginNewPageIfNeeded(requiredHeight: 24)
            let rect = CGRect(x: contentRect.minX, y: cursorY, width: contentRect.width, height: 20)
            NSAttributedString(
                string: text,
                attributes: [.font: sectionFont, .foregroundColor: UIColor.black]
            ).draw(in: rect)
            cursorY += 24
        }

        func drawTableHeader() {
            let headerHeight: CGFloat = 24
            beginNewPageIfNeeded(requiredHeight: headerHeight)
            var x = contentRect.minX
            let headerY = cursorY
            for (idx, column) in tableColumns.enumerated() {
                let width = columnWidths[idx]
                let rect = CGRect(x: x, y: headerY, width: width, height: headerHeight)
                UIColor(white: 0.92, alpha: 1).setFill()
                UIBezierPath(rect: rect).fill()
                UIColor.separator.setStroke()
                UIBezierPath(rect: rect).stroke()
                NSAttributedString(
                    string: column.0,
                    attributes: [.font: headerFont, .foregroundColor: UIColor.black]
                ).draw(in: rect.insetBy(dx: 4, dy: 6))
                x += width
            }
            cursorY += headerHeight
        }

        func drawRow(playerName: String, guernsey: String, goals: String, bestPlayers: String, gamesPlayed: String, notes: String) {
            let rowHeight: CGFloat = 24
            beginNewPageIfNeeded(requiredHeight: rowHeight)
            var x = contentRect.minX
            let values = [playerName, guernsey, goals, bestPlayers, gamesPlayed, notes]
            for (idx, value) in values.enumerated() {
                let width = columnWidths[idx]
                let rect = CGRect(x: x, y: cursorY, width: width, height: rowHeight)
                UIColor.separator.setStroke()
                UIBezierPath(rect: rect).stroke()
                NSAttributedString(
                    string: value,
                    attributes: [.font: bodyFont, .foregroundColor: UIColor.black]
                ).draw(in: rect.insetBy(dx: 4, dy: 4))
                x += width
            }
            cursorY += rowHeight
        }

        func drawDetailTable(title: String, columns: [String], rows: [[String]]) {
            drawSectionHeader(title)
            let headerHeight: CGFloat = 24
            let rowHeight: CGFloat = 24
            beginNewPageIfNeeded(requiredHeight: headerHeight)

            let weights: [CGFloat]
            if columns.count == 2, columns[1].lowercased() == "goals" || columns[1].lowercased() == "points" {
                weights = [0.82, 0.18]
            } else if columns.count == 2, columns[0].lowercased() == "rank" {
                weights = [0.18, 0.82]
            } else {
                weights = columns.enumerated().map { index, _ in
                    index == 0 ? 0.34 : (0.66 / CGFloat(max(columns.count - 1, 1)))
                }
            }
            let widths = weights.map { $0 * contentRect.width }

            var headerX = contentRect.minX
            for (index, column) in columns.enumerated() {
                let width = widths[index]
                let rect = CGRect(x: headerX, y: cursorY, width: width, height: headerHeight)
                UIColor(red: 0.93, green: 0.95, blue: 0.99, alpha: 1).setFill()
                UIBezierPath(rect: rect).fill()
                UIColor.separator.setStroke()
                UIBezierPath(rect: rect).stroke()
                NSAttributedString(
                    string: column,
                    attributes: [.font: headerFont, .foregroundColor: UIColor.black]
                ).draw(in: rect.insetBy(dx: 4, dy: 6))
                headerX += width
            }
            cursorY += headerHeight

            let safeRows = rows.isEmpty ? [["No data for selected date range"]] : rows
            for (rowIndex, row) in safeRows.enumerated() {
                beginNewPageIfNeeded(requiredHeight: rowHeight)
                if rowIndex.isMultiple(of: 2) {
                    UIColor(white: 0.985, alpha: 1).setFill()
                    UIBezierPath(rect: CGRect(x: contentRect.minX, y: cursorY, width: contentRect.width, height: rowHeight)).fill()
                }
                var x = contentRect.minX
                for (index, width) in widths.enumerated() {
                    let value = index < row.count ? row[index] : ""
                    let rect = CGRect(x: x, y: cursorY, width: width, height: rowHeight)
                    UIColor.separator.setStroke()
                    UIBezierPath(rect: rect).stroke()
                    NSAttributedString(
                        string: value,
                        attributes: [.font: bodyFont, .foregroundColor: UIColor.black]
                    ).draw(in: rect.insetBy(dx: 4, dy: 4))
                    x += width
                }
                cursorY += rowHeight
            }
            cursorY += 10
        }

        func drawCompactTable(
            title: String,
            columns: [String],
            rows: [[String]],
            highlightedNameRowIndexes: Set<Int>,
            xOrigin: CGFloat,
            width: CGFloat
        ) -> CGFloat {
            let startY = cursorY
            let sectionRect = CGRect(x: xOrigin, y: cursorY, width: width, height: 20)
            NSAttributedString(
                string: title,
                attributes: [.font: sectionFont, .foregroundColor: UIColor.black]
            ).draw(in: sectionRect)
            var localY = cursorY + 22
            let headerHeight: CGFloat = 24
            let rowHeight: CGFloat = 24
            let colWidths: [CGFloat]
            if columns.count == 2,
               columns[0].lowercased() == "role",
               columns[1].lowercased() == "name" {
                colWidths = [width * 0.36, width * 0.64]
            } else if columns.count == 2,
                      (columns[0].lowercased() == "rank" || columns[0].lowercased() == "points"),
                      columns[1].lowercased() == "player" {
                colWidths = [width * 0.16, width * 0.84]
            } else if columns.count == 2,
                      columns[0].lowercased() == "goals",
                      columns[1].lowercased() == "player" {
                colWidths = [width * 0.14, width * 0.86]
            } else if columns.count == 7,
                      columns[0].lowercased() == "name",
                      columns[1].lowercased() == "goal ump",
                      columns[2].lowercased() == "time keep",
                      columns[3].lowercased() == "boundary ump",
                      columns[4].lowercased() == "water",
                      columns[5].lowercased() == "field ump",
                      columns[6].lowercased() == "total" {
                let longestName = rows
                    .compactMap { $0.first }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .max { lhs, rhs in
                        lhs.size(withAttributes: [.font: bodyFont]).width < rhs.size(withAttributes: [.font: bodyFont]).width
                    } ?? columns[0]
                let nameHeaderWidth = columns[0].size(withAttributes: [.font: headerFont]).width
                let longestNameWidth = longestName.size(withAttributes: [.font: bodyFont]).width
                let paddedNameWidth = ceil(max(nameHeaderWidth, longestNameWidth)) + 12
                let remainingColumnCount = CGFloat(columns.count - 1)
                let minimumOtherColumnWidth: CGFloat = 44
                let maximumNameWidth = width - (remainingColumnCount * minimumOtherColumnWidth)
                let clampedNameWidth = max(60, min(paddedNameWidth, maximumNameWidth))
                let otherColumnWidth = max(minimumOtherColumnWidth, (width - clampedNameWidth) / remainingColumnCount)
                var widths = [clampedNameWidth]
                widths.append(contentsOf: Array(repeating: otherColumnWidth, count: columns.count - 1))
                colWidths = widths
            } else {
                colWidths = columns.map { _ in width / CGFloat(max(columns.count, 1)) }
            }

            var x = xOrigin
            for (index, column) in columns.enumerated() {
                let rect = CGRect(x: x, y: localY, width: colWidths[index], height: headerHeight)
                UIColor(white: 0.92, alpha: 1).setFill()
                UIBezierPath(rect: rect).fill()
                UIColor.separator.setStroke()
                UIBezierPath(rect: rect).stroke()
                NSAttributedString(
                    string: column,
                    attributes: [.font: headerFont, .foregroundColor: UIColor.black]
                ).draw(in: rect.insetBy(dx: 4, dy: 6))
                x += colWidths[index]
            }
            localY += headerHeight

            let safeRows = rows.isEmpty ? [["No data"]] : rows
            let nameColumnIndexes = Set(columns.enumerated().compactMap { index, column -> Int? in
                let normalizedColumn = column.lowercased()
                return normalizedColumn == "player" || normalizedColumn == "name" ? index : nil
            })
            for (rowIndex, row) in safeRows.enumerated() {
                x = xOrigin
                for (index, colWidth) in colWidths.enumerated() {
                    let value = index < row.count ? row[index] : ""
                    let rect = CGRect(x: x, y: localY, width: colWidth, height: rowHeight)
                    let shouldHighlightName = highlightedNameRowIndexes.contains(rowIndex) && nameColumnIndexes.contains(index)
                    if shouldHighlightName {
                        UIColor.systemYellow.withAlphaComponent(0.24).setFill()
                        UIBezierPath(rect: rect).fill()
                    }
                    UIColor.separator.setStroke()
                    UIBezierPath(rect: rect).stroke()
                    let foregroundColor: UIColor = shouldHighlightName ? .systemOrange : .black
                    let textFont: UIFont = shouldHighlightName ? (UIFont(name: "AvenirNext-DemiBold", size: 11) ?? UIFont.systemFont(ofSize: 11, weight: .semibold)) : bodyFont
                    NSAttributedString(
                        string: value,
                        attributes: [.font: textFont, .foregroundColor: foregroundColor]
                    ).draw(in: rect.insetBy(dx: 4, dy: 5))
                    x += colWidth
                }
                localY += rowHeight
            }
            return localY - startY
        }

        func drawMissingEntriesTable(rows: [MissingEntryReportRow]) {
            drawSectionHeader("Missing Entries")

            guard !missingEntryGames.isEmpty else {
                beginNewPageIfNeeded(requiredHeight: 28)
                NSAttributedString(
                    string: "No previous saved games were found.",
                    attributes: [.font: bodyFont, .foregroundColor: UIColor.darkGray]
                ).draw(in: CGRect(x: contentRect.minX, y: cursorY, width: contentRect.width, height: 22))
                cursorY += 28
                return
            }

            guard !rows.isEmpty else {
                beginNewPageIfNeeded(requiredHeight: 28)
                NSAttributedString(
                    string: "No missing entries. All required fields are complete.",
                    attributes: [.font: bodyFont, .foregroundColor: UIColor.darkGray]
                ).draw(in: CGRect(x: contentRect.minX, y: cursorY, width: contentRect.width, height: 22))
                cursorY += 28
                return
            }

            let columns = ["Grade", "Role", "Fill In"]
            let widths = [contentRect.width * 0.24, contentRect.width * 0.42, contentRect.width * 0.34]
            let roundTitleHeight: CGFloat = 28
            let headerHeight: CGFloat = 26
            let rowHeight: CGFloat = 32
            let rowsByRoundID = Dictionary(grouping: rows, by: \.roundID)

            func drawRoundTableHeader() {
                var x = contentRect.minX
                for (index, column) in columns.enumerated() {
                    let rect = CGRect(x: x, y: cursorY, width: widths[index], height: headerHeight)
                    UIColor(red: 0.93, green: 0.95, blue: 0.99, alpha: 1).setFill()
                    UIBezierPath(rect: rect).fill()
                    UIColor.separator.setStroke()
                    UIBezierPath(rect: rect).stroke()
                    NSAttributedString(
                        string: column,
                        attributes: [.font: headerFont, .foregroundColor: UIColor.black]
                    ).draw(in: rect.insetBy(dx: 5, dy: 7))
                    x += widths[index]
                }
                cursorY += headerHeight
            }

            for round in missingEntryRounds {
                guard let roundRows = rowsByRoundID[round.id], !roundRows.isEmpty else { continue }
                beginNewPageIfNeeded(requiredHeight: roundTitleHeight + headerHeight + rowHeight)

                NSAttributedString(
                    string: "Round \(round.roundNumber) v \(round.opponent)",
                    attributes: [.font: headerFont, .foregroundColor: UIColor.black]
                ).draw(in: CGRect(x: contentRect.minX, y: cursorY, width: contentRect.width, height: 22))
                cursorY += roundTitleHeight

                drawRoundTableHeader()

                for (rowIndex, row) in roundRows.enumerated() {
                    beginNewPageIfNeeded(requiredHeight: rowHeight)
                    if rowIndex.isMultiple(of: 2) {
                        UIColor(white: 0.985, alpha: 1).setFill()
                        UIBezierPath(rect: CGRect(x: contentRect.minX, y: cursorY, width: contentRect.width, height: rowHeight)).fill()
                    }

                    let values = [row.gradeName, row.role, ""]
                    var x = contentRect.minX
                    for (index, value) in values.enumerated() {
                        let rect = CGRect(x: x, y: cursorY, width: widths[index], height: rowHeight)
                        UIColor.separator.setStroke()
                        UIBezierPath(rect: rect).stroke()
                        NSAttributedString(
                            string: value,
                            attributes: [.font: bodyFont, .foregroundColor: UIColor.black]
                        ).draw(in: rect.insetBy(dx: 5, dy: 8))
                        x += widths[index]
                    }
                    cursorY += rowHeight
                }

                cursorY += 12
            }
        }

        if isMissingEntriesReport {
            drawMissingEntriesTable(rows: missingEntryRows)
            return
        }

        if relevantGames.isEmpty && !isRosterReport {
            drawSectionHeader("No completed games matched this template.")
            return
        }

        let primaryGame = relevantGames.first
        let configuration = ClubConfigurationStore.load()

        func shouldShowScore(for game: Game) -> Bool {
            guard template.includeScores else { return false }
            guard let grade = grades.first(where: { $0.id == game.gradeID }) else { return true }
            return grade.asksScore
        }

        func drawScorePills(for game: Game, title: String) {
            drawSectionHeader(title)

            let shouldShowScore = shouldShowScore(for: game)
            beginNewPageIfNeeded(requiredHeight: shouldShowScore ? 126 : 94)

            let pairedGames = relevantGames
                .filter {
                    $0.gradeID == game.gradeID &&
                    Calendar.current.isDate($0.date, inSameDayAs: game.date) &&
                    $0.opponent == game.opponent
                }
                .sorted { $0.id.uuidString < $1.id.uuidString }

            if pairedGames.count == 2,
               let gameIndex = pairedGames.firstIndex(where: { $0.id == game.id }) {
                NSAttributedString(
                    string: "Game \(gameIndex + 1)",
                    attributes: [.font: scoreDetailFont, .foregroundColor: UIColor.darkGray]
                ).draw(in: CGRect(x: contentRect.minX + 2, y: cursorY, width: 120, height: 16))
                cursorY += 18
            }

            let ourScoreText = "\(game.ourGoals).\(game.ourBehinds) (\(game.ourScore))"
            let oppScoreText = "\(game.theirGoals).\(game.theirBehinds) (\(game.theirScore))"
            let ourStyle = ClubStyle.style(for: configuration.clubTeam.name, configuration: configuration)
            let oppStyle = ClubStyle.style(for: game.opponent, configuration: configuration)

            let gap: CGFloat = 10
            let pillWidth = (contentRect.width - gap) / 2
            let pillHeight: CGFloat = shouldShowScore ? 74 : 42

            let leftRect = CGRect(x: contentRect.minX, y: cursorY, width: pillWidth, height: pillHeight)
            let rightRect = CGRect(x: contentRect.minX + pillWidth + gap, y: cursorY, width: pillWidth, height: pillHeight)

            for (rect, bgColor, textColor, teamName, scoreText) in [
                (leftRect, UIColor(ourStyle.background), UIColor(ourStyle.text), configuration.clubTeam.name, ourScoreText),
                (rightRect, UIColor(oppStyle.background), UIColor(oppStyle.text), game.opponent, oppScoreText)
            ] {
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 18)
                bgColor.setFill()
                path.fill()

                let teamAttrs: [NSAttributedString.Key: Any] = [
                    .font: scoreDetailFont,
                    .foregroundColor: textColor
                ]
                let scoreAttrs: [NSAttributedString.Key: Any] = [
                    .font: scoreBannerFont,
                    .foregroundColor: textColor
                ]

                let teamText = teamName.uppercased()
                let teamSize = (teamText as NSString).size(withAttributes: teamAttrs)
                let teamX = rect.midX - (teamSize.width / 2)
                let teamY = shouldShowScore ? (rect.minY + 10) : (rect.midY - (teamSize.height / 2))
                NSString(string: teamText).draw(
                    at: CGPoint(x: teamX, y: teamY),
                    withAttributes: teamAttrs
                )

                if shouldShowScore {
                    let scoreSize = (scoreText as NSString).size(withAttributes: scoreAttrs)
                    let scoreX = rect.midX - (scoreSize.width / 2)
                    NSString(string: scoreText).draw(
                        at: CGPoint(x: scoreX, y: rect.minY + 28),
                        withAttributes: scoreAttrs
                    )
                }
            }

            let badgeMode: String = {
                guard shouldShowScore else { return "V" }
                if game.ourScore > game.theirScore { return "W" }
                if game.ourScore < game.theirScore { return "L" }
                return "D"
            }()

            let badgeColor: UIColor = {
                switch badgeMode {
                case "W": return .systemGreen
                case "L": return .systemRed
                case "D": return .systemOrange
                default: return .white
                }
            }()

            let badgeSize: CGFloat = 42
            let badgeRect = CGRect(
                x: contentRect.midX - (badgeSize / 2),
                y: cursorY + (pillHeight / 2) - (badgeSize / 2),
                width: badgeSize,
                height: badgeSize
            )
            let badgePath = UIBezierPath(ovalIn: badgeRect)
            badgeColor.setFill()
            badgePath.fill()
            if badgeMode == "V" {
                UIColor.black.withAlphaComponent(0.2).setStroke()
                badgePath.lineWidth = 1.2
                badgePath.stroke()
            } else {
                UIColor.white.withAlphaComponent(0.25).setStroke()
                badgePath.lineWidth = 1.2
                badgePath.stroke()
            }

            let badgeTextColor: UIColor = badgeMode == "V" ? .black : .white
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .black),
                .foregroundColor: badgeTextColor
            ]
            let badgeTextSize = (badgeMode as NSString).size(withAttributes: badgeAttrs)
            NSString(string: badgeMode).draw(
                at: CGPoint(
                    x: badgeRect.midX - (badgeTextSize.width / 2),
                    y: badgeRect.midY - (badgeTextSize.height / 2)
                ),
                withAttributes: badgeAttrs
            )

            cursorY += pillHeight + 12
        }

        let minimumGamesThreshold = max(template.minimumGamesPlayed, 1)
        let bestPlayersLimit = max(0, min(template.bestPlayersLimit, 10))
        let guestVotesLimit = max(0, min(template.guestVotesLimit, 10))
        let goalKickersLimit = max(0, min(template.goalKickersLimit, 10))
        let bestAndFairestLimit = max(0, min(template.bestAndFairestLimit, 10))

        struct RosterRows {
            let rows: [[String]]
            let highlightedNameRowIndexes: Set<Int>
        }

        func reportRows(for games: [Game], gradeIDsOverride: Set<UUID>? = nil) -> (bestPlayers: RosterRows, guestVotes: RosterRows, goalKickers: RosterRows, bestAndFairest: RosterRows) {
            let sectionGradeIDs = gradeIDsOverride ?? Set(games.map(\.gradeID))
            let rosterPlayers: [Player] = {
                guard isRosterReport else { return [] }
                return players
                    .filter { player in
                        guard player.isActive, includePlayerID(player.id) else { return false }
                        guard !sectionGradeIDs.isEmpty else { return selectedGradeIDs.isEmpty || !Set(player.gradeIDs).isDisjoint(with: selectedGradeIDs) }
                        return !Set(player.gradeIDs).isDisjoint(with: sectionGradeIDs)
                    }
                    .sorted {
                        let lhsNumber = $0.number ?? Int.max
                        let rhsNumber = $1.number ?? Int.max
                        if lhsNumber != rhsNumber { return lhsNumber < rhsNumber }
                        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
            }()
            let rosterPlayerIDs = Set(rosterPlayers.map(\.id))

            func rosterRows<Value>(
                from totals: [UUID: Value],
                numericValue: (Value) -> Int,
                makeRow: (Player, Value) -> [String],
                zeroValue: Value
            ) -> RosterRows {
                let hasAnyData = totals.contains { playerID, value in
                    rosterPlayerIDs.contains(playerID) && numericValue(value) > 0
                }
                guard isRosterReport else {
                    return RosterRows(rows: [], highlightedNameRowIndexes: [])
                }
                guard hasAnyData else {
                    return RosterRows(rows: [], highlightedNameRowIndexes: [])
                }
                let rows = rosterPlayers.map { player in
                    makeRow(player, totals[player.id] ?? zeroValue)
                }
                let highlighted = Set(rows.indices.filter { index in
                    numericValue(totals[rosterPlayers[index].id] ?? zeroValue) == 0
                })
                return RosterRows(rows: rows, highlightedNameRowIndexes: highlighted)
            }

            let allBestPlayersRows: [[String]] = {
                let bestPlayersByPlayer = games.reduce(into: [UUID: Int]()) { partialResult, game in
                    for (index, playerID) in game.bestPlayersRanked.enumerated() {
                        partialResult[playerID, default: 0] += bestPlayerPoints(for: game, index: index)
                    }
                }
                if isRosterReport {
                    return rosterRows(
                        from: bestPlayersByPlayer,
                        numericValue: { $0 },
                        makeRow: { player, totalPoints in [String(totalPoints), player.name] },
                        zeroValue: 0
                    ).rows
                }
                if games.count == 1, let game = games.first {
                    return game.bestPlayersRanked.enumerated().compactMap { index, playerID in
                        guard includePlayerID(playerID), gamesByPlayer[playerID, default: 0] >= minimumGamesThreshold else { return nil }
                        let rankLabel = index == 0 ? "Best" : String(index + 1)
                        return [rankLabel, playerLookup[playerID]?.name ?? "Unknown Player"]
                    }
                }

                return bestPlayersByPlayer
                    .sorted { left, right in
                        if left.value != right.value { return left.value > right.value }
                        return (playerLookup[left.key]?.name ?? "") < (playerLookup[right.key]?.name ?? "")
                    }
                    .compactMap { (playerID, totalPoints) -> [String]? in
                        guard includePlayerID(playerID), totalPoints > 0, gamesByPlayer[playerID, default: 0] >= minimumGamesThreshold else { return nil }
                        return [String(totalPoints), playerLookup[playerID]?.name ?? "Unknown Player"]
                    }
            }()
            let bestPlayersHighlight = isRosterReport ? Set(allBestPlayersRows.indices.filter { allBestPlayersRows[$0].first == "0" }) : []
            let bestPlayersRows = bestPlayersLimit == 0 || isRosterReport ? allBestPlayersRows : Array(allBestPlayersRows.prefix(bestPlayersLimit))
            let guestVotePointsByPlayer = games.reduce(into: [UUID: Int]()) { partialResult, game in
                guard canViewVoteDetails else { return }
                for vote in game.guestVotesRanked {
                    partialResult[vote.playerID, default: 0] += guestVotePoints(for: game, rank: vote.rank)
                }
            }
            let allGuestVoteRows: [[String]] = isRosterReport
                ? rosterRows(
                    from: guestVotePointsByPlayer,
                    numericValue: { $0 },
                    makeRow: { player, totalPoints in [String(totalPoints), player.name] },
                    zeroValue: 0
                ).rows
                : guestVotePointsByPlayer
                .sorted { left, right in
                    if left.value != right.value { return left.value > right.value }
                    return (playerLookup[left.key]?.name ?? "") < (playerLookup[right.key]?.name ?? "")
                }
                .compactMap { (playerID, totalPoints) -> [String]? in
                    guard includePlayerID(playerID), totalPoints > 0, gamesByPlayer[playerID, default: 0] >= minimumGamesThreshold else { return nil }
                    return [String(totalPoints), playerLookup[playerID]?.name ?? "Unknown Player"]
                }
            let guestVoteHighlight = isRosterReport ? Set(allGuestVoteRows.indices.filter { allGuestVoteRows[$0].first == "0" }) : []
            let guestVoteRows = guestVotesLimit == 0 || isRosterReport ? allGuestVoteRows : Array(allGuestVoteRows.prefix(guestVotesLimit))
            let goalsByPlayer = games.reduce(into: [UUID: (goals: Int, oppositionGoals: Int)]()) { partialResult, game in
                for entry in game.goalKickers {
                    guard let playerID = entry.playerID else { continue }
                    partialResult[playerID, default: (goals: 0, oppositionGoals: 0)].goals += entry.goals
                    partialResult[playerID, default: (goals: 0, oppositionGoals: 0)].oppositionGoals += entry.oppositionGoals
                }
                }
            let allGoalKickerRows: [[String]] = isRosterReport
                ? rosterRows(
                    from: goalsByPlayer,
                    numericValue: { $0.goals },
                    makeRow: { player, totals in
                        let goalsText = GameGoalKickerEntry(playerID: player.id, goals: totals.goals, oppositionGoals: totals.oppositionGoals).goalsDisplayText
                        return [player.name, goalsText]
                    },
                    zeroValue: (goals: 0, oppositionGoals: 0)
                ).rows
                : goalsByPlayer
                .sorted { left, right in
                    if left.value.goals != right.value.goals { return left.value.goals > right.value.goals }
                    return playerDisplayName(for: left.key) < playerDisplayName(for: right.key)
                }
                .compactMap { (playerID, totals) -> [String]? in
                    guard includePlayerID(playerID), totals.goals > 0, gamesByPlayer[playerID, default: 0] >= minimumGamesThreshold else { return nil }
                    let goalsText = GameGoalKickerEntry(playerID: playerID, goals: totals.goals, oppositionGoals: totals.oppositionGoals).goalsDisplayText
                    return [playerDisplayName(for: playerID), goalsText]
                }
            let goalKickerHighlight = isRosterReport ? Set(allGoalKickerRows.indices.filter { row in
                guard allGoalKickerRows[row].count > 1 else { return false }
                return allGoalKickerRows[row][1] == "0"
            }) : []
            let goalKickerRows = goalKickersLimit == 0 || isRosterReport ? allGoalKickerRows : Array(allGoalKickerRows.prefix(goalKickersLimit))
            var bestAndFairestPoints: [UUID: Int] = [:]
            for game in games {
                for (index, playerID) in game.bestPlayersRanked.enumerated() {
                    bestAndFairestPoints[playerID, default: 0] += bestPlayerPoints(for: game, index: index)
                }
                if canViewVoteDetails {
                    for vote in game.guestVotesRanked {
                        bestAndFairestPoints[vote.playerID, default: 0] += guestVotePoints(for: game, rank: vote.rank)
                    }
                }
            }
            let allBestAndFairestRows: [[String]] = isRosterReport
                ? rosterRows(
                    from: bestAndFairestPoints,
                    numericValue: { $0 },
                    makeRow: { player, pointTotal in [player.name, "\(pointTotal)"] },
                    zeroValue: 0
                ).rows
                : bestAndFairestPoints
                .sorted { $0.value > $1.value }
                .compactMap { (playerID, pointTotal) -> [String]? in
                    guard includePlayerID(playerID), pointTotal > 0, gamesByPlayer[playerID, default: 0] >= minimumGamesThreshold else { return nil }
                    return [playerLookup[playerID]?.name ?? "Unknown Player", "\(pointTotal)"]
                }
            let bestAndFairestHighlight = isRosterReport ? Set(allBestAndFairestRows.indices.filter { row in
                guard allBestAndFairestRows[row].count > 1 else { return false }
                return allBestAndFairestRows[row][1] == "0"
            }) : []
            let bestAndFairestRows = bestAndFairestLimit == 0 || isRosterReport ? allBestAndFairestRows : Array(allBestAndFairestRows.prefix(bestAndFairestLimit))
            return (
                RosterRows(rows: bestPlayersRows, highlightedNameRowIndexes: bestPlayersHighlight),
                RosterRows(rows: guestVoteRows, highlightedNameRowIndexes: guestVoteHighlight),
                RosterRows(rows: goalKickerRows, highlightedNameRowIndexes: goalKickerHighlight),
                RosterRows(rows: bestAndFairestRows, highlightedNameRowIndexes: bestAndFairestHighlight)
            )
        }

        struct CompactReportTable {
            let title: String
            let columns: [String]
            let rows: [[String]]
            var highlightedNameRowIndexes: Set<Int> = []
        }

        struct RosterReportRow {
            let player: Player
            let dutyCounts: [String: Int]

            var total: Int { dutyCounts.values.reduce(0, +) }
        }

        struct RosterReportDuty {
            let key: String
            let title: String
            let names: (Game) -> [String]
        }

        struct RosterReportColumn {
            let title: String
            let weight: CGFloat
            let value: (RosterReportRow) -> String
            let numericValue: ((RosterReportRow) -> Int)?
        }

        func buildRosterReportRows(for games: [Game], gradeIDs: Set<UUID>) -> [RosterReportRow] {
            let rosterGradeIDs = playersOnlyGradeFilterIDs.isEmpty ? selectedGradeIDs : playersOnlyGradeFilterIDs
            let effectiveGradeIDs = gradeIDs.isEmpty ? rosterGradeIDs : gradeIDs
            let rosterPlayers = players
                .filter { player in
                    guard player.isActive, includePlayerID(player.id) else { return false }
                    guard !effectiveGradeIDs.isEmpty else { return true }
                    return !Set(player.gradeIDs).isDisjoint(with: effectiveGradeIDs)
                }
            let rosterPlayerIDs = Set(rosterPlayers.map(\.id))
            let playersByNormalizedName = Dictionary(grouping: rosterPlayers) { player in
                player.name
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .lowercased()
            }
            let duties = rosterReportDuties()
            var countsByPlayer: [UUID: [String: Int]] = [:]

            for game in games {
                for duty in duties {
                    for rawName in duty.names(game) {
                        let normalizedName = rawName
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                            .lowercased()
                        guard !normalizedName.isEmpty,
                              let playerID = playersByNormalizedName[normalizedName]?.first?.id,
                              rosterPlayerIDs.contains(playerID) else { continue }
                        countsByPlayer[playerID, default: [:]][duty.key, default: 0] += 1
                    }
                }
            }

            return rosterPlayers
                .map { player in
                    RosterReportRow(player: player, dutyCounts: countsByPlayer[player.id] ?? [:])
                }
                .sorted { lhs, rhs in
                    if lhs.total != rhs.total { return lhs.total > rhs.total }
                    return lhs.player.name.localizedCaseInsensitiveCompare(rhs.player.name) == .orderedAscending
                }
        }

        func rosterReportDuties() -> [RosterReportDuty] {
            var duties: [RosterReportDuty] = []

            if template.includeStaffRoles {
                duties.append(RosterReportDuty(key: "headCoach", title: "Head Coach", names: { [$0.headCoachName] }))
                duties.append(RosterReportDuty(key: "assistantCoach", title: "Assistant", names: { [$0.assistantCoachName] }))
                duties.append(RosterReportDuty(key: "teamManager", title: "Manager", names: { [$0.teamManagerName] }))
                duties.append(RosterReportDuty(key: "runner", title: "Runner", names: { [$0.runnerName] }))
            }
            if template.includeOfficials {
                duties.append(RosterReportDuty(key: "goalUmpire", title: "Goal Ump", names: { [$0.goalUmpireName] }))
                duties.append(RosterReportDuty(key: "timeKeeper", title: "Time Keep", names: { [$0.timeKeeperName] }))
                duties.append(RosterReportDuty(key: "fieldUmpire", title: "Field Ump", names: { [$0.fieldUmpireName] }))
            }
            if template.includeUmpires {
                duties.append(RosterReportDuty(key: "boundaryUmpire", title: "Boundary", names: { [$0.boundaryUmpire1Name, $0.boundaryUmpire2Name] }))
                duties.append(RosterReportDuty(key: "water", title: "Water", names: { [$0.waterBoy1Name, $0.waterBoy2Name, $0.waterBoy3Name, $0.waterBoy4Name] }))
            }
            if template.includeTrainers {
                duties.append(RosterReportDuty(key: "trainer", title: "Trainer", names: { $0.trainers }))
            }

            return duties
        }

        func rosterReportColumns(for rows: [RosterReportRow]) -> [RosterReportColumn] {
            var columns: [RosterReportColumn] = [
                RosterReportColumn(title: "Player", weight: 0.42, value: { $0.player.name }, numericValue: nil)
            ]

            for duty in rosterReportDuties() {
                if rows.contains(where: { $0.dutyCounts[duty.key, default: 0] > 0 }) {
                    columns.append(RosterReportColumn(
                        title: duty.title,
                        weight: 0.12,
                        value: { String($0.dutyCounts[duty.key, default: 0]) },
                        numericValue: { $0.dutyCounts[duty.key, default: 0] }
                    ))
                }
            }

            columns.append(RosterReportColumn(title: "Total", weight: 0.10, value: { String($0.total) }, numericValue: { $0.total }))
            return columns
        }

        func estimatedRosterReportHeight(for games: [Game], gradeIDs: Set<UUID>) -> CGFloat {
            let rowCount = max(buildRosterReportRows(for: games, gradeIDs: gradeIDs).count, 1)
            return 24 + 24 + (CGFloat(rowCount) * 24) + 10
        }

        func drawRosterReportTable(for games: [Game], gradeIDs: Set<UUID>) {
            let rows = buildRosterReportRows(for: games, gradeIDs: gradeIDs)
            let columns = rosterReportColumns(for: rows)
            let totalWeight = columns.map(\.weight).reduce(CGFloat(0), +)
            let columnWidths = columns.map { ($0.weight / max(totalWeight, 1)) * contentRect.width }
            let headerHeight: CGFloat = 24
            let rowHeight: CGFloat = 24
            let metricColumns = columns.compactMap(\.numericValue)

            drawSectionHeader("Roster")
            beginNewPageIfNeeded(requiredHeight: headerHeight + rowHeight)

            func drawHeader() {
                var x = contentRect.minX
                for (index, column) in columns.enumerated() {
                    let rect = CGRect(x: x, y: cursorY, width: columnWidths[index], height: headerHeight)
                    UIColor(white: 0.92, alpha: 1).setFill()
                    UIBezierPath(rect: rect).fill()
                    UIColor.separator.setStroke()
                    UIBezierPath(rect: rect).stroke()
                    NSAttributedString(
                        string: column.title,
                        attributes: [.font: headerFont, .foregroundColor: UIColor.black]
                    ).draw(in: rect.insetBy(dx: 4, dy: 6))
                    x += columnWidths[index]
                }
                cursorY += headerHeight
            }

            drawHeader()

            guard !rows.isEmpty else {
                let rect = CGRect(x: contentRect.minX, y: cursorY, width: contentRect.width, height: rowHeight)
                UIColor.separator.setStroke()
                UIBezierPath(rect: rect).stroke()
                NSAttributedString(
                    string: "No active players matched this roster.",
                    attributes: [.font: bodyFont, .foregroundColor: UIColor.darkGray]
                ).draw(in: rect.insetBy(dx: 4, dy: 5))
                cursorY += rowHeight + 10
                return
            }

            for (rowIndex, row) in rows.enumerated() {
                if cursorY + rowHeight > bottomLimit {
                    beginNewPage()
                    drawHeader()
                }
                if rowIndex.isMultiple(of: 2) {
                    UIColor(white: 0.985, alpha: 1).setFill()
                    UIBezierPath(rect: CGRect(x: contentRect.minX, y: cursorY, width: contentRect.width, height: rowHeight)).fill()
                }

                let shouldHighlightName = metricColumns.isEmpty || metricColumns.allSatisfy { $0(row) == 0 }
                var x = contentRect.minX
                for (index, column) in columns.enumerated() {
                    let rect = CGRect(x: x, y: cursorY, width: columnWidths[index], height: rowHeight)
                    let isNameColumn = column.title == "Player"
                    if shouldHighlightName, isNameColumn {
                        UIColor.systemYellow.withAlphaComponent(0.24).setFill()
                        UIBezierPath(rect: rect).fill()
                    }
                    UIColor.separator.setStroke()
                    UIBezierPath(rect: rect).stroke()
                    let foregroundColor: UIColor = shouldHighlightName && isNameColumn ? .systemOrange : .black
                    let textFont: UIFont = shouldHighlightName && isNameColumn
                        ? (UIFont(name: "AvenirNext-DemiBold", size: 11) ?? UIFont.systemFont(ofSize: 11, weight: .semibold))
                        : bodyFont
                    NSAttributedString(
                        string: column.value(row),
                        attributes: [.font: textFont, .foregroundColor: foregroundColor]
                    ).draw(in: rect.insetBy(dx: 4, dy: 5))
                    x += columnWidths[index]
                }
                cursorY += rowHeight
            }
            cursorY += 10
        }

        func buildStaffTables(for games: [Game]) -> [String: CompactReportTable] {
            func normalizedName(_ value: String) -> String {
                value.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            typealias RoleNameKey = String
            var coachingCounts: [RoleNameKey: Int] = [:]
            var officialCounts: [RoleNameKey: Int] = [:]
            var trainerCounts: [RoleNameKey: Int] = [:]
            struct OfficialDutyTally {
                var goalUmpire: Int = 0
                var timeKeeper: Int = 0
                var boundaryUmpire: Int = 0
                var waterBoy: Int = 0
                var fieldUmpire: Int = 0
                var total: Int { goalUmpire + timeKeeper + boundaryUmpire + waterBoy + fieldUmpire }
            }
            var officialDutyCountsByName: [String: OfficialDutyTally] = [:]

            func roleNameKey(role: String, name: String) -> RoleNameKey {
                "\(role)||\(name)"
            }

            func increment(_ dictionary: inout [RoleNameKey: Int], role: String, name: String) {
                let trimmed = normalizedName(name)
                guard !trimmed.isEmpty, includeName(trimmed) else { return }
                dictionary[roleNameKey(role: role, name: trimmed), default: 0] += 1
            }

            func incrementOfficialDuty(name: String, update: (inout OfficialDutyTally) -> Void) {
                let trimmed = normalizedName(name)
                guard !trimmed.isEmpty, includeName(trimmed) else { return }
                var tally = officialDutyCountsByName[trimmed] ?? OfficialDutyTally()
                update(&tally)
                officialDutyCountsByName[trimmed] = tally
            }

            func makeRoleCountRows(_ countsByRoleName: [RoleNameKey: Int]) -> [[String]] {
                let roleRows = countsByRoleName.compactMap { key, value -> (role: String, name: String, count: Int)? in
                        let parts = key.components(separatedBy: "||")
                        guard parts.count == 2 else { return nil }
                        return (role: parts[0], name: parts[1], count: value)
                    }
                let sortedRoleRows = roleRows.sorted { left, right in
                        if left.count != right.count { return left.count > right.count }
                        let roleComparison = left.role.localizedCaseInsensitiveCompare(right.role)
                        if roleComparison != .orderedSame {
                            return roleComparison == .orderedAscending
                        }
                        let nameComparison = left.name.localizedCaseInsensitiveCompare(right.name)
                        return nameComparison == .orderedAscending
                    }

                return sortedRoleRows.map { [$0.role, $0.name] }
            }

            for game in games {
                if template.includeStaffRoles {
                    increment(&coachingCounts, role: "Head Coach", name: game.headCoachName)
                    increment(&coachingCounts, role: "Assistant Coach", name: game.assistantCoachName)
                    increment(&coachingCounts, role: "Team Manager", name: game.teamManagerName)
                    increment(&coachingCounts, role: "Runner", name: game.runnerName)
                }
                if template.includeOfficials || template.includeUmpires {
                    if template.displayOfficialsInListView {
                        if template.includeOfficials {
                            increment(&officialCounts, role: "Goal Umpire", name: game.goalUmpireName)
                            increment(&officialCounts, role: "Time Keeper", name: game.timeKeeperName)
                            increment(&officialCounts, role: "Field Umpire", name: game.fieldUmpireName)
                        }
                        if template.includeUmpires {
                            increment(&officialCounts, role: "Boundary Umpire", name: game.boundaryUmpire1Name)
                            increment(&officialCounts, role: "Boundary Umpire", name: game.boundaryUmpire2Name)
                            increment(&officialCounts, role: "Water", name: game.waterBoy1Name)
                            increment(&officialCounts, role: "Water", name: game.waterBoy2Name)
                            increment(&officialCounts, role: "Water", name: game.waterBoy3Name)
                            increment(&officialCounts, role: "Water", name: game.waterBoy4Name)
                        }
                    } else {
                        if template.includeOfficials {
                            incrementOfficialDuty(name: game.goalUmpireName) { $0.goalUmpire += 1 }
                            incrementOfficialDuty(name: game.timeKeeperName) { $0.timeKeeper += 1 }
                            incrementOfficialDuty(name: game.fieldUmpireName) { $0.fieldUmpire += 1 }
                        }
                        if template.includeUmpires {
                            incrementOfficialDuty(name: game.boundaryUmpire1Name) { $0.boundaryUmpire += 1 }
                            incrementOfficialDuty(name: game.boundaryUmpire2Name) { $0.boundaryUmpire += 1 }
                            incrementOfficialDuty(name: game.waterBoy1Name) { $0.waterBoy += 1 }
                            incrementOfficialDuty(name: game.waterBoy2Name) { $0.waterBoy += 1 }
                            incrementOfficialDuty(name: game.waterBoy3Name) { $0.waterBoy += 1 }
                            incrementOfficialDuty(name: game.waterBoy4Name) { $0.waterBoy += 1 }
                        }
                    }
                }
                if template.includeTrainers {
                    for trainer in game.trainers {
                        increment(&trainerCounts, role: "Trainer", name: trainer)
                    }
                }
            }

            var tables: [String: CompactReportTable] = [:]
            tables["coachingStaff"] = CompactReportTable(title: "Coaching Staff", columns: ["Role", "Name"], rows: makeRoleCountRows(coachingCounts))
            if template.displayOfficialsInListView {
                tables["officials"] = CompactReportTable(title: "Officials", columns: ["Role", "Name"], rows: makeRoleCountRows(officialCounts))
            } else {
                let officialEntries: [(name: String, tally: OfficialDutyTally)] = officialDutyCountsByName.map {
                    (name: $0.key, tally: $0.value)
                }
                let sortedOfficialEntries = officialEntries.sorted { left, right in
                    if left.tally.total != right.tally.total {
                        return left.tally.total > right.tally.total
                    }
                    return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
                }
                let officialRows = sortedOfficialEntries.map { entry in
                    [
                        entry.name,
                        String(entry.tally.goalUmpire),
                        String(entry.tally.timeKeeper),
                        String(entry.tally.boundaryUmpire),
                        String(entry.tally.waterBoy),
                        String(entry.tally.fieldUmpire),
                        String(entry.tally.total)
                    ]
                }
                tables["officials"] = CompactReportTable(
                    title: "Officials",
                    columns: ["Name", "Goal Ump", "Time Keep", "Boundary Ump", "Water", "Field Ump", "Total"],
                    rows: officialRows
                )
            }
            tables["trainers"] = CompactReportTable(title: "Trainers", columns: ["Role", "Name"], rows: makeRoleCountRows(trainerCounts))
            return tables
        }

        func drawCompactTables(_ compactTables: [(key: String, table: CompactReportTable)]) {
            guard !compactTables.isEmpty else { return }
            let columnCount = max(1, min(template.normalizedReportColumnCount, 3))
            let gap: CGFloat = 10
            let columnWidth = (contentRect.width - (CGFloat(columnCount - 1) * gap)) / CGFloat(columnCount)
            var tableColumns: [[CompactReportTable]] = Array(repeating: [], count: columnCount)
            for item in compactTables {
                let assignedColumn = max(0, min(template.includeSectionColumnAssignments[item.key] ?? 0, columnCount - 1))
                tableColumns[assignedColumn].append(item.table)
            }

            func compactTableHeight(for table: CompactReportTable) -> CGFloat {
                let visibleRows = max(table.rows.count, 1)
                return 46 + (CGFloat(visibleRows) * 24)
            }

            var nextTableIndexByColumn = Array(repeating: 0, count: columnCount)
            var firstPage = true

            while tableColumns.enumerated().contains(where: { index, tables in
                nextTableIndexByColumn[index] < tables.count
            }) {
                if firstPage {
                    firstPage = false
                } else {
                    beginNewPage()
                }

                let pageStartY = cursorY
                var columnY = Array(repeating: pageStartY, count: columnCount)
                var renderedAtLeastOneTable = false

                for column in 0..<columnCount {
                    while nextTableIndexByColumn[column] < tableColumns[column].count {
                        let table = tableColumns[column][nextTableIndexByColumn[column]]
                        let tableHeight = compactTableHeight(for: table)
                        let wouldOverflow = columnY[column] + tableHeight > bottomLimit
                        if wouldOverflow, columnY[column] > pageStartY {
                            break
                        }

                        let previousCursor = cursorY
                        cursorY = columnY[column]
                        let renderedHeight = drawCompactTable(
                            title: table.title,
                            columns: table.columns,
                            rows: table.rows,
                            highlightedNameRowIndexes: table.highlightedNameRowIndexes,
                            xOrigin: contentRect.minX + CGFloat(column) * (columnWidth + gap),
                            width: columnWidth
                        )
                        cursorY = previousCursor

                        columnY[column] += renderedHeight + 8
                        nextTableIndexByColumn[column] += 1
                        renderedAtLeastOneTable = true

                        if columnY[column] >= bottomLimit {
                            break
                        }
                    }
                }

                cursorY = columnY.max() ?? pageStartY

                if !renderedAtLeastOneTable {
                    break
                }
            }
        }

        let groupingMode = ReportGroupingMode(rawValue: template.groupingModeRawValue) ?? .combinedTotals
        let gradeOrderLookup = Dictionary(selectedGrades.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let orderedGradeGroups = Dictionary(grouping: relevantGames, by: \.gradeID)
            .sorted { left, right in
                let leftOrder = gradeOrderLookup[left.key] ?? Int.max
                let rightOrder = gradeOrderLookup[right.key] ?? Int.max
                if leftOrder != rightOrder { return leftOrder < rightOrder }
                return (gradeLookup[left.key] ?? "") < (gradeLookup[right.key] ?? "")
            }

        struct RenderedSection {
            let title: String
            let games: [Game]
            let gradeIDs: Set<UUID>
        }

        let renderedSections: [RenderedSection] = {
            if groupingMode.splitByGradeEnabled, groupingMode.splitByGameEnabled {
                return orderedGradeGroups.flatMap { (gradeID, games) in
                    games
                        .sorted { $0.date > $1.date }
                        .map { game in
                            let gradeName = gradeLookup[gradeID] ?? "Unknown Grade"
                            let title = "\(gradeName) • \(formattedDate(game.date)) vs \(game.opponent)"
                            return RenderedSection(title: title, games: [game], gradeIDs: [gradeID])
                        }
                }
            }
            if groupingMode.splitByGradeEnabled {
                let gamesByGradeID = Dictionary(orderedGradeGroups.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })
                let gradeIDsToRender = isRosterReport ? selectedGrades.map(\.id) : orderedGradeGroups.map(\.0)
                return gradeIDsToRender.map { gradeID in
                    let games = gamesByGradeID[gradeID] ?? []
                    return RenderedSection(title: gradeLookup[gradeID] ?? "Unknown Grade", games: games.sorted { $0.date > $1.date }, gradeIDs: [gradeID])
                }
            }
            if groupingMode.splitByGameEnabled {
                return relevantGames.map { game in
                    RenderedSection(title: "\(formattedDate(game.date)) vs \(game.opponent)", games: [game], gradeIDs: [game.gradeID])
                }
            }
            return [RenderedSection(title: "Report", games: relevantGames, gradeIDs: selectedGradeIDs)]
        }()

        func drawOrderedSections(for games: [Game], gradeIDs: Set<UUID>, scoreGame: Game?) {
            if isRosterReport {
                drawRosterReportTable(for: games, gradeIDs: gradeIDs)
                return
            }

            let rows = reportRows(for: games, gradeIDsOverride: gradeIDs)
            let staffTables = buildStaffTables(for: games)
            let metadataGame = games.first
            var pendingCompactTables: [(key: String, table: CompactReportTable)] = []

            func flushPending() {
                drawCompactTables(pendingCompactTables)
                pendingCompactTables = []
            }

            for key in template.includeSectionOrder {
                switch key {
                case "scores":
                    if template.includeScores, let scoreGame {
                        flushPending()
                        drawScorePills(for: scoreGame, title: "Score")
                    }
                case "bestPlayers":
                    if template.includeBestPlayers, !isRosterReport || !rows.bestPlayers.rows.isEmpty {
                        let bestPlayersLabel = games.count == 1 ? "Rank" : "Points"
                        pendingCompactTables.append((key: "bestPlayers", table: CompactReportTable(title: "Best Players", columns: [bestPlayersLabel, "Player"], rows: rows.bestPlayers.rows, highlightedNameRowIndexes: rows.bestPlayers.highlightedNameRowIndexes)))
                    }
                case "guestVotes":
                    if template.includePlayerGrades, canViewVoteDetails, !isRosterReport || !rows.guestVotes.rows.isEmpty {
                        pendingCompactTables.append((key: "guestVotes", table: CompactReportTable(title: "Guest Votes", columns: ["Points", "Player"], rows: rows.guestVotes.rows, highlightedNameRowIndexes: rows.guestVotes.highlightedNameRowIndexes)))
                    }
                case "goalKickers":
                    if template.includeGoalKickers, !isRosterReport || !rows.goalKickers.rows.isEmpty {
                        let goalKickerRows = rows.goalKickers.rows.map { row -> [String] in
                            guard row.count >= 2 else { return row }
                            return [row[1], row[0]]
                        }
                        pendingCompactTables.append((key: "goalKickers", table: CompactReportTable(title: "Goal Kickers", columns: ["Goals", "Player"], rows: goalKickerRows, highlightedNameRowIndexes: rows.goalKickers.highlightedNameRowIndexes)))
                    }
                case "bestAndFairest":
                    if template.includeBestAndFairestVotes, canViewVoteDetails, !isRosterReport || !rows.bestAndFairest.rows.isEmpty {
                        pendingCompactTables.append((key: "bestAndFairest", table: CompactReportTable(title: "Best and Fairest", columns: ["Player", "Points"], rows: rows.bestAndFairest.rows, highlightedNameRowIndexes: rows.bestAndFairest.highlightedNameRowIndexes)))
                    }
                case "coachingStaff", "officials", "trainers":
                    if let table = staffTables[key], !table.rows.isEmpty {
                        pendingCompactTables.append((key: key, table: table))
                    }
                case "matchNotes":
                    if template.includeMatchNotes {
                        flushPending()
                        let notes = metadataGame?.notes.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        drawDetailTable(title: "Match Notes", columns: ["Notes"], rows: notes.isEmpty ? [] : [[notes]])
                    }
                default:
                    continue
                }
            }
            flushPending()
        }

        func compactTableHeight(for table: CompactReportTable) -> CGFloat {
            let visibleRows = max(table.rows.count, 1)
            return 46 + (CGFloat(visibleRows) * 24)
        }

        func estimatedCompactBlockHeight(_ compactTables: [(key: String, table: CompactReportTable)]) -> CGFloat {
            guard !compactTables.isEmpty else { return 0 }
            let columnCount = max(1, min(template.normalizedReportColumnCount, 3))
            var columnHeights = Array(repeating: CGFloat(0), count: columnCount)

            for item in compactTables {
                let assignedColumn = max(0, min(template.includeSectionColumnAssignments[item.key] ?? 0, columnCount - 1))
                let tableHeight = compactTableHeight(for: item.table)
                let gapAfterTable: CGFloat = 8
                columnHeights[assignedColumn] += tableHeight + gapAfterTable
            }

            return columnHeights.max() ?? 0
        }

        func estimatedOrderedSectionHeight(for games: [Game], gradeIDs: Set<UUID>, scoreGame: Game?) -> CGFloat {
            if isRosterReport {
                return estimatedRosterReportHeight(for: games, gradeIDs: gradeIDs)
            }

            let rows = reportRows(for: games, gradeIDsOverride: gradeIDs)
            let staffTables = buildStaffTables(for: games)
            var pendingCompactTables: [(key: String, table: CompactReportTable)] = []
            var estimatedHeight: CGFloat = 0

            func flushPendingEstimate() {
                estimatedHeight += estimatedCompactBlockHeight(pendingCompactTables)
                pendingCompactTables = []
            }

            for key in template.includeSectionOrder {
                switch key {
                case "scores":
                    if template.includeScores, let scoreGame {
                        flushPendingEstimate()
                        let scoreBlockHeight: CGFloat = shouldShowScore(for: scoreGame) ? 110 : 78
                        estimatedHeight += 24 + scoreBlockHeight // drawSectionHeader + score pills block
                    }
                case "bestPlayers":
                    if template.includeBestPlayers, !isRosterReport || !rows.bestPlayers.rows.isEmpty {
                        let bestPlayersLabel = games.count == 1 ? "Rank" : "Points"
                        pendingCompactTables.append((key: "bestPlayers", table: CompactReportTable(title: "Best Players", columns: [bestPlayersLabel, "Player"], rows: rows.bestPlayers.rows, highlightedNameRowIndexes: rows.bestPlayers.highlightedNameRowIndexes)))
                    }
                case "guestVotes":
                    if template.includePlayerGrades, canViewVoteDetails, !isRosterReport || !rows.guestVotes.rows.isEmpty {
                        pendingCompactTables.append((key: "guestVotes", table: CompactReportTable(title: "Guest Votes", columns: ["Points", "Player"], rows: rows.guestVotes.rows, highlightedNameRowIndexes: rows.guestVotes.highlightedNameRowIndexes)))
                    }
                case "goalKickers":
                    if template.includeGoalKickers, !isRosterReport || !rows.goalKickers.rows.isEmpty {
                        let goalKickerRows = rows.goalKickers.rows.map { row -> [String] in
                            guard row.count >= 2 else { return row }
                            return [row[1], row[0]]
                        }
                        pendingCompactTables.append((key: "goalKickers", table: CompactReportTable(title: "Goal Kickers", columns: ["Goals", "Player"], rows: goalKickerRows, highlightedNameRowIndexes: rows.goalKickers.highlightedNameRowIndexes)))
                    }
                case "bestAndFairest":
                    if template.includeBestAndFairestVotes, canViewVoteDetails, !isRosterReport || !rows.bestAndFairest.rows.isEmpty {
                        pendingCompactTables.append((key: "bestAndFairest", table: CompactReportTable(title: "Best and Fairest", columns: ["Player", "Points"], rows: rows.bestAndFairest.rows, highlightedNameRowIndexes: rows.bestAndFairest.highlightedNameRowIndexes)))
                    }
                case "coachingStaff", "officials", "trainers":
                    if let table = staffTables[key], !table.rows.isEmpty {
                        pendingCompactTables.append((key: key, table: table))
                    }
                case "matchNotes":
                    if template.includeMatchNotes {
                        flushPendingEstimate()
                        estimatedHeight += 24 + 24 + 24 + 10
                    }
                default:
                    continue
                }
            }

            flushPendingEstimate()
            return estimatedHeight
        }

        if groupingMode.splitByGradeEnabled || groupingMode.splitByGameEnabled {
            for section in renderedSections {
                if section.games.isEmpty, !isRosterReport { continue }
                let sectionGame = section.games.first
                let sectionGradeID = sectionGame?.gradeID ?? section.gradeIDs.first
                let gradeName = sectionGradeID.flatMap { gradeLookup[$0] } ?? "Unknown Grade"
                let titleParts: [String] = [
                    groupingMode.splitByGradeEnabled ? gradeName : nil,
                    groupingMode.splitByGameEnabled ? sectionGame.map { "\(formattedDate($0.date)) vs \($0.opponent)" } : nil
                ].compactMap { $0 }
                let sectionTitle = titleParts.isEmpty ? section.title : titleParts.joined(separator: " • ")

                if groupingMode.splitByGradeEnabled {
                    let sectionHeaderHeight: CGFloat = 24
                    let estimatedSectionHeight = sectionHeaderHeight + estimatedOrderedSectionHeight(for: section.games, gradeIDs: section.gradeIDs, scoreGame: sectionGame)
                    let pageContentHeight = bottomLimit - contentRect.minY
                    if estimatedSectionHeight <= pageContentHeight,
                       cursorY + estimatedSectionHeight > bottomLimit {
                        beginNewPage()
                    }
                }

                drawSectionHeader(sectionTitle)
                drawOrderedSections(for: section.games, gradeIDs: section.gradeIDs, scoreGame: sectionGame)
            }
        } else {
            drawOrderedSections(for: relevantGames, gradeIDs: selectedGradeIDs, scoreGame: primaryGame)
        }
    }

    let safeName = template.name
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: " ", with: "_")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CustomReport_\(safeName)_Preview.pdf")
    try data.write(to: url, options: Data.WritingOptions.atomic)
    return url
}

private struct PDFPreviewView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.displayMode = .singlePageContinuous
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(url: url)
    }
}

private struct CustomReportTemplateDraft {
    let name: String
    let selectedGradeIDs: [UUID]
    let sendReportOnGameSave: Bool
    let sendReportTriggerGradeID: UUID?
    let displayOfficialsInListView: Bool
    let includeScores: Bool
    let includeBestPlayers: Bool
    let bestPlayersLimit: Int
    let includeGuestVotes: Bool
    let guestVotesLimit: Int
    let includeGoalKickers: Bool
    let goalKickersLimit: Int
    let includeBestAndFairestVotes: Bool
    let bestAndFairestLimit: Int
    let includeStaffRoles: Bool
    let includeOfficials: Bool
    let includeUmpires: Bool
    let includeTrainers: Bool
    let includeMatchNotes: Bool
    let includeOnlyActiveGrades: Bool
    let includePlayersOnly: Bool
    let playersOnlyGradeFilterIDs: [UUID]
    let minimumGamesPlayed: Int
    let groupingModeRawValue: Int
    let selectedQuickPickRawValue: String
    let customDateRangeStart: Date
    let customDateRangeEnd: Date
    let selectedRecipientSectionKeys: [String]
    let selectedRecipientContactIDs: [UUID]
    let includedDataOrder: [String]
    let reportColumnCount: Int
    let includedDataColumns: [String: Int]
}

private struct CustomReportEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigationState: AppNavigationState

    let grades: [Grade]
    let contacts: [Contact]
    let sectionMemberships: [ContactSectionMembership]
    let onDelete: (() -> Void)?
    let onSave: (CustomReportTemplateDraft) -> Void

    @State private var name: String
    @State private var selectedGradeIDs: Set<UUID>
    @State private var sendReportOnGameSave: Bool
    @State private var sendReportTriggerGradeID: UUID?
    @State private var displayOfficialsInListView: Bool
    @State private var includeScores: Bool
    @State private var includeBestPlayers: Bool
    @State private var bestPlayersLimit: Int
    @State private var includeGuestVotes: Bool
    @State private var guestVotesLimit: Int
    @State private var includeGoalKickers: Bool
    @State private var goalKickersLimit: Int
    @State private var includeBestAndFairestVotes: Bool
    @State private var bestAndFairestLimit: Int
    @State private var includeStaffRoles: Bool
    @State private var includeOfficials: Bool
    @State private var includeUmpires: Bool
    @State private var includeTrainers: Bool
    @State private var includeMatchNotes: Bool
    @State private var includedDataOrder: [String]
    @State private var reportColumnCount: Int
    @State private var includedDataColumns: [String: Int]
    @State private var includeOnlyActiveGrades: Bool
    @State private var includePlayersOnly: Bool
    @State private var playersOnlyGradeFilterIDs: Set<UUID>
    @State private var minimumGamesPlayed: Int
    @State private var groupingMode: ReportGroupingMode
    @State private var selectedDateRangeQuickPick: ReportRangeQuickPick
    @State private var customDateRangeStart: Date
    @State private var customDateRangeEnd: Date
    @State private var selectedRecipientSectionKeys: Set<String>
    @State private var selectedRecipientContactIDs: Set<UUID>
    @State private var showDeleteConfirmation = false
    @State private var longPressDraggingKey: String?
    @State private var longPressDragTranslation: CGSize = .zero
    @State private var longPressDragStartIndex: Int?
    @State private var longPressDragStartColumn: Int?
    @AppStorage("contactSectionCustomTitles") private var customSectionTitlesData: String = ""

    init(
        grades: [Grade],
        contacts: [Contact],
        sectionMemberships: [ContactSectionMembership],
        initialName: String = "",
        initialSelectedGradeIDs: [UUID] = [],
        initialSendReportOnGameSave: Bool = false,
        initialSendReportTriggerGradeID: UUID? = nil,
        initialDisplayOfficialsInListView: Bool = true,
        initialIncludeScores: Bool = true,
        initialIncludeBestPlayers: Bool = true,
        initialBestPlayersLimit: Int = 6,
        initialIncludeGuestVotes: Bool = false,
        initialGuestVotesLimit: Int = 0,
        initialIncludeGoalKickers: Bool = true,
        initialGoalKickersLimit: Int = 0,
        initialIncludeBestAndFairestVotes: Bool = false,
        initialBestAndFairestLimit: Int = 5,
        initialIncludeStaffRoles: Bool = true,
        initialIncludeOfficials: Bool = true,
        initialIncludeUmpires: Bool = true,
        initialIncludeTrainers: Bool = true,
        initialIncludeMatchNotes: Bool = false,
        initialIncludedDataOrder: [String] = CustomReportTemplate.defaultIncludeSectionOrder,
        initialReportColumnCount: Int = 2,
        initialIncludedDataColumns: [String: Int] = CustomReportTemplate.defaultIncludeSectionColumns,
        initialIncludeOnlyActiveGrades: Bool = true,
        initialIncludePlayersOnly: Bool = false,
        initialPlayersOnlyGradeFilterIDs: [UUID] = [],
        initialMinimumGamesPlayed: Int = 1,
        initialGroupingModeRawValue: Int = 1,
        initialDateRangeQuickPickRawValue: String = ReportRangeQuickPick.mostRecentGame.rawValue,
        initialCustomDateRangeStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
        initialCustomDateRangeEnd: Date = Date(),
        initialRecipientSectionKeys: [String] = [],
        initialRecipientContactIDs: [UUID] = [],
        onDelete: (() -> Void)? = nil,
        onSave: @escaping (CustomReportTemplateDraft) -> Void
    ) {
        self.grades = grades
        self.contacts = contacts
        self.sectionMemberships = sectionMemberships
        self.onDelete = onDelete
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _selectedGradeIDs = State(initialValue: Set(initialSelectedGradeIDs))
        _sendReportOnGameSave = State(initialValue: initialSendReportOnGameSave)
        _sendReportTriggerGradeID = State(initialValue: initialSendReportTriggerGradeID)
        _displayOfficialsInListView = State(initialValue: initialDisplayOfficialsInListView)
        _includeScores = State(initialValue: initialIncludeScores)
        _includeBestPlayers = State(initialValue: initialIncludeBestPlayers)
        _bestPlayersLimit = State(initialValue: Self.clampedReportItemLimit(initialBestPlayersLimit, defaultValue: 0))
        _includeGuestVotes = State(initialValue: initialIncludeGuestVotes)
        _guestVotesLimit = State(initialValue: Self.clampedReportItemLimit(initialGuestVotesLimit, defaultValue: 0))
        _includeGoalKickers = State(initialValue: initialIncludeGoalKickers)
        _goalKickersLimit = State(initialValue: Self.clampedReportItemLimit(initialGoalKickersLimit, defaultValue: 0))
        _includeBestAndFairestVotes = State(initialValue: initialIncludeBestAndFairestVotes)
        _bestAndFairestLimit = State(initialValue: Self.clampedReportItemLimit(initialBestAndFairestLimit, defaultValue: 5))
        _includeStaffRoles = State(initialValue: initialIncludeStaffRoles)
        _includeOfficials = State(initialValue: initialIncludeOfficials)
        _includeUmpires = State(initialValue: initialIncludeUmpires)
        _includeTrainers = State(initialValue: initialIncludeTrainers)
        _includeMatchNotes = State(initialValue: initialIncludeMatchNotes)
        _includedDataOrder = State(initialValue: CustomReportEditView.normalizeIncludedDataOrder(initialIncludedDataOrder))
        _reportColumnCount = State(initialValue: max(1, min(initialReportColumnCount, 3)))
        _includedDataColumns = State(initialValue: CustomReportEditView.normalizeIncludedDataColumns(initialIncludedDataColumns, order: initialIncludedDataOrder, columnCount: max(1, min(initialReportColumnCount, 3))))
        _includeOnlyActiveGrades = State(initialValue: initialIncludeOnlyActiveGrades)
        _includePlayersOnly = State(initialValue: initialIncludePlayersOnly)
        _playersOnlyGradeFilterIDs = State(initialValue: Set(initialPlayersOnlyGradeFilterIDs))
        _minimumGamesPlayed = State(initialValue: max(0, initialMinimumGamesPlayed))
        _groupingMode = State(initialValue: ReportGroupingMode(rawValue: initialGroupingModeRawValue) ?? .combinedTotals)
        _selectedDateRangeQuickPick = State(initialValue: ReportRangeQuickPick(rawValue: initialDateRangeQuickPickRawValue) ?? .mostRecentGame)
        _customDateRangeStart = State(initialValue: initialCustomDateRangeStart)
        _customDateRangeEnd = State(initialValue: initialCustomDateRangeEnd)
        _selectedRecipientSectionKeys = State(initialValue: Set(initialRecipientSectionKeys))
        _selectedRecipientContactIDs = State(initialValue: Set(initialRecipientContactIDs))
    }

    private var selectedTriggerGradeOptions: [Grade] {
        grades.filter { selectedGradeIDs.contains($0.id) }
    }

    private var shouldShowSendTriggerPicker: Bool {
        sendReportOnGameSave && selectedGradeIDs.count > 1
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var splitByGameBinding: Binding<Bool> {
        Binding(
            get: { groupingMode.splitByGameEnabled },
            set: { newValue in
                groupingMode = ReportGroupingMode.from(splitByGame: newValue, splitByGrade: groupingMode.splitByGradeEnabled)
            }
        )
    }

    private var splitByGradeBinding: Binding<Bool> {
        Binding(
            get: { groupingMode.splitByGradeEnabled },
            set: { newValue in
                groupingMode = ReportGroupingMode.from(splitByGame: groupingMode.splitByGameEnabled, splitByGrade: newValue)
            }
        )
    }

    private static func normalizeIncludedDataOrder(_ rawOrder: [String]) -> [String] {
        var order: [String] = []
        for key in rawOrder where CustomReportTemplate.defaultIncludeSectionOrder.contains(key) && !order.contains(key) {
            order.append(key)
        }
        for key in CustomReportTemplate.defaultIncludeSectionOrder where !order.contains(key) {
            order.append(key)
        }
        return order
    }

    private static func normalizeIncludedDataColumns(_ rawColumns: [String: Int], order: [String], columnCount: Int) -> [String: Int] {
        let normalizedOrder = normalizeIncludedDataOrder(order)
        let clampedColumnCount = max(1, min(columnCount, 3))
        var result: [String: Int] = [:]
        var fallbackColumn = 0
        for key in normalizedOrder where key != "scores" {
            if let value = rawColumns[key] {
                result[key] = max(0, min(value, clampedColumnCount - 1))
            } else {
                result[key] = fallbackColumn
                fallbackColumn = (fallbackColumn + 1) % clampedColumnCount
            }
        }
        return result
    }

    private var nonScoreIncludedKeys: [String] {
        includedDataOrder.filter { $0 != "scores" }
    }

    private func keys(in column: Int) -> [String] {
        nonScoreIncludedKeys.filter { includedDataColumns[$0, default: 0] == column }
    }

    private func moveIncludedKey(_ draggedKey: String, to targetIndex: Int, targetColumn: Int) {
        guard nonScoreIncludedKeys.contains(draggedKey) else { return }
        let clampedColumn = max(0, min(targetColumn, reportColumnCount - 1))
        includedDataColumns[draggedKey] = clampedColumn

        var reordered = includedDataOrder.filter { $0 != draggedKey }

        let targetColumnKeys = reordered.filter { includedDataColumns[$0, default: 0] == clampedColumn }
        let clampedTargetIndex = max(0, min(targetIndex, targetColumnKeys.count))

        if clampedTargetIndex < targetColumnKeys.count {
            let targetKey = targetColumnKeys[clampedTargetIndex]
            if let insertionIndex = reordered.firstIndex(of: targetKey) {
                reordered.insert(draggedKey, at: insertionIndex)
            } else {
                reordered.append(draggedKey)
            }
        } else if let lastColumnKey = targetColumnKeys.last,
                  let insertionIndex = reordered.firstIndex(of: lastColumnKey) {
            reordered.insert(draggedKey, at: insertionIndex + 1)
        } else {
            reordered.append(draggedKey)
        }
        includedDataOrder = reordered
    }

    private let includedColumnPlaceholderCount = 10
    private let includedDataCardStepHeight: CGFloat = 64
    private let includedDataColumnStepWidth: CGFloat = 180
    private let includedDataLongPressDuration: Double = 0.35

    private func beginLongPressDrag(for key: String) {
        guard longPressDraggingKey == nil else { return }
        let column = includedDataColumns[key, default: 0]
        let columnKeys = keys(in: column)
        guard let index = columnKeys.firstIndex(of: key) else { return }
        longPressDraggingKey = key
        longPressDragStartIndex = index
        longPressDragStartColumn = column
        longPressDragTranslation = .zero
    }

    private func updateLongPressDrag(for key: String, translation: CGSize) {
        guard longPressDraggingKey == key else { return }
        longPressDragTranslation = translation

        let startColumn = longPressDragStartColumn ?? includedDataColumns[key, default: 0]
        let currentColumn = includedDataColumns[key, default: 0]
        let columnShift = Int((translation.width / includedDataColumnStepWidth).rounded())
        let targetColumn = max(0, min(startColumn + columnShift, reportColumnCount - 1))

        // Keep in-flight long-press drag attached to the source column to avoid
        // gesture cancellation when SwiftUI re-parents the card mid-drag.
        guard targetColumn == startColumn else { return }

        let currentColumnKeys = keys(in: currentColumn)
        let currentIndex = currentColumnKeys.firstIndex(of: key) ?? 0
        if longPressDragStartIndex == nil {
            longPressDragStartIndex = currentIndex
        }
        guard let startIndex = longPressDragStartIndex else { return }

        let rowShift = Int((translation.height / includedDataCardStepHeight).rounded())
        let targetColumnCountWithoutDragged = keys(in: targetColumn).filter { $0 != key }.count
        let targetIndex = max(0, min(startIndex + rowShift, targetColumnCountWithoutDragged))
        if targetColumn != currentColumn || targetIndex != currentIndex {
            moveIncludedKey(key, to: targetIndex, targetColumn: targetColumn)
        }
    }

    private func endLongPressDrag(for key: String) {
        guard longPressDraggingKey == key else { return }

        let startColumn = longPressDragStartColumn ?? includedDataColumns[key, default: 0]
        let currentColumn = includedDataColumns[key, default: 0]
        let columnShift = Int((longPressDragTranslation.width / includedDataColumnStepWidth).rounded())
        let targetColumn = max(0, min(startColumn + columnShift, reportColumnCount - 1))
        let startIndex = longPressDragStartIndex ?? 0
        let rowShift = Int((longPressDragTranslation.height / includedDataCardStepHeight).rounded())
        let targetColumnCountWithoutDragged = keys(in: targetColumn).filter { $0 != key }.count
        let targetIndex = max(0, min(startIndex + rowShift, targetColumnCountWithoutDragged))

        if targetColumn != currentColumn || targetIndex != (keys(in: currentColumn).firstIndex(of: key) ?? 0) {
            moveIncludedKey(key, to: targetIndex, targetColumn: targetColumn)
        }

        longPressDraggingKey = nil
        longPressDragTranslation = .zero
        longPressDragStartIndex = nil
        longPressDragStartColumn = nil
    }

    private func includedDataLongPressGesture(for key: String) -> some Gesture {
        let longPress = LongPressGesture(minimumDuration: includedDataLongPressDuration)
            .onEnded { _ in
                beginLongPressDrag(for: key)
            }

        let drag = DragGesture(minimumDistance: 0)
            .onChanged { value in
                updateLongPressDrag(for: key, translation: value.translation)
            }
            .onEnded { _ in
                endLongPressDrag(for: key)
            }

        return longPress.simultaneously(with: drag)
    }

    private func handleIncludedDataDrop(providers: [NSItemProvider], to slotIndex: Int, column: Int) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let draggedKey = object as? String else { return }
            DispatchQueue.main.async {
                moveIncludedKey(draggedKey, to: slotIndex, targetColumn: column)
            }
        }
        return true
    }

    private func reportColumnTitle(for column: Int) -> String {
        "Column \(column + 1)"
    }

    private var maxIncludedRowsInAnyColumn: Int {
        max(includedColumnPlaceholderCount, (0..<reportColumnCount).map { keys(in: $0).count }.max() ?? 1)
    }

    private var includedColumnBodyMinHeight: CGFloat {
        let rowHeight: CGFloat = 56
        let rowSpacing: CGFloat = 8
        let rows = CGFloat(maxIncludedRowsInAnyColumn)
        return (rows * rowHeight) + (max(rows - 1, 0) * rowSpacing)
    }

    @ViewBuilder
    private func dataIncludedRow(for key: String) -> some View {
        switch key {
        case "scores":
            Toggle("Scores", isOn: $includeScores)
        case "bestPlayers":
            toggleWithLimitPicker(title: "Best players", isOn: $includeBestPlayers, limit: $bestPlayersLimit, defaultLimitWhenEnabled: 0)
        case "guestVotes":
            if navigationState.currentRole.canViewVoteDetails {
                toggleWithLimitPicker(title: "Guest Votes", isOn: $includeGuestVotes, limit: $guestVotesLimit, defaultLimitWhenEnabled: 0)
            }
        case "goalKickers":
            toggleWithLimitPicker(title: "Goal Kickers", isOn: $includeGoalKickers, limit: $goalKickersLimit, defaultLimitWhenEnabled: 0)
        case "bestAndFairest":
            if navigationState.currentRole.canViewVoteDetails {
                toggleWithLimitPicker(title: "Best and Fairest votes", isOn: $includeBestAndFairestVotes, limit: $bestAndFairestLimit, defaultLimitWhenEnabled: 5)
            }
        case "coachingStaff":
            Toggle("Coaching Staff", isOn: $includeStaffRoles)
        case "officials":
            Toggle("Officials", isOn: $includeOfficials)
        case "trainers":
            Toggle("Trainers", isOn: $includeTrainers)
        case "matchNotes":
            Toggle("Match notes", isOn: $includeMatchNotes)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func includedDataCard(for key: String, showsDragHandle: Bool = true) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if showsDragHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
            includedDataCardRow(for: key)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ClubTheme.subCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ClubTheme.subCardStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func includedDataCardRow(for key: String) -> some View {
        switch key {
        case "bestPlayers":
            includedDataCardToggleWithLimitPicker(
                title: "Best players",
                isOn: $includeBestPlayers,
                limit: $bestPlayersLimit,
                defaultLimitWhenEnabled: 0
            )
        case "guestVotes":
            if navigationState.currentRole.canViewVoteDetails {
                includedDataCardToggleWithLimitPicker(
                    title: "Guest Votes",
                    isOn: $includeGuestVotes,
                    limit: $guestVotesLimit,
                    defaultLimitWhenEnabled: 0
                )
            }
        case "goalKickers":
            includedDataCardToggleWithLimitPicker(
                title: "Goal Kickers",
                isOn: $includeGoalKickers,
                limit: $goalKickersLimit,
                defaultLimitWhenEnabled: 0
            )
        case "bestAndFairest":
            if navigationState.currentRole.canViewVoteDetails {
                includedDataCardToggleWithLimitPicker(
                    title: "Best and Fairest votes",
                    isOn: $includeBestAndFairestVotes,
                    limit: $bestAndFairestLimit,
                    defaultLimitWhenEnabled: 5
                )
            }
        case "coachingStaff":
            includedDataCardToggle(title: "Coaching Staff", isOn: $includeStaffRoles)
        case "officials":
            includedDataCardToggle(title: "Officials", isOn: $includeOfficials)
        case "trainers":
            includedDataCardToggle(title: "Trainers", isOn: $includeTrainers)
        case "matchNotes":
            includedDataCardToggle(title: "Match notes", isOn: $includeMatchNotes)
        default:
            EmptyView()
        }
    }

    private func includedDataCardToggle(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
    }

    private func includedDataCardToggleWithLimitPicker(
        title: String,
        isOn: Binding<Bool>,
        limit: Binding<Int>,
        defaultLimitWhenEnabled: Int
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isOn.wrappedValue {
                Picker(title, selection: limit) {
                    Text("ALL").tag(0)
                    ForEach(1...10, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 74, alignment: .trailing)
            }
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .onChange(of: isOn.wrappedValue) { _, isEnabled in
            guard isEnabled else { return }
            let clampedDefault = Self.clampedReportItemLimit(defaultLimitWhenEnabled, defaultValue: 0)
            if !(0...10).contains(limit.wrappedValue) {
                limit.wrappedValue = clampedDefault
            } else if title == "Best and Fairest votes", limit.wrappedValue == 0 {
                limit.wrappedValue = clampedDefault
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date Range") {
                    Picker("Range", selection: $selectedDateRangeQuickPick) {
                        ForEach(ReportRangeQuickPick.allCases) { quickPick in
                            Text(quickPick.rawValue).tag(quickPick)
                        }
                    }

                    if selectedDateRangeQuickPick == .custom {
                        DatePicker("Start Date", selection: $customDateRangeStart, displayedComponents: .date)
                        DatePicker("End Date", selection: $customDateRangeEnd, displayedComponents: .date)
                    }
                }

                Section {
                    TextField("Report name", text: $name)
                } header: {
                    Text("Template")
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                        ForEach(grades) { grade in
                            let isSelected = selectedGradeIDs.contains(grade.id)
                            Button {
                                if isSelected {
                                    selectedGradeIDs.remove(grade.id)
                                } else {
                                    selectedGradeIDs.insert(grade.id)
                                }
                            } label: {
                                Text(grade.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 10)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? Color(uiColor: .systemGray) : ClubTheme.subCardFill)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("No grade selected means all grades.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()
                    Toggle("Send Report on Game Save", isOn: $sendReportOnGameSave)
                    Toggle("Display Officials in list view", isOn: $displayOfficialsInListView)
                    if shouldShowSendTriggerPicker {
                        Picker("Trigger grade", selection: Binding(
                            get: { sendReportTriggerGradeID ?? selectedTriggerGradeOptions.first?.id },
                            set: { sendReportTriggerGradeID = $0 }
                        )) {
                            ForEach(selectedTriggerGradeOptions) { grade in
                                Text(grade.name).tag(Optional(grade.id))
                            }
                        }
                    }
                    Text("When multiple grades are selected, choose which grade triggers the auto-send.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Grades")
                }

                Section {
                    Picker("Report columns", selection: $reportColumnCount) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: reportColumnCount) { _, newValue in
                        includedDataColumns = CustomReportEditView.normalizeIncludedDataColumns(includedDataColumns, order: includedDataOrder, columnCount: newValue)
                    }

                    dataIncludedRow(for: "scores")

                    Text("Arrange sections below to match the final report layout. Drag items to reorder within a column or move them between columns.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: reportColumnCount)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(0..<reportColumnCount, id: \.self) { column in
                            VStack(spacing: 8) {
                                Text(reportColumnTitle(for: column))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                VStack(spacing: 8) {
                                    let columnKeys = keys(in: column)
                                    ForEach(Array(columnKeys.enumerated()), id: \.element) { slotIndex, key in
                                        includedDataCard(for: key)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                            .offset(
                                                x: longPressDraggingKey == key ? longPressDragTranslation.width : 0,
                                                y: longPressDraggingKey == key ? longPressDragTranslation.height : 0
                                            )
                                            .zIndex(longPressDraggingKey == key ? 1 : 0)
                                            .opacity(longPressDraggingKey == key ? 0.95 : 1)
                                            .highPriorityGesture(AnyGesture(includedDataLongPressGesture(for: key)))
                                            .onDrag {
                                                return NSItemProvider(object: key as NSString)
                                            } preview: {
                                                includedDataCard(for: key, showsDragHandle: false)
                                                    .frame(width: 280)
                                            }
                                            .onDrop(of: [UTType.text.identifier], isTargeted: nil) { providers in
                                                handleIncludedDataDrop(providers: providers, to: slotIndex, column: column)
                                            }
                                    }

                                    ForEach(0..<max(0, includedColumnPlaceholderCount - columnKeys.count), id: \.self) { offset in
                                        let slotIndex = columnKeys.count + offset
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                                            .foregroundStyle(.secondary.opacity(0.3))
                                            .frame(height: 56)
                                            .frame(maxWidth: .infinity)
                                            .onDrop(of: [UTType.text.identifier], isTargeted: nil) { providers in
                                                handleIncludedDataDrop(providers: providers, to: slotIndex, column: column)
                                            }
                                    }

                                }
                                .frame(maxWidth: .infinity, minHeight: includedColumnBodyMinHeight, alignment: .top)
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(ClubTheme.cardFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(ClubTheme.cardStroke, lineWidth: 1)
                            )
                            .frame(maxWidth: .infinity, alignment: .top)
                            .contentShape(Rectangle())
                            .onDrop(of: [UTType.text.identifier], isTargeted: nil) { providers in
                                handleIncludedDataDrop(providers: providers, to: keys(in: column).count, column: column)
                            }
                        }
                    }
                } header: {
                    Text("Data Included")
                } footer: {
                    Text("Drag to reorder report sections and move them between columns. Scores always stays above the column layout.")
                }

                Section {
                    if recipientSections.isEmpty {
                        Text("No groups found. Create groups in Settings > Groups.")
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: 8),
                                count: UIDevice.current.userInterfaceIdiom == .phone ? 2 : 4
                            ),
                            spacing: 8
                        ) {
                            ForEach(recipientSections, id: \.id) { section in
                                let isSelected = section.sectionKeys.contains { selectedRecipientSectionKeys.contains($0) }
                                Button {
                                    if isSelected {
                                        section.sectionKeys.forEach { selectedRecipientSectionKeys.remove($0) }
                                    } else {
                                        section.sectionKeys.forEach { selectedRecipientSectionKeys.insert($0) }
                                    }
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(section.title)
                                            .font(.footnote.weight(.semibold))
                                            .lineLimit(1)
                                        Text("\(contactCount(for: section.sectionKeys))")
                                            .font(.caption2)
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .padding(.horizontal, 6)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? Color(uiColor: .systemGray) : ClubTheme.subCardFill)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    Text("Report Recipients • Groups")
                }

                Section {
                    let groupMemberContacts = contactsFromSelectedGroups()
                    if groupMemberContacts.isEmpty {
                        Text("No recipients in selected groups.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(groupMemberContacts) { contact in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(contact.name)
                                Text("From selected group")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    let individualContacts = selectedIndividualRecipients()
                    if individualContacts.isEmpty {
                        Text("No extra individual recipients selected.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(individualContacts) { contact in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(contact.name)
                                Text("Added individually")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    selectedRecipientContactIDs.remove(contact.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }

                    Menu {
                        let additionalContacts = availableAdditionalRecipients()
                        if additionalContacts.isEmpty {
                            Text("No available contacts")
                        } else {
                            ForEach(additionalContacts) { contact in
                                Button(contact.name) {
                                    selectedRecipientContactIDs.insert(contact.id)
                                }
                            }
                        }
                    } label: {
                        Label("Add Individual", systemImage: "plus")
                    }
                } header: {
                    Text("Report Recipients • Individual Recipients")
                }

                Section {
                    Toggle("Split report by game", isOn: splitByGameBinding)
                    Toggle("Split report by grade", isOn: splitByGradeBinding)
                    Toggle("Only active grades", isOn: $includeOnlyActiveGrades)
                    Toggle("Players Only", isOn: $includePlayersOnly)
                    if includePlayersOnly {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                            ForEach(grades) { grade in
                                let isSelected = playersOnlyGradeFilterIDs.contains(grade.id)
                                Button {
                                    if isSelected {
                                        playersOnlyGradeFilterIDs.remove(grade.id)
                                    } else {
                                        playersOnlyGradeFilterIDs.insert(grade.id)
                                    }
                                } label: {
                                    Text(grade.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 10)
                                        .background(
                                            Capsule()
                                                .fill(isSelected ? Color(uiColor: .systemGray) : ClubTheme.subCardFill)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("Player filter grades (optional). No grade selected means all players club wide.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Stepper("Minimum games played: \(minimumGamesPlayed)", value: $minimumGamesPlayed, in: 0...100)
                } header: {
                    Text("Filters")
                }
            }
            .navigationTitle("Custom Report")
            .onAppear {
                includeUmpires = includeOfficials
                if shouldShowSendTriggerPicker,
                   !selectedTriggerGradeOptions.contains(where: { $0.id == sendReportTriggerGradeID }) {
                    sendReportTriggerGradeID = selectedTriggerGradeOptions.first?.id
                }
            }
            .onChange(of: includeOfficials) { _, newValue in
                includeUmpires = newValue
            }
            .onChange(of: sendReportOnGameSave) { _, isOn in
                if !isOn {
                    sendReportTriggerGradeID = nil
                } else if shouldShowSendTriggerPicker,
                          !selectedTriggerGradeOptions.contains(where: { $0.id == sendReportTriggerGradeID }) {
                    sendReportTriggerGradeID = selectedTriggerGradeOptions.first?.id
                }
            }
            .onChange(of: selectedGradeIDs) { _, _ in
                if shouldShowSendTriggerPicker {
                    if !selectedTriggerGradeOptions.contains(where: { $0.id == sendReportTriggerGradeID }) {
                        sendReportTriggerGradeID = selectedTriggerGradeOptions.first?.id
                    }
                } else {
                    sendReportTriggerGradeID = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let canViewVoteDetails = navigationState.currentRole.canViewVoteDetails
                        let draft = CustomReportTemplateDraft(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            selectedGradeIDs: Array(selectedGradeIDs),
                            sendReportOnGameSave: sendReportOnGameSave,
                            sendReportTriggerGradeID: shouldShowSendTriggerPicker ? sendReportTriggerGradeID : nil,
                            displayOfficialsInListView: displayOfficialsInListView,
                            includeScores: includeScores,
                            includeBestPlayers: includeBestPlayers,
                            bestPlayersLimit: bestPlayersLimit,
                            includeGuestVotes: canViewVoteDetails ? includeGuestVotes : false,
                            guestVotesLimit: guestVotesLimit,
                            includeGoalKickers: includeGoalKickers,
                            goalKickersLimit: goalKickersLimit,
                            includeBestAndFairestVotes: canViewVoteDetails ? includeBestAndFairestVotes : false,
                            bestAndFairestLimit: bestAndFairestLimit,
                            includeStaffRoles: includeStaffRoles,
                            includeOfficials: includeOfficials,
                            includeUmpires: includeOfficials,
                            includeTrainers: includeTrainers,
                            includeMatchNotes: includeMatchNotes,
                            includeOnlyActiveGrades: includeOnlyActiveGrades,
                            includePlayersOnly: includePlayersOnly,
                            playersOnlyGradeFilterIDs: Array(playersOnlyGradeFilterIDs),
                            minimumGamesPlayed: minimumGamesPlayed,
                            groupingModeRawValue: groupingMode.rawValue,
                            selectedQuickPickRawValue: selectedDateRangeQuickPick.rawValue,
                            customDateRangeStart: customDateRangeStart,
                            customDateRangeEnd: customDateRangeEnd,
                            selectedRecipientSectionKeys: Array(selectedRecipientSectionKeys),
                            selectedRecipientContactIDs: Array(selectedRecipientContactIDs),
                            includedDataOrder: includedDataOrder,
                            reportColumnCount: reportColumnCount,
                            includedDataColumns: includedDataColumns
                        )
                        onSave(draft)
                        dismiss()
                    }
                    .saveButtonBehavior(isEnabled: canSave)
                }

                if onDelete != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Report", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .alert("Delete report?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This report template will be permanently deleted.")
        }
    }

    private static func clampedReportItemLimit(_ value: Int, defaultValue: Int) -> Int {
        let safeDefault = max(0, min(defaultValue, 10))
        if (0...10).contains(value) {
            return value
        }
        return safeDefault
    }

    @ViewBuilder
    private func toggleWithLimitPicker(
        title: String,
        isOn: Binding<Bool>,
        limit: Binding<Int>,
        defaultLimitWhenEnabled: Int
    ) -> some View {
        HStack(spacing: 12) {
            Toggle(title, isOn: isOn)
            if isOn.wrappedValue {
                Picker(title, selection: limit) {
                    Text("ALL").tag(0)
                    ForEach(1...10, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 74, alignment: .trailing)
            }
        }
        .onChange(of: isOn.wrappedValue) { _, isEnabled in
            guard isEnabled else { return }
            let clampedDefault = Self.clampedReportItemLimit(defaultLimitWhenEnabled, defaultValue: 0)
            if !(0...10).contains(limit.wrappedValue) {
                limit.wrappedValue = clampedDefault
            } else if title == "Best and Fairest votes", limit.wrappedValue == 0 {
                limit.wrappedValue = clampedDefault
            }
        }
    }

    private struct RecipientSectionOption {
        let id: String
        let sectionKeys: [String]
        let title: String
    }

    private var customSectionTitles: [String: String] {
        guard
            let data = customSectionTitlesData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private var recipientSections: [RecipientSectionOption] {
        var groupedSectionKeysByTitle: [String: Set<String>] = [:]
        for sectionKey in Set(sectionMemberships.map(\.sectionKey)) {
            let title = displayTitle(for: sectionKey)
            groupedSectionKeysByTitle[title, default: []].insert(sectionKey)
        }

        return groupedSectionKeysByTitle
            .map { title, sectionKeys in
                let sortedSectionKeys = sectionKeys.sorted()
                return RecipientSectionOption(
                    id: sortedSectionKeys.joined(separator: "|"),
                    sectionKeys: sortedSectionKeys,
                    title: title
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func contactCount(for sectionKeys: [String]) -> Int {
        let sectionKeySet = Set(sectionKeys)
        let uniqueContactIDs = Set(
            sectionMemberships
                .filter { sectionKeySet.contains($0.sectionKey) }
                .map(\.contactID)
        )
        return uniqueContactIDs.count
    }

    private func displayTitle(for sectionKey: String) -> String {
        if let custom = customSectionTitles[sectionKey], !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        switch ContactSectionKey.fromRawValue(sectionKey) {
        case let .coachesGrade(gradeID):
            return grades.first(where: { $0.id == gradeID })?.name ?? "Coaching Staff"
        default:
            return ContactSectionKey.fromRawValue(sectionKey).title
        }
    }

    private func contactsFromSelectedGroups() -> [Contact] {
        let memberIDs = Set(
            sectionMemberships
                .filter { selectedRecipientSectionKeys.contains($0.sectionKey) }
                .map(\.contactID)
        )
        return contacts
            .filter { memberIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func selectedIndividualRecipients() -> [Contact] {
        contacts
            .filter { selectedRecipientContactIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func availableAdditionalRecipients() -> [Contact] {
        let groupedIDs = Set(contactsFromSelectedGroups().map(\.id))
        return contacts
            .filter { !groupedIDs.contains($0.id) }
            .filter { !selectedRecipientContactIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct ReportRecipientsSettingsView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext

    @Query(sort: [SortDescriptor(\Grade.displayOrder), SortDescriptor(\Grade.name)]) private var grades: [Grade]
    @Query(sort: [SortDescriptor(\Contact.name)]) private var contacts: [Contact]
    @Query(sort: [SortDescriptor(\ContactGroup.name)]) private var groups: [ContactGroup]
    @Query private var memberships: [ContactGroupMembership]
    @Query private var reportRecipients: [ReportRecipient]
    @Query private var reportRecipientGroups: [ReportRecipientGroup]
    @State private var activeGroupByGrade: [UUID: UUID] = [:]
    @State private var saveErrorMessage: String?

    private enum SendMode: String, CaseIterable, Identifiable {
        case text
        case email
        case both

        var id: String { rawValue }

        var title: String {
            switch self {
            case .text: return "Text"
            case .email: return "Email"
            case .both: return "Email + Text"
            }
        }
    }

    private var configuredGrades: [Grade] {
        orderedGradesForDisplay(grades, includeInactive: true)
    }

    private var groupLookup: [UUID: ContactGroup] {
        Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var contactLookup: [UUID: Contact] {
        Dictionary(contacts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var membershipCountByGroup: [UUID: Int] {
        memberships.reduce(into: [:]) { result, membership in
            result[membership.groupID, default: 0] += 1
        }
    }

    private var isSaveErrorPresented: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )
    }

    var body: some View {
        List {
            if configuredGrades.isEmpty {
                Text("Add a grade first.")
                    .foregroundStyle(.secondary)
            }

            ForEach(configuredGrades) { grade in
                gradeSection(for: grade)
            }
        }
        .navigationTitle("Report Recipients")
        .alert("Save Error", isPresented: isSaveErrorPresented) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
    }

    @ViewBuilder
    private func gradeSection(for grade: Grade) -> some View {
        let contactRecipients = recipientsForGrade(grade.id)
        let groupRecipients = groupRecipientsForGrade(grade.id)
        let activeGroupID = resolvedActiveGroupID(for: grade.id, groupRecipients: groupRecipients)
        let individualsInActiveGroup = individualsForGroup(activeGroupID, within: contactRecipients)

        Section {
            VStack(alignment: .leading, spacing: 12) {
                groupRecipientsContent(for: grade, groupRecipients: groupRecipients)

                Divider()

                individualsContent(
                    for: grade,
                    contactRecipients: contactRecipients,
                    groupRecipients: groupRecipients,
                    activeGroupID: activeGroupID,
                    individualsInActiveGroup: individualsInActiveGroup
                )
            }
        } header: {
            Text(grade.name)
        }
    }

    @ViewBuilder
    private func groupRecipientsContent(
        for grade: Grade,
        groupRecipients: [ReportRecipientGroup]
    ) -> some View {
        Text("Recipient Groups")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)

        if groupRecipients.isEmpty {
            Text("No recipient groups added yet.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(groupRecipients) { recipient in
                groupRecipientRow(recipient, gradeID: grade.id)
            }
        }

        Menu {
            let usedGroupIDs = Set(groupRecipients.map(\.groupID))
            let availableGroups = groups.filter { !usedGroupIDs.contains($0.id) }

            if availableGroups.isEmpty {
                Text("No available groups")
            } else {
                ForEach(availableGroups) { group in
                    Menu(group.name) {
                        ForEach(SendMode.allCases) { mode in
                            Button("Send via \(mode.title)") {
                                addGroup(group, toGrade: grade.id, sendMode: mode)
                                activeGroupByGrade[grade.id] = group.id
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Add Recipient Group", systemImage: "plus")
        }
    }

    @ViewBuilder
    private func individualsContent(
        for grade: Grade,
        contactRecipients: [ReportRecipient],
        groupRecipients: [ReportRecipientGroup],
        activeGroupID: UUID?,
        individualsInActiveGroup: [ReportRecipient]
    ) -> some View {
        Text("Individuals")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)

        if groupRecipients.isEmpty {
            Text("Add a recipient group first to view individuals.")
                .foregroundStyle(.secondary)
        } else {
            if let activeGroupID, let activeGroup = groupLookup[activeGroupID] {
                Text("Current group: \(activeGroup.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if individualsInActiveGroup.isEmpty {
                Text("No individuals from the current group have been added yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(individualsInActiveGroup) { recipient in
                    individualRecipientRow(recipient)
                }
            }

            Menu {
                let availableContacts = availableIndividualsToAdd(
                    activeGroupID: activeGroupID,
                    existingRecipients: contactRecipients
                )

                if availableContacts.isEmpty {
                    Text("No available contacts")
                } else {
                    ForEach(availableContacts) { contact in
                        Menu(contact.name) {
                            ForEach(SendMode.allCases) { mode in
                                Button("Send via \(mode.title)") {
                                    addContact(contact, toGrade: grade.id, sendMode: mode)
                                }
                            }
                        }
                    }
                }
            } label: {
                Label("Add Individual", systemImage: "plus")
            }
        }
    }

    private func sendEmailBinding(for recipient: ReportRecipient) -> Binding<Bool> {
        Binding(
            get: { recipient.sendEmail },
            set: { newValue in
                recipient.sendEmail = newValue
                ensureAtLeastOneSendModeEnabled(for: recipient)
                saveContext()
            }
        )
    }

    private func sendEmailBinding(for recipient: ReportRecipientGroup) -> Binding<Bool> {
        Binding(
            get: { recipient.sendEmail },
            set: { newValue in
                recipient.sendEmail = newValue
                ensureAtLeastOneSendModeEnabled(for: recipient)
                saveContext()
            }
        )
    }

    private func sendTextBinding(for recipient: ReportRecipient) -> Binding<Bool> {
        Binding(
            get: { recipient.sendText },
            set: { newValue in
                recipient.sendText = newValue
                ensureAtLeastOneSendModeEnabled(for: recipient)
                saveContext()
            }
        )
    }

    private func sendTextBinding(for recipient: ReportRecipientGroup) -> Binding<Bool> {
        Binding(
            get: { recipient.sendText },
            set: { newValue in
                recipient.sendText = newValue
                ensureAtLeastOneSendModeEnabled(for: recipient)
                saveContext()
            }
        )
    }

    private func ensureAtLeastOneSendModeEnabled(for recipient: ReportRecipient) {
        if !recipient.sendEmail && !recipient.sendText {
            recipient.sendEmail = true
        }
    }

    private func ensureAtLeastOneSendModeEnabled(for recipient: ReportRecipientGroup) {
        if !recipient.sendEmail && !recipient.sendText {
            recipient.sendEmail = true
        }
    }

    @ViewBuilder
    private func recipientRow(
        title: String,
        subtitle: String,
        secondarySubtitle: String,
        sendEmail: Binding<Bool>,
        sendText: Binding<Bool>,
        footer: String,
        onDelete: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            HStack {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Email", isOn: sendEmail)
                    .labelsHidden()
            }

            if !secondarySubtitle.isEmpty {
                HStack {
                    Text(secondarySubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Text", isOn: sendText)
                        .labelsHidden()
                }
            } else {
                HStack {
                    Spacer()
                    Toggle("Text", isOn: sendText)
                        .labelsHidden()
                }
            }

            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func groupRecipientRow(_ recipient: ReportRecipientGroup, gradeID: UUID) -> some View {
        if let group = groupLookup[recipient.groupID] {
            let title = "Group: \(group.name)"
            let count = membershipCountByGroup[recipient.groupID, default: 0]
            let subtitle = "\(count) contact(s)"
            let footer = sendModeText(sendEmail: recipient.sendEmail, sendText: recipient.sendText)

            recipientRow(
                title: title,
                subtitle: subtitle,
                secondarySubtitle: "",
                sendEmail: sendEmailBinding(for: recipient),
                sendText: sendTextBinding(for: recipient),
                footer: footer
            ) {
                dataContext.delete(recipient)
                saveContext()
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    activeGroupByGrade[gradeID] = recipient.groupID
                } label: {
                    Label("Set Active", systemImage: "scope")
                }
                .tint(.blue)
            }
        }
    }

    @ViewBuilder
    private func individualRecipientRow(_ recipient: ReportRecipient) -> some View {
        if let contact = contactLookup[recipient.contactID] {
            let footer = sendModeText(sendEmail: recipient.sendEmail, sendText: recipient.sendText)

            recipientRow(
                title: contact.name,
                subtitle: contact.email,
                secondarySubtitle: contact.mobile.formattedMobileNumber,
                sendEmail: sendEmailBinding(for: recipient),
                sendText: sendTextBinding(for: recipient),
                footer: footer
            ) {
                dataContext.delete(recipient)
                saveContext()
            }
        }
    }

    private func individualsForGroup(_ groupID: UUID?, within recipients: [ReportRecipient]) -> [ReportRecipient] {
        guard let groupID else { return [] }
        let memberIDs = Set(memberships.filter { $0.groupID == groupID }.map(\.contactID))
        return recipients
            .filter { memberIDs.contains($0.contactID) }
            .sorted { a, b in
                let aName = contactLookup[a.contactID]?.name ?? ""
                let bName = contactLookup[b.contactID]?.name ?? ""
                return aName.localizedCaseInsensitiveCompare(bName) == .orderedAscending
            }
    }

    private func availableIndividualsToAdd(
        activeGroupID: UUID?,
        existingRecipients: [ReportRecipient]
    ) -> [Contact] {
        let usedContactIDs = Set(existingRecipients.map(\.contactID))

        let scopedContacts: [Contact]
        if let activeGroupID {
            let memberIDs = Set(memberships.filter { $0.groupID == activeGroupID }.map(\.contactID))
            scopedContacts = contacts.filter { memberIDs.contains($0.id) }
        } else {
            scopedContacts = contacts
        }

        let mergedContactIDs = Set(scopedContacts.map(\.id)).union(contacts.map(\.id))
        return contacts
            .filter { mergedContactIDs.contains($0.id) }
            .filter { !usedContactIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func recipientsForGrade(_ gradeID: UUID) -> [ReportRecipient] {
        reportRecipients
            .filter { $0.gradeID == gradeID }
            .sorted { a, b in
                let aName = contactLookup[a.contactID]?.name ?? ""
                let bName = contactLookup[b.contactID]?.name ?? ""
                return aName.localizedCaseInsensitiveCompare(bName) == .orderedAscending
            }
    }

    private func groupRecipientsForGrade(_ gradeID: UUID) -> [ReportRecipientGroup] {
        reportRecipientGroups
            .filter { $0.gradeID == gradeID }
            .sorted { a, b in
                let aName = groupLookup[a.groupID]?.name ?? ""
                let bName = groupLookup[b.groupID]?.name ?? ""
                return aName.localizedCaseInsensitiveCompare(bName) == .orderedAscending
            }
    }

    private func resolvedActiveGroupID(for gradeID: UUID, groupRecipients: [ReportRecipientGroup]) -> UUID? {
        let groupIDs = Set(groupRecipients.map(\.groupID))
        if let saved = activeGroupByGrade[gradeID], groupIDs.contains(saved) {
            return saved
        }
        return groupRecipients.first?.groupID
    }

    private func addContact(_ contact: Contact, toGrade gradeID: UUID, sendMode: SendMode) {
        guard !reportRecipients.contains(where: { $0.gradeID == gradeID && $0.contactID == contact.id }) else { return }

        dataContext.insert(
            ReportRecipient(
                gradeID: gradeID,
                contactID: contact.id,
                sendEmail: sendMode == .email || sendMode == .both,
                sendText: sendMode == .text || sendMode == .both
            )
        )
        saveContext()
    }

    private func addGroup(_ group: ContactGroup, toGrade gradeID: UUID, sendMode: SendMode) {
        guard !reportRecipientGroups.contains(where: { $0.gradeID == gradeID && $0.groupID == group.id }) else { return }

        dataContext.insert(
            ReportRecipientGroup(
                gradeID: gradeID,
                groupID: group.id,
                sendEmail: sendMode == .email || sendMode == .both,
                sendText: sendMode == .text || sendMode == .both
            )
        )
        saveContext()
    }

    private func sendModeText(sendEmail: Bool, sendText: Bool) -> String {
        switch (sendEmail, sendText) {
        case (true, true): return "Send via Email + Text"
        case (true, false): return "Send via Email"
        case (false, true): return "Send via Text"
        case (false, false): return "Send via Email"
        }
    }

    private func saveContext() {
        do {
            try dataContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}
