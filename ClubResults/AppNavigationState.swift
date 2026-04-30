import Foundation

enum AppTab: Hashable {
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

@MainActor
final class AppNavigationState: ObservableObject {
    @Published var selectedTab: AppTab = .games
    @Published var activeStatsSessionID: UUID?
    @Published var startNewStatsSessionToken = UUID()

    func activateStatsSession(id: UUID) {
        activeStatsSessionID = id
    }

    func openStatsNewSession() {
        selectedTab = .stats
        startNewStatsSessionToken = UUID()
    }
}
