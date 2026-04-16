import SwiftUI
import SwiftData

struct StaffPickerField: View {

    let title: String
    let role: StaffRole
    let gradeID: UUID?

    @Binding var value: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var staffMembers: [StaffMember]

    @State private var showAdd = false
    @State private var newName = ""

    private var options: [String] {
        guard let gradeID else { return [] }

        return staffMembers
            .filter { $0.gradeID == gradeID && $0.role == role }
            .map { $0.name }
            .sorted()
    }

    private var trimmedNewName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveNewStaff: Bool {
        gradeID != nil && !trimmedNewName.isEmpty
    }

    private var fieldFont: Font {
        .system(size: horizontalSizeClass == .compact ? 20 : 24, weight: .regular)
    }

    var body: some View {

        HStack(spacing: 12) {
            Text(title)
                .font(fieldFont)
            Spacer()

            Menu {
                ForEach(options, id: \.self) { name in
                    Button(name) { value = name }
                }

                Divider()

                Button("Add new…") {
                    newName = ""
                    showAdd = true
                }

            } label: {
                Text(value.isEmpty ? "Select…" : value)
                    .font(fieldFont)
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
            }
        }
        .padding(.vertical, horizontalSizeClass == .compact ? 6 : 10)
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Name", text: $newName)
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
                            saveNewStaff(keepSheetOpen: true)
                        }
                        .buttonStyle(AddSheetActionButtonStyle(isEnabled: canSaveNewStaff))
                        .disabled(!canSaveNewStaff)

                        Button("Save & Close") {
                            saveNewStaff(keepSheetOpen: false)
                        }
                        .buttonStyle(AddSheetActionButtonStyle(isEnabled: canSaveNewStaff))
                        .disabled(!canSaveNewStaff)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 8)
                }
                .padding()
                .navigationTitle("Add \(title)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAdd = false }
                    }
                }
            }
            .appPopupStyle()
        }
    }

    private func saveNewStaff(keepSheetOpen: Bool) {
        guard let gradeID, canSaveNewStaff else { return }

        let newStaff = StaffMember(
            name: trimmedNewName,
            role: role,
            gradeID: gradeID
        )

        modelContext.insert(newStaff)
        value = trimmedNewName

        if keepSheetOpen {
            newName = ""
        } else {
            showAdd = false
        }
    }
}

private struct AddSheetActionButtonStyle: ButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(isEnabled ? Color.blue : Color.gray.opacity(0.45))
                    .opacity(configuration.isPressed && isEnabled ? 0.85 : 1)
            )
    }
}
