import SwiftUI

struct PlayerAddView: View {
    @Environment(\.dismiss) private var dismiss

    let activeGrades: [Grade]
    let existingPlayers: [Player]
    let preselectedGradeID: UUID?
    let onSave: (String, [UUID]) -> Void

    @State private var name: String = ""
    @State private var numberText: String = ""
    @State private var selectedGradeIDs: Set<UUID> = []

    private var parsedNumber: Int? {
        let trimmed = numberText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return Int(trimmed)
    }

    private var numberIsValid: Bool {
        let trimmed = numberText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || Int(trimmed) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Player name", text: $name)
                        .textInputAutocapitalization(.words)
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
            .navigationTitle("Add Player")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(cleanedName.isEmpty || !numberIsValid)
                }
            }
            .onAppear {
                if let gid = preselectedGradeID {
                    selectedGradeIDs = [gid]
                }
            }
        }
    }

    private var cleanedName: String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func save() {
        guard !cleanedName.isEmpty else { return }

        let exists = existingPlayers.contains {
            $0.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .lowercased() == cleanedName.lowercased()
        }
        guard !exists else { return }

        onSave(cleanedName, Array(selectedGradeIDs))
        dismiss()
    }
}
