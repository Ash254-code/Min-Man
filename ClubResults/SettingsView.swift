import SwiftUI
import SwiftData
import PDFKit
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext
    @State private var saveErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ClubGradesSettingsView()
                    } label: {
                        settingsRow(title: "Club Grades", icon: "list.number")
                    }

                    NavigationLink {
                        BoundaryUmpiresSettingsView()
                    } label: {
                        settingsRow(title: "Boundary Umpires", icon: "flag.pattern.checkered")
                    }

                    NavigationLink {
                        AppAppearanceSettingsView()
                    } label: {
                        settingsRow(title: "App Appearance", icon: "circle.lefthalf.filled")
                    }

                    NavigationLink {
                        TeamsAndVenuesSettingsView()
                    } label: {
                        settingsRow(title: "Teams & Venues", icon: "flag.2.crossed")
                    }

                    NavigationLink {
                        ReportsSettingsView()
                    } label: {
                        settingsRow(title: "Reports", icon: "doc.text")
                    }

                    NavigationLink {
                        ContactsSettingsView()
                    } label: {
                        settingsRow(title: "Contacts", icon: "person.crop.rectangle")
                    }
                } header: {
                    Text("Settings")
                }

                Section {
                    NavigationLink {
                        AdminNameResetView()
                    } label: {
                        settingsRow(title: "Clear Saved Picker Names", icon: "trash")
                    }

                    NavigationLink {
                        BackupAndRestoreSettingsView()
                    } label: {
                        settingsRow(title: "Backup & Restore", icon: "externaldrive.badge.icloud")
                    }
                } header: {
                    Text("Admin")
                }
            }
            .navigationTitle("Settings")
            .task {
                seedInitialGradesIfNeeded()
            }
            .alert(
                "Save Error",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    saveErrorMessage = nil
                }
            } message: {
                Text(saveErrorMessage ?? "An unknown error occurred.")
            }
        }
    }

    @ViewBuilder
    private func settingsRow(title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
        }
    }

    private func seedInitialGradesIfNeeded() {
        let existing = (try? dataContext.fetch(FetchDescriptor<Grade>())) ?? []
        guard existing.isEmpty else { return }

        let defaults = [
            "A Grade",
            "B Grade",
            "Under 17's",
            "Under 14's",
            "Under 12's",
            "Under 9's"
        ]

        for (index, name) in defaults.enumerated() {
            dataContext.insert(Grade(name: name, isActive: true, displayOrder: index))
        }

        do {
            try dataContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}

private struct BackupAndRestoreSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var shareURL: URL?
    @State private var exportSuccessMessage: String?
    @State private var exportErrorMessage: String?
    @State private var isExporting = false
    @State private var isImportPickerPresented = false
    @State private var pendingImportURL: URL?
    @State private var pendingImportEnvelope: AppBackupEnvelope?
    @State private var importSuccessMessage: String?
    @State private var importErrorMessage: String?
    @State private var isImporting = false

    var body: some View {
        Form {
            Section {
                Text("Creates a full backup file of all saved data so it can be stored safely before updates or major changes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    exportAllData()
                } label: {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                        Text(isExporting ? "Creating Backup…" : "Export All Data")
                    }
                }
                .disabled(isExporting)

                Button(role: .destructive) {
                    isImportPickerPresented = true
                } label: {
                    HStack {
                        if isImporting {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                        Text(isImporting ? "Importing…" : "Import Backup File")
                    }
                }
                .disabled(isImporting || isExporting)
            } header: {
                Text("Data Safety")
            } footer: {
                if let exportSuccessMessage {
                    Text(exportSuccessMessage)
                        .foregroundStyle(.secondary)
                } else if let importSuccessMessage {
                    Text(importSuccessMessage)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Export creates a full JSON backup. Import restores a backup and replaces all current app data.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Backup & Restore")
        .fileImporter(
            isPresented: $isImportPickerPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportSelection(result)
        }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { shouldPresent in
                if !shouldPresent { shareURL = nil }
            }
        )) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
        .alert(
            "Export Failed",
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                exportErrorMessage = nil
            }
        } message: {
            Text(exportErrorMessage ?? "An unknown error occurred.")
        }
        .alert(
            "Replace Existing Data?",
            isPresented: Binding(
                get: { pendingImportEnvelope != nil && pendingImportURL != nil },
                set: { shouldPresent in
                    if !shouldPresent {
                        pendingImportEnvelope = nil
                        pendingImportURL = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingImportEnvelope = nil
                pendingImportURL = nil
            }
            Button("Import", role: .destructive) {
                confirmImport()
            }
        } message: {
            if let envelope = pendingImportEnvelope {
                Text(
                    """
                    This will replace all current data with the selected backup.

                    Players: \(envelope.itemCounts.players)
                    Games: \(envelope.itemCounts.games)
                    Grades: \(envelope.itemCounts.grades)
                    Exported: \(envelope.exportedAt.formatted(date: .abbreviated, time: .shortened))
                    """
                )
            }
        }
        .alert(
            "Import Failed",
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                importErrorMessage = nil
            }
        } message: {
            Text(importErrorMessage ?? "An unknown error occurred.")
        }
    }

    private func exportAllData() {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }

        do {
            let result = try AppBackupService.createFullBackupFile(modelContext: modelContext)
            shareURL = result.fileURL
            exportSuccessMessage = """
            Backup ready: \(result.fileURL.lastPathComponent)
            \(ByteCountFormatter.string(fromByteCount: Int64(result.fileSizeBytes), countStyle: .file)) • \
            \(result.itemCounts.players) players • \(result.itemCounts.games) games • \(result.itemCounts.grades) grades
            """
            importSuccessMessage = nil
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            do {
                guard url.startAccessingSecurityScopedResource() else {
                    throw AppBackupImportError.invalidFileType
                }
                defer { url.stopAccessingSecurityScopedResource() }
                pendingImportEnvelope = try AppBackupService.previewBackupFile(url: url)
                pendingImportURL = url
            } catch {
                importErrorMessage = error.localizedDescription
            }
        case let .failure(error):
            importErrorMessage = error.localizedDescription
        }
    }

    private func confirmImport() {
        guard let url = pendingImportURL else { return }
        pendingImportEnvelope = nil
        pendingImportURL = nil

        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        do {
            guard url.startAccessingSecurityScopedResource() else {
                throw AppBackupImportError.invalidFileType
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let result = try AppBackupService.importFullBackupFile(url: url, modelContext: modelContext)
            importSuccessMessage = """
            Backup imported on \(result.importedAt.formatted(date: .abbreviated, time: .shortened))
            \(result.itemCounts.players) players • \(result.itemCounts.games) games • \(result.itemCounts.grades) grades
            """
            exportSuccessMessage = nil
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }
}

private struct AdminNameResetView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext
    @Query private var grades: [Grade]
    @Query private var staffMembers: [StaffMember]

    @State private var selectedGradeIDs: Set<UUID> = []
    @State private var selectedPickerTypes: Set<AdminPickerType> = Set(AdminPickerType.allCases)
    @State private var showConfirmClear = false
    @State private var clearFeedbackMessage: String?

    private var orderedGrades: [Grade] {
        orderedGradesForDisplay(resolvedConfiguredGrades(from: grades), includeInactive: true)
    }

    private var canClear: Bool {
        !selectedGradeIDs.isEmpty && !selectedPickerTypes.isEmpty
    }

    var body: some View {
        List {
            Section {
                if orderedGrades.isEmpty {
                    Text("No grades available.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(orderedGrades) { grade in
                        Button {
                            toggleGrade(grade.id)
                        } label: {
                            checkboxRow(
                                title: grade.name,
                                isSelected: selectedGradeIDs.contains(grade.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Grades")
            } footer: {
                if !orderedGrades.isEmpty {
                    sectionBulkSelectionControls(
                        onSelectAll: selectAllGrades,
                        onUnselectAll: unselectAllGrades
                    )
                }
            }

            Section {
                ForEach(AdminPickerType.allCases) { pickerType in
                    Button {
                        togglePickerType(pickerType)
                    } label: {
                        checkboxRow(
                            title: pickerType.title,
                            isSelected: selectedPickerTypes.contains(pickerType)
                        )
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Pickers")
            } footer: {
                sectionBulkSelectionControls(
                    onSelectAll: selectAllPickerTypes,
                    onUnselectAll: unselectAllPickerTypes
                )
            }

            Section {
                Button("Clear Selected Names", role: .destructive) {
                    showConfirmClear = true
                }
                .disabled(!canClear)
            } footer: {
                if let clearFeedbackMessage {
                    Text(clearFeedbackMessage)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Select one or more grades and picker types, then clear.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Admin")
        .alert("Clear Saved Names?", isPresented: $showConfirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearSelections()
            }
        } message: {
            Text("This will remove saved picker names for the selected grades and picker types.")
        }
        .onAppear {
            if selectedGradeIDs.isEmpty {
                selectedGradeIDs = Set(orderedGrades.map(\.id))
            }
        }
    }

    private func toggleGrade(_ gradeID: UUID) {
        if selectedGradeIDs.contains(gradeID) {
            selectedGradeIDs.remove(gradeID)
        } else {
            selectedGradeIDs.insert(gradeID)
        }
    }

    private func togglePickerType(_ pickerType: AdminPickerType) {
        if selectedPickerTypes.contains(pickerType) {
            selectedPickerTypes.remove(pickerType)
        } else {
            selectedPickerTypes.insert(pickerType)
        }
    }

    private func selectAllGrades() {
        selectedGradeIDs = Set(orderedGrades.map(\.id))
    }

    private func unselectAllGrades() {
        selectedGradeIDs.removeAll()
    }

    private func selectAllPickerTypes() {
        selectedPickerTypes = Set(AdminPickerType.allCases)
    }

    private func unselectAllPickerTypes() {
        selectedPickerTypes.removeAll()
    }

    private func clearSelections() {
        guard canClear else { return }

        let selectedRoles = Set(selectedPickerTypes.map(\.role))
        let selectedLastSelectionFields = selectedPickerTypes.flatMap(\.lastSelectionFieldKeys)
        let selectedGradeIDs = self.selectedGradeIDs

        let matchingStaffMembers = staffMembers.filter {
            selectedGradeIDs.contains($0.gradeID) && selectedRoles.contains($0.role)
        }

        for staffMember in matchingStaffMembers {
            dataContext.delete(staffMember)
        }

        for gradeID in selectedGradeIDs {
            for fieldKey in selectedLastSelectionFields {
                let key = "lastStaffSelection.\(gradeID.uuidString).\(fieldKey)"
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        do {
            try dataContext.save()
            let removedCount = matchingStaffMembers.count
            clearFeedbackMessage = "Cleared \(removedCount) saved name\(removedCount == 1 ? "" : "s")."
        } catch {
            clearFeedbackMessage = "Could not clear names: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func checkboxRow(title: String, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func sectionBulkSelectionControls(
        onSelectAll: @escaping () -> Void,
        onUnselectAll: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            Button("Select All", action: onSelectAll)
                .buttonStyle(.plain)
            Button("Unselect All", action: onUnselectAll)
                .buttonStyle(.plain)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.top, 8)
    }
}

private enum AdminPickerType: String, CaseIterable, Identifiable, Hashable {
    case headCoach
    case assistantCoach
    case teamManager
    case runner
    case goalUmpire
    case fieldUmpire
    case trainer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .headCoach: return "Head Coach"
        case .assistantCoach: return "Assistant Coach"
        case .teamManager: return "Team Manager"
        case .runner: return "Runner"
        case .goalUmpire: return "Goal Umpire"
        case .fieldUmpire: return "Field Umpire"
        case .trainer: return "Trainers"
        }
    }

    var role: StaffRole {
        switch self {
        case .headCoach: return .headCoach
        case .assistantCoach: return .assistantCoach
        case .teamManager: return .teamManager
        case .runner: return .runner
        case .goalUmpire: return .goalUmpire
        case .fieldUmpire: return .fieldUmpire
        case .trainer: return .trainer
        }
    }

    var lastSelectionFieldKeys: [String] {
        switch self {
        case .headCoach: return ["headCoach"]
        case .assistantCoach: return ["assistantCoach"]
        case .teamManager: return ["teamManager"]
        case .runner: return ["runner"]
        case .goalUmpire: return ["goalUmpire"]
        case .fieldUmpire: return ["fieldUmpire"]
        case .trainer: return ["trainer1", "trainer2", "trainer3", "trainer4"]
        }
    }
}

private struct BoundaryUmpiresSettingsView: View {
    @Query private var grades: [Grade]
    @State private var mappings: [UUID: [UUID]] = [:]

    private var orderedGrades: [Grade] {
        orderedGradesForDisplay(resolvedConfiguredGrades(from: grades), includeInactive: true)
    }

    var body: some View {
        List {
            ForEach(orderedGrades) { grade in
                NavigationLink {
                    boundaryGradeSelectionView(for: grade)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(grade.name)

                        Text(mappingSummary(for: grade.id))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Boundary Umpires")
        .task {
            mappings = SettingsBackupStore.loadBoundaryUmpireGradeMappings()
            ensureMissingMappingsDefaultToSelf()
            SettingsBackupStore.saveBoundaryUmpireGradeMappings(mappings)
        }
    }

    @ViewBuilder
    private func boundaryGradeSelectionView(for gameGrade: Grade) -> some View {
        List {
            ForEach(orderedGrades) { option in
                Button {
                    toggleBoundaryGrade(option.id, for: gameGrade.id)
                } label: {
                    HStack {
                        Text(option.name)
                        Spacer()
                        if selectedBoundaryGradeIDs(for: gameGrade.id).contains(option.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .navigationTitle(gameGrade.name)
    }

    private func selectedBoundaryGradeIDs(for gameGradeID: UUID) -> [UUID] {
        let selected = mappings[gameGradeID] ?? [gameGradeID]
        if selected.isEmpty {
            return [gameGradeID]
        }
        return selected
    }

    private func toggleBoundaryGrade(_ boundaryGradeID: UUID, for gameGradeID: UUID) {
        var selected = selectedBoundaryGradeIDs(for: gameGradeID)
        if let index = selected.firstIndex(of: boundaryGradeID) {
            selected.remove(at: index)
        } else {
            selected.append(boundaryGradeID)
        }

        if selected.isEmpty {
            selected = [gameGradeID]
        }

        mappings[gameGradeID] = selected
        SettingsBackupStore.saveBoundaryUmpireGradeMappings(mappings)
    }

    private func mappingSummary(for gameGradeID: UUID) -> String {
        let selectedIDs = selectedBoundaryGradeIDs(for: gameGradeID)
        let selectedNames = orderedGrades
            .filter { selectedIDs.contains($0.id) }
            .map(\.name)

        if selectedNames.isEmpty {
            return "Boundary players from: \(orderedGrades.first(where: { $0.id == gameGradeID })?.name ?? "This grade")"
        }

        return "Boundary players from: \(selectedNames.joined(separator: ", "))"
    }

    private func ensureMissingMappingsDefaultToSelf() {
        for grade in orderedGrades {
            let selected = mappings[grade.id] ?? []
            mappings[grade.id] = selected.isEmpty ? [grade.id] : selected
        }
    }
}

private struct ClubGradesSettingsView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext

    @State private var grades: [Grade] = []
    @Query private var players: [Player]
    @Query private var games: [Game]
    @Query private var reportRecipients: [ReportRecipient]

    @State private var showAddGrade = false
    @State private var newGradeDraft = NewGradeDraft()

    @State private var gradeEditing: Grade?
    @State private var editGradeName = ""

    @State private var deletionErrorMessage: String?
    @State private var showDeletionError = false
    @State private var saveErrorMessage: String?

    private var sortedGrades: [Grade] {
        orderedGradesForDisplay(grades, includeInactive: true)
    }

    var body: some View {
        List {
            Section {
                ForEach(sortedGrades) { grade in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(grade.name)
                            if !grade.isActive {
                                Text("Inactive")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        gradeEditing = grade
                        editGradeName = grade.name
                    }
                }
                .onMove(perform: moveGrades)

                Button {
                    newGradeDraft = NewGradeDraft()
                    showAddGrade = true
                } label: {
                    Label("Add Grade", systemImage: "plus")
                }
            } header: {
                Text("Grades")
            } footer: {
                Text("Grades are used in players, games and reports. Reorder to control display order.")
            }
        }
        .navigationTitle("Club Grades")
        .toolbar { EditButton() }
        .alert("Delete Error", isPresented: $showDeletionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deletionErrorMessage ?? "Unable to delete this grade.")
        }
        .alert(
            "Save Error",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
        .sheet(isPresented: $showAddGrade) {
            AddGradeWizardView(draft: $newGradeDraft) { draft in
                if addGrade(using: draft) {
                    showAddGrade = false
                }
            } onCancel: {
                showAddGrade = false
            }
            .appPopupStyle()
        }
        .sheet(item: $gradeEditing) { grade in
            NavigationStack {
                Form {
                    TextField("Grade name", text: $editGradeName)
                        .textInputAutocapitalization(.words)

                    Section {
                        Label("Coaches", systemImage: "person.2.fill")
                            .font(.subheadline.weight(.semibold))
                        Toggle("Head Coach", isOn: bind(grade, \.asksHeadCoach))
                        Toggle("Assistant Coach", isOn: bind(grade, \.asksAssistantCoach))
                        Toggle("Team Manager", isOn: bind(grade, \.asksTeamManager))
                        Toggle("Runner", isOn: bind(grade, \.asksRunner))
                    } header: {
                        Text("New Game Wizard Fields")
                    }

                    Section {
                        Label("Officials", systemImage: "flag.fill")
                            .font(.subheadline.weight(.semibold))
                        Toggle("Goal Umpire", isOn: bind(grade, \.asksGoalUmpire))
                        Toggle("Field Umpire", isOn: bind(grade, \.asksFieldUmpire))
                        Toggle("Boundary Umpire 1", isOn: bind(grade, \.asksBoundaryUmpire1))
                        Toggle("Boundary Umpire 2", isOn: bind(grade, \.asksBoundaryUmpire2))
                    }

                    Section {
                        Label("Trainers", systemImage: "cross.case.fill")
                            .font(.subheadline.weight(.semibold))
                        Toggle("Trainer 1", isOn: bind(grade, \.asksTrainer1))
                        Toggle("Trainer 2", isOn: bind(grade, \.asksTrainer2))
                        Toggle("Trainer 3", isOn: bind(grade, \.asksTrainer3))
                        Toggle("Trainer 4", isOn: bind(grade, \.asksTrainer4))
                    }

                    Section {
                        Label("Awards", systemImage: "rosette")
                            .font(.subheadline.weight(.semibold))
                        Toggle("Notes", isOn: bind(grade, \.asksNotes))
                        Toggle("Score", isOn: bind(grade, \.asksScore))
                        Toggle("Goal Kickers", isOn: bind(grade, \.asksGoalKickers))
                        Picker("Best Players", selection: bind(grade, \.bestPlayersCount)) {
                            ForEach(1...10, id: \.self) { count in
                                Text("\(count)").tag(count)
                            }
                        }
                        Toggle("Guest Best & Fairest Votes Scan", isOn: bind(grade, \.asksGuestBestFairestVotesScan))
                    }

                    Section {
                        Label("Settings", systemImage: "gearshape.fill")
                            .font(.subheadline.weight(.semibold))
                        Toggle("Notes", isOn: bind(grade, \.asksNotes))
                        Toggle("Live Game View", isOn: bind(grade, \.allowsLiveGameView))
                        Picker(
                            "Length of Quarters",
                            selection: Binding(
                                get: { grade.quarterLengthMinutes },
                                set: { grade.quarterLengthMinutes = min(max($0, 10), 30) }
                            )
                        ) {
                            ForEach(10...30, id: \.self) { minute in
                                Text("\(minute) min").tag(minute)
                            }
                        }
                    }

                    Section {
                        Button(role: .destructive) {
                            if deleteGrade(grade) {
                                gradeEditing = nil
                            }
                        } label: {
                            Label("Delete Grade", systemImage: "trash")
                        }
                    }
                }
                .navigationTitle("Edit Grade")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { gradeEditing = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if saveEditedGrade() {
                                gradeEditing = nil
                            }
                        }
                        .disabled(isEditGradeSaveDisabled)
                    }
                }
            }
            .appPopupStyle()
        }
        .task {
            reloadGrades()
        }
    }

    private func bind(_ grade: Grade, _ keyPath: ReferenceWritableKeyPath<Grade, Bool>) -> Binding<Bool> {
        Binding(
            get: { grade[keyPath: keyPath] },
            set: { grade[keyPath: keyPath] = $0 }
        )
    }

    private func bind(_ grade: Grade, _ keyPath: ReferenceWritableKeyPath<Grade, Int>) -> Binding<Int> {
        Binding(
            get: { grade[keyPath: keyPath] },
            set: { grade[keyPath: keyPath] = min(max($0, 1), 10) }
        )
    }

    private func addGrade(using draft: NewGradeDraft) -> Bool {
        let name = clean(draft.name)
        guard !name.isEmpty else { return false }
        guard !grades.contains(where: { clean($0.name).lowercased() == name.lowercased() }) else { return false }

        let nextOrder = (grades.map(\.displayOrder).max() ?? -1) + 1
        let newGrade = Grade(
            name: name,
            isActive: true,
            displayOrder: nextOrder,
            asksHeadCoach: draft.asksHeadCoach,
            asksAssistantCoach: draft.asksAssistantCoach,
            asksTeamManager: draft.asksTeamManager,
            asksRunner: draft.asksRunner,
            asksGoalUmpire: draft.asksGoalUmpire,
            asksFieldUmpire: draft.asksFieldUmpire,
            asksBoundaryUmpire1: draft.asksBoundaryUmpire1,
            asksBoundaryUmpire2: draft.asksBoundaryUmpire2,
            asksTrainers: draft.hasAnyTrainerEnabled,
            asksTrainer1: draft.asksTrainer1,
            asksTrainer2: draft.asksTrainer2,
            asksTrainer3: draft.asksTrainer3,
            asksTrainer4: draft.asksTrainer4,
            asksNotes: draft.asksNotes,
            asksGoalKickers: draft.asksGoalKickers,
            bestPlayersCount: draft.bestPlayersCount,
            asksGuestBestFairestVotesScan: draft.asksGuestBestFairestVotesScan,
            allowsLiveGameView: draft.allowsLiveGameView,
            quarterLengthMinutes: draft.quarterLengthMinutes
        )
        dataContext.insert(newGrade)
        grades.append(newGrade)

        SettingsBackupStore.saveGrades(grades)
        saveContext()
        reloadGrades()
        return true
    }

    private func saveEditedGrade() -> Bool {
        guard let gradeEditing else { return false }

        let name = clean(editGradeName)
        guard !name.isEmpty else { return false }
        guard !grades.contains(where: { $0.id != gradeEditing.id && clean($0.name).lowercased() == name.lowercased() }) else { return false }

        gradeEditing.name = name
        gradeEditing.asksTrainers = gradeEditing.asksTrainer1 || gradeEditing.asksTrainer2 || gradeEditing.asksTrainer3 || gradeEditing.asksTrainer4
        SettingsBackupStore.saveGrades(grades)
        saveContext()
        reloadGrades()
        return true
    }

    private var isEditGradeSaveDisabled: Bool {
        guard let gradeEditing else { return true }
        let name = clean(editGradeName)
        guard !name.isEmpty else { return true }
        return grades.contains(where: { $0.id != gradeEditing.id && clean($0.name).lowercased() == name.lowercased() })
    }

    private func moveGrades(from source: IndexSet, to destination: Int) {
        var reordered = sortedGrades
        reordered.move(fromOffsets: source, toOffset: destination)

        for (index, grade) in reordered.enumerated() {
            grade.displayOrder = index
        }

        SettingsBackupStore.saveGrades(reordered)
        saveContext()
        reloadGrades()
    }

    private func deleteGrade(_ grade: Grade) -> Bool {
        if games.contains(where: { $0.gradeID == grade.id }) {
            deletionErrorMessage = "This grade has games attached. Reassign or remove those games first."
            showDeletionError = true
            return false
        }

        if players.contains(where: { $0.gradeIDs.contains(grade.id) }) {
            deletionErrorMessage = "This grade has players attached. Remove the grade from players first."
            showDeletionError = true
            return false
        }

        for recipient in reportRecipients where recipient.gradeID == grade.id {
            dataContext.delete(recipient)
        }

        dataContext.delete(grade)

        let remaining = orderedGradesForDisplay(
            grades.filter { $0.id != grade.id },
            includeInactive: true
        )

        for (index, item) in remaining.enumerated() {
            item.displayOrder = index
        }

        SettingsBackupStore.saveGrades(remaining)
        saveContext()
        reloadGrades()
        return true
    }

    private func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveContext() {
        do {
            try dataContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func reloadGrades() {
        do {
            let descriptor = FetchDescriptor<Grade>(
                sortBy: [
                    SortDescriptor(\Grade.displayOrder),
                    SortDescriptor(\Grade.name)
                ]
            )
            let fetched = try dataContext.fetch(descriptor)

            if fetched.isEmpty {
                let backups = SettingsBackupStore.loadGrades()
                if !backups.isEmpty {
                    grades = backups.map {
                        Grade(
                            id: $0.id,
                            name: $0.name,
                            isActive: $0.isActive,
                            displayOrder: $0.displayOrder,
                            asksHeadCoach: $0.asksHeadCoach,
                            asksAssistantCoach: $0.asksAssistantCoach,
                    asksTeamManager: $0.asksTeamManager,
                    asksRunner: $0.asksRunner,
                    asksGoalUmpire: $0.asksGoalUmpire,
                            asksFieldUmpire: $0.asksFieldUmpire,
                            asksBoundaryUmpire1: $0.asksBoundaryUmpire1,
                            asksBoundaryUmpire2: $0.asksBoundaryUmpire2,
                            asksTrainers: $0.asksTrainers,
                            asksTrainer1: $0.asksTrainer1,
                            asksTrainer2: $0.asksTrainer2,
                            asksTrainer3: $0.asksTrainer3,
                            asksTrainer4: $0.asksTrainer4,
                            asksNotes: $0.asksNotes,
                            asksScore: $0.asksScore,
                            asksLiveGameView: $0.asksLiveGameView,
                            asksGoalKickers: $0.asksGoalKickers,
                            bestPlayersCount: $0.bestPlayersCount,
                            asksGuestBestFairestVotesScan: $0.asksGuestBestFairestVotesScan,
                            allowsLiveGameView: $0.allowsLiveGameView,
                            quarterLengthMinutes: $0.quarterLengthMinutes
                        )
                    }

                    for item in backups {
                        dataContext.insert(
                            Grade(
                                id: item.id,
                                name: item.name,
                                isActive: item.isActive,
                                displayOrder: item.displayOrder,
                                asksHeadCoach: item.asksHeadCoach,
                                asksAssistantCoach: item.asksAssistantCoach,
                                asksTeamManager: item.asksTeamManager,
                                asksRunner: item.asksRunner,
                                asksGoalUmpire: item.asksGoalUmpire,
                                asksFieldUmpire: item.asksFieldUmpire,
                                asksBoundaryUmpire1: item.asksBoundaryUmpire1,
                                asksBoundaryUmpire2: item.asksBoundaryUmpire2,
                                asksTrainers: item.asksTrainers,
                                asksTrainer1: item.asksTrainer1,
                                asksTrainer2: item.asksTrainer2,
                                asksTrainer3: item.asksTrainer3,
                                asksTrainer4: item.asksTrainer4,
                                asksNotes: item.asksNotes,
                                asksScore: item.asksScore,
                                asksLiveGameView: item.asksLiveGameView,
                                asksGoalKickers: item.asksGoalKickers,
                                bestPlayersCount: item.bestPlayersCount,
                                asksGuestBestFairestVotesScan: item.asksGuestBestFairestVotesScan,
                                allowsLiveGameView: item.allowsLiveGameView,
                                quarterLengthMinutes: item.quarterLengthMinutes
                            )
                        )
                    }

                    try? dataContext.save()

                    let afterRestore = (try? dataContext.fetch(descriptor)) ?? []
                    if !afterRestore.isEmpty {
                        grades = afterRestore
                    }
                    return
                }
            }

            grades = fetched
            SettingsBackupStore.saveGrades(grades)
        } catch {
            saveErrorMessage = error.localizedDescription
            let backups = SettingsBackupStore.loadGrades()
            grades = backups.map {
                Grade(
                    id: $0.id,
                    name: $0.name,
                    isActive: $0.isActive,
                    displayOrder: $0.displayOrder,
                    asksHeadCoach: $0.asksHeadCoach,
                    asksAssistantCoach: $0.asksAssistantCoach,
                    asksTeamManager: $0.asksTeamManager,
                    asksRunner: $0.asksRunner,
                    asksGoalUmpire: $0.asksGoalUmpire,
                    asksFieldUmpire: $0.asksFieldUmpire,
                    asksBoundaryUmpire1: $0.asksBoundaryUmpire1,
                    asksBoundaryUmpire2: $0.asksBoundaryUmpire2,
                    asksTrainers: $0.asksTrainers,
                    asksTrainer1: $0.asksTrainer1,
                    asksTrainer2: $0.asksTrainer2,
                    asksTrainer3: $0.asksTrainer3,
                    asksTrainer4: $0.asksTrainer4,
                    asksNotes: $0.asksNotes,
                    asksScore: $0.asksScore,
                    asksLiveGameView: $0.asksLiveGameView,
                    asksGoalKickers: $0.asksGoalKickers,
                    bestPlayersCount: $0.bestPlayersCount,
                    asksGuestBestFairestVotesScan: $0.asksGuestBestFairestVotesScan,
                    allowsLiveGameView: $0.allowsLiveGameView,
                    quarterLengthMinutes: $0.quarterLengthMinutes
                )
            }
        }
    }
}

private struct AppAppearanceSettingsView: View {
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $appAppearance) {
                    ForEach(AppAppearance.allCases) { item in
                        Text(item.title).tag(item.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("App Appearance")
            }
        }
        .navigationTitle("App Appearance")
    }
}

private struct NewGradeDraft {
    var name = ""
    var asksHeadCoach = true
    var asksAssistantCoach = true
    var asksTeamManager = true
    var asksRunner = true
    var asksGoalUmpire = true
    var asksFieldUmpire = true
    var asksBoundaryUmpire1 = true
    var asksBoundaryUmpire2 = true
    var asksTrainer1 = true
    var asksTrainer2 = true
    var asksTrainer3 = true
    var asksTrainer4 = true
    var asksNotes = true
    var asksGoalKickers = true
    var bestPlayersCount = 6
    var asksGuestBestFairestVotesScan = false
    var allowsLiveGameView = true
    var quarterLengthMinutes = 20

    var hasAnyTrainerEnabled: Bool {
        asksTrainer1 || asksTrainer2 || asksTrainer3 || asksTrainer4
    }
}

private struct AddGradeWizardView: View {
    enum Step: Int {
        case gradeName
        case coaches
        case officials
        case trainers
        case awards
        case settings
    }

    @Binding var draft: NewGradeDraft
    let onSave: (NewGradeDraft) -> Void
    let onCancel: () -> Void

    @State private var step: Step = .gradeName

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .gradeName:
                    Section {
                        TextField("Grade name", text: $draft.name)
                            .textInputAutocapitalization(.words)
                    } header: {
                        Text("Grade")
                    }
                case .coaches:
                    Section {
                        Toggle("Head Coach", isOn: $draft.asksHeadCoach)
                        Toggle("Assistant Coach", isOn: $draft.asksAssistantCoach)
                        Toggle("Team Manager", isOn: $draft.asksTeamManager)
                        Toggle("Runner", isOn: $draft.asksRunner)
                    } header: {
                        Text("Coaches")
                    }
                case .officials:
                    Section {
                        Toggle("Goal Umpire", isOn: $draft.asksGoalUmpire)
                        Toggle("Field Umpire", isOn: $draft.asksFieldUmpire)
                        Toggle("Boundary Umpire 1", isOn: $draft.asksBoundaryUmpire1)
                        Toggle("Boundary Umpire 2", isOn: $draft.asksBoundaryUmpire2)
                    } header: {
                        Text("Officials")
                    }
                case .trainers:
                    Section {
                        Toggle("Trainer 1", isOn: $draft.asksTrainer1)
                        Toggle("Trainer 2", isOn: $draft.asksTrainer2)
                        Toggle("Trainer 3", isOn: $draft.asksTrainer3)
                        Toggle("Trainer 4", isOn: $draft.asksTrainer4)
                    } header: {
                        Text("Trainers")
                    }
                case .awards:
                    Section {
                        Toggle("Notes", isOn: $draft.asksNotes)
                        Toggle("Goal Kickers", isOn: $draft.asksGoalKickers)
                        Picker("Best Players", selection: $draft.bestPlayersCount) {
                            ForEach(1...10, id: \.self) { count in
                                Text("\(count)").tag(count)
                            }
                        }
                        Toggle("Guest B & F Votes", isOn: $draft.asksGuestBestFairestVotesScan)
                    } header: {
                        Text("Awards")
                    }
                case .settings:
                    Section {
                        Toggle("Notes", isOn: $draft.asksNotes)
                        Toggle("Live Game View", isOn: $draft.allowsLiveGameView)
                        Picker("Length of Quarters", selection: $draft.quarterLengthMinutes) {
                            ForEach(10...30, id: \.self) { minute in
                                Text("\(minute) min").tag(minute)
                            }
                        }
                    } header: {
                        Text("Settings")
                    }
                }
            }
            .navigationTitle("Add Grade")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        if step != .gradeName {
                            Button("Back") {
                                step = Step(rawValue: step.rawValue - 1) ?? .gradeName
                            }
                        }
                        Spacer()
                        if step == .settings {
                            Button("Save") { onSave(draft) }
                                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } else {
                            Button("Next") {
                                step = Step(rawValue: step.rawValue + 1) ?? .settings
                            }
                            .disabled(step == .gradeName && draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
    }
}

private struct ContactsSettingsView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext

    @State private var contacts: [Contact] = []
    @Query private var reportRecipients: [ReportRecipient]

    @State private var showAddContact = false
    @State private var contactEditing: Contact?
    @State private var saveErrorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(contacts) { contact in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(contact.name)
                            .font(.headline)

                        Text(contact.mobile)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(contact.email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        contactEditing = contact
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteContact(contact)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                Button {
                    showAddContact = true
                } label: {
                    Label("Add Contact", systemImage: "plus")
                }
            } header: {
                Text("Required fields: Name, Mobile, Email")
            }

            Section {
                NavigationLink {
                    ReportRecipientsSettingsView()
                } label: {
                    HStack {
                        Label("Recipients By Grade", systemImage: "paperplane")
                        Spacer()
                        Text("\(reportRecipients.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Move report contacts here: choose who receives each grade's game report by Email and/or Text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Report Delivery")
            }
        }
        .navigationTitle("Contacts")
        .sheet(isPresented: $showAddContact) {
            ContactEditSheet(
                title: "Add Contact",
                allowsSaveAndAddAnother: true,
                onSave: { name, mobile, email in
                    let newContact = Contact(name: name, mobile: mobile, email: email)
                    dataContext.insert(newContact)
                    contacts.append(newContact)
                    contacts.sort {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    SettingsBackupStore.saveContacts(contacts)
                    saveContext()
                    reloadContacts()
                    return true
                }
            )
            .appPopupStyle()
        }
        .sheet(item: $contactEditing) { contact in
            ContactEditSheet(
                title: "Edit Contact",
                initialName: contact.name,
                initialMobile: contact.mobile,
                initialEmail: contact.email,
                onSave: { name, mobile, email in
                    contact.name = name
                    contact.mobile = mobile
                    contact.email = email
                    SettingsBackupStore.saveContacts(contacts)
                    saveContext()
                    reloadContacts()
                    return true
                }
            )
            .appPopupStyle()
        }
        .alert(
            "Save Error",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
        .task {
            reloadContacts()
        }
    }

    private func deleteContact(_ contact: Contact) {
        for recipient in reportRecipients where recipient.contactID == contact.id {
            dataContext.delete(recipient)
        }

        dataContext.delete(contact)
        contacts.removeAll { $0.id == contact.id }

        SettingsBackupStore.saveContacts(contacts)
        saveContext()
        reloadContacts()
    }

    private func saveContext() {
        do {
            try dataContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
            let backups = SettingsBackupStore.loadContacts()
            contacts = backups
                .map {
                    Contact(
                        id: $0.id,
                        name: $0.name,
                        mobile: $0.mobile,
                        email: $0.email
                    )
                }
                .sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
        }
    }

    private func reloadContacts() {
        do {
            let descriptor = FetchDescriptor<Contact>(
                sortBy: [SortDescriptor(\Contact.name)]
            )
            let fetched = try dataContext.fetch(descriptor)

            if fetched.isEmpty {
                let backups = SettingsBackupStore.loadContacts()
                if !backups.isEmpty {
                    contacts = backups
                        .map {
                            Contact(
                                id: $0.id,
                                name: $0.name,
                                mobile: $0.mobile,
                                email: $0.email
                            )
                        }
                        .sorted {
                            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                        }

                    for item in backups {
                        dataContext.insert(
                            Contact(
                                id: item.id,
                                name: item.name,
                                mobile: item.mobile,
                                email: item.email
                            )
                        )
                    }

                    try? dataContext.save()

                    let afterRestore = (try? dataContext.fetch(descriptor)) ?? []
                    if !afterRestore.isEmpty {
                        contacts = afterRestore
                    }
                    return
                }
            }

            contacts = fetched
            SettingsBackupStore.saveContacts(contacts)
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}

private struct ContactEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let initialName: String
    let initialMobile: String
    let initialEmail: String
    let allowsSaveAndAddAnother: Bool
    let onSave: (String, String, String) -> Bool
    let onDelete: (() -> Void)?

    @State private var name: String
    @State private var mobile: String
    @State private var email: String

    init(
        title: String,
        initialName: String = "",
        initialMobile: String = "",
        initialEmail: String = "",
        allowsSaveAndAddAnother: Bool = false,
        onSave: @escaping (String, String, String) -> Bool,
        onDelete: (() -> Void)? = nil
    ) {
        self.title = title
        self.initialName = initialName
        self.initialMobile = initialMobile
        self.initialEmail = initialEmail
        self.allowsSaveAndAddAnother = allowsSaveAndAddAnother
        self.onSave = onSave
        self.onDelete = onDelete

        _name = State(initialValue: initialName)
        _mobile = State(initialValue: initialMobile)
        _email = State(initialValue: initialEmail)
    }

    private var canSave: Bool {
        !clean(name).isEmpty &&
        !clean(mobile).isEmpty &&
        !clean(email).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)

                TextField("Mobile", text: $mobile)
                    .keyboardType(.phonePad)

                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HStack(spacing: 12) {
                        if onDelete != nil {
                            Button(role: .destructive) {
                                onDelete?()
                                dismiss()
                            } label: {
                                Image(systemName: "trash")
                            }
                        }

                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveAndClose()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(canSave ? .blue : .gray)
                    .disabled(!canSave)
                }
                if allowsSaveAndAddAnother {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save & Add Another") {
                            saveAndAddAnother()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(canSave ? .blue : .gray)
                        .disabled(!canSave)
                    }
                }
            }
        }
    }

    private func saveAndClose() {
        guard onSave(clean(name), clean(mobile), clean(email)) else { return }
        dismiss()
    }

    private func saveAndAddAnother() {
        guard onSave(clean(name), clean(mobile), clean(email)) else { return }
        name = ""
        mobile = ""
        email = ""
    }

    private func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ReportsSettingsView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext
    @Query(sort: [SortDescriptor(\CustomReportTemplate.name)]) private var templates: [CustomReportTemplate]
    @Query(sort: [SortDescriptor(\Grade.displayOrder), SortDescriptor(\Grade.name)]) private var grades: [Grade]
    @Query(sort: [SortDescriptor(\Contact.name)]) private var contacts: [Contact]
    @Query(sort: [SortDescriptor(\Game.date, order: .reverse)]) private var games: [Game]
    @Query(sort: [SortDescriptor(\Player.name)]) private var players: [Player]

    @State private var templateEditing: CustomReportTemplate?
    @State private var templateActioning: CustomReportTemplate?
    @State private var templatePreviewing: CustomReportTemplate?
    @State private var templateSharing: CustomReportTemplate?
    @State private var isCreatingTemplate = false
    @State private var saveErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if templates.isEmpty {
                    Text("No custom reports yet. Create one to save reusable report filters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                ForEach(templates) { template in
                    Button {
                        templateActioning = template
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(template.name)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(templateDetails(for: template))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .contextMenu {
                        Button(role: .destructive) {
                            dataContext.delete(template)
                            saveContext()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                Button {
                    isCreatingTemplate = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Custom Report")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.top, 4)
            }
            .padding(.vertical)
        }
        .navigationTitle("Reports")
        .confirmationDialog(
            templateActioning?.name ?? "Custom Report",
            isPresented: Binding(
                get: { templateActioning != nil },
                set: { if !$0 { templateActioning = nil } }
            )
        ) {
            if let template = templateActioning {
                Button("Preview") {
                    templatePreviewing = template
                }
                Button("Share") {
                    templateSharing = template
                }
                Button("Edit") {
                    templateEditing = template
                }
                Button("Delete", role: .destructive) {
                    dataContext.delete(template)
                    saveContext()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .sheet(isPresented: $isCreatingTemplate) {
            CustomReportEditView(grades: grades) { name, selectedGradeIDs, includeBestPlayers, includePlayerGrades, includeGoalKickers, includeGuernseyNumbers, includeBestAndFairestVotes, includeStaffRoles, includeTrainers, includeMatchNotes, includeOnlyActiveGrades, minimumGamesPlayed, groupingModeRawValue in
                let template = CustomReportTemplate(
                    name: name,
                    gradeIDs: selectedGradeIDs,
                    includeBestPlayers: includeBestPlayers,
                    includePlayerGrades: includePlayerGrades,
                    includeGoalKickers: includeGoalKickers,
                    includeGuernseyNumbers: includeGuernseyNumbers,
                    includeBestAndFairestVotes: includeBestAndFairestVotes,
                    includeStaffRoles: includeStaffRoles,
                    includeTrainers: includeTrainers,
                    includeMatchNotes: includeMatchNotes,
                    includeOnlyActiveGrades: includeOnlyActiveGrades,
                    minimumGamesPlayed: minimumGamesPlayed,
                    groupingModeRawValue: groupingModeRawValue
                )
                dataContext.insert(template)
                saveContext()
            }
            .appPopupStyle()
        }
        .sheet(item: $templatePreviewing) { template in
            CustomReportPreviewView(
                template: template,
                grades: grades,
                games: games,
                players: players
            )
                .appPopupStyle()
        }
        .sheet(item: $templateSharing) { template in
            CustomReportShareView(
                template: template,
                grades: grades,
                contacts: contacts
            )
            .appPopupStyle()
        }
        .sheet(item: $templateEditing) { template in
            CustomReportEditView(
                grades: grades,
                initialName: template.name,
                initialSelectedGradeIDs: template.gradeIDs,
                initialIncludeBestPlayers: template.includeBestPlayers,
                initialIncludePlayerGrades: template.includePlayerGrades,
                initialIncludeGoalKickers: template.includeGoalKickers,
                initialIncludeGuernseyNumbers: template.includeGuernseyNumbers,
                initialIncludeBestAndFairestVotes: template.includeBestAndFairestVotes,
                initialIncludeStaffRoles: template.includeStaffRoles,
                initialIncludeTrainers: template.includeTrainers,
                initialIncludeMatchNotes: template.includeMatchNotes,
                initialIncludeOnlyActiveGrades: template.includeOnlyActiveGrades,
                initialMinimumGamesPlayed: template.minimumGamesPlayed,
                initialGroupingModeRawValue: template.groupingModeRawValue
            ) { name, selectedGradeIDs, includeBestPlayers, includePlayerGrades, includeGoalKickers, includeGuernseyNumbers, includeBestAndFairestVotes, includeStaffRoles, includeTrainers, includeMatchNotes, includeOnlyActiveGrades, minimumGamesPlayed, groupingModeRawValue in
                template.name = name
                template.gradeIDs = selectedGradeIDs
                template.includeBestPlayers = includeBestPlayers
                template.includePlayerGrades = includePlayerGrades
                template.includeGoalKickers = includeGoalKickers
                template.includeGuernseyNumbers = includeGuernseyNumbers
                template.includeBestAndFairestVotes = includeBestAndFairestVotes
                template.includeStaffRoles = includeStaffRoles
                template.includeTrainers = includeTrainers
                template.includeMatchNotes = includeMatchNotes
                template.includeOnlyActiveGrades = includeOnlyActiveGrades
                template.minimumGamesPlayed = minimumGamesPlayed
                template.groupingModeRawValue = groupingModeRawValue
                saveContext()
            }
            .appPopupStyle()
        }
        .alert(
            "Save Error",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
    }

    private func templateDetails(for template: CustomReportTemplate) -> String {
        buildTemplateDetails(for: template, grades: grades)
    }

    private func saveContext() {
        do {
            try dataContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}

private struct CustomReportPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let template: CustomReportTemplate
    let grades: [Grade]
    let games: [Game]
    let players: [Player]
    @State private var pdfURL: URL?
    @State private var errorMessage: String?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if let pdfURL {
                    PDFPreviewView(url: pdfURL)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 30))
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    ProgressView("Generating PDF preview…")
                }
            }
            .navigationTitle("Preview")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(pdfURL == nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let pdfURL {
                    ShareSheet(items: [pdfURL])
                } else {
                    ShareSheet(items: [])
                }
            }
            .task {
                guard pdfURL == nil, errorMessage == nil else { return }
                do {
                    pdfURL = try makeTemplatePreviewPDF(
                        template: template,
                        grades: grades,
                        games: games,
                        players: players
                    )
                } catch {
                    errorMessage = "Could not generate preview PDF."
                }
            }
        }
    }
}

private struct CustomReportShareView: View {
    @Environment(\.dismiss) private var dismiss

    let template: CustomReportTemplate
    let grades: [Grade]
    let contacts: [Contact]

    @State private var selectedContactIDs: Set<UUID> = []
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    private var selectedContacts: [Contact] {
        contacts.filter { selectedContactIDs.contains($0.id) }
    }

    private var shareMessage: String {
        var lines: [String] = []
        lines.append("Custom report: \(template.name)")
        lines.append(buildTemplateDetails(for: template, grades: grades))
        if selectedContacts.isEmpty {
            lines.append("Selected contacts: none")
        } else {
            lines.append("Selected contacts: \(selectedContacts.map(\.name).joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if contacts.isEmpty {
                        Text("No contacts found. Add contacts in Settings > Contacts first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(contacts) { contact in
                            Button {
                                if selectedContactIDs.contains(contact.id) {
                                    selectedContactIDs.remove(contact.id)
                                } else {
                                    selectedContactIDs.insert(contact.id)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(contact.name)
                                        Text(contact.email)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedContactIDs.contains(contact.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Select Contacts")
                }
            }
            .navigationTitle("Share Report")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") {
                        shareItems = [shareMessage]
                        showShareSheet = true
                    }
                    .disabled(contacts.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
    }
}

private func buildTemplateDetails(for template: CustomReportTemplate, grades: [Grade]) -> String {
    let gradeNames = grades
        .filter { !template.includeOnlyActiveGrades || $0.isActive }
        .filter { template.gradeIDs.isEmpty || template.gradeIDs.contains($0.id) }
        .map(\.name)

    var items: [String] = []
    if template.includeBestPlayers { items.append("Best players") }
    if template.includePlayerGrades { items.append("Player grades") }
    if template.includeGoalKickers { items.append("Goal kickers") }
    if template.includeGuernseyNumbers { items.append("Guernsey numbers") }
    if template.includeBestAndFairestVotes { items.append("B&F votes") }
    if template.includeStaffRoles { items.append("Staff roles") }
    if template.includeTrainers { items.append("Trainers") }
    if template.includeMatchNotes { items.append("Match notes") }

    let gradesText: String = {
        if gradeNames.isEmpty { return "All grades" }
        return "Grades: " + gradeNames.joined(separator: ", ")
    }()

    let grouping = ReportGroupingMode(rawValue: template.groupingModeRawValue) ?? .combinedTotals
    let filters = "Filters: min games \(template.minimumGamesPlayed), \(template.includeOnlyActiveGrades ? "active grades only" : "active + inactive"), \(grouping.filterSummary)"
    let sections = "Includes: " + (items.isEmpty ? "No sections selected" : items.joined(separator: ", "))
    return [gradesText, sections, filters].joined(separator: " • ")
}

private enum ReportGroupingMode: Int, CaseIterable, Identifiable {
    case combinedTotals = 0
    case splitByGameAndGrade = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .combinedTotals:
            return "Combine totals"
        case .splitByGameAndGrade:
            return "Split by game & grade"
        }
    }

    var filterSummary: String {
        switch self {
        case .combinedTotals:
            return "combined totals"
        case .splitByGameAndGrade:
            return "split by game and grade"
        }
    }
}

private func makeTemplatePreviewPDF(
    template: CustomReportTemplate,
    grades: [Grade],
    games: [Game],
    players: [Player]
) throws -> URL {
    let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
    let groupingMode = ReportGroupingMode(rawValue: template.groupingModeRawValue) ?? .combinedTotals
    let selectedGrades = grades
        .filter { !template.includeOnlyActiveGrades || $0.isActive }
        .filter { template.gradeIDs.isEmpty || template.gradeIDs.contains($0.id) }
    let selectedGradeIDs = Set(selectedGrades.map(\.id))
    let relevantGames = games
        .filter { selectedGradeIDs.isEmpty || selectedGradeIDs.contains($0.gradeID) }
        .filter { !$0.isDraft && $0.date <= Date() }
        .sorted { $0.date > $1.date }
    let playerLookup = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
    let gradeLookup = Dictionary(uniqueKeysWithValues: grades.map { ($0.id, $0.name) })
    var gamesByPlayer: [UUID: Int] = [:]
    for game in relevantGames {
        var seenPlayerIDs = Set<UUID>()
        for entry in game.goalKickers {
            if let playerID = entry.playerID {
                seenPlayerIDs.insert(playerID)
            }
        }
        for playerID in game.bestPlayersRanked {
            seenPlayerIDs.insert(playerID)
        }
        for playerID in seenPlayerIDs {
            gamesByPlayer[playerID, default: 0] += 1
        }
    }

    let data = renderer.pdfData { context in
        let horizontalInset: CGFloat = 30
        let verticalInset: CGFloat = 28
        let contentRect = pageBounds.insetBy(dx: horizontalInset, dy: verticalInset)
        var cursorY = contentRect.minY
        let bottomLimit = contentRect.maxY

        func beginNewPageIfNeeded(requiredHeight: CGFloat) {
            if cursorY + requiredHeight <= bottomLimit { return }
            context.beginPage()
            cursorY = contentRect.minY
        }

        func beginNewPage() {
            context.beginPage()
            cursorY = contentRect.minY
        }

        beginNewPage()

        let titleFont = UIFont(name: "AvenirNext-Bold", size: 22) ?? UIFont.boldSystemFont(ofSize: 22)
        let subtitleFont = UIFont(name: "AvenirNext-Medium", size: 12) ?? UIFont.systemFont(ofSize: 12, weight: .medium)
        let sectionFont = UIFont(name: "AvenirNext-DemiBold", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .semibold)
        let bodyFont = UIFont(name: "AvenirNext-Regular", size: 11) ?? UIFont.systemFont(ofSize: 11)
        let headerFont = UIFont(name: "AvenirNext-DemiBold", size: 10) ?? UIFont.systemFont(ofSize: 10, weight: .semibold)

        if let logo = UIImage(named: "club_logo") {
            let logoRect = CGRect(x: contentRect.minX, y: cursorY, width: 56, height: 56)
            logo.draw(in: logoRect)
        }

        let titleX = contentRect.minX + 68
        let titleRect = CGRect(x: titleX, y: cursorY + 4, width: contentRect.width - 68, height: 28)
        NSAttributedString(
            string: "Custom Report Preview",
            attributes: [.font: titleFont, .foregroundColor: UIColor.label]
        ).draw(in: titleRect)

        let subtitle = "Template: \(template.name) • Layout: \(groupingMode.title) • Generated \(Date().formatted(date: .abbreviated, time: .shortened))"
        let subtitleRect = CGRect(x: titleX, y: titleRect.maxY + 2, width: contentRect.width - 68, height: 22)
        NSAttributedString(
            string: subtitle,
            attributes: [.font: subtitleFont, .foregroundColor: UIColor.secondaryLabel]
        ).draw(in: subtitleRect)
        cursorY += 72

        let tableColumns: [(String, CGFloat)] = [
            ("Player Name", 0.34),
            ("Guernsey", 0.11),
            ("Goals", 0.11),
            ("Best Players", 0.16),
            ("Games", 0.10),
            ("Notes", 0.18)
        ]
        let tableWidth = contentRect.width
        let columnWidths = tableColumns.map { $0.1 * tableWidth }

        func drawSectionHeader(_ text: String) {
            beginNewPageIfNeeded(requiredHeight: 24)
            let rect = CGRect(x: contentRect.minX, y: cursorY, width: contentRect.width, height: 20)
            NSAttributedString(string: text, attributes: [.font: sectionFont]).draw(in: rect)
            cursorY += 24
        }

        func drawTableHeader() {
            beginNewPageIfNeeded(requiredHeight: 24)
            var x = contentRect.minX
            let headerY = cursorY
            for (idx, column) in tableColumns.enumerated() {
                let width = columnWidths[idx]
                let rect = CGRect(x: x, y: headerY, width: width, height: 22)
                UIColor.systemGray5.setFill()
                UIBezierPath(rect: rect).fill()
                UIColor.separator.setStroke()
                UIBezierPath(rect: rect).stroke()
                NSAttributedString(
                    string: column.0,
                    attributes: [.font: headerFont, .foregroundColor: UIColor.label]
                ).draw(in: rect.insetBy(dx: 4, dy: 5))
                x += width
            }
            cursorY += 22
        }

        func drawRow(playerName: String, guernsey: String, goals: String, bestPlayers: String, gamesPlayed: String, notes: String) {
            beginNewPageIfNeeded(requiredHeight: 20)
            var x = contentRect.minX
            let values = [playerName, guernsey, goals, bestPlayers, gamesPlayed, notes]
            for (idx, value) in values.enumerated() {
                let width = columnWidths[idx]
                let rect = CGRect(x: x, y: cursorY, width: width, height: 20)
                UIColor.separator.setStroke()
                UIBezierPath(rect: rect).stroke()
                NSAttributedString(
                    string: value,
                    attributes: [.font: bodyFont, .foregroundColor: UIColor.label]
                ).draw(in: rect.insetBy(dx: 4, dy: 4))
                x += width
            }
            cursorY += 20
        }

        if relevantGames.isEmpty {
            drawSectionHeader("No completed games matched this template.")
            return
        }

        switch groupingMode {
        case .splitByGameAndGrade:
            for game in relevantGames {
                let gradeName = gradeLookup[game.gradeID] ?? "Unknown Grade"
                drawSectionHeader("\(gradeName) • \(game.date.formatted(date: .abbreviated, time: .omitted)) vs \(game.opponent)")
                drawTableHeader()

                var rowsByPlayer: [UUID: (goals: Int, bestCount: Int)] = [:]
                for entry in game.goalKickers {
                    guard let playerID = entry.playerID else { continue }
                    var stats = rowsByPlayer[playerID] ?? (0, 0)
                    stats.goals += entry.goals
                    rowsByPlayer[playerID] = stats
                }
                for playerID in game.bestPlayersRanked {
                    var stats = rowsByPlayer[playerID] ?? (0, 0)
                    stats.bestCount += 1
                    rowsByPlayer[playerID] = stats
                }

                if rowsByPlayer.isEmpty {
                    drawRow(playerName: "No player stats", guernsey: "-", goals: "-", bestPlayers: "-", gamesPlayed: "0", notes: "")
                } else {
                    for (playerID, stats) in rowsByPlayer.sorted(by: { (lhs, rhs) in
                        (playerLookup[lhs.key]?.name ?? "") < (playerLookup[rhs.key]?.name ?? "")
                    }) {
                        if template.minimumGamesPlayed > 0, gamesByPlayer[playerID, default: 0] < template.minimumGamesPlayed {
                            continue
                        }
                        let player = playerLookup[playerID]
                        let guernsey = template.includeGuernseyNumbers ? (player?.number.map(String.init) ?? "-") : "-"
                        let notes = template.includeMatchNotes ? game.notes.trimmingCharacters(in: .whitespacesAndNewlines) : ""
                        drawRow(
                            playerName: player?.name ?? "Unknown Player",
                            guernsey: guernsey,
                            goals: template.includeGoalKickers ? "\(stats.goals)" : "-",
                            bestPlayers: template.includeBestPlayers ? "\(stats.bestCount)" : "-",
                            gamesPlayed: "1",
                            notes: notes
                        )
                    }
                }
                cursorY += 10
            }
        case .combinedTotals:
            let groupedGames = Dictionary(grouping: relevantGames, by: \.gradeID)
            for (gradeID, gradeGames) in groupedGames.sorted(by: { (gradeLookup[$0.key] ?? "") < (gradeLookup[$1.key] ?? "") }) {
                let gradeName = gradeLookup[gradeID] ?? "Unknown Grade"
                drawSectionHeader("\(gradeName) • Combined totals")
                drawTableHeader()

                var rowsByPlayer: [UUID: (goals: Int, bestCount: Int, gamesPlayed: Int)] = [:]
                for game in gradeGames {
                    var touchedInGame = Set<UUID>()
                    for entry in game.goalKickers {
                        guard let playerID = entry.playerID else { continue }
                        var stats = rowsByPlayer[playerID] ?? (0, 0, 0)
                        stats.goals += entry.goals
                        rowsByPlayer[playerID] = stats
                        touchedInGame.insert(playerID)
                    }
                    for playerID in game.bestPlayersRanked {
                        var stats = rowsByPlayer[playerID] ?? (0, 0, 0)
                        stats.bestCount += 1
                        rowsByPlayer[playerID] = stats
                        touchedInGame.insert(playerID)
                    }
                    for playerID in touchedInGame {
                        var stats = rowsByPlayer[playerID] ?? (0, 0, 0)
                        stats.gamesPlayed += 1
                        rowsByPlayer[playerID] = stats
                    }
                }

                for (playerID, stats) in rowsByPlayer.sorted(by: { (lhs, rhs) in
                    (playerLookup[lhs.key]?.name ?? "") < (playerLookup[rhs.key]?.name ?? "")
                }) {
                    if template.minimumGamesPlayed > 0, gamesByPlayer[playerID, default: 0] < template.minimumGamesPlayed {
                        continue
                    }
                    let player = playerLookup[playerID]
                    let guernsey = template.includeGuernseyNumbers ? (player?.number.map(String.init) ?? "-") : "-"
                    drawRow(
                        playerName: player?.name ?? "Unknown Player",
                        guernsey: guernsey,
                        goals: template.includeGoalKickers ? "\(stats.goals)" : "-",
                        bestPlayers: template.includeBestPlayers ? "\(stats.bestCount)" : "-",
                        gamesPlayed: "\(stats.gamesPlayed)",
                        notes: ""
                    )
                }
                cursorY += 10
            }
        }
    }

    let safeName = template.name
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: " ", with: "_")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CustomReport_\(safeName)_Preview.pdf")
    try data.write(to: url, options: .atomic)
    return url
}

private struct PDFPreviewView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.displayMode = .singlePageContinuous
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(url: url)
    }
}

private struct CustomReportEditView: View {
    @Environment(\.dismiss) private var dismiss

    let grades: [Grade]
    let onSave: (String, [UUID], Bool, Bool, Bool, Bool, Bool, Bool, Bool, Bool, Bool, Int, Int) -> Void

    @State private var name: String
    @State private var selectedGradeIDs: Set<UUID>
    @State private var includeBestPlayers: Bool
    @State private var includePlayerGrades: Bool
    @State private var includeGoalKickers: Bool
    @State private var includeGuernseyNumbers: Bool
    @State private var includeBestAndFairestVotes: Bool
    @State private var includeStaffRoles: Bool
    @State private var includeTrainers: Bool
    @State private var includeMatchNotes: Bool
    @State private var includeOnlyActiveGrades: Bool
    @State private var minimumGamesPlayed: Int
    @State private var groupingMode: ReportGroupingMode

    init(
        grades: [Grade],
        initialName: String = "",
        initialSelectedGradeIDs: [UUID] = [],
        initialIncludeBestPlayers: Bool = true,
        initialIncludePlayerGrades: Bool = true,
        initialIncludeGoalKickers: Bool = true,
        initialIncludeGuernseyNumbers: Bool = true,
        initialIncludeBestAndFairestVotes: Bool = true,
        initialIncludeStaffRoles: Bool = true,
        initialIncludeTrainers: Bool = true,
        initialIncludeMatchNotes: Bool = false,
        initialIncludeOnlyActiveGrades: Bool = true,
        initialMinimumGamesPlayed: Int = 0,
        initialGroupingModeRawValue: Int = 0,
        onSave: @escaping (String, [UUID], Bool, Bool, Bool, Bool, Bool, Bool, Bool, Bool, Bool, Int, Int) -> Void
    ) {
        self.grades = grades
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _selectedGradeIDs = State(initialValue: Set(initialSelectedGradeIDs))
        _includeBestPlayers = State(initialValue: initialIncludeBestPlayers)
        _includePlayerGrades = State(initialValue: initialIncludePlayerGrades)
        _includeGoalKickers = State(initialValue: initialIncludeGoalKickers)
        _includeGuernseyNumbers = State(initialValue: initialIncludeGuernseyNumbers)
        _includeBestAndFairestVotes = State(initialValue: initialIncludeBestAndFairestVotes)
        _includeStaffRoles = State(initialValue: initialIncludeStaffRoles)
        _includeTrainers = State(initialValue: initialIncludeTrainers)
        _includeMatchNotes = State(initialValue: initialIncludeMatchNotes)
        _includeOnlyActiveGrades = State(initialValue: initialIncludeOnlyActiveGrades)
        _minimumGamesPlayed = State(initialValue: max(0, initialMinimumGamesPlayed))
        _groupingMode = State(initialValue: ReportGroupingMode(rawValue: initialGroupingModeRawValue) ?? .combinedTotals)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Report name", text: $name)
                } header: {
                    Text("Template")
                }

                Section {
                    ForEach(grades) { grade in
                        Button {
                            if selectedGradeIDs.contains(grade.id) {
                                selectedGradeIDs.remove(grade.id)
                            } else {
                                selectedGradeIDs.insert(grade.id)
                            }
                        } label: {
                            HStack {
                                Text(grade.name)
                                Spacer()
                                if selectedGradeIDs.contains(grade.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }

                    Text("No grade selected means all grades.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Grades")
                }

                Section {
                    Toggle("Best players", isOn: $includeBestPlayers)
                    Toggle("Player grades", isOn: $includePlayerGrades)
                    Toggle("Goal kickers", isOn: $includeGoalKickers)
                    Toggle("Guernsey numbers", isOn: $includeGuernseyNumbers)
                    Toggle("Best & Fairest votes", isOn: $includeBestAndFairestVotes)
                    Toggle("Staff roles", isOn: $includeStaffRoles)
                    Toggle("Trainers", isOn: $includeTrainers)
                    Toggle("Match notes", isOn: $includeMatchNotes)
                } header: {
                    Text("Data Included")
                }

                Section {
                    Picker("Report layout", selection: $groupingMode) {
                        ForEach(ReportGroupingMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Toggle("Only active grades", isOn: $includeOnlyActiveGrades)
                    Stepper("Minimum games played: \(minimumGamesPlayed)", value: $minimumGamesPlayed, in: 0...100)
                } header: {
                    Text("Filters")
                }
            }
            .navigationTitle("Custom Report")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            name.trimmingCharacters(in: .whitespacesAndNewlines),
                            Array(selectedGradeIDs),
                            includeBestPlayers,
                            includePlayerGrades,
                            includeGoalKickers,
                            includeGuernseyNumbers,
                            includeBestAndFairestVotes,
                            includeStaffRoles,
                            includeTrainers,
                            includeMatchNotes,
                            includeOnlyActiveGrades,
                            minimumGamesPlayed,
                            groupingMode.rawValue
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

private struct ReportRecipientsSettingsView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext

    @Query(sort: [SortDescriptor(\Grade.displayOrder), SortDescriptor(\Grade.name)]) private var grades: [Grade]
    @Query(sort: [SortDescriptor(\Contact.name)]) private var contacts: [Contact]
    @Query private var reportRecipients: [ReportRecipient]
    @State private var saveErrorMessage: String?

    private enum SendMode: String, CaseIterable, Identifiable {
        case text
        case email
        case both

        var id: String { rawValue }

        var title: String {
            switch self {
            case .text: return "Text"
            case .email: return "Email"
            case .both: return "Email + Text"
            }
        }
    }

    private var configuredGrades: [Grade] {
        orderedGradesForDisplay(grades, includeInactive: true)
    }

    var body: some View {
        List {
            if configuredGrades.isEmpty {
                Text("Add a grade first.")
                    .foregroundStyle(.secondary)
            }

            ForEach(configuredGrades) { grade in
                Section {
                    let recipients = recipientsForGrade(grade.id)

                    if recipients.isEmpty {
                        Text("No contacts added.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(recipients) { recipient in
                        if let contact = contacts.first(where: { $0.id == recipient.contactID }) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(contact.name)
                                    .font(.headline)

                                HStack {
                                    Text(contact.email)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    Toggle(
                                        "Email",
                                        isOn: Binding(
                                            get: { recipient.sendEmail },
                                            set: { newValue in
                                                recipient.sendEmail = newValue
                                                if !recipient.sendEmail && !recipient.sendText {
                                                    recipient.sendText = true
                                                }
                                                saveContext()
                                            }
                                        )
                                    )
                                    .labelsHidden()
                                }

                                HStack {
                                    Text(contact.mobile)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    Toggle(
                                        "Text",
                                        isOn: Binding(
                                            get: { recipient.sendText },
                                            set: { newValue in
                                                recipient.sendText = newValue
                                                if !recipient.sendEmail && !recipient.sendText {
                                                    recipient.sendEmail = true
                                                }
                                                saveContext()
                                            }
                                        )
                                    )
                                    .labelsHidden()
                                }

                                Text(sendModeText(recipient))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    dataContext.delete(recipient)
                                    saveContext()
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }

                    Menu {
                        let usedContactIDs = Set(recipients.map(\.contactID))
                        let available = contacts.filter { !usedContactIDs.contains($0.id) }

                        if available.isEmpty {
                            Text("No available contacts")
                        } else {
                            ForEach(available) { contact in
                                Menu(contact.name) {
                                    ForEach(SendMode.allCases) { mode in
                                        Button("Send via \(mode.title)") {
                                            addContact(contact, toGrade: grade.id, sendMode: mode)
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Add Contact", systemImage: "plus")
                    }
                } header: {
                    Text(grade.name)
                }
            }
        }
        .navigationTitle("Report Recipients")
        .alert(
            "Save Error",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
    }

    private func recipientsForGrade(_ gradeID: UUID) -> [ReportRecipient] {
        reportRecipients
            .filter { $0.gradeID == gradeID }
            .sorted { a, b in
                let aName = contacts.first(where: { $0.id == a.contactID })?.name ?? ""
                let bName = contacts.first(where: { $0.id == b.contactID })?.name ?? ""
                return aName.localizedCaseInsensitiveCompare(bName) == .orderedAscending
            }
    }

    private func addContact(_ contact: Contact, toGrade gradeID: UUID, sendMode: SendMode) {
        guard !reportRecipients.contains(where: {
            $0.gradeID == gradeID && $0.contactID == contact.id
        }) else { return }

        let sendEmail = sendMode == .email || sendMode == .both
        let sendText = sendMode == .text || sendMode == .both

        dataContext.insert(
            ReportRecipient(
                gradeID: gradeID,
                contactID: contact.id,
                sendEmail: sendEmail,
                sendText: sendText
            )
        )
        saveContext()
    }

    private func sendModeText(_ recipient: ReportRecipient) -> String {
        switch (recipient.sendEmail, recipient.sendText) {
        case (true, true): return "Send via Email + Text"
        case (true, false): return "Send via Email"
        case (false, true): return "Send via Text"
        case (false, false): return "Send via Email"
        }
    }

    private func saveContext() {
        do {
            try dataContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}
