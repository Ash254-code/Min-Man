import Foundation
import SwiftData

/// Provides a CloudKit-enabled ModelContainer for the app's SwiftData models.
public struct CloudModelContainerProvider {
    
    /// Creates and returns a shared ModelContainer configured for CloudKit syncing.
    ///
    /// The container is configured with all app model types and uses the CloudKit container identifier specified
    /// in `CloudSyncConfig.containerIdentifier`.
    ///
    /// Make sure to enable the iCloud capability with CloudKit for your app target,
    /// and update the container identifier string in `CloudSyncConfig.containerIdentifier` to match your CloudKit container.
    ///
    /// - Throws: Errors thrown by ModelContainer initialization.
    /// - Returns: A ModelContainer configured for CloudKit syncing.
    public static func makeSharedContainer() throws -> ModelContainer {
        // Build the schema including all SwiftData model classes in the app.
        let schema = Schema([
            Grade.self,
            StatType.self,
            Player.self,
            Game.self,
            ReportRecipient.self,
            ReportRecipientGroup.self,
            Contact.self,
            ContactGroup.self,
            ContactGroupMembership.self,
            ContactSectionMembership.self,
            StaffMember.self,
            CustomReportTemplate.self,
            CustomReportRecipientSection.self,
            CustomReportRecipientGroup.self,
            CustomReportRecipientContact.self,
            NESStatsSession.self,
            NESStatEvent.self,
            OppositionClub.self,
            StaffDefaults.self,
            // StaffRole is likely an enum, so omitted
        ])
        
        // Create ModelConfiguration with CloudKit support.
        // Use the newer API if available, otherwise fallback.
        let cloudKitConfig: ModelConfiguration
        
        // Attempt to use ModelConfiguration.CloudKitDatabaseIdentifier if available.
        // Since we can't check API availability dynamically, we provide both options with fallback.
        if #available(iOS 17.0, macOS 14.0, *) {
            cloudKitConfig = ModelConfiguration(
                cloudKitDatabase: .private(CloudSyncConfig.containerIdentifier)
            )
        } else {
            cloudKitConfig = ModelConfiguration(
                cloudKitContainer: CloudSyncConfig.containerIdentifier
            )
        }
        
        // Attempt to initialize the ModelContainer with cloudKitConfig.
        // If it fails and we are in DEBUG, fallback to in-memory container.
        do {
            return try ModelContainer(for: schema, configurations: [cloudKitConfig])
        } catch {
            #if DEBUG
            // Fallback to an in-memory ModelContainer for previews/tests.
            return ModelContainer(for: schema, configurations: [
                ModelConfiguration(inMemory: true)
            ])
            #else
            throw error
            #endif
        }
    }
}

/// Holds configuration constants for CloudKit syncing.
public enum CloudSyncConfig {
    /// The CloudKit container identifier.
    /// Change this string to match your CloudKit container in the Apple Developer portal.
    public static var containerIdentifier: String = "iCloud.com.example.yourcontainer"
}

public extension EnvironmentValues {
    /// Convenience accessor for the shared CloudKit-enabled model container.
    ///
    /// Usage:
    /// ```swift
    /// @Environment(\.cloudModelContainer) private var container
    /// ```
    var cloudModelContainer: ModelContainer? {
        try? CloudModelContainerProvider.makeSharedContainer()
    }
}
