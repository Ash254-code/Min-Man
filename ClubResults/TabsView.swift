import SwiftUI
import SwiftData

struct TabsView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            GamesView()
                .tabItem { Label("Games", systemImage: "list.bullet") }

            PlayersView()
                .tabItem { Label("Players", systemImage: "person.3") }

            TotalsView()
                .tabItem { Label("Totals", systemImage: "chart.bar") }

            // ✅ NEW: Pres tab
            PresView()
                .tabItem { Label("Pres", systemImage: "rectangle.stack") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task {
            // Safe to call every launch
            LockedGradeSeed.ensureGradesExist(modelContext: modelContext)
        }
    }
}
