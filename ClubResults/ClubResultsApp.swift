import SwiftUI
import SwiftData
import UIKit

final class ClubResultsAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        CloudKitStatsInviteService.shared.handleRemoteNotification(userInfo: userInfo)
        completionHandler(.newData)
    }
}

@main
struct ClubResultsApp: App {
    @UIApplicationDelegateAdaptor(ClubResultsAppDelegate.self) private var appDelegate
    private static let modelStoreDirectoryName = "ClubResultsSwiftData"
    private static let modelStoreFileName = "ClubResults.store"
    private static let cloudKitContainerIdentifier = "iCloud.MINMAN.ClubResults"
    private static let emergencyStoreDirectoryName = "ClubResultsSwiftData-Emergency"
    private static let automaticCloudSyncInterval: UInt64 = 120_000_000_000

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var navigationState = AppNavigationState()
    @StateObject private var authCoordinator = AuthenticationCoordinator()
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue
    @State private var hasRunAutomaticCloudSync = false
    @State private var periodicCloudSyncTask: Task<Void, Never>?
    @State private var isAutomaticCloudSyncRunning = false
    private let modelContainer: ModelContainer = {
        let schema = Schema([
            Player.self,
            Game.self,
            Grade.self,
            Contact.self,
            ReportRecipient.self,
            CustomReportTemplate.self,
            ContactSectionMembership.self,
            CustomReportRecipientSection.self,
            CustomReportRecipientGroup.self,
            CustomReportRecipientContact.self,
            ContactGroup.self,
            ContactGroupMembership.self,
            ReportRecipientGroup.self,
            StaffMember.self,
            StaffDefault.self,
            StatType.self,
            StatsSession.self,
            StatEvent.self,
            StatsInviteAssignment.self,
            CloudSyncedPreference.self
        ])
        return makeModelContainer(schema: schema)
    }()

    private static func makeModelContainer(schema: Schema) -> ModelContainer {
        let storeURL = modelStoreURL()
        let recoveryStoreURL = recoveryStoreURL()
        let emergencyStoreURL = emergencyStoreURL()

        do {
            return try makeCloudContainer(schema: schema, storeURL: storeURL)
        } catch let cloudError {
            if let container = try? retryCloudContainer(schema: schema, storeURL: storeURL) {
                return container
            }

            debugPrint("CloudKit container unavailable. Falling back to local storage. Error: \(cloudError)")

            if let container = try? makeLocalContainer(schema: schema, storeURL: storeURL) {
                return container
            }

            debugPrint("Local disk container unavailable at primary store. Retrying with a clean recovery store.")

            if let container = try? retryRecoveryLocalContainer(schema: schema, recoveryStoreURL: recoveryStoreURL) {
                return container
            }

            debugPrint("Recovery disk container unavailable. Falling back to a clean emergency local store.")

            if let container = try? retryEmergencyLocalContainer(schema: schema, emergencyStoreURL: emergencyStoreURL) {
                return container
            }

            fatalError("Failed to create any SwiftData container.")
        }
    }

    private static func retryCloudContainer(schema: Schema, storeURL: URL) throws -> ModelContainer {
        try resetStoreDirectory(for: storeURL)
        return try makeCloudContainer(schema: schema, storeURL: storeURL)
    }

    private static func retryRecoveryLocalContainer(schema: Schema, recoveryStoreURL: URL) throws -> ModelContainer {
        try resetStoreDirectory(for: recoveryStoreURL)
        return try makeLocalContainer(schema: schema, storeURL: recoveryStoreURL)
    }

    private static func retryEmergencyLocalContainer(schema: Schema, emergencyStoreURL: URL) throws -> ModelContainer {
        try resetStoreDirectory(for: emergencyStoreURL)
        return try makeLocalContainer(schema: schema, storeURL: emergencyStoreURL)
    }

    private static func makeCloudContainer(schema: Schema, storeURL: URL) throws -> ModelContainer {
        let cloudConfiguration = ModelConfiguration(
            url: storeURL,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
        return try ModelContainer(for: schema, configurations: cloudConfiguration)
    }

    private static func makeLocalContainer(schema: Schema, storeURL: URL) throws -> ModelContainer {
        let localConfiguration = ModelConfiguration(
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: localConfiguration)
    }

    private static func modelStoreURL() -> URL {
        let applicationSupportURL = URL.applicationSupportDirectory
            .appending(path: modelStoreDirectoryName, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true
            )
        } catch {
            fatalError("Failed to prepare app support directory: \(error)")
        }
        return applicationSupportURL.appending(path: modelStoreFileName)
    }

