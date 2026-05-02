import SwiftUI
import SwiftData

@main
struct ClubResultsApp: App {
    private static let modelStoreDirectoryName = "ClubResultsSwiftData"
    private static let modelStoreFileName = "ClubResults.store"
    private static let cloudKitContainerIdentifier = "iCloud.MINMAN.ClubResults"

    @State private var showSplash = true
    @StateObject private var navigationState = AppNavigationState()
    @StateObject private var authCoordinator = AuthenticationCoordinator()
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue
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
            StatsInviteAssignment.self
        ])
        return makeModelContainer(schema: schema)
    }()

    private static func makeModelContainer(schema: Schema) -> ModelContainer {
        let storeURL = modelStoreURL()
        let cloudConfiguration = ModelConfiguration(
            url: storeURL,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
        let localConfiguration = ModelConfiguration(
            url: storeURL,
            cloudKitDatabase: .none
        )
        let inMemoryConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)

        do {
            return try ModelContainer(for: schema, configurations: cloudConfiguration)
        } catch let cloudError {
            do {
                try resetStoreDirectory(for: storeURL)
                return try ModelContainer(for: schema, configurations: cloudConfiguration)
            } catch let cloudRetryError {
                do {
                    debugPrint("CloudKit container unavailable. Falling back to local storage. First error: \(cloudError). Retry error: \(cloudRetryError)")
                    return try ModelContainer(for: schema, configurations: localConfiguration)
                } catch let localError {
                    do {
                        debugPrint("Local disk container unavailable. Falling back to in-memory store. Error: \(localError)")
                        return try ModelContainer(for: schema, configurations: inMemoryConfiguration)
                    } catch {
                        fatalError("Failed to create any SwiftData container: \(error)")
                    }
                }
            }
        }
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
                ZStack {
                    AuthenticationGateView {
                        ContentView()
                    }
                        .opacity(showSplash ? 0 : 1)

                    if showSplash {
                        SplashView()
                            .transition(.opacity)
                    }
                }
            }
            .environmentObject(authCoordinator)
            .environmentObject(navigationState)
            .preferredColorScheme(preferredScheme)
            .tint(.appleBlue)
            .onOpenURL { url in
                guard let invite = StatsInviteLinking.parse(url) else { return }
                navigationState.openStatsInvite(sessionID: invite.sessionID)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
            }
        }
        .modelContainer(modelContainer)
    }
}
