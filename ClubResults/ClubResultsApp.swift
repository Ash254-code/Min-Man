import SwiftUI
import SwiftData

@main
struct ClubResultsApp: App {

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
        let configuration = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)

        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            do {
                try removeStoreFiles(at: storeURL)
                return try ModelContainer(for: schema, configurations: configuration)
            } catch {
                fatalError("Failed to create local SwiftData container: \(error)")
            }
        }
    }

    private static func modelStoreURL() -> URL {
        let applicationSupportURL = URL.applicationSupportDirectory
        do {
            try FileManager.default.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true
            )
        } catch {
            fatalError("Failed to prepare app support directory: \(error)")
        }
        return applicationSupportURL.appending(path: "ClubResults.store")
    }

    private static func removeStoreFiles(at storeURL: URL) throws {
        let fileManager = FileManager.default
        let auxiliaryExtensions = ["-shm", "-wal"]

        if fileManager.fileExists(atPath: storeURL.path()) {
            try fileManager.removeItem(at: storeURL)
        }

        for suffix in auxiliaryExtensions {
            let auxiliaryURL = URL(fileURLWithPath: storeURL.path() + suffix)
            if fileManager.fileExists(atPath: auxiliaryURL.path()) {
                try fileManager.removeItem(at: auxiliaryURL)
            }
        }
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
