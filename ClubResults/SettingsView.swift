import SwiftUI
import SwiftData
import PDFKit
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var saveErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
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
        let existing = (try? modelContext.fetch(FetchDescriptor<Grade>())) ?? []
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
            modelContext.insert(Grade(name: name, isActive: true, displayOrder: index))
        }

        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
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
    @Environment(\.modelContext) private var modelContext

    @State private var grades: [Grade] = []
    @Query private var players: [Player]
    @Query private var games: [Game]
    @Query private var reportRecipients: [ReportRecipient]

    @State private var showAddGrade = false
    @State private var newGradeName = ""

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
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        gradeEditing = grade
                        editGradeName = grade.name
                    }
                }
                .onMove(perform: moveGrades)

                Button {
                    newGradeName = ""
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
            NavigationStack {
                Form {
                    TextField("Grade name", text: $newGradeName)
                        .textInputAutocapitalization(.words)
                }
                .navigationTitle("Add Grade")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showAddGrade = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if addGrade() {
                                showAddGrade = false
                            }
                        }
                        .disabled(clean(newGradeName).isEmpty)
                    }
                }
            }
            .appPopupStyle()
        }
        .sheet(item: $gradeEditing) { grade in
            NavigationStack {
                Form {
                    TextField("Grade name", text: $editGradeName)
                        .textInputAutocapitalization(.words)

                    Section("New Game Wizard Fields") {
                        Toggle("Head Coach", isOn: bind(grade, \.asksHeadCoach))
                        Toggle("Assistant Coach", isOn: bind(grade, \.asksAssistantCoach))
                        Toggle("Team Manager", isOn: bind(grade, \.asksTeamManager))
                        Toggle("Runner", isOn: bind(grade, \.asksRunner))
                        Toggle("Goal Umpire", isOn: bind(grade, \.asksGoalUmpire))
                        Toggle("Boundary Umpire 1", isOn: bind(grade, \.asksBoundaryUmpire1))
                        Toggle("Boundary Umpire 2", isOn: bind(grade, \.asksBoundaryUmpire2))
                        Toggle("Trainers", isOn: bind(grade, \.asksTrainers))
                        Toggle("Notes", isOn: bind(grade, \.asksNotes))
                        Toggle("Goal Kickers", isOn: bind(grade, \.asksGoalKickers))
                        Picker("Best Players", selection: bind(grade, \.bestPlayersCount)) {
                            ForEach(1...10, id: \.self) { count in
                                Text("\(count)").tag(count)
                            }
                        }
                        Toggle("Guest Best & Fairest Votes Scan", isOn: bind(grade, \.asksGuestBestFairestVotesScan))
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

    private func addGrade() -> Bool {
        let name = clean(newGradeName)
        guard !name.isEmpty else { return false }
        guard !grades.contains(where: { clean($0.name).lowercased() == name.lowercased() }) else { return false }

        let nextOrder = (grades.map(\.displayOrder).max() ?? -1) + 1
        let newGrade = Grade(name: name, isActive: true, displayOrder: nextOrder)
        modelContext.insert(newGrade)
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
            modelContext.delete(recipient)
        }

        modelContext.delete(grade)

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
            try modelContext.save()
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
            let fetched = try modelContext.fetch(descriptor)

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
                    asksBoundaryUmpire1: $0.asksBoundaryUmpire1,
                    asksBoundaryUmpire2: $0.asksBoundaryUmpire2,
                    asksTrainers: $0.asksTrainers,
                            asksNotes: $0.asksNotes,
                            asksGoalKickers: $0.asksGoalKickers,
                            bestPlayersCount: $0.bestPlayersCount,
                            asksGuestBestFairestVotesScan: $0.asksGuestBestFairestVotesScan
                        )
                    }

                    for item in backups {
                        modelContext.insert(
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
                                asksBoundaryUmpire1: item.asksBoundaryUmpire1,
                                asksBoundaryUmpire2: item.asksBoundaryUmpire2,
                                asksTrainers: item.asksTrainers,
                                asksNotes: item.asksNotes,
                                asksGoalKickers: item.asksGoalKickers,
                                bestPlayersCount: item.bestPlayersCount,
                                asksGuestBestFairestVotesScan: item.asksGuestBestFairestVotesScan
                            )
                        )
                    }

                    try? modelContext.save()

                    let afterRestore = (try? modelContext.fetch(descriptor)) ?? []
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
                    asksBoundaryUmpire1: $0.asksBoundaryUmpire1,
                    asksBoundaryUmpire2: $0.asksBoundaryUmpire2,
                    asksTrainers: $0.asksTrainers,
                    asksNotes: $0.asksNotes,
                    asksGoalKickers: $0.asksGoalKickers,
                    bestPlayersCount: $0.bestPlayersCount,
                    asksGuestBestFairestVotesScan: $0.asksGuestBestFairestVotesScan
                )
            }
        }
    }
}

