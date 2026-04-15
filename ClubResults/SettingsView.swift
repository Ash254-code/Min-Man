import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Grade.name)]) private var grades: [Grade]

    @State private var showAddGrade = false
    @State private var newGradeName = ""

    private var activeGrades: [Grade] {
        grades.filter { $0.isActive }
    }

    private var trimmedGradeName: String {
        newGradeName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveGrade: Bool {
        let name = trimmedGradeName
        guard !name.isEmpty else { return false }
        return !activeGrades.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Drag to reorder grades")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    newGradeName = ""
                    showAddGrade = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                        Text("Add Grade")
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                .buttonStyle(.plain)

                List {
                    ForEach(activeGrades) { grade in
                        Text(grade.name)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .navigationTitle("Club Grades")
            .sheet(isPresented: $showAddGrade) {
                addGradeSheet
            }
        }
    }

    private var addGradeSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Grade name", text: $newGradeName)
                    .textInputAutocapitalization(.words)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )

                Spacer()

                HStack(spacing: 12) {
                    Button("Save & Add Another") {
                        saveGrade(keepSheetOpen: true)
                    }
                    .buttonStyle(PopupSaveButtonStyle(isEnabled: canSaveGrade))
                    .disabled(!canSaveGrade)

                    Button("Save & Close") {
                        saveGrade(keepSheetOpen: false)
                    }
                    .buttonStyle(PopupSaveButtonStyle(isEnabled: canSaveGrade))
                    .disabled(!canSaveGrade)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(20)
            .navigationTitle("Add Grade")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAddGrade = false
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.45)])
    }

    private func saveGrade(keepSheetOpen: Bool) {
        guard canSaveGrade else { return }

        modelContext.insert(Grade(name: trimmedGradeName, isActive: true))

        if keepSheetOpen {
            newGradeName = ""
        } else {
            showAddGrade = false
        }
    }
}

private struct PopupSaveButtonStyle: ButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.72))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(isEnabled ? Color.blue : Color.gray.opacity(0.45))
                    .opacity(configuration.isPressed && isEnabled ? 0.85 : 1)
            )
    }
}
