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
            seedInitialGradesIfNeeded()
        }
    }

    private func seedInitialGradesIfNeeded() {
        let existing = (try? modelContext.fetch(FetchDescriptor<Grade>())) ?? []
        guard existing.isEmpty else { return }

        ["A Grade", "B Grade", "Under 17's", "Under 14's", "Under 12's", "Under 9's"]
            .forEach { modelContext.insert(Grade(name: $0, isActive: true)) }

        try? modelContext.save()
    }
}
