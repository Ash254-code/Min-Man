import SwiftUI
import SwiftData

struct PlayerAddView: View {
    @Environment(\.dismiss) private var dismiss

    let activeGrades: [Grade]
    let existingPlayers: [Player]
    let preselectedGradeID: UUID?
    let onSave: (String, [UUID]) -> Void

    @State private var name: String = ""
    @State private var selectedGradeIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Player name", text: $name)
                        .textInputAutocapitalization(.words)
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
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let gid = preselectedGradeID {
                    selectedGradeIDs = [gid]
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let exists = existingPlayers.contains {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed.lowercased()
        }
        guard !exists else { return }

        onSave(trimmed, Array(selectedGradeIDs))
        dismiss()
    }
}
