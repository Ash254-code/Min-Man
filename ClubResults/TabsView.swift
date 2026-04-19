import SwiftUI
import SwiftData

struct TabsView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext

    var body: some View {
        TabView {
            GamesView()
                .tabItem { Label("Games", systemImage: "list.bullet") }

            TotalsView()
                .tabItem { Label("Totals", systemImage: "chart.bar") }

            PresView()
                .tabItem { Label("Pres", systemImage: "rectangle.stack") }

            ReportsSettingsView()
                .tabItem { Label("Reports", systemImage: "doc.text") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task {
            seedInitialGradesIfNeeded()
        }
    }

    private func seedInitialGradesIfNeeded() {
        let existing = (try? dataContext.fetch(FetchDescriptor<Grade>())) ?? []
        guard existing.isEmpty else { return }

        let defaults = ["A Grade", "B Grade", "Under 17's", "Under 14's", "Under 12's", "Under 9's"]
        for (index, name) in defaults.enumerated() {
            dataContext.insert(Grade(name: name, isActive: true, displayOrder: index))
        }

        try? dataContext.save()
    }
}
