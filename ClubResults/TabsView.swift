import SwiftUI
import SwiftData
import UIKit

struct TabsView: View {
    @Environment(\.modelContext) private var dataContext: ModelContext
    @EnvironmentObject private var navigationState: AppNavigationState
    @State private var settingsResetToken = UUID()

    private var hidesPresentationTabForIPhoneAdmin: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && navigationState.currentRole == .admin
    }

    var body: some View {
        GeometryReader { proxy in
            let isPortrait = proxy.size.height > proxy.size.width

            TabView(selection: selectionBinding) {
                if navigationState.canAccess(tab: .games) {
                    GamesView()
                        .tag(AppTab.games)
                        .tabItem { tabItemLabel(for: .games, isPortrait: isPortrait) }
                }

                if navigationState.canAccess(tab: .game) {
                    GameTabRootView()
                        .tag(AppTab.game)
                        .tabItem { tabItemLabel(for: .game, isPortrait: isPortrait) }
                }

                if navigationState.canAccess(tab: .stats) {
                    statsTabView
                        .tag(AppTab.stats)
                        .tabItem { tabItemLabel(for: .stats, isPortrait: isPortrait) }
                }

                if navigationState.canAccess(tab: .totals) {
                    TotalsView()
                        .tag(AppTab.totals)
                        .tabItem { tabItemLabel(for: .totals, isPortrait: isPortrait) }
                }

                if navigationState.canAccess(tab: .pres) && !hidesPresentationTabForIPhoneAdmin {
                    PresView()
                        .tag(AppTab.pres)
                        .tabItem { tabItemLabel(for: .pres, isPortrait: isPortrait) }
                }

                if navigationState.canAccess(tab: .settings) {
                    SettingsView(resetToken: settingsResetToken)
                        .tag(AppTab.settings)
                        .tabItem { tabItemLabel(for: .settings, isPortrait: isPortrait) }
                }
            }
            .task {
                seedInitialGradesIfNeeded()
            }
            .onChange(of: navigationState.currentRole) { _, _ in
                if !navigationState.canAccess(tab: navigationState.selectedTab) {
                    navigationState.selectedTab = navigationState.currentRole.visibleTabs.first ?? .games
                }
            }
        }
    }

    @ViewBuilder
    private func tabItemLabel(for tab: AppTab, isPortrait: Bool) -> some View {
        let title = tabTitle(for: tab)
        let systemImage = tabSystemImage(for: tab)

        if isPortrait {
            Image(systemName: systemImage)
                .accessibilityLabel(title)
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    @ViewBuilder
    private var statsTabView: some View {
        if navigationState.currentRole == .statTaker {
            StatTakerStatsView()
        } else {
            StatsRootView()
        }
    }

    private func tabTitle(for tab: AppTab) -> String {
        if tab == .stats, navigationState.currentRole == .statTaker {
            return "Stats View"
        }

        return tab.title
    }

    private func tabSystemImage(for tab: AppTab) -> String {
        if tab == .stats, navigationState.currentRole == .statTaker {
            return "rectangle.grid.2x2.fill"
        }

        return tab.systemImage
    }

    private func seedInitialGradesIfNeeded() {
        LockedGradeSeed.ensureGradesExist(modelContext: dataContext)
    }

    private var selectionBinding: Binding<AppTab> {
        Binding(
            get: {
                if navigationState.canAccess(tab: navigationState.selectedTab) {
                    return navigationState.selectedTab
                }

                return navigationState.currentRole.visibleTabs.first ?? .games
            },
            set: { newValue in
                if newValue == .settings {
                    settingsResetToken = UUID()
                }
                navigationState.selectedTab = newValue
            }
        )
    }
}

private struct GameTabRootView: View {
    @EnvironmentObject private var navigationState: AppNavigationState

    var body: some View {
        liveGameContent
    }

    @ViewBuilder
    private var liveGameContent: some View {
        if let draftGameID = navigationState.activeLiveGameDraftID {
            NewGameWizardView(
                initialGradeID: navigationState.activeLiveGameGradeID,
                draftGameID: draftGameID,
                reopenLiveViewOnAppear: true,
                onBackToHomeFromLive: { _ in
                    navigationState.closeLiveGameTab(selectHome: true)
                },
                handoffLiveGameToDedicatedTab: false,
                isEmbeddedInGameTab: true,
                onEmbeddedFlowFinished: {
                    navigationState.closeLiveGameTab(selectHome: false)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "No Active Live Game",
                systemImage: "figure.australian.football",
                description: Text("Start a new live game from Home and it will open here.")
            )
            .frame(maxWidth: .infinity, minHeight: 260)
        }
    }
}
