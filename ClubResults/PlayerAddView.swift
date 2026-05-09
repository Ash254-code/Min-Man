import SwiftUI

struct PlayerAddView: View {
    @Environment(\.dismiss) private var dismiss

    let activeGrades: [Grade]
    let existingPlayers: [Player]
    let preselectedGradeID: UUID?
    let onSave: (String, String, String, Int?, [UUID]) -> Void
    let onSaveComplete: (() -> Void)?

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var preferredName: String = ""
    @State private var numberText: String = ""
    @State private var selectedGradeIDs: Set<UUID> = []
    @State private var nameValidationMessage: String?

    init(
        activeGrades: [Grade],
        existingPlayers: [Player],
        preselectedGradeID: UUID?,
        onSave: @escaping (String, String, String, Int?, [UUID]) -> Void,
        onSaveComplete: (() -> Void)? = nil
    ) {
        self.activeGrades = activeGrades
        self.existingPlayers = existingPlayers
        self.preselectedGradeID = preselectedGradeID
        self.onSave = onSave
        self.onSaveComplete = onSaveComplete
    }

    private var parsedNumber: Int? {
        let trimmed = numberText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return Int(trimmed)
    }

    private var numberIsValid: Bool {
        let trimmed = numberText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || Int(trimmed) != nil
    }

    private var canSave: Bool {
        numberIsValid && !cleanedFirstName.isEmpty && !cleanedLastName.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("First Name", text: $firstName)
                        .textInputAutocapitalization(.words)
                        .onChange(of: firstName) { _, _ in
                            nameValidationMessage = nil
                        }

                    TextField("Surname", text: $lastName)
                        .textInputAutocapitalization(.words)
                        .onChange(of: lastName) { _, _ in
                            nameValidationMessage = nil
                        }

                    TextField("Preferred Name", text: $preferredName)
                        .textInputAutocapitalization(.words)
                        .onChange(of: preferredName) { _, _ in
                            nameValidationMessage = nil
                        }

                    if let nameValidationMessage {
                        Text(nameValidationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Number") {
                    TextField("Optional", text: $numberText)
                        .keyboardType(.numberPad)

                    if !numberIsValid {
                        Text("Enter digits only.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Grades") {
                    if activeGrades.isEmpty {
                        Text("No active grades.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeGrades) { g in
                            Toggle(g.name, isOn: Binding(
                                get: { selectedGradeIDs.contains(g.id) },
                                set: { isOn in
                                    if isOn { selectedGradeIDs.insert(g.id) }
                                    else { selectedGradeIDs.remove(g.id) }
                                }
                            ))
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .clubGlassBackground()
            .navigationTitle("Add Player")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .saveButtonBehavior(isEnabled: canSave)
                }
            }
            .onAppear {
                if let gid = preselectedGradeID {
                    selectedGradeIDs = [gid]
                }
            }
        }
    }

    private var cleanedFirstName: String {
        firstName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private var cleanedLastName: String {
        lastName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private var cleanedPreferredName: String {
        preferredName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func save() {
        nameValidationMessage = nil

        guard !cleanedFirstName.isEmpty else {
            nameValidationMessage = "Please enter a first name."
            return
        }

        guard !cleanedLastName.isEmpty else {
            nameValidationMessage = "Please enter a surname."
            return
        }

        let duplicateKey = Player.duplicateMatchKey(firstName: cleanedFirstName, lastName: cleanedLastName)
        let exists = existingPlayers.contains { $0.duplicateMatchKey == duplicateKey }
        guard !exists else {
            nameValidationMessage = "A player with that first name and surname already exists."
            return
        }

        onSave(
            cleanedFirstName,
            cleanedLastName,
            cleanedPreferredName,
            parsedNumber,
            Array(selectedGradeIDs)
        )
        onSaveComplete?()
        dismiss()
    }
}
