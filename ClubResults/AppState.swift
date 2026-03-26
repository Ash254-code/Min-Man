import Foundation

enum BestPlayerPoints {
    /// Rank 1..6 => 6..1 points
    static func points(forRank rank: Int) -> Int {
        return max(0, 7 - rank)
    }
}

struct PlayerTotals: Identifiable {
    let id: UUID
    let playerName: String
    let goals: Int
    let bestPoints: Int
    let bestAppearances: Int
}
