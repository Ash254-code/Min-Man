import SwiftUI
import SwiftData
import PDFKit
import MessageUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext
    @AppStorage("settings.open.contacts") private var shouldOpenContacts = false
    @State private var saveErrorMessage: String?
    @State private var showContactsSettings = false
    var resetToken: UUID = UUID()

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
                        PlayersView()
                    } label: {
                        settingsRow(title: "Players", icon: "person.3")
                    }

                    NavigationLink {
                        UmpiresSettingsView()
                    } label: {
                        settingsRow(title: "Umpires", icon: "flag.pattern.checkered")
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
                        ContactsSettingsView()
                    } label: {
                        settingsRow(title: "Contacts", icon: "person.crop.rectangle")
                    }

                    NavigationLink {
                        GroupsSettingsView()
                    } label: {
                        settingsRow(title: "Groups", icon: "person.3.sequence")
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

                    NavigationLink {
                        PinCodeSettingsView()
                    } label: {
                        settingsRow(title: "PIN Code", icon: "number.square")
                    }
                } header: {
                    Text("Admin")
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(isPresented: $showContactsSettings) {
                ContactsSettingsView()
            }
            .task {
                seedInitialGradesIfNeeded()
            }
            .onAppear {
                guard shouldOpenContacts else { return }
                shouldOpenContacts = false
                showContactsSettings = true
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
        .id(resetToken)
    }

    private let settingsIconColumnWidth: CGFloat = 40

    @ViewBuilder
    private func settingsRow(title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: settingsIconColumnWidth, alignment: .leading)
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
        let selectedLastSelectionFields: [String] = selectedPickerTypes.reduce(into: []) { result, pickerType in
            result.append(contentsOf: pickerType.lastSelectionFieldKeys)
        }
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

private struct UmpiresSettingsView: View {
    @Query private var grades: [Grade]
    @State private var mappings: [UUID: [UUID]] = [:]

    private var orderedGrades: [Grade] {
        orderedGradesForDisplay(resolvedConfiguredGrades(from: grades), includeInactive: true)
    }

    var body: some View {
        List {
            Section {
                Text("Choose which grade lists provide names in the umpire duties picker. These selections control the names shown for Umpire 1, Umpire 2, and Field Umpire.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

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
        .navigationTitle("Umpires")
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
            return "Umpires from: \(orderedGrades.first(where: { $0.id == gameGradeID })?.name ?? "This grade")"
        }

        return "Umpires from: \(selectedNames.joined(separator: ", "))"
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
                        Toggle("Umpire 1", isOn: bind(grade, \.asksBoundaryUmpire1))
                        Toggle("Umpire 2", isOn: bind(grade, \.asksBoundaryUmpire2))
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
                        Toggle("Score", isOn: bind(grade, \.asksScore))
                        Toggle("Goal Kickers", isOn: bind(grade, \.asksGoalKickers))
                        Picker("Best Players", selection: bind(grade, \.bestPlayersCount)) {
                            ForEach(1...10, id: \.self) { count in
                                Text("\(count)").tag(count)
                            }
                        }
                        Toggle("Guest Best & Fairest Votes", isOn: bind(grade, \.asksGuestBestFairestVotesScan))
                        if grade.asksGuestBestFairestVotesScan {
                            Picker("Guest Best Players", selection: bind(grade, \.guestBestPlayersCount)) {
                                ForEach(1...10, id: \.self) { count in
                                    Text("\(count)").tag(count)
                                }
                            }
                        }
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
                        .saveButtonBehavior(isEnabled: !isEditGradeSaveDisabled)
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
            guestBestPlayersCount: draft.guestBestPlayersCount,
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
                            guestBestPlayersCount: $0.guestBestPlayersCount,
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
                                guestBestPlayersCount: item.guestBestPlayersCount,
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
                    guestBestPlayersCount: $0.guestBestPlayersCount,
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
    var guestBestPlayersCount = 3
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
                        Toggle("Umpire 1", isOn: $draft.asksBoundaryUmpire1)
                        Toggle("Umpire 2", isOn: $draft.asksBoundaryUmpire2)
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
                        Toggle("Goal Kickers", isOn: $draft.asksGoalKickers)
                        Picker("Best Players", selection: $draft.bestPlayersCount) {
                            ForEach(1...10, id: \.self) { count in
                                Text("\(count)").tag(count)
                            }
                        }
                        Toggle("Guest B & F Votes", isOn: $draft.asksGuestBestFairestVotesScan)
                        if draft.asksGuestBestFairestVotesScan {
                            Picker("Guest Best Players", selection: $draft.guestBestPlayersCount) {
                                ForEach(1...10, id: \.self) { count in
                                    Text("\(count)").tag(count)
                                }
                            }
                        }
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
                                .saveButtonBehavior(isEnabled: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
    @Query private var sectionMemberships: [ContactSectionMembership]

    @State private var showAddContact = false
    @State private var contactEditing: Contact?
    @State private var saveErrorMessage: String?

    var body: some View {
        List {
            Section {
                Text("Required fields: Name, Mobile, Email")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if contacts.isEmpty {
                    Text("No contacts added.")
                        .foregroundStyle(.secondary)
                }

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
                Text("Contacts")
            } footer: {
                Text("Manage contact group assignments from Settings > Groups.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Contacts")
        .sheet(isPresented: $showAddContact) {
            ContactEditSheet(
                title: "Add Contact",
                allowsSaveAndAddAnother: false,
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
                },
                onDelete: {
                    deleteContact(contact)
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

        for membership in sectionMemberships where membership.contactID == contact.id {
            dataContext.delete(membership)
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

private struct GroupsSettingsView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext

    @State private var contacts: [Contact] = []
    @Query(sort: [SortDescriptor(\Grade.displayOrder), SortDescriptor(\Grade.name)]) private var grades: [Grade]
    @Query private var sectionMemberships: [ContactSectionMembership]

    @State private var showAddContact = false
    @State private var addSectionKey: String?
    @State private var showAddExistingContactForSection = false
    @State private var sectionForExistingContact: String?
    @State private var contactEditing: Contact?
    @State private var isManagingGroups = false
    @State private var saveErrorMessage: String?
    @AppStorage("contactSectionCustomTitles") private var customSectionTitlesData: String = ""
    @AppStorage("contactSectionCustomGroups") private var customSectionKeysData: String = ""
    @AppStorage("contactSectionHiddenGroups") private var hiddenSectionKeysData: String = ""

    var body: some View {
        List {
            ForEach(baseSections.filter {
                if case .fixed = $0.section { return true }
                return false
            }, id: \.sectionKey) { section in
                sectionView(fallbackTitle: section.fallbackTitle, sectionKey: section.sectionKey)
            }

            Section {
                if orderedGrades.isEmpty {
                    Text("Add club grades in Settings > Club Grades to manage coach contacts by grade.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(baseSections.filter { $0.section == .coachesGrade }, id: \.sectionKey) { section in
                        sectionView(fallbackTitle: section.fallbackTitle, sectionKey: section.sectionKey)
                    }
                }
            } header: {
                Text("Coaches")
            }

            ForEach(customSections, id: \.sectionKey) { section in
                sectionView(fallbackTitle: section.fallbackTitle, sectionKey: section.sectionKey)
            }

            Section {
                NavigationLink {
                    ReportsSettingsView()
                } label: {
                    Label("Report Recipients", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        .navigationTitle("Groups")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isManagingGroups = true
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Manage Groups")
            }
        }
        .sheet(isPresented: $showAddContact) {
            ContactEditSheet(
                title: "Add Contact",
                allowsSaveAndAddAnother: false,
                onSave: { name, mobile, email in
                    let contact = Contact(name: name, mobile: mobile, email: email)
                    dataContext.insert(contact)
                    if let addSectionKey {
                        assignContact(contact.id, toSection: addSectionKey)
                    }
                    saveContext()
                    return true
                }
            )
            .appPopupStyle()
        }
        .sheet(isPresented: $showAddExistingContactForSection) {
            ExistingContactAssignmentSheet(
                contacts: contacts,
                assignedContactIDs: Set(
                    sectionMemberships
                        .filter { $0.sectionKey == sectionForExistingContact }
                        .map(\.contactID)
                ),
                onSelect: { contact in
                    guard let sectionKey = sectionForExistingContact else { return }
                    assignContact(contact.id, toSection: sectionKey)
                    saveContext()
                    sectionForExistingContact = nil
                    showAddExistingContactForSection = false
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
                    saveContext()
                    return true
                }
            )
            .appPopupStyle()
        }
        .sheet(isPresented: $isManagingGroups) {
            GroupManagerSheet(initialGroups: manageableGroups) { drafts in
                applyGroupDrafts(drafts)
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
        .task {
            reloadContacts()
        }
    }

    private var orderedGrades: [Grade] {
        orderedGradesForDisplay(resolvedConfiguredGrades(from: grades), includeInactive: true)
    }

    private var customGroupKeys: [String] {
        guard
            let data = customSectionKeysData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private var hiddenGroupKeys: Set<String> {
        guard
            let data = hiddenSectionKeysData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return Set(decoded)
    }

    private var baseSections: [GroupSectionDescriptor] {
        let primary = primarySections.map {
            GroupSectionDescriptor(section: .fixed($0), sectionKey: $0.rawValue, fallbackTitle: $0.title)
        }
        let gradeSections = orderedGrades.map {
            GroupSectionDescriptor(
                section: .coachesGrade,
                sectionKey: ContactSectionKey.coachesGrade($0.id).rawValue,
                fallbackTitle: $0.name
            )
        }
        return (primary + gradeSections).filter { !hiddenGroupKeys.contains($0.sectionKey) }
    }

    private var customSections: [GroupSectionDescriptor] {
        customGroupKeys
            .filter { !hiddenGroupKeys.contains($0) }
            .map { key in
                GroupSectionDescriptor(
                    section: .custom,
                    sectionKey: key,
                    fallbackTitle: "Custom Group"
                )
            }
    }

    private var manageableGroups: [GroupManagementDraft] {
        (baseSections + customSections).map { section in
            GroupManagementDraft(
                sectionKey: section.sectionKey,
                name: displayTitle(for: section.sectionKey, fallback: section.fallbackTitle),
                fallbackTitle: section.fallbackTitle,
                isCustom: section.section == .custom
            )
        }
    }

    private func sectionView(fallbackTitle: String, sectionKey: String) -> some View {
        Section {
            let members = contactsForSection(sectionKey)

            if members.isEmpty {
                Text("No contacts added.")
                    .foregroundStyle(.secondary)
            }

            ForEach(members) { contact in
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
                        removeContact(contact.id, fromSection: sectionKey)
                    } label: {
                        Label("Remove", systemImage: "minus.circle")
                    }
                }
            }

            Menu {
                Button {
                    addSectionKey = sectionKey
                    showAddContact = true
                } label: {
                    Label("New Contact", systemImage: "person.badge.plus")
                }

                Button {
                    sectionForExistingContact = sectionKey
                    showAddExistingContactForSection = true
                } label: {
                    Label("Existing Contact", systemImage: "person.2")
                }
            } label: {
                Label("Add Contact", systemImage: "plus")
            }
        } header: {
            HStack {
                Text(displayTitle(for: sectionKey, fallback: fallbackTitle))
            }
        }
    }

    private func contactsForSection(_ sectionKey: String) -> [Contact] {
        let ids = Set(sectionMemberships.filter { $0.sectionKey == sectionKey }.map(\.contactID))
        return contacts.filter { ids.contains($0.id) }
    }

    private func assignContact(_ contactID: UUID, toSection sectionKey: String) {
        guard !sectionMemberships.contains(where: { $0.contactID == contactID && $0.sectionKey == sectionKey }) else {
            return
        }
        dataContext.insert(ContactSectionMembership(contactID: contactID, sectionKey: sectionKey))
    }

    private func removeContact(_ contactID: UUID, fromSection sectionKey: String) {
        for membership in sectionMemberships where membership.contactID == contactID && membership.sectionKey == sectionKey {
            dataContext.delete(membership)
        }
        saveContext()
    }

    private func clearGroup(_ sectionKey: String) {
        for membership in sectionMemberships where membership.sectionKey == sectionKey {
            dataContext.delete(membership)
        }
        removeCustomTitle(for: sectionKey)
        saveContext()
    }

    private func saveContext() {
        do {
            try dataContext.save()
            SettingsBackupStore.saveContacts(contacts)
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private var primarySections: [ContactSectionKey] {
        [
            .registrar,
            .coordinatorsSenior,
            .coordinatorsJunior,
            .marketing,
            .committee,
            .other
        ]
    }

    private func reloadContacts() {
        do {
            let descriptor = FetchDescriptor<Contact>(sortBy: [SortDescriptor(\Contact.name)])
            contacts = try dataContext.fetch(descriptor)
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private var customSectionTitles: [String: String] {
        guard
            let data = customSectionTitlesData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private func displayTitle(for sectionKey: String, fallback: String) -> String {
        if let custom = customSectionTitles[sectionKey], !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        return fallback
    }

    private func setCustomTitle(_ title: String, for sectionKey: String, fallback: String) {
        var updated = customSectionTitles
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned == fallback {
            updated.removeValue(forKey: sectionKey)
        } else {
            updated[sectionKey] = cleaned
        }
        if let data = try? JSONEncoder().encode(updated), let json = String(data: data, encoding: .utf8) {
            customSectionTitlesData = json
        }
    }

    private func removeCustomTitle(for sectionKey: String) {
        var updated = customSectionTitles
        updated.removeValue(forKey: sectionKey)
        if let data = try? JSONEncoder().encode(updated), let json = String(data: data, encoding: .utf8) {
            customSectionTitlesData = json
        }
    }

    private func saveCustomGroupKeys(_ keys: [String]) {
        guard let data = try? JSONEncoder().encode(keys), let json = String(data: data, encoding: .utf8) else { return }
        customSectionKeysData = json
    }

    private func saveHiddenGroupKeys(_ keys: Set<String>) {
        guard let data = try? JSONEncoder().encode(Array(keys)), let json = String(data: data, encoding: .utf8) else { return }
        hiddenSectionKeysData = json
    }

    private func applyGroupDrafts(_ drafts: [GroupManagementDraft]) {
        let existingKeys = Set(manageableGroups.map(\.sectionKey))
        let keptKeys = Set(drafts.map(\.sectionKey))
        let deletedKeys = existingKeys.subtracting(keptKeys)

        for key in deletedKeys {
            clearGroup(key)
        }

        var updatedHidden = hiddenGroupKeys
        let customKeys = drafts.filter(\.isCustom).map(\.sectionKey)
        saveCustomGroupKeys(customKeys)

        let baseKeys = Set((baseSections + customSections).filter { !$0.section.isCustom }.map(\.sectionKey))
        for key in deletedKeys where baseKeys.contains(key) {
            updatedHidden.insert(key)
        }
        saveHiddenGroupKeys(updatedHidden)

        for draft in drafts {
            setCustomTitle(draft.name, for: draft.sectionKey, fallback: draft.fallbackTitle)
        }
    }
}

private struct GroupSectionDescriptor {
    enum SectionKind: Equatable {
        case fixed(ContactSectionKey)
        case coachesGrade
        case custom

        var isCustom: Bool {
            self == .custom
        }
    }

    let section: SectionKind
    let sectionKey: String
    let fallbackTitle: String
}

private struct PinCodeSettingsView: View {
    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        Form {
            Section("Verify Current Code") {
                SecureField("Current 4-digit code", text: $currentPIN)
                    .keyboardType(.numberPad)
            }

            Section("Set New Code") {
                SecureField("New 4-digit code", text: $newPIN)
                    .keyboardType(.numberPad)
                SecureField("Confirm new code", text: $confirmPIN)
                    .keyboardType(.numberPad)
            }

            Section {
                Button("Change Delete Code") {
                    changeCode()
                }
            }

            if let successMessage {
                Section {
                    Text(successMessage)
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("PIN Code")
        .alert(
            "Could Not Change Code",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func changeCode() {
        successMessage = nil
        let trimmedCurrent = currentPIN.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newPIN.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirm = confirmPIN.trimmingCharacters(in: .whitespacesAndNewlines)

        guard DeleteCodeStore.verify(trimmedCurrent) else {
            errorMessage = "Current code is incorrect."
            return
        }

        guard DeleteCodeStore.isValidCode(trimmedNew) else {
            errorMessage = "New code must be exactly 4 digits."
            return
        }

        guard trimmedNew == trimmedConfirm else {
            errorMessage = "New code and confirmation do not match."
            return
        }

        DeleteCodeStore.save(trimmedNew)
        currentPIN = ""
        newPIN = ""
        confirmPIN = ""
        successMessage = "Delete code updated successfully."
    }
}

private enum ContactSectionKey: Hashable, Identifiable {
    case coaches
    case coachesGrade(UUID)
    case registrar
    case coordinatorsSenior
    case coordinatorsJunior
    case marketing
    case committee
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coaches: return "Coaches"
        case .coachesGrade: return "Grade"
        case .registrar: return "Registrar"
        case .coordinatorsSenior: return "Coordinators - Senior"
        case .coordinatorsJunior: return "Coordinators - Junior"
        case .marketing: return "Marketing"
        case .committee: return "Committee"
        case .other: return "Other"
        }
    }

    var rawValue: String {
        switch self {
        case .coaches:
            return "coaches"
        case let .coachesGrade(gradeID):
            return "coaches:\(gradeID.uuidString)"
        case .registrar:
            return "registrar"
        case .coordinatorsSenior:
            return "coordinators:senior"
        case .coordinatorsJunior:
            return "coordinators:junior"
        case .marketing:
            return "marketing"
        case .committee:
            return "committee"
        case .other:
            return "other"
        }
    }

    static func fromRawValue(_ value: String) -> ContactSectionKey {
        if value == ContactSectionKey.coaches.rawValue { return .coaches }
        if value == ContactSectionKey.registrar.rawValue { return .registrar }
        if value == ContactSectionKey.coordinatorsSenior.rawValue { return .coordinatorsSenior }
        if value == ContactSectionKey.coordinatorsJunior.rawValue { return .coordinatorsJunior }
        if value == ContactSectionKey.marketing.rawValue { return .marketing }
        if value == ContactSectionKey.committee.rawValue { return .committee }
        if value == ContactSectionKey.other.rawValue { return .other }
        if value.hasPrefix("coaches:"), let uuid = UUID(uuidString: String(value.dropFirst("coaches:".count))) {
            return .coachesGrade(uuid)
        }
        return .other
    }
}

private struct GroupNameEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    var initialName: String = ""
    let onSave: (String) -> Bool

    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Group name", text: $name)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if onSave(cleaned) { dismiss() }
                    }
                    .saveButtonBehavior(isEnabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                name = initialName
            }
        }
    }
}

private struct GroupMembersSheet: View {
    let group: ContactGroup
    let contacts: [Contact]
    let memberships: [ContactGroupMembership]
    let onAssign: (UUID) -> Void
    let onRemove: (UUID) -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var isRenaming = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(contacts) { contact in
                    Button {
                        if isInGroup(contact.id) {
                            onRemove(contact.id)
                        } else {
                            onAssign(contact.id)
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
                            if isInGroup(contact.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle(group.name)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Rename") { isRenaming = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete", role: .destructive) { onDelete() }
                }
            }
        }
        .sheet(isPresented: $isRenaming) {
            GroupNameEditSheet(title: "Rename Group", initialName: group.name) { newName in
                guard !newName.isEmpty else { return false }
                onRename(newName)
                return true
            }
            .appPopupStyle()
        }
    }

    private func isInGroup(_ contactID: UUID) -> Bool {
        memberships.contains(where: { $0.groupID == group.id && $0.contactID == contactID })
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
    @State private var showDeleteConfirmation = false

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

    private var hasChanges: Bool {
        clean(name) != clean(initialName) ||
        clean(mobile) != clean(initialMobile) ||
        clean(email) != clean(initialEmail)
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
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        if onDelete != nil {
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                            }
                        }

                        Button("Save") { saveAndClose() }
                            .buttonStyle(.borderedProminent)
                            .saveButtonBehavior(isEnabled: canSave && hasChanges)
                    }
                }
                if allowsSaveAndAddAnother {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save & Add Another") {
                            saveAndAddAnother()
                        }
                        .buttonStyle(.borderedProminent)
                        .saveButtonBehavior(isEnabled: canSave)
                    }
                }
            }
        }
        .alert("Delete contact?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This contact will be permanently deleted.")
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

private struct ExistingContactAssignmentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let contacts: [Contact]
    let assignedContactIDs: Set<UUID>
    let onSelect: (Contact) -> Void

    private var availableContacts: [Contact] {
        contacts.filter { !assignedContactIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if availableContacts.isEmpty {
                    Text("All contacts are already in this section.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(availableContacts) { contact in
                        Button {
                            onSelect(contact)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(contact.name)
                                Text(contact.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Existing Contact")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct GroupManagementDraft: Identifiable, Equatable {
    let sectionKey: String
    var name: String
    let fallbackTitle: String
    let isCustom: Bool

    var id: String { sectionKey }
}

private struct GroupManagerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: ([GroupManagementDraft]) -> Void

    @State private var draftGroups: [GroupManagementDraft]
    @State private var initialGroups: [GroupManagementDraft]
    @State private var pendingDeleteGroupID: GroupManagementDraft.ID?
    @State private var showDeleteConfirmation = false

    init(initialGroups: [GroupManagementDraft], onSave: @escaping ([GroupManagementDraft]) -> Void) {
        self.onSave = onSave
        _draftGroups = State(initialValue: initialGroups)
        _initialGroups = State(initialValue: initialGroups)
    }

    private var hasChanges: Bool {
        draftGroups != initialGroups
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach($draftGroups) { $group in
                    HStack(spacing: 12) {
                        TextField("Group Name", text: $group.name)
                            .textInputAutocapitalization(.words)

                        Button(role: .destructive) {
                            pendingDeleteGroupID = group.id
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    draftGroups.append(
                        GroupManagementDraft(
                            sectionKey: "custom:\(UUID().uuidString)",
                            name: "",
                            fallbackTitle: "Custom Group",
                            isCustom: true
                        )
                    )
                } label: {
                    Label("Add Group", systemImage: "plus")
                }
            }
            .navigationTitle("Manage Groups")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(normalizedDrafts())
                        dismiss()
                    }
                    .disabled(!hasChanges)
                    .foregroundStyle(hasChanges ? .blue : .gray)
                }
            }
        }
        .alert("Delete group?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                guard let groupID = pendingDeleteGroupID else { return }
                draftGroups.removeAll { $0.id == groupID }
                pendingDeleteGroupID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteGroupID = nil
            }
        } message: {
            Text("This removes all contacts from the group.")
        }
    }

    private func normalizedDrafts() -> [GroupManagementDraft] {
        var seen = Set<String>()
        return draftGroups.compactMap { group in
            let cleaned = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = cleaned.isEmpty ? group.fallbackTitle : cleaned
            guard !seen.contains(group.sectionKey) else { return nil }
            seen.insert(group.sectionKey)
            return GroupManagementDraft(
                sectionKey: group.sectionKey,
                name: finalName,
                fallbackTitle: group.fallbackTitle,
                isCustom: group.isCustom
            )
        }
    }
}

struct ReportsSettingsView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext
    @Query(sort: [SortDescriptor(\CustomReportTemplate.name)]) private var templates: [CustomReportTemplate]
    @Query(sort: [SortDescriptor(\Grade.displayOrder), SortDescriptor(\Grade.name)]) private var grades: [Grade]
    @Query(sort: [SortDescriptor(\Contact.name)]) private var contacts: [Contact]
    @Query(sort: [SortDescriptor(\ContactGroup.name)]) private var groups: [ContactGroup]
    @Query private var groupMemberships: [ContactGroupMembership]
    @Query private var sectionMemberships: [ContactSectionMembership]
    @Query private var customReportRecipientSections: [CustomReportRecipientSection]
    @Query private var customReportRecipientGroups: [CustomReportRecipientGroup]
    @Query private var customReportRecipientContacts: [CustomReportRecipientContact]
    @Query(sort: [SortDescriptor(\Game.date, order: .reverse)]) private var games: [Game]
    @Query(sort: [SortDescriptor(\Player.name)]) private var players: [Player]

    @State private var templateEditing: CustomReportTemplate?
    @State private var templateActioning: CustomReportTemplate?
    @State private var templatePreviewing: TemplateRunRequest?
    @State private var isCreatingTemplate = false
    @State private var saveErrorMessage: String?
    @State private var isMoveModeEnabled = false
    @State private var moveDraftOrder: [UUID] = []
    @State private var draggingTemplateID: UUID?
    @State private var draggingTranslation: CGSize = .zero
    @State private var draggingStartIndex: Int?
    @State private var draggingLastTargetIndex: Int?
    @AppStorage("reports.templateOrder.v1") private var templateOrderData = ""
    var onOpenContactsSettings: (() -> Void)? = nil

    private let templateGridColumnCount = 4
    private let templateGridSpacing: CGFloat = 12
    private let templateTileHeight: CGFloat = 94

    private var displayedTemplates: [CustomReportTemplate] {
        let templateByID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
        let activeOrder = activeTemplateOrderIDs()
        let orderedFromStore = activeOrder.compactMap { templateByID[$0] }
        let remaining = templates.filter { !activeOrder.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return orderedFromStore + remaining
    }

    private var templateGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: templateGridSpacing), count: templateGridColumnCount)
    }

    private var placeholderSlotCount: Int {
        let minimumSlots = templateGridColumnCount * 2
        let templateCount = displayedTemplates.count
        if templateCount < minimumSlots { return minimumSlots }
        if templateCount == minimumSlots { return minimumSlots + templateGridColumnCount }
        let rowCount = Int(ceil(Double(templateCount) / Double(templateGridColumnCount)))
        return rowCount * templateGridColumnCount
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer()
                    Button {
                        onOpenContactsSettings?()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }

                if templates.isEmpty {
                    Text("No custom reports yet. Create one to save reusable report filters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                GeometryReader { proxy in
                    let tileWidth = max(
                        0,
                        (proxy.size.width - (templateGridSpacing * CGFloat(templateGridColumnCount - 1)))
                        / CGFloat(templateGridColumnCount)
                    )

                    Group {
                        if isMoveModeEnabled {
                            ZStack(alignment: .topLeading) {
                                LazyVGrid(columns: templateGridColumns, spacing: templateGridSpacing) {
                                    ForEach(0..<placeholderSlotCount, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.gray.opacity(0.14))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .stroke(Color.gray.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                                            )
                                            .frame(height: templateTileHeight)
                                    }
                                }

                                LazyVGrid(columns: templateGridColumns, spacing: templateGridSpacing) {
                                    ForEach(displayedTemplates) { template in
                                        reportTile(for: template, tileWidth: tileWidth)
                                            .zIndex(draggingTemplateID == template.id ? 2 : 1)
                                    }
                                }
                                .animation(.spring(response: 0.25, dampingFraction: 0.78), value: moveDraftOrder)
                            }
                        } else {
                            LazyVGrid(columns: templateGridColumns, spacing: templateGridSpacing) {
                                ForEach(displayedTemplates) { template in
                                    reportTile(for: template, tileWidth: tileWidth)
                                }

                                Button {
                                    isCreatingTemplate = true
                                } label: {
                                    VStack(spacing: 2) {
                                        Text("+")
                                            .font(.system(size: 34, weight: .bold, design: .rounded))
                                            .lineLimit(1)

                                        Text("Create Custom Report")
                                            .font(.headline.weight(.semibold))
                                            .multilineTextAlignment(.center)
                                            .lineLimit(2)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                    .padding(12)
                                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                                .frame(height: templateTileHeight)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: gridHeightEstimate())
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Reports")
        .toolbar {
            if isMoveModeEnabled {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        finishMoveModeAndSave()
                    }
                }
            }
        }
        .onAppear {
            syncTemplateOrderWithCurrentTemplates()
        }
        .onChange(of: templates.map(\.id)) { _ in
            syncTemplateOrderWithCurrentTemplates()
            syncMoveDraftWithCurrentTemplates()
        }
        .confirmationDialog("Report actions", isPresented: Binding(
            get: { templateActioning != nil },
            set: { if !$0 { templateActioning = nil } }
        ), titleVisibility: .visible) {
            if let template = templateActioning {
                Button("Edit") {
                    templateEditing = template
                }
                Button("Duplicate") {
                    duplicateTemplate(template)
                }
                Button("Preview") {
                    templatePreviewing = TemplateRunRequest(
                        template: template,
                        dateRange: reportDateRange(for: template),
                        emailRecipients: recipientEmails(for: template)
                    )
                }
                Button("Move") {
                    beginMoveMode()
                }
                Button("Delete Report", role: .destructive) {
                    deleteTemplate(template)
                }
            }
        }
        .sheet(isPresented: $isCreatingTemplate) {
            CustomReportEditView(
                grades: grades,
                contacts: contacts,
                sectionMemberships: sectionMemberships
            ) { name, selectedGradeIDs, includeScores, includeBestPlayers, bestPlayersLimit, includeGuestVotes, guestVotesLimit, includeGoalKickers, goalKickersLimit, includeBestAndFairestVotes, bestAndFairestLimit, includeStaffRoles, includeOfficials, includeUmpires, includeTrainers, includeMatchNotes, includeOnlyActiveGrades, minimumGamesPlayed, groupingModeRawValue, selectedQuickPickRawValue, customDateRangeStart, customDateRangeEnd, selectedRecipientSectionKeys, selectedRecipientContactIDs in
                let normalizedStart = min(customDateRangeStart, customDateRangeEnd)
                let normalizedEnd = max(customDateRangeStart, customDateRangeEnd)
                let template = CustomReportTemplate(
                    name: name,
                    gradeIDs: selectedGradeIDs,
                    includeScores: includeScores,
                    includeBestPlayers: includeBestPlayers,
                    bestPlayersLimit: bestPlayersLimit,
                    includePlayerGrades: includeGuestVotes,
                    guestVotesLimit: guestVotesLimit,
                    includeGoalKickers: includeGoalKickers,
                    goalKickersLimit: goalKickersLimit,
                    includeGuernseyNumbers: false,
                    includeBestAndFairestVotes: includeBestAndFairestVotes,
                    bestAndFairestLimit: bestAndFairestLimit,
                    includeStaffRoles: includeStaffRoles,
                    includeOfficials: includeOfficials,
                    includeUmpires: includeUmpires,
                    includeTrainers: includeTrainers,
                    includeMatchNotes: includeMatchNotes,
                    includeOnlyActiveGrades: includeOnlyActiveGrades,
                    minimumGamesPlayed: minimumGamesPlayed,
                    groupingModeRawValue: groupingModeRawValue,
                    dateRangeQuickPickRawValue: selectedQuickPickRawValue,
                    customDateRangeStart: normalizedStart,
                    customDateRangeEnd: normalizedEnd
                )
                dataContext.insert(template)
                selectedRecipientSectionKeys.forEach { sectionKey in
                    dataContext.insert(CustomReportRecipientSection(templateID: template.id, sectionKey: sectionKey))
                }
                selectedRecipientContactIDs.forEach { contactID in
                    dataContext.insert(CustomReportRecipientContact(templateID: template.id, contactID: contactID))
                }
                saveContext()
                let selectedQuickPick = ReportRangeQuickPick(rawValue: selectedQuickPickRawValue) ?? .mostRecentGame
                let selectedDateRange = buildDateRange(
                    for: selectedQuickPick,
                    template: template,
                    games: games,
                    customStartDate: normalizedStart,
                    customEndDate: normalizedEnd
                )
                templatePreviewing = TemplateRunRequest(
                    template: template,
                    dateRange: selectedDateRange,
                    emailRecipients: recipientEmails(for: template)
                )
            }
            .appPopupStyle()
        }
        .sheet(item: $templatePreviewing) { request in
            CustomReportPreviewView(
                template: request.template,
                grades: grades,
                games: games,
                players: players,
                selectedDateRange: request.dateRange,
                emailRecipients: request.emailRecipients
            )
                .appPopupStyle()
        }
        .sheet(item: $templateEditing) { template in
            CustomReportEditView(
                grades: grades,
                contacts: contacts,
                sectionMemberships: sectionMemberships,
                initialName: template.name,
                initialSelectedGradeIDs: template.gradeIDs,
                initialIncludeScores: template.includeScores,
                initialIncludeBestPlayers: template.includeBestPlayers,
                initialBestPlayersLimit: template.bestPlayersLimit,
                initialIncludeGuestVotes: template.includePlayerGrades,
                initialGuestVotesLimit: template.guestVotesLimit,
                initialIncludeGoalKickers: template.includeGoalKickers,
                initialGoalKickersLimit: template.goalKickersLimit,
                initialIncludeBestAndFairestVotes: template.includeBestAndFairestVotes,
                initialBestAndFairestLimit: template.bestAndFairestLimit,
                initialIncludeStaffRoles: template.includeStaffRoles,
                initialIncludeOfficials: template.includeOfficials,
                initialIncludeUmpires: template.includeUmpires,
                initialIncludeTrainers: template.includeTrainers,
                initialIncludeMatchNotes: template.includeMatchNotes,
                initialIncludeOnlyActiveGrades: template.includeOnlyActiveGrades,
                initialMinimumGamesPlayed: template.minimumGamesPlayed,
                initialGroupingModeRawValue: template.groupingModeRawValue,
                initialDateRangeQuickPickRawValue: template.dateRangeQuickPickRawValue,
                initialCustomDateRangeStart: template.customDateRangeStart,
                initialCustomDateRangeEnd: template.customDateRangeEnd,
                initialRecipientSectionKeys: customReportRecipientSections
                    .filter { $0.templateID == template.id }
                    .map(\.sectionKey),
                initialRecipientContactIDs: customReportRecipientContacts
                    .filter { $0.templateID == template.id }
                    .map(\.contactID),
                onDelete: {
                    deleteTemplate(template)
                }
            ) { name, selectedGradeIDs, includeScores, includeBestPlayers, bestPlayersLimit, includeGuestVotes, guestVotesLimit, includeGoalKickers, goalKickersLimit, includeBestAndFairestVotes, bestAndFairestLimit, includeStaffRoles, includeOfficials, includeUmpires, includeTrainers, includeMatchNotes, includeOnlyActiveGrades, minimumGamesPlayed, groupingModeRawValue, selectedQuickPickRawValue, customDateRangeStart, customDateRangeEnd, selectedRecipientSectionKeys, selectedRecipientContactIDs in
                let normalizedStart = min(customDateRangeStart, customDateRangeEnd)
                let normalizedEnd = max(customDateRangeStart, customDateRangeEnd)
                template.name = name
                template.gradeIDs = selectedGradeIDs
                template.includeScores = includeScores
                template.includeBestPlayers = includeBestPlayers
                template.bestPlayersLimit = bestPlayersLimit
                template.includePlayerGrades = includeGuestVotes
                template.guestVotesLimit = guestVotesLimit
                template.includeGoalKickers = includeGoalKickers
                template.goalKickersLimit = goalKickersLimit
                template.includeGuernseyNumbers = false
                template.includeBestAndFairestVotes = includeBestAndFairestVotes
                template.bestAndFairestLimit = bestAndFairestLimit
                template.includeStaffRoles = includeStaffRoles
                template.includeOfficials = includeOfficials
                template.includeUmpires = includeUmpires
                template.includeTrainers = includeTrainers
                template.includeMatchNotes = includeMatchNotes
                template.includeOnlyActiveGrades = includeOnlyActiveGrades
                template.minimumGamesPlayed = minimumGamesPlayed
                template.groupingModeRawValue = groupingModeRawValue
                template.dateRangeQuickPickRawValue = selectedQuickPickRawValue
                template.customDateRangeStart = normalizedStart
                template.customDateRangeEnd = normalizedEnd

                for recipientSection in customReportRecipientSections where recipientSection.templateID == template.id {
                    dataContext.delete(recipientSection)
                }
                for recipientGroup in customReportRecipientGroups where recipientGroup.templateID == template.id {
                    dataContext.delete(recipientGroup)
                }
                for recipientContact in customReportRecipientContacts where recipientContact.templateID == template.id {
                    dataContext.delete(recipientContact)
                }
                selectedRecipientSectionKeys.forEach { sectionKey in
                    dataContext.insert(CustomReportRecipientSection(templateID: template.id, sectionKey: sectionKey))
                }
                selectedRecipientContactIDs.forEach { contactID in
                    dataContext.insert(CustomReportRecipientContact(templateID: template.id, contactID: contactID))
                }
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

    private func saveContext() {
        do {
            try dataContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func reportTile(for template: CustomReportTemplate, tileWidth: CGFloat) -> some View {
        let wobbleDirection = template.id.uuidString.hashValue.isMultiple(of: 2) ? 1.0 : -1.0
        let baseTile = VStack(spacing: 6) {
            Text(template.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(gradesSummary(for: template))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            guard !isMoveModeEnabled else { return }
            templatePreviewing = TemplateRunRequest(
                template: template,
                dateRange: reportDateRange(for: template),
                emailRecipients: recipientEmails(for: template)
            )
        }
        .onLongPressGesture {
            guard !isMoveModeEnabled else { return }
            templateActioning = template
        }
        .scaleEffect(draggingTemplateID == template.id ? 1.08 : (isMoveModeEnabled ? 1.02 : 1))
        .rotationEffect(.degrees(isMoveModeEnabled ? (wobbleDirection * 3.2) : 0))
        .offset(draggingTemplateID == template.id ? draggingTranslation : .zero)
        .shadow(color: .black.opacity(draggingTemplateID == template.id ? 0.2 : 0), radius: 12, y: 8)
        .animation(
            isMoveModeEnabled
            ? .easeInOut(duration: 0.1).repeatForever(autoreverses: true)
            : .default,
            value: isMoveModeEnabled
        )
        .frame(maxWidth: .infinity)
        .frame(height: templateTileHeight)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        if isMoveModeEnabled {
            baseTile
                .gesture(templateMoveGesture(for: template.id, tileWidth: tileWidth))
        } else {
            baseTile
        }
    }

    private func deleteTemplate(_ template: CustomReportTemplate) {
        for recipientSection in customReportRecipientSections where recipientSection.templateID == template.id {
            dataContext.delete(recipientSection)
        }
        for recipientGroup in customReportRecipientGroups where recipientGroup.templateID == template.id {
            dataContext.delete(recipientGroup)
        }
        for recipientContact in customReportRecipientContacts where recipientContact.templateID == template.id {
            dataContext.delete(recipientContact)
        }
        dataContext.delete(template)
        removeTemplateIDFromOrder(template.id)
        saveContext()
    }

    private func duplicateTemplate(_ template: CustomReportTemplate) {
        let duplicatedTemplate = CustomReportTemplate(
            name: "\(template.name) Copy",
            gradeIDs: template.gradeIDs,
            includeScores: template.includeScores,
            includeBestPlayers: template.includeBestPlayers,
            bestPlayersLimit: template.bestPlayersLimit,
            includePlayerGrades: template.includePlayerGrades,
            guestVotesLimit: template.guestVotesLimit,
            includeGoalKickers: template.includeGoalKickers,
            goalKickersLimit: template.goalKickersLimit,
            includeGuernseyNumbers: template.includeGuernseyNumbers,
            includeBestAndFairestVotes: template.includeBestAndFairestVotes,
            bestAndFairestLimit: template.bestAndFairestLimit,
            includeStaffRoles: template.includeStaffRoles,
            includeOfficials: template.includeOfficials,
            includeUmpires: template.includeUmpires,
            includeTrainers: template.includeTrainers,
            includeMatchNotes: template.includeMatchNotes,
            includeOnlyActiveGrades: template.includeOnlyActiveGrades,
            minimumGamesPlayed: template.minimumGamesPlayed,
            groupingModeRawValue: template.groupingModeRawValue,
            dateRangeQuickPickRawValue: template.dateRangeQuickPickRawValue,
            customDateRangeStart: template.customDateRangeStart,
            customDateRangeEnd: template.customDateRangeEnd
        )
        dataContext.insert(duplicatedTemplate)
        for section in customReportRecipientSections where section.templateID == template.id {
            dataContext.insert(CustomReportRecipientSection(templateID: duplicatedTemplate.id, sectionKey: section.sectionKey))
        }
        for group in customReportRecipientGroups where group.templateID == template.id {
            dataContext.insert(CustomReportRecipientGroup(templateID: duplicatedTemplate.id, groupID: group.groupID))
        }
        for contact in customReportRecipientContacts where contact.templateID == template.id {
            dataContext.insert(CustomReportRecipientContact(templateID: duplicatedTemplate.id, contactID: contact.contactID))
        }
        appendTemplateIDToOrder(duplicatedTemplate.id)
        saveContext()
        templateEditing = duplicatedTemplate
    }

    private func beginMoveMode() {
        syncTemplateOrderWithCurrentTemplates()
        moveDraftOrder = persistedTemplateOrderIDs()
        isMoveModeEnabled = true
    }

    private func finishMoveModeAndSave() {
        persistTemplateOrder(moveDraftOrder)
        isMoveModeEnabled = false
        draggingTemplateID = nil
        draggingTranslation = .zero
        draggingStartIndex = nil
        draggingLastTargetIndex = nil
    }

    private func activeTemplateOrderIDs() -> [UUID] {
        isMoveModeEnabled ? moveDraftOrder : persistedTemplateOrderIDs()
    }

    private func syncMoveDraftWithCurrentTemplates() {
        let currentTemplateIDs = Set(templates.map(\.id))
        moveDraftOrder = moveDraftOrder.filter { currentTemplateIDs.contains($0) }
        let missing = templates.map(\.id).filter { !moveDraftOrder.contains($0) }
        moveDraftOrder.append(contentsOf: missing)
    }

    private func persistedTemplateOrderIDs() -> [UUID] {
        guard let data = templateOrderData.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values.compactMap(UUID.init(uuidString:))
    }

    private func persistTemplateOrder(_ order: [UUID]) {
        let values = order.map(\.uuidString)
        guard let data = try? JSONEncoder().encode(values),
              let value = String(data: data, encoding: .utf8) else { return }
        templateOrderData = value
    }

    private func syncTemplateOrderWithCurrentTemplates() {
        let currentTemplateIDs = templates.map(\.id)
        let existingOrder = persistedTemplateOrderIDs().filter { currentTemplateIDs.contains($0) }
        let missingTemplateIDs = currentTemplateIDs.filter { !existingOrder.contains($0) }
        persistTemplateOrder(existingOrder + missingTemplateIDs)
    }

    private func appendTemplateIDToOrder(_ id: UUID) {
        var order = persistedTemplateOrderIDs()
        order.removeAll { $0 == id }
        order.append(id)
        persistTemplateOrder(order)
    }

    private func removeTemplateIDFromOrder(_ id: UUID) {
        var order = persistedTemplateOrderIDs()
        order.removeAll { $0 == id }
        persistTemplateOrder(order)
    }

    private func templateMoveGesture(for templateID: UUID, tileWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard isMoveModeEnabled else { return }
                if draggingTemplateID != templateID {
                    draggingTemplateID = templateID
                    draggingStartIndex = moveDraftOrder.firstIndex(of: templateID)
                    draggingLastTargetIndex = draggingStartIndex
                }

                draggingTranslation = value.translation
                updateDragReorder(tileWidth: tileWidth)
            }
            .onEnded { _ in
                draggingTemplateID = nil
                draggingTranslation = .zero
                draggingStartIndex = nil
                draggingLastTargetIndex = nil
            }
    }

    private func updateDragReorder(tileWidth: CGFloat) {
        guard let draggingTemplateID else { return }
        guard let sourceIndex = moveDraftOrder.firstIndex(of: draggingTemplateID) else { return }
        guard let draggingStartIndex else { return }

        let cellWidth = max(tileWidth + templateGridSpacing, 1)
        let cellHeight = templateTileHeight + templateGridSpacing
        let horizontalShift = Int((draggingTranslation.width / cellWidth).rounded())
        let verticalShift = Int((draggingTranslation.height / cellHeight).rounded())
        let proposedTarget = draggingStartIndex + horizontalShift + (verticalShift * templateGridColumnCount)
        let clampedTarget = min(max(0, proposedTarget), moveDraftOrder.count - 1)

        guard clampedTarget != sourceIndex else { return }
        guard clampedTarget != draggingLastTargetIndex else { return }

        var currentOrder = moveDraftOrder
        let movedID = currentOrder.remove(at: sourceIndex)
        currentOrder.insert(movedID, at: clampedTarget)
        moveDraftOrder = currentOrder
        draggingLastTargetIndex = clampedTarget
    }

    private func gridHeightEstimate() -> CGFloat {
        let rowCount: Int = {
            if isMoveModeEnabled {
                return max(1, Int(ceil(Double(placeholderSlotCount) / Double(templateGridColumnCount))))
            }
            return max(1, Int(ceil(Double(displayedTemplates.count + 1) / Double(templateGridColumnCount))))
        }()
        return (CGFloat(rowCount) * templateTileHeight) + (CGFloat(max(0, rowCount - 1)) * templateGridSpacing)
    }

    private func gradesSummary(for template: CustomReportTemplate) -> String {
        let selectedGradeNames = grades
            .filter { template.gradeIDs.contains($0.id) }
            .map(\.name)

        return selectedGradeNames.isEmpty ? "All grades" : selectedGradeNames.joined(separator: " • ")
    }

    private func reportDateRange(for template: CustomReportTemplate) -> ReportDateRange {
        let quickPick = ReportRangeQuickPick(rawValue: template.dateRangeQuickPickRawValue) ?? .mostRecentGame
        return buildDateRange(
            for: quickPick,
            template: template,
            games: games,
            customStartDate: template.customDateRangeStart,
            customEndDate: template.customDateRangeEnd
        )
    }

    private func recipientEmails(for template: CustomReportTemplate) -> [String] {
        let sectionKeys = Set(
            customReportRecipientSections
                .filter { $0.templateID == template.id }
                .map(\.sectionKey)
        )
        let sectionContactIDs = Set(
            sectionMemberships
                .filter { sectionKeys.contains($0.sectionKey) }
                .map(\.contactID)
        )

        let groupIDs = Set(
            customReportRecipientGroups
                .filter { $0.templateID == template.id }
                .map(\.groupID)
        )
        let groupContactIDs = Set(
            groupMemberships
                .filter { groupIDs.contains($0.groupID) }
                .map(\.contactID)
        )

        let individualContactIDs = Set(
            customReportRecipientContacts
                .filter { $0.templateID == template.id }
                .map(\.contactID)
        )

        let contactIDs = sectionContactIDs
            .union(groupContactIDs)
            .union(individualContactIDs)

        return contacts
            .filter { contactIDs.contains($0.id) }
            .map { $0.email.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

private struct TemplateRunRequest: Identifiable {
    let template: CustomReportTemplate
    let dateRange: ReportDateRange
    let emailRecipients: [String]

    var id: String {
        "\(template.id.uuidString)-\(dateRange.start.timeIntervalSince1970)-\(dateRange.end.timeIntervalSince1970)"
    }
}

private struct ReportDateRange {
    let start: Date
    let end: Date

    func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}

private enum ReportRangeQuickPick: String, CaseIterable, Identifiable {
    case mostRecentGame = "Most Recent Game"
    case previousWeek = "Previous Week"
    case previousMonth = "Previous Month"
    case currentYear = "Current Year"
    case custom = "Custom Date Range"

    var id: String { rawValue }
}

private func buildDateRange(
    for quickPick: ReportRangeQuickPick,
    template: CustomReportTemplate,
    games: [Game],
    customStartDate: Date,
    customEndDate: Date
) -> ReportDateRange {
    let calendar = Calendar.current
    let today = Date()
    switch quickPick {
    case .mostRecentGame:
        let scopedGames = games
            .filter { template.gradeIDs.isEmpty || template.gradeIDs.contains($0.gradeID) }
            .filter { !$0.isDraft && $0.date <= today }
        let mostRecentGameDate = scopedGames.map(\.date).max() ?? today
        let dayStart = calendar.startOfDay(for: mostRecentGameDate)
        let dayEnd = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: dayStart) ?? mostRecentGameDate
        return ReportDateRange(start: dayStart, end: dayEnd)
    case .previousWeek:
        let dayStart = calendar.startOfDay(for: today)
        let start = calendar.date(byAdding: .day, value: -7, to: dayStart) ?? dayStart
        let end = calendar.date(byAdding: DateComponents(second: -1), to: dayStart) ?? today
        return ReportDateRange(start: start, end: end)
    case .previousMonth:
        let dayStart = calendar.startOfDay(for: today)
        let start = calendar.date(byAdding: .month, value: -1, to: dayStart) ?? dayStart
        let end = calendar.date(byAdding: DateComponents(second: -1), to: dayStart) ?? today
        return ReportDateRange(start: start, end: end)
    case .currentYear:
        let year = calendar.component(.year, from: today)
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? calendar.startOfDay(for: today)
        return ReportDateRange(start: start, end: today)
    case .custom:
        let start = min(customStartDate, customEndDate)
        let end = max(customStartDate, customEndDate)
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        return ReportDateRange(
            start: startDay,
            end: calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endDay) ?? end
        )
    }
}

private struct CustomReportPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let template: CustomReportTemplate
    let grades: [Grade]
    let games: [Game]
    let players: [Player]
    let selectedDateRange: ReportDateRange
    let emailRecipients: [String]
    @State private var pdfURL: URL?
    @State private var errorMessage: String?
    @State private var showShareSheet = false
    @State private var showMailComposer = false
    @State private var showMailUnavailableAlert = false

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
                        if MFMailComposeViewController.canSendMail() {
                            showMailComposer = true
                        } else {
                            showMailUnavailableAlert = true
                            showShareSheet = true
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(pdfURL == nil || emailRecipients.isEmpty)
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
            .sheet(isPresented: $showMailComposer) {
                if let pdfURL {
                    ReportMailComposeView(
                        recipients: emailRecipients,
                        subject: "Custom Report: \(template.name)",
                        body: "Attached is the custom report PDF.",
                        attachmentURL: pdfURL
                    )
                }
            }
            .alert("Mail Not Configured", isPresented: $showMailUnavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Mail is not configured on this device. We opened the share sheet so you can still export the PDF.")
            }
            .task {
                guard pdfURL == nil, errorMessage == nil else { return }
                do {
                    pdfURL = try makeTemplatePreviewPDF(
                        template: template,
                        grades: grades,
                        games: games,
                        players: players,
                        dateRange: selectedDateRange
                    )
                } catch {
                    errorMessage = "Could not generate preview PDF."
                }
            }
        }
    }
}

private struct ReportMailComposeView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    let recipients: [String]
    let subject: String
    let body: String
    let attachmentURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: { dismiss() })
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        if let data = try? Data(contentsOf: attachmentURL) {
            controller.addAttachmentData(data, mimeType: "application/pdf", fileName: attachmentURL.lastPathComponent)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
            onFinish()
        }
    }
}

private struct CustomReportShareView: View {
    @Environment(\.dismiss) private var dismiss

    let template: CustomReportTemplate
    let grades: [Grade]
    let contacts: [Contact]
    let groups: [ContactGroup]
    let memberships: [ContactGroupMembership]
    let sectionMemberships: [ContactSectionMembership]
    let selectedDateRange: ReportDateRange

    @State private var selectedContactIDs: Set<UUID> = []
    @State private var selectedGroupIDs: Set<UUID> = []
    @State private var activeGroupID: UUID?
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    private var selectedContacts: [Contact] {
        contacts.filter { selectedContactIDs.contains($0.id) }
    }

    private var selectedGroups: [ContactGroup] {
        groups.filter { selectedGroupIDs.contains($0.id) }
    }

    private var contactCountByGroupID: [UUID: Int] {
        let validContactIDs = Set(contacts.map(\.id))
        return Dictionary(
            grouping: memberships.filter { validContactIDs.contains($0.contactID) },
            by: \.groupID
        ).mapValues { Set($0.map(\.contactID)).count }
    }

    private var activeGroupMembers: [Contact] {
        guard let activeGroupID else { return [] }
        let memberIDs = Set(memberships.filter { $0.groupID == activeGroupID }.map(\.contactID))
        return contacts
            .filter { memberIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var additionalContacts: [Contact] {
        let memberIDs = Set(activeGroupMembers.map(\.id))
        return contacts
            .filter { !memberIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var shareMessage: String {
        var lines: [String] = []
        lines.append("Custom report: \(template.name)")
        lines.append(buildTemplateDetails(for: template, grades: grades, dateRange: selectedDateRange))
        lines.append(selectedContacts.isEmpty ? "Selected contacts: none" : "Selected contacts: \(selectedContacts.map(\.name).joined(separator: ", "))")
        lines.append(selectedGroups.isEmpty ? "Selected groups: none" : "Selected groups: \(selectedGroups.map(\.name).joined(separator: ", "))")
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if groups.isEmpty {
                        Text("No groups found. Add groups in Settings > Contacts first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(groups) { group in
                            Button {
                                if selectedGroupIDs.contains(group.id) {
                                    selectedGroupIDs.remove(group.id)
                                    if activeGroupID == group.id {
                                        activeGroupID = selectedGroupIDs.first
                                    }
                                } else {
                                    selectedGroupIDs.insert(group.id)
                                    activeGroupID = group.id
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(group.name)
                                            .foregroundStyle(.primary)
                                        Text("\(contactCountByGroupID[group.id, default: 0]) contact(s)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedGroupIDs.contains(group.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    activeGroupID = group.id
                                } label: {
                                    Label("Set Active", systemImage: "scope")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                } header: {
                    Text("Recipient Groups")
                } footer: {
                    Text("Swipe a group and tap Set Active to show its members in Individuals.")
                }

                Section {
                    if activeGroupID == nil {
                        Text("Select a recipient group to view its individual contacts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if activeGroupMembers.isEmpty {
                        Text("No contacts in the selected group.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeGroupMembers) { contact in
                            Button {
                                if selectedContactIDs.contains(contact.id) { selectedContactIDs.remove(contact.id) }
                                else { selectedContactIDs.insert(contact.id) }
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

                    if contacts.isEmpty {
                        Text("No contacts found. Add contacts in Settings > Contacts first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Menu {
                            if additionalContacts.isEmpty {
                                Text("No additional contacts available")
                            } else {
                                ForEach(additionalContacts) { contact in
                                    Button {
                                        selectedContactIDs.insert(contact.id)
                                    } label: {
                                        Text(contact.name)
                                    }
                                }
                            }
                        } label: {
                            Label("Add Individual from Contact List", systemImage: "plus")
                        }
                    }
                } header: {
                    Text("Individuals")
                }
            }
            .navigationTitle("Share Report")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") {
                        shareItems = [shareMessage]
                        showShareSheet = true
                    }
                    .disabled(contacts.isEmpty && groups.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
    }
}

private func buildTemplateDetails(for template: CustomReportTemplate, grades: [Grade], dateRange: ReportDateRange) -> String {
    let gradeNames = grades
        .filter { !template.includeOnlyActiveGrades || $0.isActive }
        .filter { template.gradeIDs.isEmpty || template.gradeIDs.contains($0.id) }
        .map(\.name)

    var items: [String] = []
    if template.includeScores { items.append("Scores") }
    if template.includeBestPlayers { items.append("Best players") }
    if template.includePlayerGrades { items.append("Guest Votes") }
    if template.includeGoalKickers { items.append("Goal kickers") }
    if template.includeBestAndFairestVotes { items.append("B&F votes") }
    if template.includeStaffRoles { items.append("Coaches") }
    if template.includeOfficials { items.append("Officials") }
    if template.includeUmpires { items.append("Umpires") }
    if template.includeTrainers { items.append("Trainers") }
    if template.includeMatchNotes { items.append("Match notes") }

    let gradesText: String = {
        if gradeNames.isEmpty { return "All grades" }
        return "Grades: " + gradeNames.joined(separator: ", ")
    }()

    let grouping = ReportGroupingMode(rawValue: template.groupingModeRawValue) ?? .combinedTotals
    let filters = "Filters: min games \(template.minimumGamesPlayed), \(template.includeOnlyActiveGrades ? "active grades only" : "active + inactive"), \(grouping.filterSummary)"
    let dateRangeText = "Date range: \(formattedDate(dateRange.start)) – \(formattedDate(dateRange.end))"
    let sections = "Includes: " + (items.isEmpty ? "No sections selected" : items.joined(separator: ", "))
    return [gradesText, sections, filters, dateRangeText].joined(separator: " • ")
}

private func formattedDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
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
    players: [Player],
    dateRange: ReportDateRange
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
        .filter { dateRange.contains($0.date) }
        .sorted { $0.date > $1.date }
    let playerLookup = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
    let gradeLookup = Dictionary(uniqueKeysWithValues: grades.map { ($0.id, $0.name) })
    let selectedGradeNames = selectedGrades.map(\.name)
    let gradeSummary = selectedGradeNames.isEmpty ? "All grades" : selectedGradeNames.joined(separator: ", ")
    let dateSummary: String = {
        let start = dateRange.start.formatted(date: .abbreviated, time: .omitted)
        let end = dateRange.end.formatted(date: .abbreviated, time: .omitted)
        return start == end ? start : "\(start) – \(end)"
    }()
    var gamesByPlayer: [UUID: Int] = [:]

    func guestVotePoints(for rank: Int) -> Int {
        switch rank {
        case 1: return 3
        case 2: return 2
        case 3: return 1
        default: return 0
        }
    }

    func bestPlayerPoints(for index: Int) -> Int {
        switch index {
        case 0: return 3
        case 1: return 2
        case 2: return 1
        default: return 0
        }
    }

    func metadataSummary(for game: Game) -> String {
        var parts: [String] = []
        if template.includeStaffRoles {
            let staff = [game.headCoachName, game.assistantCoachName, game.teamManagerName, game.runnerName]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !staff.isEmpty { parts.append("Staff: \(staff.joined(separator: ", "))") }
        }
        if template.includeOfficials {
            let officials = [game.goalUmpireName, game.fieldUmpireName]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !officials.isEmpty { parts.append("Officials: \(officials.joined(separator: ", "))") }
        }
        if template.includeUmpires {
            let umpires = [game.boundaryUmpire1Name, game.boundaryUmpire2Name]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !umpires.isEmpty { parts.append("Boundary: \(umpires.joined(separator: ", "))") }
        }
        if template.includeTrainers {
            let trainers = game.trainers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !trainers.isEmpty { parts.append("Trainers: \(trainers.joined(separator: ", "))") }
        }
        if template.includeMatchNotes {
            let notes = game.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty { parts.append("Notes: \(notes)") }
        }
        return parts.joined(separator: " • ")
    }
    for game in relevantGames {
        var seenPlayerIDs = Set<UUID>()
        if template.includeGoalKickers {
            for entry in game.goalKickers {
                if let playerID = entry.playerID {
                    seenPlayerIDs.insert(playerID)
                }
            }
        }
        if template.includeBestPlayers || template.includeBestAndFairestVotes {
            for playerID in game.bestPlayersRanked {
                seenPlayerIDs.insert(playerID)
            }
        }
        if template.includePlayerGrades || template.includeBestAndFairestVotes {
            for vote in game.guestVotesRanked {
                seenPlayerIDs.insert(vote.playerID)
            }
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
        let scoreBannerFont = UIFont(name: "AvenirNext-Bold", size: 26) ?? UIFont.systemFont(ofSize: 26, weight: .bold)
        let scoreDetailFont = UIFont(name: "AvenirNext-DemiBold", size: 12) ?? UIFont.systemFont(ofSize: 12, weight: .semibold)

        if let logo = UIImage(named: "club_logo") {
            let logoRect = CGRect(x: contentRect.minX, y: cursorY, width: 56, height: 56)
            logo.draw(in: logoRect)
        }

        let titleX = contentRect.minX + 68
        let titleRect = CGRect(x: titleX, y: cursorY + 4, width: contentRect.width - 68, height: 28)
        NSAttributedString(
            string: template.name,
            attributes: [.font: titleFont, .foregroundColor: UIColor.black]
        ).draw(in: titleRect)

        let subtitle = "\(dateSummary) • \(gradeSummary)"
        let subtitleRect = CGRect(x: titleX, y: titleRect.maxY + 2, width: contentRect.width - 68, height: 22)
        NSAttributedString(
            string: subtitle,
            attributes: [.font: subtitleFont, .foregroundColor: UIColor.darkGray]
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
            NSAttributedString(
                string: text,
                attributes: [.font: sectionFont, .foregroundColor: UIColor.black]
            ).draw(in: rect)
            cursorY += 24
        }

        func drawTableHeader() {
            beginNewPageIfNeeded(requiredHeight: 24)
            var x = contentRect.minX
            let headerY = cursorY
            for (idx, column) in tableColumns.enumerated() {
                let width = columnWidths[idx]
                let rect = CGRect(x: x, y: headerY, width: width, height: 22)
                UIColor(white: 0.92, alpha: 1).setFill()
                UIBezierPath(rect: rect).fill()
                UIColor.separator.setStroke()
                UIBezierPath(rect: rect).stroke()
                NSAttributedString(
                    string: column.0,
                    attributes: [.font: headerFont, .foregroundColor: UIColor.black]
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
                    attributes: [.font: bodyFont, .foregroundColor: UIColor.black]
                ).draw(in: rect.insetBy(dx: 4, dy: 4))
                x += width
            }
            cursorY += 20
        }

        func drawDetailTable(title: String, columns: [String], rows: [[String]]) {
            drawSectionHeader(title)
            beginNewPageIfNeeded(requiredHeight: 24)

            let weights: [CGFloat]
            if columns.count == 2, columns[1].lowercased() == "goals" || columns[1].lowercased() == "points" {
                weights = [0.82, 0.18]
            } else if columns.count == 2, columns[0].lowercased() == "rank" {
                weights = [0.18, 0.82]
            } else {
                weights = columns.enumerated().map { index, _ in
                    index == 0 ? 0.34 : (0.66 / CGFloat(max(columns.count - 1, 1)))
                }
            }
            let widths = weights.map { $0 * contentRect.width }

            var headerX = contentRect.minX
            for (index, column) in columns.enumerated() {
                let width = widths[index]
                let rect = CGRect(x: headerX, y: cursorY, width: width, height: 22)
                UIColor(red: 0.93, green: 0.95, blue: 0.99, alpha: 1).setFill()
                UIBezierPath(rect: rect).fill()
                UIColor.separator.setStroke()
                UIBezierPath(rect: rect).stroke()
                NSAttributedString(
                    string: column,
                    attributes: [.font: headerFont, .foregroundColor: UIColor.black]
                ).draw(in: rect.insetBy(dx: 4, dy: 5))
                headerX += width
            }
            cursorY += 22

            let safeRows = rows.isEmpty ? [["No data for selected date range"]] : rows
            for (rowIndex, row) in safeRows.enumerated() {
                beginNewPageIfNeeded(requiredHeight: 20)
                if rowIndex.isMultiple(of: 2) {
                    UIColor(white: 0.985, alpha: 1).setFill()
                    UIBezierPath(rect: CGRect(x: contentRect.minX, y: cursorY, width: contentRect.width, height: 20)).fill()
                }
                var x = contentRect.minX
                for (index, width) in widths.enumerated() {
                    let value = index < row.count ? row[index] : ""
                    let rect = CGRect(x: x, y: cursorY, width: width, height: 20)
                    UIColor.separator.setStroke()
                    UIBezierPath(rect: rect).stroke()
                    NSAttributedString(
                        string: value,
                        attributes: [.font: bodyFont, .foregroundColor: UIColor.black]
                    ).draw(in: rect.insetBy(dx: 4, dy: 4))
                    x += width
                }
                cursorY += 20
            }
            cursorY += 10
        }

        func drawCompactTable(
            title: String,
            columns: [String],
            rows: [[String]],
            xOrigin: CGFloat,
            width: CGFloat
        ) -> CGFloat {
            let startY = cursorY
            let sectionRect = CGRect(x: xOrigin, y: cursorY, width: width, height: 20)
            NSAttributedString(
                string: title,
                attributes: [.font: sectionFont, .foregroundColor: UIColor.black]
            ).draw(in: sectionRect)
            var localY = cursorY + 22
            let colWidths = columns.map { _ in width / CGFloat(max(columns.count, 1)) }

            var x = xOrigin
            for (index, column) in columns.enumerated() {
                let rect = CGRect(x: x, y: localY, width: colWidths[index], height: 20)
                UIColor(white: 0.92, alpha: 1).setFill()
                UIBezierPath(rect: rect).fill()
                UIColor.separator.setStroke()
                UIBezierPath(rect: rect).stroke()
                NSAttributedString(
                    string: column,
                    attributes: [.font: headerFont, .foregroundColor: UIColor.black]
                ).draw(in: rect.insetBy(dx: 4, dy: 4))
                x += colWidths[index]
            }
            localY += 20

            let safeRows = rows.isEmpty ? [["No data"]] : rows
            for row in safeRows {
                x = xOrigin
                for (index, colWidth) in colWidths.enumerated() {
                    let value = index < row.count ? row[index] : ""
                    let rect = CGRect(x: x, y: localY, width: colWidth, height: 18)
                    UIColor.separator.setStroke()
                    UIBezierPath(rect: rect).stroke()
                    NSAttributedString(
                        string: value,
                        attributes: [.font: bodyFont, .foregroundColor: UIColor.black]
                    ).draw(in: rect.insetBy(dx: 4, dy: 3))
                    x += colWidth
                }
                localY += 18
            }
            return localY - startY
        }

        if relevantGames.isEmpty {
            drawSectionHeader("No completed games matched this template.")
            return
        }

        let primaryGame = relevantGames.first
        let configuration = ClubConfigurationStore.load()

        func drawScorePills(for game: Game, title: String) {
            drawSectionHeader(title)
            beginNewPageIfNeeded(requiredHeight: 100)
            let ourScoreText = "\(game.ourGoals).\(game.ourBehinds) (\(game.ourScore))"
            let oppScoreText = "\(game.theirGoals).\(game.theirBehinds) (\(game.theirScore))"
            let ourStyle = ClubStyle.style(for: configuration.clubTeam.name, configuration: configuration)
            let oppStyle = ClubStyle.style(for: game.opponent, configuration: configuration)
            let pills: [(String, UIColor, UIColor)] = [
                (ourScoreText, UIColor(ourStyle.background), UIColor(ourStyle.text)),
                (oppScoreText, UIColor(oppStyle.background), UIColor(oppStyle.text))
            ]
            let gap: CGFloat = 10
            let pillWidth = (contentRect.width - gap) / 2
            var x = contentRect.minX
            for (index, pill) in pills.enumerated() {
                let rect = CGRect(x: x, y: cursorY, width: pillWidth, height: 74)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 18)
                pill.1.setFill()
                path.fill()
                let teamName = index == 0 ? configuration.clubTeam.name : game.opponent
                NSAttributedString(
                    string: teamName.uppercased(),
                    attributes: [.font: scoreDetailFont, .foregroundColor: pill.2]
                ).draw(in: CGRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16))
                NSAttributedString(
                    string: pill.0,
                    attributes: [.font: scoreBannerFont, .foregroundColor: pill.2]
                ).draw(in: CGRect(x: rect.minX + 12, y: rect.minY + 28, width: rect.width - 24, height: 36))
                x += pillWidth + gap
            }
            cursorY += 86
        }

        let minimumGamesThreshold = max(template.minimumGamesPlayed, 1)
        let bestPlayersLimit = max(0, min(template.bestPlayersLimit, 10))
        let guestVotesLimit = max(0, min(template.guestVotesLimit, 10))
        let goalKickersLimit = max(0, min(template.goalKickersLimit, 10))
        let bestAndFairestLimit = max(0, min(template.bestAndFairestLimit, 10))

        func reportRows(for game: Game?) -> (bestPlayers: [[String]], guestVotes: [[String]], goalKickers: [[String]], bestAndFairest: [[String]]) {
            let rankedBestPlayerIDs: [UUID] = game?.bestPlayersRanked ?? []
            let allBestPlayersRows = rankedBestPlayerIDs.enumerated().compactMap { (index: Int, playerID: UUID) -> [String]? in
                guard gamesByPlayer[playerID, default: 0] >= minimumGamesThreshold else { return nil }
                return ["\(index + 1)", playerLookup[playerID]?.name ?? "Unknown Player"]
            }
            let bestPlayersRows = bestPlayersLimit == 0 ? allBestPlayersRows : Array(allBestPlayersRows.prefix(bestPlayersLimit))
            let allGuestVoteRows = (game?.guestVotesRanked ?? [])
                .filter { gamesByPlayer[$0.playerID, default: 0] >= minimumGamesThreshold }
                .sorted { $0.rank < $1.rank }
                .map { vote in
                    ["\(vote.rank)", playerLookup[vote.playerID]?.name ?? "Unknown Player"]
                }
            let guestVoteRows = guestVotesLimit == 0 ? allGuestVoteRows : Array(allGuestVoteRows.prefix(guestVotesLimit))
            let allGoalKickerRows = (game?.goalKickers ?? [])
                .filter { entry in
                    guard let playerID = entry.playerID else { return false }
                    return gamesByPlayer[playerID, default: 0] >= minimumGamesThreshold && entry.goals > 0
                }
                .sorted { $0.goals > $1.goals }
                .map { entry in
                    let name = entry.playerID.flatMap { playerLookup[$0]?.name } ?? "Unknown Player"
                    return [name, "\(entry.goals)"]
                }
            let goalKickerRows = goalKickersLimit == 0 ? allGoalKickerRows : Array(allGoalKickerRows.prefix(goalKickersLimit))
            var bestAndFairestPoints: [UUID: Int] = [:]
            for (index, playerID) in (game?.bestPlayersRanked ?? []).enumerated() {
                bestAndFairestPoints[playerID, default: 0] += bestPlayerPoints(for: index)
            }
            for vote in (game?.guestVotesRanked ?? []) {
                bestAndFairestPoints[vote.playerID, default: 0] += guestVotePoints(for: vote.rank)
            }
            let allBestAndFairestRows = bestAndFairestPoints
                .sorted { $0.value > $1.value }
                .compactMap { (playerID, pointTotal) -> [String]? in
                    guard pointTotal > 0, gamesByPlayer[playerID, default: 0] >= minimumGamesThreshold else { return nil }
                    return [playerLookup[playerID]?.name ?? "Unknown Player", "\(pointTotal)"]
                }
            let bestAndFairestRows = bestAndFairestLimit == 0 ? allBestAndFairestRows : Array(allBestAndFairestRows.prefix(bestAndFairestLimit))
            return (bestPlayersRows, guestVoteRows, goalKickerRows, bestAndFairestRows)
        }

        struct CompactReportTable {
            let title: String
            let columns: [String]
            let rows: [[String]]
        }

        func buildCompactTables(for rows: (bestPlayers: [[String]], guestVotes: [[String]], goalKickers: [[String]], bestAndFairest: [[String]])) -> [CompactReportTable] {
            var compactTables: [CompactReportTable] = []
            if template.includeBestPlayers {
                compactTables.append(CompactReportTable(title: "Best Players", columns: ["Rank", "Player"], rows: rows.bestPlayers))
            }
            if template.includeGoalKickers {
                compactTables.append(CompactReportTable(title: "Goal Kickers", columns: ["Player", "Goals"], rows: rows.goalKickers))
            }
            if template.includePlayerGrades {
                compactTables.append(CompactReportTable(title: "Guest Votes", columns: ["Rank", "Player"], rows: rows.guestVotes))
            }
            if template.includeBestAndFairestVotes {
                compactTables.append(CompactReportTable(title: "Best and Fairest", columns: ["Player", "Points"], rows: rows.bestAndFairest))
            }
            return compactTables
        }

        func drawCompactTables(_ compactTables: [CompactReportTable]) {
            guard !compactTables.isEmpty else { return }
            let gap: CGFloat = 10
            let halfWidth = (contentRect.width - gap) / 2
            var index = 0
            while index < compactTables.count {
                beginNewPageIfNeeded(requiredHeight: 160)
                let leftTable = compactTables[index]
                let leftHeight = drawCompactTable(
                    title: leftTable.title,
                    columns: leftTable.columns,
                    rows: leftTable.rows,
                    xOrigin: contentRect.minX,
                    width: halfWidth
                )
                let rowStartY = cursorY
                var rowHeight = leftHeight

                if index + 1 < compactTables.count {
                    let rightTable = compactTables[index + 1]
                    let rightHeight = drawCompactTable(
                        title: rightTable.title,
                        columns: rightTable.columns,
                        rows: rightTable.rows,
                        xOrigin: contentRect.minX + halfWidth + gap,
                        width: halfWidth
                    )
                    rowHeight = max(leftHeight, rightHeight)
                }

                cursorY = rowStartY + rowHeight + 8
                index += 2
            }
        }

        let gradeOrderLookup = Dictionary(uniqueKeysWithValues: selectedGrades.enumerated().map { ($0.element.id, $0.offset) })
        let gradeGames = Dictionary(grouping: relevantGames, by: \.gradeID)
            .compactMap { gradeID, games -> (gradeID: UUID, game: Game)? in
                guard let game = games.max(by: { $0.date < $1.date }) else { return nil }
                return (gradeID: gradeID, game: game)
            }
            .sorted {
                let leftOrder = gradeOrderLookup[$0.gradeID] ?? Int.max
                let rightOrder = gradeOrderLookup[$1.gradeID] ?? Int.max
                if leftOrder != rightOrder { return leftOrder < rightOrder }
                return (gradeLookup[$0.gradeID] ?? "") < (gradeLookup[$1.gradeID] ?? "")
            }

        if gradeGames.count > 1 {
            for gradeGame in gradeGames {
                let gradeName = gradeLookup[gradeGame.gradeID] ?? "Unknown Grade"
                drawSectionHeader(gradeName)
                let game = gradeGame.game
                if template.includeScores {
                    drawScorePills(for: game, title: "Score")
                }
                let rows = reportRows(for: game)
                drawCompactTables(buildCompactTables(for: rows))
            }
        } else {
            if template.includeScores {
                if let game = primaryGame {
                    drawScorePills(for: game, title: "Score")
                } else {
                    let scoreRows = relevantGames.map { game in
                        let gradeName = gradeLookup[game.gradeID] ?? "Unknown Grade"
                        let our = "\(game.ourGoals).\(game.ourBehinds) (\(game.ourScore))"
                        let opponent = "\(game.theirGoals).\(game.theirBehinds) (\(game.theirScore))"
                        return [formattedDate(game.date), gradeName, game.opponent, our, opponent]
                    }
                    drawDetailTable(
                        title: "Scores",
                        columns: ["Date", "Grade", "Opponent", "Us", "Them"],
                        rows: scoreRows
                    )
                }
            }
            let rows = reportRows(for: primaryGame)
            drawCompactTables(buildCompactTables(for: rows))
        }

        if template.includeStaffRoles {
            let rows = primaryGame.map { game in
                [[
                    game.headCoachName.trimmingCharacters(in: .whitespacesAndNewlines),
                    game.assistantCoachName.trimmingCharacters(in: .whitespacesAndNewlines),
                    game.teamManagerName.trimmingCharacters(in: .whitespacesAndNewlines),
                    game.runnerName.trimmingCharacters(in: .whitespacesAndNewlines)
                ]]
            } ?? []
            drawDetailTable(title: "Coaches", columns: ["Head", "Assistant", "Manager", "Runner"], rows: rows)
        }

        if template.includeOfficials {
            let rows = primaryGame.map { game in
                [[
                    game.goalUmpireName.trimmingCharacters(in: .whitespacesAndNewlines),
                    game.fieldUmpireName.trimmingCharacters(in: .whitespacesAndNewlines)
                ]]
            } ?? []
            drawDetailTable(title: "Officials", columns: ["Goal", "Field"], rows: rows)
        }

        if template.includeUmpires {
            let rows = primaryGame.map { game in
                [[
                    game.boundaryUmpire1Name.trimmingCharacters(in: .whitespacesAndNewlines),
                    game.boundaryUmpire2Name.trimmingCharacters(in: .whitespacesAndNewlines)
                ]]
            } ?? []
            drawDetailTable(title: "Umpires", columns: ["Boundary 1", "Boundary 2"], rows: rows)
        }

        if template.includeTrainers {
            let rows = primaryGame.map { game in
                game.trainers
                    .map { ["Trainer", $0.trimmingCharacters(in: .whitespacesAndNewlines)] }
            } ?? []
            drawDetailTable(title: "Trainers", columns: ["Role", "Name"], rows: rows)
        }

        if template.includeMatchNotes {
            let rows = primaryGame.map { game in
                [[game.notes.trimmingCharacters(in: .whitespacesAndNewlines)]]
            } ?? []
            drawDetailTable(title: "Match Notes", columns: ["Notes"], rows: rows)
        }
    }

    let safeName = template.name
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: " ", with: "_")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CustomReport_\(safeName)_Preview.pdf")
    try data.write(to: url, options: Data.WritingOptions.atomic)
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
    let contacts: [Contact]
    let sectionMemberships: [ContactSectionMembership]
    let onDelete: (() -> Void)?
    let onSave: (String, [UUID], Bool, Bool, Int, Bool, Int, Bool, Int, Bool, Int, Bool, Bool, Bool, Bool, Bool, Bool, Int, Int, String, Date, Date, [String], [UUID]) -> Void

    @State private var name: String
    @State private var selectedGradeIDs: Set<UUID>
    @State private var includeScores: Bool
    @State private var includeBestPlayers: Bool
    @State private var bestPlayersLimit: Int
    @State private var includeGuestVotes: Bool
    @State private var guestVotesLimit: Int
    @State private var includeGoalKickers: Bool
    @State private var goalKickersLimit: Int
    @State private var includeBestAndFairestVotes: Bool
    @State private var bestAndFairestLimit: Int
    @State private var includeStaffRoles: Bool
    @State private var includeOfficials: Bool
    @State private var includeUmpires: Bool
    @State private var includeTrainers: Bool
    @State private var includeMatchNotes: Bool
    @State private var includeOnlyActiveGrades: Bool
    @State private var minimumGamesPlayed: Int
    @State private var groupingMode: ReportGroupingMode
    @State private var selectedDateRangeQuickPick: ReportRangeQuickPick
    @State private var customDateRangeStart: Date
    @State private var customDateRangeEnd: Date
    @State private var selectedRecipientSectionKeys: Set<String>
    @State private var selectedRecipientContactIDs: Set<UUID>
    @State private var showDeleteConfirmation = false
    @AppStorage("contactSectionCustomTitles") private var customSectionTitlesData: String = ""

    init(
        grades: [Grade],
        contacts: [Contact],
        sectionMemberships: [ContactSectionMembership],
        initialName: String = "",
        initialSelectedGradeIDs: [UUID] = [],
        initialIncludeScores: Bool = true,
        initialIncludeBestPlayers: Bool = false,
        initialBestPlayersLimit: Int = 0,
        initialIncludeGuestVotes: Bool = false,
        initialGuestVotesLimit: Int = 0,
        initialIncludeGoalKickers: Bool = false,
        initialGoalKickersLimit: Int = 0,
        initialIncludeBestAndFairestVotes: Bool = false,
        initialBestAndFairestLimit: Int = 5,
        initialIncludeStaffRoles: Bool = false,
        initialIncludeOfficials: Bool = false,
        initialIncludeUmpires: Bool = false,
        initialIncludeTrainers: Bool = false,
        initialIncludeMatchNotes: Bool = false,
        initialIncludeOnlyActiveGrades: Bool = true,
        initialMinimumGamesPlayed: Int = 1,
        initialGroupingModeRawValue: Int = 1,
        initialDateRangeQuickPickRawValue: String = ReportRangeQuickPick.mostRecentGame.rawValue,
        initialCustomDateRangeStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
        initialCustomDateRangeEnd: Date = Date(),
        initialRecipientSectionKeys: [String] = [],
        initialRecipientContactIDs: [UUID] = [],
        onDelete: (() -> Void)? = nil,
        onSave: @escaping (String, [UUID], Bool, Bool, Int, Bool, Int, Bool, Int, Bool, Int, Bool, Bool, Bool, Bool, Bool, Bool, Int, Int, String, Date, Date, [String], [UUID]) -> Void
    ) {
        self.grades = grades
        self.contacts = contacts
        self.sectionMemberships = sectionMemberships
        self.onDelete = onDelete
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _selectedGradeIDs = State(initialValue: Set(initialSelectedGradeIDs))
        _includeScores = State(initialValue: initialIncludeScores)
        _includeBestPlayers = State(initialValue: initialIncludeBestPlayers)
        _bestPlayersLimit = State(initialValue: Self.clampedReportItemLimit(initialBestPlayersLimit, defaultValue: 0))
        _includeGuestVotes = State(initialValue: initialIncludeGuestVotes)
        _guestVotesLimit = State(initialValue: Self.clampedReportItemLimit(initialGuestVotesLimit, defaultValue: 0))
        _includeGoalKickers = State(initialValue: initialIncludeGoalKickers)
        _goalKickersLimit = State(initialValue: Self.clampedReportItemLimit(initialGoalKickersLimit, defaultValue: 0))
        _includeBestAndFairestVotes = State(initialValue: initialIncludeBestAndFairestVotes)
        _bestAndFairestLimit = State(initialValue: Self.clampedReportItemLimit(initialBestAndFairestLimit, defaultValue: 5))
        _includeStaffRoles = State(initialValue: initialIncludeStaffRoles)
        _includeOfficials = State(initialValue: initialIncludeOfficials)
        _includeUmpires = State(initialValue: initialIncludeUmpires)
        _includeTrainers = State(initialValue: initialIncludeTrainers)
        _includeMatchNotes = State(initialValue: initialIncludeMatchNotes)
        _includeOnlyActiveGrades = State(initialValue: initialIncludeOnlyActiveGrades)
        _minimumGamesPlayed = State(initialValue: max(0, initialMinimumGamesPlayed))
        _groupingMode = State(initialValue: ReportGroupingMode(rawValue: initialGroupingModeRawValue) ?? .combinedTotals)
        _selectedDateRangeQuickPick = State(initialValue: ReportRangeQuickPick(rawValue: initialDateRangeQuickPickRawValue) ?? .mostRecentGame)
        _customDateRangeStart = State(initialValue: initialCustomDateRangeStart)
        _customDateRangeEnd = State(initialValue: initialCustomDateRangeEnd)
        _selectedRecipientSectionKeys = State(initialValue: Set(initialRecipientSectionKeys))
        _selectedRecipientContactIDs = State(initialValue: Set(initialRecipientContactIDs))
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date Range") {
                    Picker("Range", selection: $selectedDateRangeQuickPick) {
                        ForEach(ReportRangeQuickPick.allCases) { quickPick in
                            Text(quickPick.rawValue).tag(quickPick)
                        }
                    }

                    if selectedDateRangeQuickPick == .custom {
                        DatePicker("Start Date", selection: $customDateRangeStart, displayedComponents: .date)
                        DatePicker("End Date", selection: $customDateRangeEnd, displayedComponents: .date)
                    }
                }

                Section {
                    TextField("Report name", text: $name)
                } header: {
                    Text("Template")
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                        ForEach(grades) { grade in
                            let isSelected = selectedGradeIDs.contains(grade.id)
                            Button {
                                if isSelected {
                                    selectedGradeIDs.remove(grade.id)
                                } else {
                                    selectedGradeIDs.insert(grade.id)
                                }
                            } label: {
                                Text(grade.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 10)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? Color.blue : Color.secondary.opacity(0.2))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("No grade selected means all grades.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Grades")
                }

                Section {
                    Toggle("Scores", isOn: $includeScores)
                    toggleWithLimitPicker(title: "Best players", isOn: $includeBestPlayers, limit: $bestPlayersLimit, defaultLimitWhenEnabled: 0)
                    toggleWithLimitPicker(title: "Guest Votes", isOn: $includeGuestVotes, limit: $guestVotesLimit, defaultLimitWhenEnabled: 0)
                    toggleWithLimitPicker(title: "Goal Kickers", isOn: $includeGoalKickers, limit: $goalKickersLimit, defaultLimitWhenEnabled: 0)
                    toggleWithLimitPicker(title: "Best and Fairest votes", isOn: $includeBestAndFairestVotes, limit: $bestAndFairestLimit, defaultLimitWhenEnabled: 5)
                    Toggle("Coaches", isOn: $includeStaffRoles)
                    Toggle("Officials", isOn: $includeOfficials)
                    Toggle("Umpires", isOn: $includeUmpires)
                    Toggle("Trainers", isOn: $includeTrainers)
                    Toggle("Match notes", isOn: $includeMatchNotes)
                } header: {
                    Text("Data Included")
                }

                Section {
                    if recipientSections.isEmpty {
                        Text("No groups found. Create groups in Settings > Groups.")
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                            spacing: 8
                        ) {
                            ForEach(recipientSections, id: \.sectionKey) { section in
                                let isSelected = selectedRecipientSectionKeys.contains(section.sectionKey)
                                Button {
                                    if isSelected {
                                        selectedRecipientSectionKeys.remove(section.sectionKey)
                                    } else {
                                        selectedRecipientSectionKeys.insert(section.sectionKey)
                                    }
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(section.title)
                                            .font(.footnote.weight(.semibold))
                                            .lineLimit(1)
                                        Text("\(contactCountBySectionKey[section.sectionKey, default: 0])")
                                            .font(.caption2)
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .padding(.horizontal, 6)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? Color.blue : Color.secondary.opacity(0.2))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    Text("Report Recipients • Groups")
                }

                Section {
                    let groupMemberContacts = contactsFromSelectedGroups()
                    if groupMemberContacts.isEmpty {
                        Text("No recipients in selected groups.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(groupMemberContacts) { contact in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(contact.name)
                                Text("From selected group")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    let individualContacts = selectedIndividualRecipients()
                    if individualContacts.isEmpty {
                        Text("No extra individual recipients selected.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(individualContacts) { contact in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(contact.name)
                                Text("Added individually")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    selectedRecipientContactIDs.remove(contact.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }

                    Menu {
                        let additionalContacts = availableAdditionalRecipients()
                        if additionalContacts.isEmpty {
                            Text("No available contacts")
                        } else {
                            ForEach(additionalContacts) { contact in
                                Button(contact.name) {
                                    selectedRecipientContactIDs.insert(contact.id)
                                }
                            }
                        }
                    } label: {
                        Label("Add Individual", systemImage: "plus")
                    }
                } header: {
                    Text("Report Recipients • Individual Recipients")
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
                            includeScores,
                            includeBestPlayers,
                            bestPlayersLimit,
                            includeGuestVotes,
                            guestVotesLimit,
                            includeGoalKickers,
                            goalKickersLimit,
                            includeBestAndFairestVotes,
                            bestAndFairestLimit,
                            includeStaffRoles,
                            includeOfficials,
                            includeUmpires,
                            includeTrainers,
                            includeMatchNotes,
                            includeOnlyActiveGrades,
                            minimumGamesPlayed,
                            groupingMode.rawValue,
                            selectedDateRangeQuickPick.rawValue,
                            customDateRangeStart,
                            customDateRangeEnd,
                            Array(selectedRecipientSectionKeys),
                            Array(selectedRecipientContactIDs)
                        )
                        dismiss()
                    }
                    .saveButtonBehavior(isEnabled: canSave)
                }

                if onDelete != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Report", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .alert("Delete report?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This report template will be permanently deleted.")
        }
    }

    private static func clampedReportItemLimit(_ value: Int, defaultValue: Int) -> Int {
        let safeDefault = max(0, min(defaultValue, 10))
        if (0...10).contains(value) {
            return value
        }
        return safeDefault
    }

    @ViewBuilder
    private func toggleWithLimitPicker(
        title: String,
        isOn: Binding<Bool>,
        limit: Binding<Int>,
        defaultLimitWhenEnabled: Int
    ) -> some View {
        HStack(spacing: 12) {
            Toggle(title, isOn: isOn)
            if isOn.wrappedValue {
                Picker(title, selection: limit) {
                    Text("ALL").tag(0)
                    ForEach(1...10, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 74, alignment: .trailing)
            }
        }
        .onChange(of: isOn.wrappedValue) { isEnabled in
            guard isEnabled else { return }
            let clampedDefault = Self.clampedReportItemLimit(defaultLimitWhenEnabled, defaultValue: 0)
            if !(0...10).contains(limit.wrappedValue) {
                limit.wrappedValue = clampedDefault
            } else if title == "Best and Fairest votes", limit.wrappedValue == 0 {
                limit.wrappedValue = clampedDefault
            }
        }
    }

    private struct RecipientSectionOption {
        let sectionKey: String
        let title: String
    }

    private var customSectionTitles: [String: String] {
        guard
            let data = customSectionTitlesData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private var recipientSections: [RecipientSectionOption] {
        let sectionKeys = Set(sectionMemberships.map(\.sectionKey))
        return sectionKeys
            .map { RecipientSectionOption(sectionKey: $0, title: displayTitle(for: $0)) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var contactCountBySectionKey: [String: Int] {
        Dictionary(grouping: sectionMemberships, by: \.sectionKey)
            .mapValues { Set($0.map(\.contactID)).count }
    }

    private func displayTitle(for sectionKey: String) -> String {
        if let custom = customSectionTitles[sectionKey], !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        switch ContactSectionKey.fromRawValue(sectionKey) {
        case let .coachesGrade(gradeID):
            return grades.first(where: { $0.id == gradeID })?.name ?? "Coaches"
        default:
            return ContactSectionKey.fromRawValue(sectionKey).title
        }
    }

    private func contactsFromSelectedGroups() -> [Contact] {
        let memberIDs = Set(
            sectionMemberships
                .filter { selectedRecipientSectionKeys.contains($0.sectionKey) }
                .map(\.contactID)
        )
        return contacts
            .filter { memberIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func selectedIndividualRecipients() -> [Contact] {
        contacts
            .filter { selectedRecipientContactIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func availableAdditionalRecipients() -> [Contact] {
        let groupedIDs = Set(contactsFromSelectedGroups().map(\.id))
        return contacts
            .filter { !groupedIDs.contains($0.id) }
            .filter { !selectedRecipientContactIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct ReportRecipientsSettingsView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext

    @Query(sort: [SortDescriptor(\Grade.displayOrder), SortDescriptor(\Grade.name)]) private var grades: [Grade]
    @Query(sort: [SortDescriptor(\Contact.name)]) private var contacts: [Contact]
    @Query(sort: [SortDescriptor(\ContactGroup.name)]) private var groups: [ContactGroup]
    @Query private var memberships: [ContactGroupMembership]
    @Query private var reportRecipients: [ReportRecipient]
    @Query private var reportRecipientGroups: [ReportRecipientGroup]
    @State private var activeGroupByGrade: [UUID: UUID] = [:]
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
                let contactRecipients = recipientsForGrade(grade.id)
                let groupRecipients = groupRecipientsForGrade(grade.id)
                let groupIDs = Set(groupRecipients.map(\.groupID))
                let activeGroupID = {
                        if let saved = activeGroupByGrade[grade.id], groupIDs.contains(saved) { return saved }
                    return groupRecipients.first!.groupID
                    }()
                let individualsInActiveGroup = individualsForGroup(activeGroupID, within: contactRecipients)

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recipient Groups")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if groupRecipients.isEmpty {
                            Text("No recipient groups added yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(groupRecipients) { recipient in
                                if let group = groups.first(where: { $0.id == recipient.groupID }) {
                                    let count = memberships.filter { $0.groupID == group.id }.count
                                    recipientRow(
                                        title: "Group: \(group.name)",
                                        subtitle: "\(count) contact(s)",
                                        secondarySubtitle: "",
                                        sendEmail: Binding(
                                            get: { recipient.sendEmail },
                                            set: { newValue in
                                                recipient.sendEmail = newValue
                                                if !recipient.sendEmail && !recipient.sendText { recipient.sendText = true }
                                                saveContext()
                                            }
                                        ),
                                        sendText: Binding(
                                            get: { recipient.sendText },
                                            set: { newValue in
                                                recipient.sendText = newValue
                                                if !recipient.sendEmail && !recipient.sendText { recipient.sendEmail = true }
                                                saveContext()
                                            }
                                        ),
                                        footer: sendModeText(sendEmail: recipient.sendEmail, sendText: recipient.sendText)
                                    ) {
                                        dataContext.delete(recipient)
                                        saveContext()
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            activeGroupByGrade[grade.id] = recipient.groupID
                                        } label: {
                                            Label("Set Active", systemImage: "scope")
                                        }
                                        .tint(.blue)
                                    }
                                }
                            }
                        }

                        Menu {
                            let usedGroupIDs = Set(groupRecipients.map(\.groupID))
                            let availableGroups = groups.filter { !usedGroupIDs.contains($0.id) }

                            if availableGroups.isEmpty {
                                Text("No available groups")
                            } else {
                                ForEach(availableGroups) { group in
                                    Menu(group.name) {
                                        ForEach(SendMode.allCases) { mode in
                                            Button("Send via \(mode.title)") {
                                                addGroup(group, toGrade: grade.id, sendMode: mode)
                                                activeGroupByGrade[grade.id] = group.id
                                            }
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("Add Recipient Group", systemImage: "plus")
                        }

                        Divider()

                        Text("Individuals")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if groupRecipients.isEmpty {
                            Text("Add a recipient group first to view individuals.")
                                .foregroundStyle(.secondary)
                        } else {
                            if let activeGroup = groups.first(where: { $0.id == activeGroupID }) {
                                Text("Current group: \(activeGroup.name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if individualsInActiveGroup.isEmpty {
                                Text("No individuals from the current group have been added yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(individualsInActiveGroup) { recipient in
                                    if let contact = contacts.first(where: { $0.id == recipient.contactID }) {
                                        recipientRow(
                                            title: contact.name,
                                            subtitle: contact.email,
                                            secondarySubtitle: contact.mobile,
                                            sendEmail: Binding(
                                                get: { recipient.sendEmail },
                                                set: { newValue in
                                                    recipient.sendEmail = newValue
                                                    if !recipient.sendEmail && !recipient.sendText { recipient.sendText = true }
                                                    saveContext()
                                                }
                                            ),
                                            sendText: Binding(
                                                get: { recipient.sendText },
                                                set: { newValue in
                                                    recipient.sendText = newValue
                                                    if !recipient.sendEmail && !recipient.sendText { recipient.sendEmail = true }
                                                    saveContext()
                                                }
                                            ),
                                            footer: sendModeText(sendEmail: recipient.sendEmail, sendText: recipient.sendText)
                                        ) {
                                            dataContext.delete(recipient)
                                            saveContext()
                                        }
                                    }
                                }
                            }

                            Menu {
                                let availableContacts = availableIndividualsToAdd(
                                    activeGroupID: activeGroupID,
                                    existingRecipients: contactRecipients
                                )

                                if availableContacts.isEmpty {
                                    Text("No available contacts")
                                } else {
                                    ForEach(availableContacts) { contact in
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
                                Label("Add Individual", systemImage: "plus")
                            }
                        }
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

    @ViewBuilder
    private func recipientRow(
        title: String,
        subtitle: String,
        secondarySubtitle: String,
        sendEmail: Binding<Bool>,
        sendText: Binding<Bool>,
        footer: String,
        onDelete: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            HStack {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Email", isOn: sendEmail)
                    .labelsHidden()
            }

            if !secondarySubtitle.isEmpty {
                HStack {
                    Text(secondarySubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Text", isOn: sendText)
                        .labelsHidden()
                }
            } else {
                HStack {
                    Spacer()
                    Toggle("Text", isOn: sendText)
                        .labelsHidden()
                }
            }

            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func individualsForGroup(_ groupID: UUID?, within recipients: [ReportRecipient]) -> [ReportRecipient] {
        guard let groupID else { return [] }
        let memberIDs = Set(memberships.filter { $0.groupID == groupID }.map(\.contactID))
        return recipients
            .filter { memberIDs.contains($0.contactID) }
            .sorted { a, b in
                let aName = contacts.first(where: { $0.id == a.contactID })?.name ?? ""
                let bName = contacts.first(where: { $0.id == b.contactID })?.name ?? ""
                return aName.localizedCaseInsensitiveCompare(bName) == .orderedAscending
            }
    }

    private func availableIndividualsToAdd(
        activeGroupID: UUID?,
        existingRecipients: [ReportRecipient]
    ) -> [Contact] {
        let usedContactIDs = Set(existingRecipients.map(\.contactID))

        let scopedContacts: [Contact]
        if let activeGroupID {
            let memberIDs = Set(memberships.filter { $0.groupID == activeGroupID }.map(\.contactID))
            scopedContacts = contacts.filter { memberIDs.contains($0.id) }
        } else {
            scopedContacts = contacts
        }

        let mergedContactIDs = Set(scopedContacts.map(\.id)).union(contacts.map(\.id))
        return contacts
            .filter { mergedContactIDs.contains($0.id) }
            .filter { !usedContactIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

    private func groupRecipientsForGrade(_ gradeID: UUID) -> [ReportRecipientGroup] {
        reportRecipientGroups
            .filter { $0.gradeID == gradeID }
            .sorted { a, b in
                let aName = groups.first(where: { $0.id == a.groupID })?.name ?? ""
                let bName = groups.first(where: { $0.id == b.groupID })?.name ?? ""
                return aName.localizedCaseInsensitiveCompare(bName) == .orderedAscending
            }
    }

    private func addContact(_ contact: Contact, toGrade gradeID: UUID, sendMode: SendMode) {
        guard !reportRecipients.contains(where: { $0.gradeID == gradeID && $0.contactID == contact.id }) else { return }

        dataContext.insert(
            ReportRecipient(
                gradeID: gradeID,
                contactID: contact.id,
                sendEmail: sendMode == .email || sendMode == .both,
                sendText: sendMode == .text || sendMode == .both
            )
        )
        saveContext()
    }

    private func addGroup(_ group: ContactGroup, toGrade gradeID: UUID, sendMode: SendMode) {
        guard !reportRecipientGroups.contains(where: { $0.gradeID == gradeID && $0.groupID == group.id }) else { return }

        dataContext.insert(
            ReportRecipientGroup(
                gradeID: gradeID,
                groupID: group.id,
                sendEmail: sendMode == .email || sendMode == .both,
                sendText: sendMode == .text || sendMode == .both
            )
        )
        saveContext()
    }

    private func sendModeText(sendEmail: Bool, sendText: Bool) -> String {
        switch (sendEmail, sendText) {
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
