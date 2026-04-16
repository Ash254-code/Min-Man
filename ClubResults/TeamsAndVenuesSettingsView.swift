import SwiftUI
import UIKit

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
                    VStack(alignment: .leading, spacing: 6) {
                        teamNamePill(
                            name: configuration.clubTeam.name,
                            primaryHex: configuration.clubTeam.primaryColorHex,
                            secondaryHex: configuration.clubTeam.secondaryColorHex,
                            tertiaryHex: configuration.clubTeam.tertiaryColorHex,
                            width: standardPillWidth
                        )

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
                        VStack(alignment: .leading, spacing: 6) {
                            teamNamePill(
                                name: opposition.name,
                                primaryHex: opposition.primaryColorHex,
                                secondaryHex: opposition.secondaryColorHex,
                                tertiaryHex: opposition.tertiaryColorHex,
                                width: standardPillWidth
                            )

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

    private var standardPillWidth: CGFloat {
        ClubStyle.standardPillWidth(configuration: configuration, fontTextStyle: .headline)
    }

    @ViewBuilder
    private func teamNamePill(name: String, primaryHex: String, secondaryHex: String?, tertiaryHex: String?, width: CGFloat) -> some View {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = cleaned.isEmpty ? "Team" : cleaned
        let style = ClubStyle.style(
            primaryHex: primaryHex,
            secondaryHex: secondaryHex,
            tertiaryHex: tertiaryHex,
            fallback: ClubStyle.ourScoreStyle
        )

        Text(label)
            .font(.headline)
            .foregroundStyle(style.text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: width, alignment: .center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(style.background)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(style.border.opacity(0.95), lineWidth: 1.5)
            )
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
                HStack(spacing: 12) {
                    teamPill
                    Spacer()
                    if isEditing {
                        editIconButton {
                            teamNameDraft = draftTeamName
                            teamNameEditorPresented = true
                        }
                    }
                }
            }

            Section("Colours") {
                editableColorRow(title: "Primary", hex: draftPrimaryHex, editAction: {
                    presentColorPicker(.primary)
                }, deleteAction: nil)

                editableColorRow(title: "Secondary", hex: draftSecondaryHex, editAction: {
                    presentColorPicker(.secondary)
                }, deleteAction: nil)

                if hasTertiary {
                    editableColorRow(title: "Tertiary", hex: draftTertiaryHex, editAction: {
                        presentColorPicker(.tertiary)
                    }, deleteAction: {
                        draftTertiaryHex = ""
                    })
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
                    HStack {
                        Text(venue)
                        Spacer()
                        if isEditing {
                            editIconButton {
                                venueEditorIndex = index
                                venueNameDraft = venue
                                venueEditorPresented = true
                            }
                            deleteIconButton {
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
                Button(isEditing ? "Cancel" : "Edit") {
                    if isEditing {
                        syncFromBindings()
                        isEditing = false
                    } else {
                        isEditing = true
                    }
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

        let style = ClubStyle.style(
            primaryHex: draftPrimaryHex,
            secondaryHex: draftSecondaryHex,
            tertiaryHex: draftTertiaryHex,
            fallback: ClubStyle.ourScoreStyle
        )

        return Text(displayName)
            .font(.headline)
            .foregroundStyle(style.text)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(style.background)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(style.border.opacity(0.95), lineWidth: 1.5)
            )
    }

    @ViewBuilder
    private func editableColorRow(title: String, hex: String, editAction: @escaping () -> Void, deleteAction: (() -> Void)?) -> some View {
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

            if isEditing {
                editIconButton(action: editAction)
                if let deleteAction {
                    deleteIconButton(action: deleteAction)
                }
            }
        }
    }

    @ViewBuilder
    private func editIconButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.blue)
    }

    @ViewBuilder
    private func deleteIconButton(action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "trash")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderless)
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