    private static func recoveryStoreURL() -> URL {
        let applicationSupportURL = URL.applicationSupportDirectory
            .appending(path: "\(modelStoreDirectoryName)-Recovery", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true
            )
        } catch {
            fatalError("Failed to prepare recovery app support directory: \(error)")
        }
        return applicationSupportURL.appending(path: modelStoreFileName)
    }

    private static func emergencyStoreURL() -> URL {
        let cachesURL = URL.cachesDirectory
            .appending(path: emergencyStoreDirectoryName, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(
                at: cachesURL,
                withIntermediateDirectories: true
            )
        } catch {
            fatalError("Failed to prepare emergency cache directory: \(error)")
        }
        return cachesURL.appending(path: modelStoreFileName)
    }

    private static func resetStoreDirectory(for storeURL: URL) throws {
        let fileManager = FileManager.default
        let storeDirectoryURL = storeURL.deletingLastPathComponent()

        if fileManager.fileExists(atPath: storeDirectoryURL.path()) {
            let contents = try fileManager.contentsOfDirectory(
                at: storeDirectoryURL,
                includingPropertiesForKeys: nil
            )
            for url in contents {
                try fileManager.removeItem(at: url)
            }
        }

        try fileManager.createDirectory(
            at: storeDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private var preferredScheme: ColorScheme? {
        switch AppAppearance(rawValue: appAppearance) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // ✅ FORCE premium background at the absolute root
                ClubTheme.bgGradient
                    .ignoresSafeArea()

                // subtle glow layers (same as AppScreenStyle)
                RadialGradient(
                    gradient: Gradient(colors: [Color.white.opacity(0.12), Color.clear]),
                    center: .topTrailing,
                    startRadius: 40,
                    endRadius: 380
                )
                .ignoresSafeArea()

                RadialGradient(
                    gradient: Gradient(colors: [Color.white.opacity(0.08), Color.clear]),
                    center: .bottomLeading,
                    startRadius: 40,
                    endRadius: 420
                )
                .ignoresSafeArea()

                // Your app content
                AuthenticationGateView {
                    ContentView()
                }
            }
            .environmentObject(authCoordinator)
            .environmentObject(navigationState)
            .preferredColorScheme(preferredScheme)
            .tint(.appleBlue)
            .onOpenURL { url in
                guard let deepLink = StatsInviteLinking.parse(url) else { return }
                _navigationState.wrappedValue.openStatsInvite(sessionID: deepLink.sessionID)
            }
            .onAppear {
                applicationDidAppear()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
        }
        .modelContainer(modelContainer)
    }

    private func applicationDidAppear() {
        UIApplication.shared.registerForRemoteNotifications()
        CloudSyncedPreferencesStore.configure(modelContext: modelContainer.mainContext)

        if !hasRunAutomaticCloudSync {
            hasRunAutomaticCloudSync = true
            Task { @MainActor in
                await runAutomaticCloudSyncOnOpen()
            }
        }
        startPeriodicCloudSyncIfNeeded()

        Task {
            try? await CloudKitStatsInviteService.shared.ensureTallySubscription()
        }
    }

    @MainActor
    private func runAutomaticCloudSyncOnOpen() async {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await performAutomaticCloudSyncCycle()
    }

    @MainActor
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            startPeriodicCloudSyncIfNeeded()
        case .inactive, .background:
            stopPeriodicCloudSync()
            Task { @MainActor in
                await performAutomaticCloudSyncCycle()
            }
        @unknown default:
            break
        }
    }

    @MainActor
    private func startPeriodicCloudSyncIfNeeded() {
        guard periodicCloudSyncTask == nil else { return }
        periodicCloudSyncTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.automaticCloudSyncInterval)
                guard !Task.isCancelled else { break }
                await performAutomaticCloudSyncCycle()
            }
        }
    }

    @MainActor
    private func stopPeriodicCloudSync() {
        periodicCloudSyncTask?.cancel()
        periodicCloudSyncTask = nil
    }

    @MainActor
    private func performAutomaticCloudSyncCycle() async {
        guard !isAutomaticCloudSyncRunning else { return }
        isAutomaticCloudSyncRunning = true
        defer { isAutomaticCloudSyncRunning = false }

        let context = modelContainer.mainContext
        try? context.save()
        try? await CloudKitStatsInviteService.shared.ensureTallySubscription()

        _ = try? await CloudFullBackupSyncService.syncFullBackupSnapshot(modelContext: context)

        let hasLocalUserData = CloudFullBackupSyncService.localUserDataCount(modelContext: context) > 0

        // Safety guard: do not push an empty install over the cloud backup snapshot.
        if hasLocalUserData {
            CloudSyncedPreferencesStore.pushAllLocalPreferencesToCloud()
            try? context.save()
        }
    }
}
