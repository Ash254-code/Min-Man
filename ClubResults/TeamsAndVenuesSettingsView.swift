import SwiftUI

struct TeamsAndVenuesSettingsView: View {
    @State private var configuration: ClubConfiguration = ClubConfigurationStore.load()

    var body: some View {
        List {
            Section("Your Team") {
                NavigationLink {
                    TeamProfileEditorView(
                        title: "Your Team",
                        teamName: $configuration.clubTeam.name,
                        primaryHex: $configuration.clubTeam.primaryColorHex,
                        secondaryHex: Binding(
                            get: { configuration.clubTeam.secondaryColorHex ?? "" },
                            set: { configuration.clubTeam.secondaryColorHex = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                        ),
                        tertiaryHex: Binding(
                            get: { configuration.clubTeam.tertiaryColorHex ?? "" },
                            set: { configuration.clubTeam.tertiaryColorHex = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                        ),
                        venues: $configuration.clubTeam.venues,
                        onSave: save
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(configuration.clubTeam.name)
                        Text(venueSummary(configuration.clubTeam.venues))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Opposition Teams") {
                ForEach($configuration.oppositions) { $opposition in
                    NavigationLink {
                        TeamProfileEditorView(
                            title: opposition.name,
                            teamName: $opposition.name,
                            primaryHex: $opposition.primaryColorHex,
                            secondaryHex: Binding(
                                get: { opposition.secondaryColorHex ?? "" },
                                set: { opposition.secondaryColorHex = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                            ),
                            tertiaryHex: Binding(
                                get: { opposition.tertiaryColorHex ?? "" },
                                set: { opposition.tertiaryColorHex = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                            ),
                            venues: $opposition.venues,
                            onSave: save
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(opposition.name)
                            Text(venueSummary(opposition.venues))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteOppositions)

                Button {
                    addOpposition()
                } label: {
                    Label("Add Opposition", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Teams & Venues")
        .toolbar { EditButton() }
        .onAppear {
            configuration = ClubConfigurationStore.load()
        }
    }

    private func save() {
        ClubConfigurationStore.save(configuration)
    }

    private func addOpposition() {
        configuration.oppositions.append(
            OppositionTeamProfile(
                id: UUID(),
                name: "New Opposition",
                primaryColorHex: "#1D4ED8",
                secondaryColorHex: nil,
                tertiaryColorHex: nil,
                venues: []
            )
        )
        save()
    }

    private func deleteOppositions(at offsets: IndexSet) {
        configuration.oppositions.remove(atOffsets: offsets)
        save()
    }

    private func venueSummary(_ venues: [String]) -> String {
        let sanitized = venues
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3)

        if sanitized.isEmpty {
            return "No venues configured"
        }

        return sanitized.joined(separator: ", ")
    }
}

private struct TeamProfileEditorView: View {
    let title: String
    @Binding var teamName: String
    @Binding var primaryHex: String
    @Binding var secondaryHex: String
    @Binding var tertiaryHex: String
    @Binding var venues: [String]
    let onSave: () -> Void

    @State private var draftTeamName: String = ""
    @State private var draftPrimaryHex: String = ""
    @State private var draftSecondaryHex: String = ""
    @State private var draftTertiaryHex: String = ""
    @State private var draftVenues: [String] = []
    @State private var isEditing = false

    var body: some View {
        Form {
            Section("Team") {
                teamPill

                TextField("Name", text: $draftTeamName)
                    .textInputAutocapitalization(.words)
                    .disabled(!isEditing)
            }

            Section("Colours") {
                TeamColorPickerRow(title: TeamColorSlot.primary.title, hexValue: $draftPrimaryHex, isEnabled: isEditing)
                TeamColorPickerRow(title: TeamColorSlot.secondary.title, hexValue: $draftSecondaryHex, isEnabled: isEditing)
                TeamColorPickerRow(title: TeamColorSlot.tertiary.title, hexValue: $draftTertiaryHex, isEnabled: isEditing)

                Text("Pick up to three colours. Primary is required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Venues (up to 3)") {
                ForEach(0..<3, id: \.self) { index in
                    TextField(
                        "Venue \(index + 1)",
                        text: Binding(
                            get: { index < draftVenues.count ? draftVenues[index] : "" },
                            set: { newValue in
                                setVenue(newValue, at: index)
                            }
                        )
                    )
                    .textInputAutocapitalization(.words)
                    .disabled(!isEditing)
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing { syncFromBindings() }
                    isEditing.toggle()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isEditing && hasChanges && canSave {
                HStack {
                    Spacer()
                    Button("Save") {
                        applyDraftToBindings()
                        onSave()
                        isEditing = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
        }
        .onAppear {
            syncFromBindings()
        }
    }

    private var canSave: Bool {
        !draftTeamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draftPrimaryHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasChanges: Bool {
        draftTeamName != teamName ||
        draftPrimaryHex != primaryHex ||
        draftSecondaryHex != secondaryHex ||
        draftTertiaryHex != tertiaryHex ||
        normalizedDraftVenues != normalizedPersistedVenues
    }

    private var normalizedDraftVenues: [String] {
        draftVenues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private var normalizedPersistedVenues: [String] {
        venues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private var teamPill: some View {
        let name = draftTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.isEmpty ? "Team" : name

        return Text(displayName)
            .font(.headline)
            .foregroundStyle(Color(hex: draftSecondaryHex, fallback: .white))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(hex: draftPrimaryHex, fallback: .blue))
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func syncFromBindings() {
        draftTeamName = teamName
        draftPrimaryHex = primaryHex
        draftSecondaryHex = secondaryHex
        draftTertiaryHex = tertiaryHex
        draftVenues = Array(venues.prefix(3))
    }

    private func applyDraftToBindings() {
        teamName = draftTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
        primaryHex = draftPrimaryHex
        secondaryHex = draftSecondaryHex.trimmingCharacters(in: .whitespacesAndNewlines)
        tertiaryHex = draftTertiaryHex.trimmingCharacters(in: .whitespacesAndNewlines)
        venues = Array(
            draftVenues
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(3)
        )
    }

    private func setVenue(_ venue: String, at index: Int) {
        var mutable = draftVenues
        while mutable.count <= index {
            mutable.append("")
        }
        mutable[index] = venue
        draftVenues = Array(mutable.prefix(3))
    }
}

private struct TeamColorPickerRow: View {
    let title: String
    @Binding var hexValue: String
    let isEnabled: Bool

    var body: some View {
        ColorPicker(
            title,
            selection: Binding(
                get: { Color(hex: hexValue, fallback: .blue) },
                set: { hexValue = $0.toHex() }
            ),
            supportsOpacity: false
        )
        .disabled(!isEnabled)
    }
}
