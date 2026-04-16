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
    @State private var showChooser = false
    @State private var newName = ""
    @State private var chooserDetent: PresentationDetent = .large

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

    private var chooserTitleFont: Font {
        .system(size: horizontalSizeClass == .compact ? 24 : 28, weight: .semibold)
    }

    private var chooserRowHeight: CGFloat { horizontalSizeClass == .compact ? 56 : 72 }

    private var chooserHeaderAndPaddingHeight: CGFloat { horizontalSizeClass == .compact ? 128 : 148 }

    private var chooserOptionsCount: Int {
        options.count + 2 // "Select…" + "Add New"
    }

    private var isCompactLayout: Bool { horizontalSizeClass == .compact }

    private var chooserHeight: CGFloat {
        PickerSheetPresentation.preferredHeight(
            optionCount: chooserOptionsCount,
            rowHeight: chooserRowHeight,
            chromeHeight: chooserHeaderAndPaddingHeight,
            minVisibleRows: 3,
            isCompactLayout: isCompactLayout
        )
    }

    var body: some View {

        HStack(spacing: 12) {
            Text(title)
                .font(fieldFont)
            Spacer()

            Button {
                showChooser = true
            } label: {
                Text(value.isEmpty ? "Select…" : value)
                    .font(fieldFont)
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .padding(.horizontal, horizontalSizeClass == .compact ? 14 : 18)
                    .padding(.vertical, horizontalSizeClass == .compact ? 10 : 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
            }
            .buttonStyle(.plain)
            .disabled(gradeID == nil)
        }
        .padding(.vertical, horizontalSizeClass == .compact ? 6 : 10)
        .sheet(isPresented: $showChooser) {
            NavigationStack {
                List {
                    Button {
                        value = ""
                        showChooser = false
                    } label: {
                        chooserRow(title: "Select…", selected: value.isEmpty)
                    }
                    .buttonStyle(.plain)

                    ForEach(options, id: \.self) { name in
                        Button {
                            value = name
                            showChooser = false
                        } label: {
                            chooserRow(title: name, selected: value == name)
                        }
                        .buttonStyle(.plain)
                    }

                    Section {
                        Button {
                            showChooser = false
                            newName = ""
                            DispatchQueue.main.async {
                                showAdd = true
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.tint)
                                Text("Add New")
                                    .font(.system(size: horizontalSizeClass == .compact ? 22 : 26, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                            .padding(.vertical, horizontalSizeClass == .compact ? 8 : 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .environment(\.defaultMinListRowHeight, horizontalSizeClass == .compact ? 56 : 72)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showChooser = false }
                    }
                }
            }
            .presentationDetents([.height(chooserHeight), .large], selection: $chooserDetent)
            .presentationDragIndicator(.visible)
            .onAppear {
                chooserDetent = .height(chooserHeight)
            }
            .onChange(of: options.count) { _, _ in
                chooserDetent = .height(chooserHeight)
            }
            .onChange(of: showChooser) { _, isPresented in
                if isPresented {
                    chooserDetent = .height(chooserHeight)
                }
            }
        }
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

    @ViewBuilder
    private func chooserRow(title: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(chooserTitleFont)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: horizontalSizeClass == .compact ? 22 : 26, weight: .semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, horizontalSizeClass == .compact ? 8 : 12)
        .contentShape(Rectangle())
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