private struct AppAppearanceSettingsView: View {
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue

    var body: some View {
        Form {
            Section("App Appearance") {
                Picker("Theme", selection: $appAppearance) {
                    ForEach(AppAppearance.allCases) { item in
                        Text(item.title).tag(item.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }
        }
        .navigationTitle("App Appearance")
    }
}

private struct ContactsSettingsView: View {
    @Environment(\.modelContext) private var modelContext

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

            Section("Report Delivery") {
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
            }
        }
        .navigationTitle("Contacts")
        .sheet(isPresented: $showAddContact) {
            ContactEditSheet(
                title: "Add Contact",
                allowsSaveAndAddAnother: true,
                onSave: { name, mobile, email in
                    let newContact = Contact(name: name, mobile: mobile, email: email)
                    modelContext.insert(newContact)
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
                allowsSaveAndAddAnother: false,
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
            modelContext.delete(recipient)
        }

        modelContext.delete(contact)
        contacts.removeAll { $0.id == contact.id }

        SettingsBackupStore.saveContacts(contacts)
        saveContext()
        reloadContacts()
    }

    private func saveContext() {
        do {
            try modelContext.save()
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
            let fetched = try modelContext.fetch(descriptor)

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
                        modelContext.insert(
                            Contact(
                                id: item.id,
                                name: item.name,
                                mobile: item.mobile,
                                email: item.email
                            )
                        )
                    }

                    try? modelContext.save()

                    let afterRestore = (try? modelContext.fetch(descriptor)) ?? []
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
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Spacer()

                    if allowsSaveAndAddAnother {
                        Button("Save & Add Another") {
                            saveAndAddAnother()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(canSave ? .blue : .gray)
                        .disabled(!canSave)
                    }

                    Button(allowsSaveAndAddAnother ? "Save & Close" : "Save") {
                        saveAndClose()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(canSave ? .blue : .gray)
                    .disabled(!canSave)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func saveAndAddAnother() {
        guard onSave(clean(name), clean(mobile), clean(email)) else { return }

        name = ""
        mobile = ""
        email = ""
    }

    private func saveAndClose() {
        guard onSave(clean(name), clean(mobile), clean(email)) else { return }
        dismiss()
    }

    private func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ReportsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
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
                            modelContext.delete(template)
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
                    modelContext.delete(template)
                    saveContext()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .sheet(isPresented: $isCreatingTemplate) {
            CustomReportEditView(grades: grades) { name, selectedGradeIDs, includeBestPlayers, includePlayerGrades, includeGoalKickers, includeGuernseyNumbers, includeBestAndFairestVotes, includeStaffRoles, includeTrainers, includeMatchNotes, includeOnlyActiveGrades, minimumGamesPlayed in
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
                    minimumGamesPlayed: minimumGamesPlayed
                )
                modelContext.insert(template)
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
                initialMinimumGamesPlayed: template.minimumGamesPlayed
            ) { name, selectedGradeIDs, includeBestPlayers, includePlayerGrades, includeGoalKickers, includeGuernseyNumbers, includeBestAndFairestVotes, includeStaffRoles, includeTrainers, includeMatchNotes, includeOnlyActiveGrades, minimumGamesPlayed in
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
            try modelContext.save()
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
                Section("Select Contacts") {
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

    let filters = "Filters: min games \(template.minimumGamesPlayed), \(template.includeOnlyActiveGrades ? "active grades only" : "active + inactive")"
    let sections = "Includes: " + (items.isEmpty ? "No sections selected" : items.joined(separator: ", "))
    return [gradesText, sections, filters].joined(separator: " • ")
}

private func makeTemplatePreviewPDF(
    template: CustomReportTemplate,
    grades: [Grade],
    games: [Game],
    players: [Player]
) throws -> URL {
    let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)

    let title = "Custom Report Preview"
    let body = templatePreviewText(
        template: template,
        grades: grades,
        games: games,
        players: players
    )

    let data = renderer.pdfData { context in
        context.beginPage()

        let titleStyle = NSMutableParagraphStyle()
        titleStyle.lineBreakMode = .byWordWrapping
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 24),
            .paragraphStyle: titleStyle
        ]

        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.lineBreakMode = .byWordWrapping
        bodyStyle.lineSpacing = 4
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13),
            .paragraphStyle: bodyStyle
        ]

        let contentRect = pageBounds.insetBy(dx: 36, dy: 36)
        let titleRect = CGRect(x: contentRect.minX, y: contentRect.minY, width: contentRect.width, height: 34)
        NSAttributedString(string: title, attributes: titleAttributes).draw(in: titleRect)

        let bodyRect = CGRect(x: contentRect.minX, y: titleRect.maxY + 12, width: contentRect.width, height: contentRect.height - 46)
        NSAttributedString(string: body, attributes: bodyAttributes).draw(in: bodyRect)
    }

    let safeName = template.name
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: " ", with: "_")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CustomReport_\(safeName)_Preview.pdf")
    try data.write(to: url, options: .atomic)
    return url
}

private func templatePreviewText(
    template: CustomReportTemplate,
    grades: [Grade],
    games: [Game],
    players: [Player]
) -> String {
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
        for playerID in game.bestPlayersRanked {
            seenPlayerIDs.insert(playerID)
        }
        for kicker in game.goalKickers {
            if let playerID = kicker.playerID {
                seenPlayerIDs.insert(playerID)
            }
        }
        for playerID in seenPlayerIDs {
            gamesByPlayer[playerID, default: 0] += 1
        }
    }

    var lines: [String] = []
    lines.append("Template: \(template.name)")
    lines.append(buildTemplateDetails(for: template, grades: grades))
    lines.append("")

    if selectedGrades.isEmpty {
        lines.append("Grades in scope: All grades")
    } else {
        lines.append("Grades in scope: \(selectedGrades.map(\.name).joined(separator: ", "))")
    }
    lines.append("Games matched: \(relevantGames.count)")
    lines.append("")

    if template.includePlayerGrades || template.includeGuernseyNumbers {
        lines.append("Players")
        for grade in selectedGrades {
            let gradePlayers = players
                .filter { $0.gradeIDs.contains(grade.id) }
                .filter { !template.includeOnlyActiveGrades || $0.isActive }
                .filter { template.minimumGamesPlayed <= 0 || gamesByPlayer[$0.id, default: 0] >= template.minimumGamesPlayed }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            if gradePlayers.isEmpty {
                lines.append("- \(grade.name): no players")
            } else {
                let names = gradePlayers.map { player in
                    if template.includeGuernseyNumbers, let number = player.number {
                        return "\(player.name) (#\(number))"
                    }
                    return player.name
                }
                lines.append("- \(grade.name): \(names.prefix(15).joined(separator: ", "))")
                if names.count > 15 {
                    lines.append("  +\(names.count - 15) more")
                }
            }
        }
        lines.append("")
    }

    lines.append("Previous Games Included")
    if relevantGames.isEmpty {
        lines.append("- No completed games match this template.")
        lines.append("")
    } else {
        for game in relevantGames {
            let gradeName = gradeLookup[game.gradeID] ?? "Unknown Grade"
            lines.append("\(game.date.formatted(date: .abbreviated, time: .omitted)) • \(gradeName) vs \(game.opponent)")
            lines.append("Score: \(game.ourGoals).\(game.ourBehinds) (\(game.ourScore)) - \(game.theirGoals).\(game.theirBehinds) (\(game.theirScore))")
            if !game.venue.isEmpty {
                lines.append("Venue: \(game.venue)")
            }

            if template.includeGoalKickers {
                if game.goalKickers.isEmpty {
                    lines.append("Goal kickers: none")
                } else {
                    let goalLines = game.goalKickers
                        .sorted { $0.goals > $1.goals }
                        .compactMap { entry -> String? in
                            guard let playerID = entry.playerID else { return nil }
                            let playerName = playerLookup[playerID]?.name ?? "Unknown Player"
                            return "\(playerName) \(entry.goals)"
                        }
                    lines.append("Goal kickers: \(goalLines.joined(separator: ", "))")
                }
            }

            if template.includeBestPlayers {
                if game.bestPlayersRanked.isEmpty {
                    lines.append("Best players: none")
                } else {
                    let bestList = game.bestPlayersRanked.enumerated().map { (idx, playerID) -> String in
                        let playerName = playerLookup[playerID]?.name ?? "Unknown Player"
                        if template.includeGuernseyNumbers, let number = playerLookup[playerID]?.number {
                            return "\(idx + 1). \(playerName) (#\(number))"
                        }
                        return "\(idx + 1). \(playerName)"
                    }
                    lines.append("Best players: \(bestList.joined(separator: "; "))")
                }
            }

            if template.includeBestAndFairestVotes {
                lines.append("B&F vote scan: \(game.guestBestFairestVotesScanPDF == nil ? "No" : "Yes")")
            }

            if template.includeMatchNotes {
                let trimmedNotes = game.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedNotes.isEmpty {
                    lines.append("Notes: \(trimmedNotes)")
                }
            }

            lines.append("")
        }
    }

    if template.includeGoalKickers {
        var goalsByPlayer: [UUID: Int] = [:]
        for game in relevantGames {
            for entry in game.goalKickers {
                guard let playerID = entry.playerID else { continue }
                goalsByPlayer[playerID, default: 0] += entry.goals
            }
        }
        let topGoalKickers = goalsByPlayer
            .sorted { $0.value > $1.value }
            .prefix(10)

        lines.append("Goal Kicker Totals")
        if topGoalKickers.isEmpty {
            lines.append("- No goal kicker data")
        } else {
            for (playerID, goals) in topGoalKickers {
                let playerName = playerLookup[playerID]?.name ?? "Unknown Player"
                lines.append("- \(playerName): \(goals)")
            }
        }
        lines.append("")
    }

    if template.includeBestPlayers {
        var bestCountByPlayer: [UUID: Int] = [:]
        for game in relevantGames {
            for playerID in game.bestPlayersRanked {
                bestCountByPlayer[playerID, default: 0] += 1
            }
        }
        let topBestPlayers = bestCountByPlayer
            .sorted { $0.value > $1.value }
            .prefix(10)

        lines.append("Best Player Appearance Totals")
        if topBestPlayers.isEmpty {
            lines.append("- No best player data")
        } else {
            for (playerID, appearances) in topBestPlayers {
                let playerName = playerLookup[playerID]?.name ?? "Unknown Player"
                lines.append("- \(playerName): \(appearances)")
            }
        }
        lines.append("")
    }

    if template.includeBestAndFairestVotes {
        let scannedVotesCount = relevantGames.filter { $0.guestBestFairestVotesScanPDF != nil }.count
        lines.append("Best & Fairest Votes")
        lines.append("- Games with vote scan attached: \(scannedVotesCount) of \(relevantGames.count)")
        lines.append("")
    }

    if template.includeStaffRoles || template.includeTrainers {
        lines.append("Staff / Trainers")
        lines.append("- Included by template settings (staff entries are configured per game and grade).")
        lines.append("")
    }

    return lines.joined(separator: "\n")
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
    let onSave: (String, [UUID], Bool, Bool, Bool, Bool, Bool, Bool, Bool, Bool, Bool, Int) -> Void

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
        onSave: @escaping (String, [UUID], Bool, Bool, Bool, Bool, Bool, Bool, Bool, Bool, Bool, Int) -> Void
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
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Template") {
                    TextField("Report name", text: $name)
                }

                Section("Grades") {
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
                }

                Section("Data Included") {
                    Toggle("Best players", isOn: $includeBestPlayers)
                    Toggle("Player grades", isOn: $includePlayerGrades)
                    Toggle("Goal kickers", isOn: $includeGoalKickers)
                    Toggle("Guernsey numbers", isOn: $includeGuernseyNumbers)
                    Toggle("Best & Fairest votes", isOn: $includeBestAndFairestVotes)
                    Toggle("Staff roles", isOn: $includeStaffRoles)
                    Toggle("Trainers", isOn: $includeTrainers)
                    Toggle("Match notes", isOn: $includeMatchNotes)
                }

                Section("Filters") {
                    Toggle("Only active grades", isOn: $includeOnlyActiveGrades)
                    Stepper("Minimum games played: \(minimumGamesPlayed)", value: $minimumGamesPlayed, in: 0...100)
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
                            minimumGamesPlayed
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
    @Environment(\.modelContext) private var modelContext

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
                Section(grade.name) {
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
                                    modelContext.delete(recipient)
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

        modelContext.insert(
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
            try modelContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}
