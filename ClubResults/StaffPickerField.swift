import SwiftUI
import SwiftData

struct StaffPickerField: View {

    let title: String
    let role: StaffRole
    let gradeID: UUID?

    @Binding var value: String

    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var staffMembers: [StaffMember]
    @Query(sort: [SortDescriptor(\Player.name)]) private var players: [Player]

    @State private var showAdd = false
    @State private var showChooser = false
    @State private var newName = ""
    @State private var chooserDetent: PresentationDetent = .large
    @State private var pendingDeletedOptionName: String?

    private var options: [String] {
        let savedForRole = StaffPickerNameStore.persistedNames(for: role, gradeID: gradeID)

        let namesFromDataStore = staffNamesForSelectedGrade
        let namesFromBoundarySelection = boundarySelectionPlayerNames

        return StaffPickerNameStore.visibleNames(
            from: namesFromDataStore + namesFromBoundarySelection + savedForRole,
            role: role,
            gradeID: gradeID
        )
    }

    private var staffNamesForSelectedGrade: [String] {
        guard let gradeID else { return [] }
        return staffMembers
            .filter { $0.gradeID == gradeID && $0.role == role }
            .map(\.name)
    }

    private var boundarySelectionPlayerNames: [String] {
        guard let gradeID else { return [] }
        guard role == .boundaryUmpire || role == .fieldUmpire || role == .waterBoy else { return [] }

        let mappings = SettingsBackupStore.loadBoundaryUmpireGradeMappings()
        let selectedGradeIDs = mappings[gradeID].flatMap { $0.isEmpty ? nil : $0 } ?? [gradeID]
        let selectedGradeIDSet = Set(selectedGradeIDs)

        return players
            .filter { !selectedGradeIDSet.isDisjoint(with: $0.gradeIDs) }
            .map(\.name)
    }

