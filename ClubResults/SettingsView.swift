import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Grade.name)]) private var grades: [Grade]
    @Query private var players: [Player]
    @Query private var games: [Game]
    @Query private var reportRoutings: [ReportRouting]

    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue

    @State private var showAddGrade = false
    @State private var newGradeName = ""

    @State private var gradeEditing: Grade?
    @State private var editGradeName = ""

    @State private var deletionErrorMessage: String?
    @State private var showDeletionError = false

    @State private var draftEmailByGrade: [UUID: String] = [:]
    @State private var draftPhoneByGrade: [UUID: String] = [:]

    private var activeGrades: [Grade] {
        grades.filter { $0.isActive }
    }

    var body: some View {
        NavigationStack {
            List {
                clubGradesSection
                appearanceSection
                reportsSection
            }
            .navigationTitle("Settings")
            .alert("Can’t Delete Grade", isPresented: $showDeletionError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(deletionErrorMessage ?? "This grade is currently in use.")
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
            .onAppear(perform: seedInitialGradesIfNeeded)
            .onAppear(perform: syncReportRoutingsWithGrades)
            .onChange(of: grades.count) { _, _ in
                syncReportRoutingsWithGrades()
            }
        }
    }

    private var clubGradesSection: some View {
        Section("Club Grades") {
            if grades.isEmpty {
                Text("No grades yet.")
                    .foregroundStyle(.secondary)
            }

            ForEach(grades) { grade in
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

            Button {
                newGradeName = ""
                showAddGrade = true
            } label: {
                Label("Add Grade", systemImage: "plus")
            }
        }
    }

    private var appearanceSection: some View {
        Section("App Appearance") {
            Picker("Theme", selection: $appAppearance) {
                ForEach(AppAppearance.allCases) { item in
                    Text(item.title).tag(item.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var reportsSection: some View {
        Section("Reports") {
            if activeGrades.isEmpty {
                Text("Add a grade first to configure report recipients.")
                    .foregroundStyle(.secondary)
            }

            ForEach(activeGrades) { grade in
                VStack(alignment: .leading, spacing: 10) {
                    Text(grade.name)
                        .font(.headline)

                    recipientList(
                        title: "Emails",
                        items: routing(for: grade.id).emails,
                        onDelete: { removeEmail($0, from: grade.id) }
                    )

                    HStack {
                        TextField("Add email", text: Binding(
                            get: { draftEmailByGrade[grade.id, default: ""] },
                            set: { draftEmailByGrade[grade.id] = $0 }
                        ))
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button("Add") {
                            addEmail(for: grade.id)
                        }
                        .disabled(clean(draftEmailByGrade[grade.id, default: ""]).isEmpty)
                    }

                    recipientList(
                        title: "Mobile Numbers",
                        items: routing(for: grade.id).mobileNumbers,
                        onDelete: { removePhone($0, from: grade.id) }
                    )

                    HStack {
                        TextField("Add mobile", text: Binding(
                            get: { draftPhoneByGrade[grade.id, default: ""] },
                            set: { draftPhoneByGrade[grade.id] = $0 }
                        ))
                        .keyboardType(.phonePad)

                        Button("Add") {
                            addPhone(for: grade.id)
                        }
                        .disabled(clean(draftPhoneByGrade[grade.id, default: ""]).isEmpty)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private func recipientList(title: String, items: [String], onDelete: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if items.isEmpty {
                Text("None")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.self) { item in
                    HStack {
                        Text(item)
                            .font(.subheadline)
                        Spacer()
                        Button(role: .destructive) {
                            onDelete(item)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func seedInitialGradesIfNeeded() {
        guard grades.isEmpty else { return }

        let defaults = ["A Grade", "B Grade", "Under 17's", "Under 14's", "Under 12's", "Under 9's"]
        defaults.forEach { modelContext.insert(Grade(name: $0, isActive: true)) }
        try? modelContext.save()
    }

    private func addGrade() {
        let name = clean(newGradeName)
        guard !name.isEmpty else { return }
        guard !grades.contains(where: { clean($0.name).lowercased() == name.lowercased() }) else { return }

        modelContext.insert(Grade(name: name, isActive: true))
        try? modelContext.save()
    }

    private func saveEditedGrade() {
        guard let gradeEditing else { return }
        let name = clean(editGradeName)
        guard !name.isEmpty else { return }
        guard !grades.contains(where: { $0.id != gradeEditing.id && clean($0.name).lowercased() == name.lowercased() }) else { return }

        gradeEditing.name = name
        try? modelContext.save()
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

        if let routing = reportRoutings.first(where: { $0.gradeID == grade.id }) {
            modelContext.delete(routing)
        }

        modelContext.delete(grade)
        try? modelContext.save()
    }

    private func syncReportRoutingsWithGrades() {
        let gradeIDs = Set(activeGrades.map(\.id))

        for gid in gradeIDs where !reportRoutings.contains(where: { $0.gradeID == gid }) {
            modelContext.insert(ReportRouting(gradeID: gid))
        }

        for route in reportRoutings where !gradeIDs.contains(route.gradeID) {
            modelContext.delete(route)
        }

        try? modelContext.save()
    }

    private func routing(for gradeID: UUID) -> ReportRouting {
        if let existing = reportRoutings.first(where: { $0.gradeID == gradeID }) {
            return existing
        }

        let created = ReportRouting(gradeID: gradeID)
        modelContext.insert(created)
        try? modelContext.save()
        return created
    }

    private func addEmail(for gradeID: UUID) {
        let email = clean(draftEmailByGrade[gradeID, default: ""])
        guard !email.isEmpty else { return }

        let route = routing(for: gradeID)
        if !route.emails.contains(where: { $0.caseInsensitiveCompare(email) == .orderedSame }) {
            route.emails.append(email)
            route.emails.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }

        draftEmailByGrade[gradeID] = ""
        try? modelContext.save()
    }

    private func addPhone(for gradeID: UUID) {
        let phone = clean(draftPhoneByGrade[gradeID, default: ""])
        guard !phone.isEmpty else { return }

        let route = routing(for: gradeID)
        if !route.mobileNumbers.contains(phone) {
            route.mobileNumbers.append(phone)
            route.mobileNumbers.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }

        draftPhoneByGrade[gradeID] = ""
        try? modelContext.save()
    }

    private func removeEmail(_ email: String, from gradeID: UUID) {
        let route = routing(for: gradeID)
        route.emails.removeAll { $0 == email }
        try? modelContext.save()
    }

    private func removePhone(_ phone: String, from gradeID: UUID) {
        let route = routing(for: gradeID)
        route.mobileNumbers.removeAll { $0 == phone }
        try? modelContext.save()
    }

    private func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
