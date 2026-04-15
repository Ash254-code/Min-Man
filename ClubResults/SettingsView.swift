import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Grade.name)]) private var grades: [Grade]
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
        guard grades.isEmpty else { return }

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

    @Query(sort: [SortDescriptor(\Grade.name)]) private var grades: [Grade]
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
                        Button("Save") {
                            addGrade()
                            showAddGrade = false
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
    }

    private func addGrade() {
        let name = clean(newGradeName)
        guard !name.isEmpty else { return }
        guard !grades.contains(where: { clean($0.name).lowercased() == name.lowercased() }) else { return }

        let nextOrder = (grades.map(\.displayOrder).max() ?? -1) + 1
        modelContext.insert(Grade(name: name, isActive: true, displayOrder: nextOrder))
        saveContext()
    }

    private func saveEditedGrade() {
        guard let gradeEditing else { return }
        let name = clean(editGradeName)
        guard !name.isEmpty else { return }
        guard !grades.contains(where: { $0.id != gradeEditing.id && clean($0.name).lowercased() == name.lowercased() }) else { return }

        gradeEditing.name = name
        saveContext()
    }

    private func moveGrades(from source: IndexSet, to destination: Int) {
        var reordered = sortedGrades
        reordered.move(fromOffsets: source, toOffset: destination)

        for (index, grade) in reordered.enumerated() {
            grade.displayOrder = index
        }

        saveContext()
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

        saveContext()
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

    @Query(sort: [SortDescriptor(\Contact.name)]) private var contacts: [Contact]
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
            ContactEditSheet(title: "Add Contact") { name, mobile, email in
                modelContext.insert(Contact(name: name, mobile: mobile, email: email))
                saveContext()
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
                saveContext()
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
    }

    private func deleteContact(_ contact: Contact) {
        for recipient in reportRecipients where recipient.contactID == contact.id {
            modelContext.delete(recipient)
        }
        modelContext.delete(contact)
        saveContext()
    }

    private func saveContext() {
        do {
            try modelContext.save()
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
    let onSave: (String, String, String) -> Void

    @State private var name: String
    @State private var mobile: String
    @State private var email: String

    init(
        title: String,
        initialName: String = "",
        initialMobile: String = "",
        initialEmail: String = "",
        onSave: @escaping (String, String, String) -> Void
    ) {
        self.title = title
        self.initialName = initialName
        self.initialMobile = initialMobile
        self.initialEmail = initialEmail
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
                    Button("Save") {
                        onSave(clean(name), clean(mobile), clean(email))
                        dismiss()
                    }
                    .disabled(!canSave)
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