    private var trimmedNewName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveNewStaff: Bool {
        !trimmedNewName.isEmpty
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

    private var chooserExpandedDetent: PresentationDetent {
        PickerSheetPresentation.expandedDetent(isCompactLayout: isCompactLayout)
    }

    var body: some View {

        HStack(spacing: 12) {
            Text(title)
                .font(fieldFont)
            Spacer()

            Button {
                showChooser = true
            } label: {
                HStack(spacing: 8) {
                    Text(value.isEmpty ? "Select…" : value)
                        .font(fieldFont)
                        .foregroundStyle(value.isEmpty ? .secondary : .primary)
                        .lineLimit(1)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: horizontalSizeClass == .compact ? 13 : 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
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
        .sheet(isPresented: $showChooser, onDismiss: handleChooserDismissed) {
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) {
                                requestDeleteOption(name)
                            }
                        }
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
            .presentationDetents([.height(chooserHeight), chooserExpandedDetent], selection: $chooserDetent)
            .presentationDragIndicator(.visible)
            .onChange(of: options.count) { _, _ in
                if showChooser {
                    chooserDetent = chooserExpandedDetent
                }
            }
            .onChange(of: showChooser) { _, isPresented in
                if isPresented {
                    chooserDetent = chooserExpandedDetent
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
                        Button("Save") {
                            saveNewStaff()
                        }
                        .buttonStyle(.borderedProminent)
                        .saveButtonBehavior(isEnabled: canSaveNewStaff)
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



    private func saveNewStaff() {
        guard canSaveNewStaff else { return }

        let cleanedName = trimmedNewName
        StaffPickerNameStore.persistName(cleanedName, for: role, gradeID: gradeID)

        if let gradeID {
            let nameAlreadyExists = staffMembers.contains { member in
                member.gradeID == gradeID
                    && member.role == role
                    && member.name.compare(cleanedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }

            if !nameAlreadyExists {
                let newStaff = StaffMember(
                    name: cleanedName,
                    role: role,
                    gradeID: gradeID
                )
                dataContext.insert(newStaff)
            }
        }

        value = cleanedName
        showAdd = false
    }

    private func deleteOption(_ name: String) {
        StaffPickerNameStore.hideName(name, for: role, gradeID: gradeID)
        if value.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            value = ""
        }
    }

    private func requestDeleteOption(_ name: String) {
        pendingDeletedOptionName = name
        showChooser = false
    }

    private func handleChooserDismissed() {
        guard let name = pendingDeletedOptionName else { return }
        pendingDeletedOptionName = nil
        deleteOption(name)
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

enum StaffPickerNameStore {
    static func persistedNames(for role: StaffRole, gradeID: UUID?) -> [String] {
        guard let key = pickerNamesKey(for: role, gradeID: gradeID) else { return [] }
        let names = UserDefaults.standard.stringArray(forKey: key) ?? []
        return deduplicatedNames(from: names)
    }

    static func visibleNames(from names: [String], role: StaffRole, gradeID: UUID?) -> [String] {
        let hidden = hiddenNameSet(for: role, gradeID: gradeID)
        return deduplicatedNames(from: names).filter { !hidden.contains(normalized($0)) }
    }

    static func persistName(_ name: String, for role: StaffRole, gradeID: UUID?) {
        guard let key = pickerNamesKey(for: role, gradeID: gradeID) else { return }

        let cleanedName = cleaned(name)
        guard !cleanedName.isEmpty else { return }

        var names = UserDefaults.standard.stringArray(forKey: key) ?? []
        names.append(cleanedName)
        UserDefaults.standard.set(deduplicatedNames(from: names), forKey: key)

        removeHiddenName(cleanedName, for: role, gradeID: gradeID)
    }

    static func hideName(_ name: String, for role: StaffRole, gradeID: UUID?) {
        let cleanedName = cleaned(name)
        guard !cleanedName.isEmpty else { return }

        if let pickerKey = pickerNamesKey(for: role, gradeID: gradeID) {
            let currentNames = UserDefaults.standard.stringArray(forKey: pickerKey) ?? []
            let filteredNames = currentNames.filter {
                normalized($0) != normalized(cleanedName)
            }
            UserDefaults.standard.set(deduplicatedNames(from: filteredNames), forKey: pickerKey)
        }

        guard let hiddenKey = hiddenNamesKey(for: role, gradeID: gradeID) else { return }
        var hiddenNames = UserDefaults.standard.stringArray(forKey: hiddenKey) ?? []
        hiddenNames.append(cleanedName)
        UserDefaults.standard.set(deduplicatedNames(from: hiddenNames), forKey: hiddenKey)
    }

    static func isHidden(_ name: String, for role: StaffRole, gradeID: UUID?) -> Bool {
        let cleanedName = cleaned(name)
        guard !cleanedName.isEmpty else { return false }
        return hiddenNameSet(for: role, gradeID: gradeID).contains(normalized(cleanedName))
    }

    private static func removeHiddenName(_ name: String, for role: StaffRole, gradeID: UUID?) {
        guard let key = hiddenNamesKey(for: role, gradeID: gradeID) else { return }
        let cleanedName = cleaned(name)
        let filteredNames = (UserDefaults.standard.stringArray(forKey: key) ?? []).filter {
            normalized($0) != normalized(cleanedName)
        }
        UserDefaults.standard.set(deduplicatedNames(from: filteredNames), forKey: key)
    }

    private static func hiddenNameSet(for role: StaffRole, gradeID: UUID?) -> Set<String> {
        guard let key = hiddenNamesKey(for: role, gradeID: gradeID) else { return [] }
        let hiddenNames = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(hiddenNames.map(normalized))
    }

    private static func pickerNamesKey(for role: StaffRole, gradeID: UUID?) -> String? {
        guard let gradeID else { return nil }
        return "staffPickerNames.\(gradeID.uuidString).\(role.rawValue)"
    }

    private static func hiddenNamesKey(for role: StaffRole, gradeID: UUID?) -> String? {
        guard let gradeID else { return nil }
        return "staffPickerNames.hidden.\(gradeID.uuidString).\(role.rawValue)"
    }

    private nonisolated static func deduplicatedNames(from names: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []

        for rawName in names {
            let cleanedName = cleaned(rawName)
            guard !cleanedName.isEmpty else { continue }

            let foldedName = normalized(cleanedName)
            guard !seen.contains(foldedName) else { continue }

            seen.insert(foldedName)
            unique.append(cleanedName)
        }

        return unique.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private nonisolated static func cleaned(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func normalized(_ name: String) -> String {
        cleaned(name).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
