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
                secondaryColorHex: "#FFFFFF",
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
    private enum ColorSlot: String {
        case primary
        case secondary
        case tertiary

        var title: String { rawValue.capitalized }
    }

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

    @State private var teamNameEditorPresented = false
    @State private var teamNameDraft = ""

    @State private var venueEditorPresented = false
    @State private var venueEditorIndex = 0
    @State private var venueNameDraft = ""

    @State private var colorPickerPresented = false
    @State private var colorPickerSlot: ColorSlot = .primary

    var body: some View {
        Form {
            Section("Team") {
                teamPill
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if isEditing {
                            Button("Edit") {
                                teamNameDraft = draftTeamName
                                teamNameEditorPresented = true
                            }
                            .tint(.blue)
                        }
                    }
            }

            Section("Colours") {
                colorRow(title: "Primary", hex: draftPrimaryHex)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if isEditing {
                            Button("Edit") { presentColorPicker(.primary) }
                                .tint(.blue)
                        }
                    }

                colorRow(title: "Secondary", hex: draftSecondaryHex)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if isEditing {
                            Button("Edit") { presentColorPicker(.secondary) }
                                .tint(.blue)
                        }
                    }

                if hasTertiary {
                    colorRow(title: "Tertiary", hex: draftTertiaryHex)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if isEditing {
                                Button("Edit") { presentColorPicker(.tertiary) }
                                    .tint(.blue)
                                Button("Delete", role: .destructive) {
                                    draftTertiaryHex = ""
                                }
                            }
                        }
                } else if isEditing {
                    Button {
                        draftTertiaryHex = "#FFFFFF"
                    } label: {
                        Label("Add Tertiary", systemImage: "plus")
                    }
                }

                Text("Primary and Secondary are default. Add tertiary if needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Venues (up to 3)") {
                ForEach(Array(draftVenues.enumerated()), id: \.offset) { index, venue in
                    Text(venue)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if isEditing {
                                Button("Edit") {
                                    venueEditorIndex = index
                                    venueNameDraft = venue
                                    venueEditorPresented = true
                                }
                                .tint(.blue)

                                Button("Delete", role: .destructive) {
                                    draftVenues.remove(at: index)
                                }
                            }
                        }
                }

                if draftVenues.isEmpty {
                    Text("No venues yet")
                        .foregroundStyle(.secondary)
                }

                if isEditing && draftVenues.count < 3 {
                    Button {
                        venueEditorIndex = draftVenues.count
                        venueNameDraft = ""
                        venueEditorPresented = true
                    } label: {
                        Label("Add Venue", systemImage: "plus")
                    }
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
        .sheet(isPresented: $colorPickerPresented) {
            NavigationStack {
                Form {
                    ColorPicker(
                        colorPickerSlot.title,
                        selection: Binding(
                            get: { Color(hex: colorHex(for: colorPickerSlot), fallback: .blue) },
                            set: { newColor in setColorHex(newColor.toHex(), for: colorPickerSlot) }
                        ),
                        supportsOpacity: false
                    )
                }
                .navigationTitle("Edit \(colorPickerSlot.title)")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { colorPickerPresented = false }
                    }
                }
            }
            .presentationDetents([.height(220)])
        }
        .alert("Edit Team Name", isPresented: $teamNameEditorPresented) {
            TextField("Team name", text: $teamNameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let cleaned = teamNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    draftTeamName = cleaned
                }
            }
        }
        .alert("Venue", isPresented: $venueEditorPresented) {
            TextField("Venue name", text: $venueNameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let cleaned = venueNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { return }
                if venueEditorIndex < draftVenues.count {
                    draftVenues[venueEditorIndex] = cleaned
                } else if draftVenues.count < 3 {
                    draftVenues.append(cleaned)
                }
            }
        }
        .onAppear {
            syncFromBindings()
        }
    }

    private var hasTertiary: Bool {
        !draftTertiaryHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSave: Bool {
        !draftTeamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draftPrimaryHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draftSecondaryHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasChanges: Bool {
        draftTeamName != teamName ||
        draftPrimaryHex != primaryHex ||
        draftSecondaryHex != secondaryHex ||
        draftTertiaryHex != tertiaryHex ||
        draftVenues != venues
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

    @ViewBuilder
    private func colorRow(title: String, hex: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Circle()
                .fill(Color(hex: hex, fallback: .blue))
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.25), lineWidth: 1)
                )
        }
    }

    private func presentColorPicker(_ slot: ColorSlot) {
        colorPickerSlot = slot
        colorPickerPresented = true
    }

    private func colorHex(for slot: ColorSlot) -> String {
        switch slot {
        case .primary: return draftPrimaryHex
        case .secondary: return draftSecondaryHex
        case .tertiary: return draftTertiaryHex
        }
    }

    private func setColorHex(_ hex: String, for slot: ColorSlot) {
        switch slot {
        case .primary: draftPrimaryHex = hex
        case .secondary: draftSecondaryHex = hex
        case .tertiary: draftTertiaryHex = hex
        }
    }

    private func syncFromBindings() {
        draftTeamName = teamName
        draftPrimaryHex = primaryHex
        draftSecondaryHex = secondaryHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "#FFFFFF" : secondaryHex
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
}
