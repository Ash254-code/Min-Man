import Foundation
internal import Combine

enum AppRole: String, CaseIterable, Identifiable {
    case admin
    case restrictedAdmin
    case teamManager
    case coach
    case statTaker
    case supporter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .admin:
            return "Admin"
        case .restrictedAdmin:
            return "Restricted Admin"
        case .teamManager:
            return "Team Manager"
        case .coach:
            return "Coach"
        case .statTaker:
            return "Stat Taker"
        case .supporter:
            return "Supporter"
        }
    }

    var summary: String {
        switch self {
        case .admin:
            return "Full access to app settings and management features."
        case .restrictedAdmin:
            return "Admin access with selected limits."
        case .teamManager:
            return "Manage team operations and match-day tasks."
        case .coach:
            return "Access coaching tools and team information."
        case .statTaker:
            return "Record and manage live match statistics."
        case .supporter:
            return "View-only access for supporters and followers."
        }
    }

    var icon: String {
        switch self {
        case .admin:
            return "person.crop.circle.badge.checkmark"
        case .restrictedAdmin:
            return "lock.shield"
        case .teamManager:
            return "person.2.badge.gearshape"
        case .coach:
            return "figure.australian.football"
        case .statTaker:
            return "chart.bar.xaxis"
        case .supporter:
            return "hands.clap"
        }
    }

    var visibleTabs: [AppTab] {
        switch self {
        case .admin, .restrictedAdmin:
            return [.games, .game, .stats, .totals, .pres, .settings]
        case .teamManager:
            return [.games, .game, .stats, .totals, .settings]
        case .coach:
            return [.games, .stats, .totals, .settings]
        case .statTaker:
            return [.games, .stats, .totals, .settings]
        case .supporter:
            return [.games, .totals, .settings]
        }
    }

    var canEditGames: Bool {
        switch self {
        case .supporter, .statTaker:
            return false
        default:
            return true
        }
    }

    var showsSupporterSettingsOnly: Bool {
        self == .supporter || self == .statTaker
    }

    var showsTeamManagerSettingsOnly: Bool {
        self == .teamManager
    }

    var showsCoachSettingsOnly: Bool {
        self == .coach
    }

    var hasRestrictedAdminSettings: Bool {
        self == .restrictedAdmin
    }

    var canStartStatsSessions: Bool {
        switch self {
        case .teamManager, .coach, .statTaker, .supporter:
            return false
        default:
            return true
        }
    }

    var canModifyStatsSessions: Bool {
        switch self {
        case .teamManager, .coach, .statTaker, .supporter:
            return false
        default:
            return true
        }
    }

    var canStartGames: Bool {
        switch self {
        case .coach, .statTaker, .supporter:
            return false
        default:
            return true
        }
    }

    var canManageInvites: Bool {
        switch self {
        case .admin, .restrictedAdmin:
            return true
        default:
            return false
        }
    }

    var canViewVoteDetails: Bool {
        switch self {
        case .admin, .restrictedAdmin, .teamManager:
            return true
        default:
            return false
        }
    }
}

enum AppTab: Hashable {
    case games
    case game
    case totals
    case stats
    case pres
    case settings

    var title: String {
        switch self {
        case .games: return "Home"
        case .game: return "Live"
        case .totals: return "Totals"
        case .stats: return "Stats"
        case .pres: return "Pres"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .games: return "house"
        case .game: return "figure.australian.football"
        case .totals: return "chart.bar"
        case .stats: return "chart.bar.xaxis"
        case .pres: return "rectangle.stack"
        case .settings: return "gearshape"
        }
    }
}

struct LiveGameSyncGoalKicker: Codable, Equatable {
    var playerID: UUID
    var goals: Int
}

struct LiveGameSyncSnapshot: Equatable {
    var gradeID: UUID
    var date: Date
    var opposition: String
    var currentQuarter: String
    var periodMinutes: Int
    var remainingSeconds: Int
    var isTimerRunning: Bool
    var timerAnchorDate: Date?
    var timerAnchorSecondsRemaining: Int?
    var ourGoals: Int
    var ourBehinds: Int
    var theirGoals: Int
    var theirBehinds: Int
    var goalKickers: [LiveGameSyncGoalKicker]

    var ourPoints: Int { ourGoals * 6 + ourBehinds }
    var theirPoints: Int { theirGoals * 6 + theirBehinds }

    func syncedRemainingSeconds(at date: Date = Date()) -> Int {
        guard isTimerRunning,
              let timerAnchorDate,
              let timerAnchorSecondsRemaining else {
            return remainingSeconds
        }
        let elapsed = max(0, Int(date.timeIntervalSince(timerAnchorDate)))
        return max(0, timerAnchorSecondsRemaining - elapsed)
    }

