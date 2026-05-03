import Foundation
import SwiftData

struct DuplicatePlayerGroup: Identifiable {
    let key: String
    let players: [Player]

    var id: String { key }

    var title: String {
        guard let firstPlayer = players.first else { return "Duplicate Player" }
        return Player.combineName(first: firstPlayer.firstName, last: firstPlayer.lastName)
    }
}

enum PlayerDuplicateService {
    enum MergeError: LocalizedError {
        case notEnoughPlayers

        var errorDescription: String? {
            switch self {
            case .notEnoughPlayers:
                return "At least two duplicate players are required to merge."
            }
        }
    }

    static func duplicateGroupLookup(in players: [Player]) -> [UUID: DuplicatePlayerGroup] {
        players
            .reduce(into: [String: [Player]]()) { partialResult, player in
                let key = player.duplicateMatchKey
                guard !key.replacingOccurrences(of: "|", with: "").isEmpty else { return }
                partialResult[key, default: []].append(player)
            }
            .values
            .filter { $0.count > 1 }
            .map { players in
                let sortedPlayers = players.sorted { lhs, rhs in
                    if lhs.name != rhs.name {
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return DuplicatePlayerGroup(key: sortedPlayers[0].duplicateMatchKey, players: sortedPlayers)
            }
            .reduce(into: [:]) { partialResult, group in
                for player in group.players {
                    partialResult[player.id] = group
                }
            }
    }

    @discardableResult
    static func merge(players: [Player], modelContext: ModelContext) throws -> Player {
        guard players.count > 1 else {
            throw MergeError.notEnoughPlayers
        }

        let orderedPlayers = players.sorted { lhs, rhs in
            let lhsScore = playerMergeScore(lhs)
            let rhsScore = playerMergeScore(rhs)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            if lhs.name != rhs.name {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let mergedPlayer = orderedPlayers[0]
        let mergedIDs = Set(orderedPlayers.map(\.id))
        let obsoleteIDs = Set(orderedPlayers.dropFirst().map(\.id))

        mergedPlayer.setName(
            firstName: canonicalNameComponent(from: orderedPlayers.map(\.firstName)),
            lastName: canonicalNameComponent(from: orderedPlayers.map(\.lastName)),
            preferredName: orderedPlayers
                .map(\.preferredName)
                .map(\.cleanedName)
                .first(where: { !$0.isEmpty }) ?? ""
        )
        mergedPlayer.number = resolvedNumber(from: orderedPlayers)
        mergedPlayer.gradeIDs = mergedGradeIDs(from: orderedPlayers)
        mergedPlayer.isActive = orderedPlayers.contains(where: \.isActive)

        let games = try modelContext.fetch(FetchDescriptor<Game>())
        for game in games {
            game.bestPlayersRanked = game.bestPlayersRanked.map { obsoleteIDs.contains($0) ? mergedPlayer.id : $0 }
            game.guestVotesRanked = game.guestVotesRanked.map { entry in
                guard obsoleteIDs.contains(entry.playerID) else { return entry }
                return GameGuestVoteEntry(id: entry.id, rank: entry.rank, playerID: mergedPlayer.id)
            }
            game.goalKickers = mergedGoalKickers(from: game.goalKickers, mergedPlayerID: mergedPlayer.id, mergedIDs: mergedIDs)
        }

        let statEvents = try modelContext.fetch(FetchDescriptor<StatEvent>())
        for statEvent in statEvents where obsoleteIDs.contains(statEvent.playerId) {
            statEvent.playerId = mergedPlayer.id
        }

        for player in orderedPlayers.dropFirst() {
            modelContext.delete(player)
        }

        try modelContext.save()
        return mergedPlayer
    }

    private static func playerMergeScore(_ player: Player) -> Int {
        var score = 0
        if player.isActive { score += 8 }
        if player.number != nil { score += 4 }
        if !player.preferredName.cleanedName.isEmpty { score += 2 }
        score += min(player.gradeIDs.count, 5)
        score += min(player.firstName.cleanedName.count + player.lastName.cleanedName.count, 50)
        return score
    }

    private static func canonicalNameComponent(from values: [String]) -> String {
        values
            .map(\.cleanedName)
            .filter { !$0.isEmpty }
            .sorted {
                if $0.count != $1.count {
                    return $0.count > $1.count
                }
                return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            .first ?? ""
    }

    private static func resolvedNumber(from players: [Player]) -> Int? {
        let uniqueNumbers = Array(Set(players.compactMap(\.number))).sorted()
        return uniqueNumbers.count == 1 ? uniqueNumbers[0] : nil
    }

    private static func mergedGradeIDs(from players: [Player]) -> [UUID] {
        var seen = Set<UUID>()
        return players
            .flatMap(\.gradeIDs)
            .filter { seen.insert($0).inserted }
    }

    private static func mergedGoalKickers(
        from entries: [GameGoalKickerEntry],
        mergedPlayerID: UUID,
        mergedIDs: Set<UUID>
    ) -> [GameGoalKickerEntry] {
        var combinedEntries: [GameGoalKickerEntry] = []
        var indexByPlayerID: [UUID: Int] = [:]

        for entry in entries {
            guard let playerID = entry.playerID else {
                combinedEntries.append(entry)
                continue
            }

            let resolvedPlayerID = mergedIDs.contains(playerID) ? mergedPlayerID : playerID
            if let existingIndex = indexByPlayerID[resolvedPlayerID] {
                combinedEntries[existingIndex].goals += entry.goals
                combinedEntries[existingIndex].points += entry.points
            } else {
                indexByPlayerID[resolvedPlayerID] = combinedEntries.count
                combinedEntries.append(
                    GameGoalKickerEntry(
                        id: entry.id,
                        playerID: resolvedPlayerID,
                        goals: entry.goals,
                        points: entry.points
                    )
                )
            }
        }

        return combinedEntries
    }
}
