import SwiftUI
import SwiftData

struct TabsView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext
    @State private var selectedTab: AppTab = .games
    @State private var settingsResetToken = UUID()

    var body: some View {
        TabView(selection: selectionBinding) {
            GamesView()
                .tag(AppTab.games)
                .tabItem { Label("Games", systemImage: "list.bullet") }

            TotalsView()
                .tag(AppTab.totals)
                .tabItem { Label("Totals", systemImage: "chart.bar") }

            PresView()
                .tag(AppTab.pres)
                .tabItem { Label("Pres", systemImage: "rectangle.stack") }

            ReportsSettingsView {
                UserDefaults.standard.set(true, forKey: "settings.open.contacts")
                settingsResetToken = UUID()
                selectedTab = .settings
            }
                .tag(AppTab.reports)
                .tabItem { Label("Reports", systemImage: "doc.text") }

            SettingsView(resetToken: settingsResetToken)
                .tag(AppTab.settings)
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

    private var selectionBinding: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == .settings {
                    settingsResetToken = UUID()
                }
                selectedTab = newValue
            }
        )
    }
}

private enum AppTab: Hashable {
    case games
    case totals
    case pres
    case reports
    case settings
}
