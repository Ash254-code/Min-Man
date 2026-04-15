import SwiftUI

struct TeamsAndVenuesSettingsView: View {
    @State private var configuration: ClubConfiguration = ClubConfigurationStore.load()

    var body: some View {
        List {
            Section("Your Team") {
                NavigationLink {
                    TeamProfileEditorView(
                        title: "Your Team",
                        teamName: Binding(
                            get: { configuration.clubTeam.name },
                            set: {
                                configuration.clubTeam.name = $0
                                save()
                            }
                        ),
                        primaryHex: Binding(
                            get: { configuration.clubTeam.primaryColorHex },
                            set: {
                                configuration.clubTeam.primaryColorHex = $0
                                save()
                            }
                        ),
                        secondaryHex: Binding(
                            get: { configuration.clubTeam.secondaryColorHex ?? "" },
                            set: {
                                configuration.clubTeam.secondaryColorHex = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
                                save()
                            }
                        ),
                        tertiaryHex: Binding(
                            get: { configuration.clubTeam.tertiaryColorHex ?? "" },
                            set: {
                                configuration.clubTeam.tertiaryColorHex = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
                                save()
                            }
                        ),
                        venues: Binding(
                            get: { configuration.clubTeam.venues },
                            set: {
                                configuration.clubTeam.venues = $0
                                save()
                            }
                        )
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
                            teamName: Binding(
                                get: { opposition.name },
                                set: {
                                    opposition.name = $0
                                    save()
                                }
                            ),
                            primaryHex: Binding(
                                get: { opposition.primaryColorHex },
                                set: {
                                    opposition.primaryColorHex = $0
                                    save()
                                }
                            ),
                            secondaryHex: Binding(
                                get: { opposition.secondaryColorHex ?? "" },
                                set: {
                                    opposition.secondaryColorHex = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
                                    save()
                                }
                            ),
                            tertiaryHex: Binding(
                                get: { opposition.tertiaryColorHex ?? "" },
                                set: {
                                    opposition.tertiaryColorHex = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
                                    save()
                                }
                            ),
                            venues: Binding(
                                get: { opposition.venues },
                                set: {
                                    opposition.venues = $0
                                    save()
                                }
                            )
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

    var body: some View {
        Form {
            Section("Team") {
                TextField("Name", text: $teamName)
                    .textInputAutocapitalization(.words)
            }

            Section("Colours") {
                TeamColorPickerRow(title: TeamColorSlot.primary.title, hexValue: $primaryHex)
                TeamColorPickerRow(title: TeamColorSlot.secondary.title, hexValue: $secondaryHex)
                TeamColorPickerRow(title: TeamColorSlot.tertiary.title, hexValue: $tertiaryHex)

                Text("Pick up to three colours. Primary is required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Venues (up to 3)") {
                ForEach(0..<3, id: \.self) { index in
                    TextField(
                        "Venue \(index + 1)",
                        text: Binding(
                            get: { index < venues.count ? venues[index] : "" },
                            set: { newValue in
                                setVenue(newValue, at: index)
                            }
                        )
                    )
                    .textInputAutocapitalization(.words)
                }
            }
        }
        .navigationTitle(title)
    }

    private func setVenue(_ venue: String, at index: Int) {
        var mutable = venues
        while mutable.count <= index {
            mutable.append("")
        }
        mutable[index] = venue
        venues = Array(mutable.prefix(3))
    }
}

private struct TeamColorPickerRow: View {
    let title: String
    @Binding var hexValue: String

    var body: some View {
        ColorPicker(
            title,
            selection: Binding(
                get: { Color(hex: hexValue, fallback: .blue) },
                set: { hexValue = $0.toHex() }
            ),
            supportsOpacity: false
        )
    }
}
