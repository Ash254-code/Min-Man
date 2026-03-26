import Foundation

// Backing storage for persisted data
private var trainersData: Data = Data()
private var goalKickersData: Data = Data()
private var bestPlayersData: Data = Data()

// Placeholder model; replace with your actual definition if it exists elsewhere
struct GoalKickerEntry: Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var goals: Int = 0
}

var trainers: [String] {
    get { (try? JSONDecoder().decode([String].self, from: trainersData)) ?? [] }
    set { trainersData = (try? JSONEncoder().encode(newValue)) ?? Data() }
}

var goalKickers: [GoalKickerEntry] {
    get { (try? JSONDecoder().decode([GoalKickerEntry].self, from: goalKickersData)) ?? [] }
    set { goalKickersData = (try? JSONEncoder().encode(newValue)) ?? Data() }
}

var bestPlayersRanked: [UUID] {
    get { (try? JSONDecoder().decode([UUID].self, from: bestPlayersData)) ?? [] }
    set { bestPlayersData = (try? JSONEncoder().encode(newValue)) ?? Data() }
}
