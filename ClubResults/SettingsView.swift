import SwiftUI
import SwiftData

private struct GradeBackup: Codable {
    let id: UUID
    let name: String
    let isActive: Bool
    let displayOrder: Int
}

private struct ContactBackup: Codable {
    let id: UUID
    let name: String
    let mobile: String
    let email: String
}

private enum SettingsBackupStore {
    private static let gradesKey = "settings.backup.grades.v1"
    private static let contactsKey = "settings.backup.contacts.v1"

    static func saveGrades(_ grades: [Grade]) {
        let payload = grades.map { GradeBackup(id: $0.id, name: $0.name, isActive: $0.isActive, displayOrder: $0.displayOrder) }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: gradesKey)
    }

    static func loadGrades() -> [GradeBackup] {
        guard let data = UserDefaults.standard.data(forKey: gradesKey),
              let decoded = try? JSONDecoder().decode([GradeBackup].self, from: data) else {
            return []
        }
        return decoded
    }

    static func saveContacts(_ contacts: [Contact]) {
        let payload = contacts.map { ContactBackup(id: $0.id, name: $0.name, mobile: $0.mobile, email: $0.email) }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: contactsKey)
    }

    static func loadContacts() -> [ContactBackup] {
        guard let data = UserDefaults.standard.data(forKey: contactsKey),
              let decoded = try? JSONDecoder().decode([ContactBackup].self, from: data) else {
            return []
        }
        return decoded
    }
}

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
                    AppAppearanceSettingsView()
                } label: {
                    settingsRow(title: "App Appearance", icon: "circle.lefthalf.filled")
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
            .alert("Save Error", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { saveErrorMessage = nil }
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

        let defaults = ["A Grade", "B Grade", "Under 17's", "Under 14's", "Under 12's", "Under 9's"]
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
                        Button("Edit") {
                            gradeEditing = grade
                            editGradeName = grade.name
                        }
                        .buttonStyle(.borderless)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteGrade(grade)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
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
                Text("Drag to reorder grades")
            }
        }
        .navigationTitle("Club Grades")
        .toolbar { EditButton() }
        .alert("Can’t Delete Grade", isPresented: $showDeletionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deletionErrorMessage ?? "This grade is currently in use.")
        }
        .alert("Save Error", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
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
                        Button("Cancel") { showAddGrade = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save & Add Another") {
                            if addGrade() {
                                newGradeName = ""
                            }
                        }
                        .disabled(clean(newGradeName).isEmpty)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save & Close") {
                            if addGrade() {
                                showAddGrade = false
                            }
                        }
                        .disabled(clean(newGradeName).isEmpty)
                    }
                }
            }
        }
        .sheet(item: $gradeEditing) { _ in
            NavigationStack {
                Form {
                    TextField("Grade name", text: $editGradeName)
                        .textInputAutocapitalization(.words)
                }
                .navigationTitle("Edit Grade")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { gradeEditing = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveEditedGrade()
                            gradeEditing = nil
                        }
                        .disabled(clean(editGradeName).isEmpty)
                    }
                }
            }
        }
        .task {
            reloadGrades()
        }
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

    private func saveEditedGrade() {
        guard let gradeEditing else { return }
        let name = clean(editGradeName)
        guard !name.isEmpty else { return }
        guard !grades.contains(where: { $0.id != gradeEditing.id && clean($0.name).lowercased() == name.lowercased() }) else { return }

        gradeEditing.name = name
        SettingsBackupStore.saveGrades(grades)
        saveContext()
        reloadGrades()
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

    private func deleteGrade(_ grade: Grade) {
        if games.contains(where: { $0.gradeID == grade.id }) {
            deletionErrorMessage = "This grade has games attached. Reassign or remove those games first."
            showDeletionError = true
            return
        }

        if players.contains(where: { $0.gradeIDs.contains(grade.id) }) {
            deletionErrorMessage = "This grade has players attached. Remove the grade from players first."
            showDeletionError = true
            return
        }

        for recipient in reportRecipients where recipient.gradeID == grade.id {
            modelContext.delete(recipient)
        }

        modelContext.delete(grade)

        let remaining = orderedGradesForDisplay(grades.filter { $0.id != grade.id }, includeInactive: true)
        for (index, item) in remaining.enumerated() {
            item.displayOrder = index
        }

        SettingsBackupStore.saveGrades(remaining)
        saveContext()
        reloadGrades()
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
                sortBy: [SortDescriptor(\Grade.displayOrder), SortDescriptor(\Grade.name)]
            )
            let fetched = try modelContext.fetch(descriptor)
            if fetched.isEmpty {
                let backups = SettingsBackupStore.loadGrades()
                if !backups.isEmpty {
                    for item in backups {
                        modelContext.insert(Grade(id: item.id, name: item.name, isActive: item.isActive, displayOrder: item.displayOrder))
                    }
                    try modelContext.save()
                    grades = try modelContext.fetch(descriptor)
                    return
                }
            }
            grades = fetched
            SettingsBackupStore.saveGrades(grades)
        } catch {
            saveErrorMessage = error.localizedDescription
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
        }
        .navigationTitle("Contacts")
        .sheet(isPresented: $showAddContact) {
            ContactEditSheet(title: "Add Contact", allowsSaveAndAddAnother: true) { name, mobile, email in
                let newContact = Contact(name: name, mobile: mobile, email: email)
                modelContext.insert(newContact)
                contacts.append(newContact)
                contacts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                SettingsBackupStore.saveContacts(contacts)
                saveContext()
                reloadContacts()
                return true
            }
        }
        .sheet(item: $contactEditing) { contact in
            ContactEditSheet(
                title: "Edit Contact",
                initialName: contact.name,
                initialMobile: contact.mobile,
                initialEmail: contact.email
            ) { name, mobile, email in
                contact.name = name
                contact.mobile = mobile
                contact.email = email
                SettingsBackupStore.saveContacts(contacts)
                saveContext()
                reloadContacts()
                return true
            }
        }
        .alert("Save Error", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
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
                    for item in backups {
                        modelContext.insert(Contact(id: item.id, name: item.name, mobile: item.mobile, email: item.email))
                    }
                    try modelContext.save()
                    contacts = try modelContext.fetch(descriptor)
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

    @State private var name: String
    @State private var mobile: String
    @State private var email: String

    init(
        title: String,
        initialName: String = "",
        initialMobile: String = "",
        initialEmail: String = "",
        allowsSaveAndAddAnother: Bool = false,
        onSave: @escaping (String, String, String) -> Bool
    ) {
        self.title = title
        self.initialName = initialName
        self.initialMobile = initialMobile
        self.initialEmail = initialEmail
        self.allowsSaveAndAddAnother = allowsSaveAndAddAnother
        self.onSave = onSave

        _name = State(initialValue: initialName)
        _mobile = State(initialValue: initialMobile)
        _email = State(initialValue: initialEmail)
    }

    private var canSave: Bool {
        !clean(name).isEmpty && !clean(mobile).isEmpty && !clean(email).isEmpty
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
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(allowsSaveAndAddAnother ? "Save & Add Another" : "Save") {
                        if onSave(clean(name), clean(mobile), clean(email)) {
                            if allowsSaveAndAddAnother {
                                name = ""
                                mobile = ""
                                email = ""
                            } else {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!canSave)
                }
                if allowsSaveAndAddAnother {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save & Close") {
                            if onSave(clean(name), clean(mobile), clean(email)) {
                                dismiss()
                            }
                        }
                        .disabled(!canSave)
                    }
                }
            }
        }
    }

    private func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ReportsSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Grade.name)]) private var grades: [Grade]
    @Query(sort: [SortDescriptor(\Contact.name)]) private var contacts: [Contact]
    @Query private var reportRecipients: [ReportRecipient]
    @State private var saveErrorMessage: String?

    private var activeGrades: [Grade] {
        orderedGradesForDisplay(grades)
    }

    var body: some View {
        List {
            if activeGrades.isEmpty {
                Text("Add a grade first.")
                    .foregroundStyle(.secondary)
            }

            ForEach(activeGrades) { grade in
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
                                    Toggle("Email", isOn: Binding(
                                        get: { recipient.sendEmail },
                                        set: { newValue in
                                            recipient.sendEmail = newValue
                                            if !recipient.sendEmail && !recipient.sendText {
                                                recipient.sendText = true
                                            }
                                            saveContext()
                                        }
                                    ))
                                    .labelsHidden()
                                }

                                HStack {
                                    Text(contact.mobile)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Toggle("Text", isOn: Binding(
                                        get: { recipient.sendText },
                                        set: { newValue in
                                            recipient.sendText = newValue
                                            if !recipient.sendEmail && !recipient.sendText {
                                                recipient.sendEmail = true
                                            }
                                            saveContext()
                                        }
                                    ))
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
                                Button(contact.name) {
                                    addContact(contact, toGrade: grade.id)
                                }
                            }
                        }
                    } label: {
                        Label("Add Contact", systemImage: "plus")
                    }
                }
            }
        }
        .navigationTitle("Reports")
        .alert("Save Error", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
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

    private func addContact(_ contact: Contact, toGrade gradeID: UUID) {
        guard !reportRecipients.contains(where: { $0.gradeID == gradeID && $0.contactID == contact.id }) else { return }
        modelContext.insert(ReportRecipient(gradeID: gradeID, contactID: contact.id, sendEmail: true, sendText: true))
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
