import Foundation

struct StatsInviteDeepLink: Equatable {
    let sessionID: UUID
    let recordName: String
    let inviteeEmail: String
}

enum StatsInviteLinking {
    private static let scheme = "clubresults"
    private static let host = "stats-invite"

    static func appURL(sessionID: UUID, recordName: String, inviteeEmail: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "sessionID", value: sessionID.uuidString.lowercased()),
            URLQueryItem(name: "recordName", value: recordName),
            URLQueryItem(name: "inviteeEmail", value: inviteeEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        ]
        return components.url
    }

    static func parse(_ url: URL) -> StatsInviteDeepLink? {
        guard
            url.scheme?.caseInsensitiveCompare(scheme) == .orderedSame,
            url.host?.caseInsensitiveCompare(host) == .orderedSame
        else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let values = Dictionary(queryItems.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })

        guard
            let sessionIDRaw = values["sessionID"],
            let sessionID = UUID(uuidString: sessionIDRaw),
            let recordName = values["recordName"],
            !recordName.isEmpty,
            let inviteeEmail = values["inviteeEmail"],
            !inviteeEmail.isEmpty
        else {
            return nil
        }

        return StatsInviteDeepLink(
            sessionID: sessionID,
            recordName: recordName,
            inviteeEmail: inviteeEmail
        )
    }
}
