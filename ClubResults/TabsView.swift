import SwiftUI
import SwiftData

struct TabsView: View {
    @Environment(\.modelContext) private var dataContext: ModelContext
    @State private var selectedTab: AppTab = .games
    @State private var settingsResetToken = UUID()

    var body: some View {
        GeometryReader { proxy in
            let isPortrait = proxy.size.height > proxy.size.width

            TabView(selection: selectionBinding) {
                GamesView()
                    .tag(AppTab.games)
                    .tabItem { Label(tabTitle(for: .games, isPortrait: isPortrait), systemImage: "list.bullet") }

                TotalsView()
                    .tag(AppTab.totals)
                    .tabItem { Label(tabTitle(for: .totals, isPortrait: isPortrait), systemImage: "chart.bar") }

                StatsRootView()
                    .tag(AppTab.stats)
                    .tabItem { Label(tabTitle(for: .stats, isPortrait: isPortrait), systemImage: "waveform.circle") }

                PresView()
                    .tag(AppTab.pres)
                    .tabItem { Label(tabTitle(for: .pres, isPortrait: isPortrait), systemImage: "rectangle.stack") }

                ReportsSettingsView {
                    UserDefaults.standard.set(true, forKey: "settings.open.contacts")
                    settingsResetToken = UUID()
                    selectedTab = .settings
                }
                .tag(AppTab.reports)
                .tabItem { Label(tabTitle(for: .reports, isPortrait: isPortrait), systemImage: "doc.text") }

                SettingsView(resetToken: settingsResetToken)
                    .tag(AppTab.settings)
                    .tabItem { Label(tabTitle(for: .settings, isPortrait: isPortrait), systemImage: "gearshape") }
            }
            .task {
                seedInitialGradesIfNeeded()
            }
        }
    }

    private func tabTitle(for tab: AppTab, isPortrait: Bool) -> String {
        guard isPortrait else {
            switch tab {
            case .games: return "Games"
            case .totals: return "Totals"
            case .stats: return "Stats"
            case .pres: return "Pres"
            case .reports: return "Reports"
            case .settings: return "Settings"
            }
        }

        switch tab {
        case .games: return "Games"
        case .totals: return "Tot"
        case .stats: return "Stats"
        case .pres: return "Pres"
        case .reports: return "Reps"
        case .settings: return "Set"
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
    case stats
    case pres
    case reports
    case settings
}
