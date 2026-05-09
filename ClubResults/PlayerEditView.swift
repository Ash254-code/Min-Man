import SwiftUI
import SwiftData

struct PlayerEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext

    @Bindable var player: Player

    // These let PlayersView pass context.
    let orderedGrades: [Grade]
    let existingPlayers: [Player]
    let onSaveComplete: (() -> Void)?

    @State private var draftFirstName: String = ""
    @State private var draftLastName: String = ""
    @State private var draftPreferredName: String = ""
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
        existingPlayers: [Player],
        onSaveComplete: (() -> Void)? = nil
    ) {
        let split = Player.splitName(player.name)
        self.player = player
        self.orderedGrades = orderedGrades
        self.existingPlayers = existingPlayers
        self.onSaveComplete = onSaveComplete

        _draftFirstName = State(initialValue: player.firstName.isEmpty ? split.first : player.firstName)
        _draftLastName = State(initialValue: player.lastName.isEmpty ? split.last : player.lastName)
        _draftPreferredName = State(initialValue: player.preferredName)
        _draftNumberText = State(initialValue: player.number.map { String($0) } ?? "")
        _draftIsActive = State(initialValue: player.isActive)
        _draftGradeIDs = State(initialValue: player.gradeIDs)
    }

    private var firstNameTrimmed: String {
        draftFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var lastNameTrimmed: String {
        draftLastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var preferredNameTrimmed: String {
        draftPreferredName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameIsDuplicate: Bool {
        let duplicateKey = Player.duplicateMatchKey(firstName: firstNameTrimmed, lastName: lastNameTrimmed)
        return existingPlayers.contains {
            $0.id != player.id && $0.duplicateMatchKey == duplicateKey
        }
    }

    private var parsedNumber: Int? {
        let t = draftNumberText.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        return Int(t)
    }

    private var canSave: Bool {
        !firstNameTrimmed.isEmpty && !lastNameTrimmed.isEmpty && !nameIsDuplicate
    }

    private var hasChanges: Bool {
        firstNameTrimmed != player.firstName.trimmingCharacters(in: .whitespacesAndNewlines) ||
        lastNameTrimmed != player.lastName.trimmingCharacters(in: .whitespacesAndNewlines) ||
        preferredNameTrimmed != player.preferredName.trimmingCharacters(in: .whitespacesAndNewlines) ||
        parsedNumber != player.number ||
        draftIsActive != player.isActive ||
        Set(draftGradeIDs) != Set(player.gradeIDs)
    }

    var body: some View {
        List {
            Section("Player") {
                HStack {
                    Text("First Name")
                    Spacer()
                    TextField("First Name", text: $draftFirstName)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                HStack {
                    Text("Surname")
                    Spacer()
                    TextField("Surname", text: $draftLastName)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                HStack {
                    Text("Preferred Name")
                    Spacer()
                    TextField("Optional", text: $draftPreferredName)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                if nameIsDuplicate {
                    Text("A player with that first name and surname already exists.")
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
        .background(Color.clear)
        .clubGlassBackground()
        .navigationTitle("Edit Player")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    player.setName(
                        firstName: firstNameTrimmed,
                        lastName: lastNameTrimmed,
                        preferredName: preferredNameTrimmed
                    )
                    player.number = parsedNumber
                    player.isActive = draftIsActive
                    player.gradeIDs = draftGradeIDs
                    try? dataContext.save()
                    onSaveComplete?()
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
