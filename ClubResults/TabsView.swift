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
                    .tabItem { tabItemLabel(for: .games, isPortrait: isPortrait) }

                TotalsView()
                    .tag(AppTab.totals)
                    .tabItem { tabItemLabel(for: .totals, isPortrait: isPortrait) }

                StatsRootView()
                    .tag(AppTab.stats)
                    .tabItem { tabItemLabel(for: .stats, isPortrait: isPortrait) }

                PresView()
                    .tag(AppTab.pres)
                    .tabItem { tabItemLabel(for: .pres, isPortrait: isPortrait) }

                ReportsSettingsView {
                    UserDefaults.standard.set(true, forKey: "settings.open.contacts")
                    settingsResetToken = UUID()
                    selectedTab = .settings
                }
                .tag(AppTab.reports)
                .tabItem { tabItemLabel(for: .reports, isPortrait: isPortrait) }

                SettingsView(resetToken: settingsResetToken)
                    .tag(AppTab.settings)
                    .tabItem { tabItemLabel(for: .settings, isPortrait: isPortrait) }
            }
            .task {
                seedInitialGradesIfNeeded()
            }
        }
    }

    @ViewBuilder
    private func tabItemLabel(for tab: AppTab, isPortrait: Bool) -> some View {
        if isPortrait {
            Image(systemName: tab.systemImage)
                .accessibilityLabel(tab.title)
        } else {
            Label(tab.title, systemImage: tab.systemImage)
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

    var title: String {
        switch self {
        case .games: return "Games"
        case .totals: return "Totals"
        case .stats: return "Stats"
        case .pres: return "Pres"
        case .reports: return "Reports"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .games: return "list.bullet"
        case .totals: return "chart.bar"
        case .stats: return "waveform.circle"
        case .pres: return "rectangle.stack"
        case .reports: return "doc.text"
        case .settings: return "gearshape"
        }
    }
}
