import SwiftUI
import SwiftData

struct PlayerEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext

    @Bindable var player: Player

    // These let PlayersView pass context.
    let orderedGrades: [Grade]
    let existingPlayers: [Player]

    @State private var draftName: String = ""
    @State private var draftNumberText: String = ""
    @State private var draftIsActive: Bool = true
    @State private var draftGradeIDs: [UUID] = []
    @State private var showDiscardWarning = false
    @State private var showDeletePrompt = false
    @State private var deleteCode = ""
    @State private var showWrongDeleteCode = false

    init(
        player: Player,
        orderedGrades: [Grade],
        existingPlayers: [Player]
    ) {
        self.player = player
        self.orderedGrades = orderedGrades
        self.existingPlayers = existingPlayers

        _draftName = State(initialValue: player.name)
        _draftNumberText = State(initialValue: player.number.map { String($0) } ?? "")
        _draftIsActive = State(initialValue: player.isActive)
        _draftGradeIDs = State(initialValue: player.gradeIDs)
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

    private var hasChanges: Bool {
        nameTrimmed != player.name.trimmingCharacters(in: .whitespacesAndNewlines) ||
        parsedNumber != player.number ||
        draftIsActive != player.isActive ||
        Set(draftGradeIDs) != Set(player.gradeIDs)
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

                Toggle("Active", isOn: $draftIsActive)
            }

            Section("Grades") {
                if orderedGrades.isEmpty {
                    Text("No grades available.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(orderedGrades) { g in
                        Toggle(isOn: Binding(
                            get: { draftGradeIDs.contains(g.id) },
                            set: { isOn in
                                if isOn {
                                    if !draftGradeIDs.contains(g.id) { draftGradeIDs.append(g.id) }
                                } else {
                                    draftGradeIDs.removeAll { $0 == g.id }
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
                    deleteCode = ""
                    showDeletePrompt = true
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
                    player.isActive = draftIsActive
                    player.gradeIDs = draftGradeIDs
                    try? dataContext.save()
                    dismiss()
                }
                .saveButtonBehavior(isEnabled: canSave && hasChanges)
            }

            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    if hasChanges {
                        showDiscardWarning = true
                    } else {
                        dismiss()
                    }
                }
            }
        }
        .alert("Discard changes?", isPresented: $showDiscardWarning) {
            Button("Keep Editing", role: .cancel) { }
            Button("Discard Changes", role: .destructive) { dismiss() }
        } message: {
            Text("You have unsaved changes.")
        }
        .alert("Enter delete code", isPresented: $showDeletePrompt) {
            SecureField("Code", text: $deleteCode)
            Button("Delete", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) {
                deleteCode = ""
            }
        } message: {
            Text("Deleting a player is permanent.")
        }
        .alert("Wrong code", isPresented: $showWrongDeleteCode) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Player was not deleted.")
        }
    }

    private func confirmDelete() {
        let trimmedCode = deleteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DeleteCodeStore.verify(trimmedCode) else {
            showDeletePrompt = false
            showWrongDeleteCode = true
            return
        }

        dataContext.delete(player)
        try? dataContext.save()
        dismiss()
    }
}
