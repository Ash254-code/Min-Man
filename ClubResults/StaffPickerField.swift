import SwiftUI
import SwiftData

struct StaffPickerField: View {

    let title: String
    let role: StaffRole
    let gradeID: UUID?

    @Binding var value: String

    @Environment(\.modelContext) private var modelContext
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

    var body: some View {

        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .regular))
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
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    TextField("Name", text: $newName)
                }
                .navigationTitle("Add \(title)")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            guard
                                let gradeID,
                                !newName.trimmingCharacters(in: .whitespaces).isEmpty
                            else { return }

                            let newStaff = StaffMember(
                                name: newName,
                                role: role,
                                gradeID: gradeID
                            )

                            modelContext.insert(newStaff)
                            value = newName
                            showAdd = false
                        }
                    }
                }
            }
        }
    }
}