    func isTimerActive(at date: Date = Date()) -> Bool {
        isTimerRunning && syncedRemainingSeconds(at: date) > 0
    }
}

@MainActor
final class AppNavigationState: ObservableObject {
    private static let appRoleKey = "app.role.preview"

    @Published var selectedTab: AppTab = .games
    @Published var activeStatsSessionID: UUID?
    @Published private(set) var activeLiveStatsSessionID: UUID?
    @Published private(set) var pendingStatsInviteSessionID: UUID?
    @Published var startNewStatsSessionToken = UUID()
    @Published private(set) var activeLiveGameDraftID: UUID?
    @Published private(set) var activeLiveGameGradeID: UUID?
    @Published private(set) var activeLiveGameSnapshot: LiveGameSyncSnapshot?
    @Published private(set) var syncedStatsSessionID: UUID?
    @Published private(set) var currentRole: AppRole
    @Published private(set) var authenticatedRole: AppRole?

    var isRoleLocked: Bool {
        authenticatedRole != nil
    }

    var canPreviewRoles: Bool {
        authenticatedRole == nil || authenticatedRole == .admin
    }

    init() {
        if let rawValue = UserDefaults.standard.string(forKey: Self.appRoleKey),
           let storedRole = AppRole(rawValue: rawValue) {
            currentRole = storedRole
        } else {
            currentRole = .admin
        }
    }

    func canAccess(tab: AppTab) -> Bool {
        currentRole.visibleTabs.contains(tab)
    }

    func setPreviewRole(_ role: AppRole) {
        guard canPreviewRoles else { return }
        UserDefaults.standard.set(role.rawValue, forKey: Self.appRoleKey)
        apply(role: role)
    }

    func setAuthenticatedRole(_ role: AppRole) {
        authenticatedRole = role
        apply(role: role)
    }

    func clearAuthenticatedRole() {
        authenticatedRole = nil
        let previewRole: AppRole
        if let rawValue = UserDefaults.standard.string(forKey: Self.appRoleKey),
           let storedRole = AppRole(rawValue: rawValue) {
            previewRole = storedRole
        } else {
            previewRole = .admin
        }
        apply(role: previewRole)
    }

    func activateStatsSession(id: UUID) {
        activeStatsSessionID = id
    }

    func clearActiveStatsSession() {
        if syncedStatsSessionID == activeStatsSessionID {
            syncedStatsSessionID = nil
        }
        activeStatsSessionID = nil
    }

    func setActiveLiveStatsSession(id: UUID) {
        activeLiveStatsSessionID = id
    }

    func clearActiveLiveStatsSession(id: UUID? = nil) {
        guard id == nil || activeLiveStatsSessionID == id else { return }
        if syncedStatsSessionID == activeLiveStatsSessionID {
            syncedStatsSessionID = nil
        }
        activeLiveStatsSessionID = nil
    }

    func updateLiveGameSnapshot(_ snapshot: LiveGameSyncSnapshot) {
        activeLiveGameSnapshot = snapshot
    }

    func openLiveGameTab(draftGameID: UUID, gradeID: UUID) {
        guard currentRole.visibleTabs.contains(.game) else { return }
        activeLiveGameDraftID = draftGameID
        activeLiveGameGradeID = gradeID
        selectedTab = .game
    }

    func closeLiveGameTab(selectHome: Bool = true) {
        activeLiveGameDraftID = nil
        activeLiveGameGradeID = nil
        clearActiveLiveGameSnapshot()
        if selectHome {
            selectedTab = .games
        }
    }

    func clearActiveLiveGameSnapshot() {
        activeLiveGameSnapshot = nil
        syncedStatsSessionID = nil
    }

    func syncActiveLiveGame(toStatsSessionID sessionID: UUID) {
        guard activeLiveGameSnapshot != nil,
              activeLiveStatsSessionID == sessionID else { return }
        syncedStatsSessionID = sessionID
    }

    func clearLiveGameSync() {
        syncedStatsSessionID = nil
    }

    func openStatsNewSession() {
        guard currentRole.canStartStatsSessions else { return }
        selectedTab = .stats
        startNewStatsSessionToken = UUID()
    }

    func openStatsInvite(sessionID: UUID) {
        pendingStatsInviteSessionID = sessionID
        if currentRole.visibleTabs.contains(.stats) {
            selectedTab = .stats
        }
    }

    func clearPendingStatsInvite() {
        pendingStatsInviteSessionID = nil
    }

    private func apply(role: AppRole) {
        currentRole = role
        if pendingStatsInviteSessionID != nil, role.visibleTabs.contains(.stats) {
            selectedTab = .stats
        } else if !role.visibleTabs.contains(selectedTab) {
            selectedTab = role.visibleTabs.first ?? .games
        }
    }
}
