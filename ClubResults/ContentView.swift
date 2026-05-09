import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var hasNormalizedPlayers = false

    var body: some View {
        TabsView()
            .task {
                guard !hasNormalizedPlayers else { return }
                hasNormalizedPlayers = true
                normalizePersistedPlayersIfNeeded()
            }
    }

    private func normalizePersistedPlayersIfNeeded() {
        let descriptor = FetchDescriptor<Player>()
        guard let players = try? modelContext.fetch(descriptor) else { return }

        var didChange = false
        for player in players {
            didChange = player.normalizeStoredNamesIfNeeded() || didChange
        }

        if didChange {
            try? modelContext.save()
        }
    }
}

#Preview {
    ContentView()
        .clubGlassBackground() // preview-only so it looks right in canvas
}
