import SwiftUI
import SwiftData

struct PlayerEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var dataContext: ModelContext

    @Bindable var player: Player

    // These let PlayersView pass context, but they’re optional to use.
    let orderedGrades: [Grade]
    let existingPlayers: [Player]
    let onRequestDelete: (Player) -> Void

    @State private var draftName: String = ""
    @State private var draftNumberText: String = ""

    init(
        player: Player,
        orderedGrades: [Grade],
        existingPlayers: [Player],
        onRequestDelete: @escaping (Player) -> Void
    ) {
        self.player = player
        self.orderedGrades = orderedGrades
        self.existingPlayers = existingPlayers
        self.onRequestDelete = onRequestDelete

        _draftName = State(initialValue: player.name)
        _draftNumberText = State(initialValue: player.number.map(String.init) ?? "")
    }

    private var nameTrimmed: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameIsDuplicate: Bool {
        let lower = nameTrimmed.lowercased()
        return existingPlayers.contains { $0.id != player.id && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lower }
    }

    private var parsedNumber: Int? {
        let t = draftNumberText.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        return Int(t)
    }

    private var canSave: Bool {
        !nameTrimmed.isEmpty && !nameIsDuplicate
    }

    var body: some View {
        List {
            Section("Player") {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("Name", text: $draftName)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                if nameIsDuplicate {
                    Text("That name already exists.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    Text("Number")
                    Spacer()
                    TextField("Optional", text: $draftNumberText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }
            }

            Section("Grades") {
                if orderedGrades.isEmpty {
                    Text("No grades available.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(orderedGrades) { g in
                        Toggle(isOn: Binding(
                            get: { player.gradeIDs.contains(g.id) },
                            set: { isOn in
                                if isOn {
                                    if !player.gradeIDs.contains(g.id) { player.gradeIDs.append(g.id) }
                                } else {
                                    player.gradeIDs.removeAll { $0 == g.id }
                                }
                            }
                        )) {
                            Text(g.name)
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    onRequestDelete(player)
                } label: {
                    Label("Delete player", systemImage: "trash")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Edit Player")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    let split = Player.splitName(nameTrimmed)
                    player.setName(firstName: split.first, lastName: split.last)
                    player.number = parsedNumber
                    try? dataContext.save()
                    dismiss()
                }
                .disabled(!canSave)
            }

            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
