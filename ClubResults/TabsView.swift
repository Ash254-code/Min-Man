import SwiftUI
import SwiftData
import UIKit

struct TabsView: View {
    @Environment(\.modelContext) private var dataContext: ModelContext
    @EnvironmentObject private var navigationState: AppNavigationState
    @State private var settingsResetToken = UUID()

    init() {
        Self.configureTabBarAppearance()
        Self.configureNavigationBarAppearance()
    }

    private var hidesPresentationTabForIPhoneAdmin: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && navigationState.currentRole == .admin
    }

    var body: some View {
        GeometryReader { proxy in
            let isPortrait = proxy.size.height > proxy.size.width

            TabView(selection: selectionBinding) {
                if navigationState.canAccess(tab: .games) {
                    gradientPage {
                        GamesView()
                    }
                    .floatingTabBarBackground()
                    .tag(AppTab.games)
                    .tabItem { tabItemLabel(for: .games, isPortrait: isPortrait) }
                }

                if navigationState.canAccess(tab: .game) {
                    gradientPage {
                        GameTabRootView()
                    }
                    .floatingTabBarBackground()
                    .tag(AppTab.game)
                    .tabItem { tabItemLabel(for: .game, isPortrait: isPortrait) }
                }

                if navigationState.canAccess(tab: .stats) {
                    gradientPage {
                        statsTabView
                    }
                    .floatingTabBarBackground()
                    .tag(AppTab.stats)
                    .tabItem { tabItemLabel(for: .stats, isPortrait: isPortrait) }
                }

                if navigationState.canAccess(tab: .totals) {
                    gradientPage {
                        TotalsView()
                    }
                    .floatingTabBarBackground()
                    .tag(AppTab.totals)
                    .tabItem { tabItemLabel(for: .totals, isPortrait: isPortrait) }
                }

                if navigationState.canAccess(tab: .pres) && !hidesPresentationTabForIPhoneAdmin {
                    gradientPage {
                        PresView()
                    }
                    .floatingTabBarBackground()
                    .tag(AppTab.pres)
                    .tabItem { tabItemLabel(for: .pres, isPortrait: isPortrait) }
                }

                if navigationState.canAccess(tab: .settings) {
                    gradientPage {
                        SettingsView(resetToken: settingsResetToken)
                    }
                    .floatingTabBarBackground()
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
            .background {
                ClubTheme.bgGradient
                    .ignoresSafeArea()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if UIDevice.current.userInterfaceIdiom == .phone {
                    iPhoneTabBar(isPortrait: isPortrait)
                        .padding(.horizontal, 22)
                        .padding(.top, 2)
                        .padding(.bottom, iPhoneTabBarBottomPadding(for: proxy.safeAreaInsets))
                        .offset(y: iPhoneTabBarLoweringOffset(for: proxy.safeAreaInsets))
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

    private var visibleIPhoneTabs: [AppTab] {
        navigationState.currentRole.visibleTabs.filter { tab in
            navigationState.canAccess(tab: tab) && !(tab == .pres && hidesPresentationTabForIPhoneAdmin)
        }
    }

    private func selectTab(_ tab: AppTab) {
        if tab == .settings {
            settingsResetToken = UUID()
        }
        navigationState.selectedTab = tab
    }

    private func gradientPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            ClubTheme.bgGradient
                .ignoresSafeArea()
            content()
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .iPhoneTransparentChrome()
        }
    }

    private func tabTitle(for tab: AppTab) -> String {
        if tab == .stats, navigationState.currentRole == .statTaker {
            return "Stats View"
        }

        return tab.title
    }


    private func iPhoneTabBarBottomPadding(for safeAreaInsets: EdgeInsets) -> CGFloat {
        safeAreaInsets.bottom > 0 ? 2 : 6
    }

    private func iPhoneTabBarLoweringOffset(for safeAreaInsets: EdgeInsets) -> CGFloat {
        safeAreaInsets.bottom > 0 ? max(safeAreaInsets.bottom - 2, 24) : 16
    }

    private func iPhoneTabBar(isPortrait: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(visibleIPhoneTabs, id: \.self) { tab in
                let isSelected = selectionBinding.wrappedValue == tab
                Button {
                    selectTab(tab)
                } label: {
                    Image(systemName: tabSystemImage(for: tab))
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.appleBlue : Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(ClubTheme.subCardFill)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tabTitle(for: tab))
            }
        }
        .padding(6)
        .background(
            Capsule(style: .continuous)
                .fill(ClubTheme.cardFill.opacity(0.92))
                .overlay(
                    Capsule(style: .continuous)
                        .fill(ClubTheme.cardOverlay)
                )
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(ClubTheme.cardStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
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

    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()

        if UIDevice.current.userInterfaceIdiom == .phone {
            appearance.configureWithTransparentBackground()
            appearance.backgroundEffect = nil
            appearance.backgroundColor = .clear
            appearance.backgroundImage = UIImage()
            appearance.shadowColor = .clear

            UITabBar.appearance().backgroundImage = UIImage()
            UITabBar.appearance().shadowImage = UIImage()
            UITabBar.appearance().backgroundColor = .clear
            UITabBar.appearance().barTintColor = .clear
            UITabBar.appearance().isTranslucent = true
        } else {
            let backgroundColor = UIColor.secondarySystemGroupedBackground
            appearance.configureWithOpaqueBackground()
            appearance.backgroundEffect = nil
            appearance.backgroundColor = backgroundColor
            appearance.backgroundImage = solidColorImage(backgroundColor)
            appearance.shadowColor = UIColor.separator.withAlphaComponent(0.35)

            UITabBar.appearance().backgroundImage = solidColorImage(backgroundColor)
            UITabBar.appearance().shadowImage = nil
            UITabBar.appearance().backgroundColor = backgroundColor
            UITabBar.appearance().barTintColor = backgroundColor
            UITabBar.appearance().isTranslucent = false
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    private static func configureNavigationBarAppearance() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
        UINavigationBar.appearance().isTranslucent = true
        UINavigationBar.appearance().backgroundColor = .clear
        UINavigationBar.appearance().barTintColor = .clear
    }

    private static func solidColorImage(_ color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
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

private extension View {
    @ViewBuilder
    func iPhoneTransparentChrome() -> some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            ignoresSafeArea(.container, edges: .top)
                .toolbarBackground(.hidden, for: .navigationBar)
        } else {
            self
        }
    }

    @ViewBuilder
    func floatingTabBarBackground() -> some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            toolbar(.hidden, for: .tabBar)
                .toolbarBackground(.hidden, for: .navigationBar)
        } else {
            toolbarBackground(ClubTheme.cardFill, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
        }
    }
}

private struct IPhoneTopFadeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            content
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.08),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        } else {
            content
        }
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
