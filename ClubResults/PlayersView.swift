import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Players List

struct PlayersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Player.name) private var queriedPlayers: [Player]
    @Query private var grades: [Grade]
    @State private var playersForDisplay: [Player] = []

    @State private var showAdd = false

    // nil = All grades
    @State private var selectedGradeID: UUID? = nil
    @State private var searchText = ""

    // ✅ Delete gate (code protected)
    @State private var showDeletePrompt = false
    @State private var deleteCode = ""
    @State private var playerPendingDelete: Player? = nil
    @State private var showWrongCode = false

    // ✅ CSV Import
    @State private var showImporter = false
    @State private var showImportOptions = false
    @State private var importMode: CSVImportMode = .skipDuplicates
    @State private var pendingImportURL: URL? = nil

    @State private var importResult: CSVImportResult? = nil
    @State private var showImportResult = false
    @State private var importErrorMessage: String? = nil
    @State private var showImportError = false
    @State private var addErrorMessage: String? = nil
    @State private var showAddError = false

    // MARK: - Grade Ordering

    private var resolvedGrades: [Grade] {
        resolvedConfiguredGrades(from: grades)
    }

    private var orderedGrades: [Grade] {
        orderedGradesForDisplay(resolvedGrades, includeInactive: true)
    }

    private var activeGrades: [Grade] {
        orderedGrades.filter { $0.isActive }
    }

    private var selectedGradeLabel: String {
        guard let gid = effectiveSelectedGradeID,
              let g = activeGrades.first(where: { $0.id == gid }) else {
            return "All"
        }
        return g.name
    }

    /// Treat stale/invalid grade selections as "All" so the list doesn't silently hide every player.
    private var effectiveSelectedGradeID: UUID? {
        guard let selectedGradeID else { return nil }
        guard activeGrades.contains(where: { $0.id == selectedGradeID }) else { return nil }
        return selectedGradeID
    }

    private var filteredPlayers: [Player] {
        // First filter by selected grade (if any)
        let gradeFiltered: [Player]
        if let gid = effectiveSelectedGradeID {
            gradeFiltered = playersForDisplay.filter { $0.gradeIDs.contains(gid) }
        } else {
            gradeFiltered = playersForDisplay
        }

        // Then filter by search text (if any)
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return gradeFiltered }

        return gradeFiltered.filter { p in
            p.name.localizedCaseInsensitiveContains(text)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // Players
                playersSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .toolbarBackground(.hidden, for: .navigationBar)

            // ✅ We provide our own title row (Players + grade pill)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.large)

            .toolbar { playersToolbar }

            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    PlayerAddView(
                        activeGrades: activeGrades,
                        existingPlayers: playersForDisplay,
                        preselectedGradeID: effectiveSelectedGradeID,
                        onSave: createAndSavePlayer(name:number:gradeIDs:)
                    )
                    .toolbarBackground(.hidden, for: .navigationBar)
                }
                .appPopupStyle()
            }

            // ✅ file importer
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: csvAllowedTypes(),
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    pendingImportURL = url
                    showImportOptions = true
                case .failure(let error):
                    importErrorMessage = "Could not open file: \(error.localizedDescription)"
                    showImportError = true
                }
            }

            // ✅ Import options sheet
            .confirmationDialog(
                "Import Players from CSV",
                isPresented: $showImportOptions,
                titleVisibility: .visible
            ) {
                Button("Skip duplicates (recommended)") {
                    importMode = .skipDuplicates
                    runCSVImportIfPossible()
                }
                Button("Update existing (match by full name)") {
                    importMode = .updateExisting
                    runCSVImportIfPossible()
                }
                Button("Replace ALL players (danger)") {
                    importMode = .replaceAll
                    runCSVImportIfPossible()
                }
                Button("Cancel", role: .cancel) {
                    pendingImportURL = nil
                }
            } message: {
                if let selectedGradeID = effectiveSelectedGradeID,
                   let selected = activeGrades.first(where: { $0.id == selectedGradeID }) {
                    Text("Choose what happens when a player name already exists. Rows without a grade will default to \(selected.name). You can import multiple grades in one cell using commas or semicolons.")
                } else {
                    Text("Choose what happens when a player name already exists. You can import multiple grades in one cell using commas or semicolons.")
                }
            }

            // ✅ Delete prompts
            .alert("Enter delete code", isPresented: $showDeletePrompt) {
                SecureField("Code", text: $deleteCode)
                Button("Delete", role: .destructive) { confirmDelete() }
                Button("Cancel", role: .cancel) { cancelDelete() }
            } message: {
                Text("Deleting a player is permanent.")
            }
            .alert("Wrong code", isPresented: $showWrongCode) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Player was not deleted.")
            }

            // ✅ Import result
            .alert("Import complete", isPresented: $showImportResult) {
                Button("OK", role: .cancel) { importResult = nil }
            } message: {
                Text(importResult?.prettySummary ?? "Done.")
            }

            // ✅ Import error
            .alert("Import failed", isPresented: $showImportError) {
                Button("OK", role: .cancel) { importErrorMessage = nil }
            } message: {
                Text(importErrorMessage ?? "Unknown error.")
            }
            .alert("Could not save player", isPresented: $showAddError) {
                Button("OK", role: .cancel) { addErrorMessage = nil }
            } message: {
                Text(addErrorMessage ?? "Unknown error.")
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search players")
        .onAppear { reloadPlayersFromStore() }
        .onChange(of: queriedPlayers.count) { _, _ in
            reloadPlayersFromStore()
        }
    }

    // MARK: - Players Section

    private var playersSection: some View {
        Section {
            ForEach(filteredPlayers) { player in
                NavigationLink {
                    PlayerEditView(
                        player: player,
                        orderedGrades: orderedGrades,
                        existingPlayers: playersForDisplay,
                        onRequestDelete: { p in requestDelete(p) }
                    )
                } label: {
                    PlayerRowAFL(
                        name: player.name,
                        number: player.number,
                        gradeNames: gradeNamesArray(for: player)
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        requestDelete(player)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onDelete { idx in
                if let first = idx.first {
                    requestDelete(filteredPlayers[first])
                }
            }

            if filteredPlayers.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "person.3")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.7))
                        Text("No players to show")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.vertical, 14)
                    Spacer()
                }
                .premiumGlassCard(cornerRadius: 20)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }
        } header: {
            Text("PLAYERS")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var playersToolbar: some ToolbarContent {
        // ✅ Title + grade pill (left side, large-title area)
        ToolbarItem(placement: .principal) {
            HStack(spacing: 10) {
                Text("Players")
                    .font(.largeTitle.weight(.bold))

                FilteredGradeTitle(
                    selectedGradeID: selectedGradeID,
                    grades: activeGrades
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        // ✅ Actions on the right
        ToolbarItemGroup(placement: .navigationBarTrailing) {

            GradeFilterButton(
                grades: activeGrades,
                selectedGradeID: $selectedGradeID,
                includeAll: true
            )

            Button { showImporter = true } label: { Image(systemName: "square.and.arrow.down") }
            Button { showAdd = true } label: { Image(systemName: "plus") }
        }
    }

    // MARK: - Delete

    private func requestDelete(_ player: Player) {
        playerPendingDelete = player
        deleteCode = ""
        showDeletePrompt = true
    }

    private func confirmDelete() {
        guard deleteCode == "1234", let player = playerPendingDelete else {
            showDeletePrompt = false
            showWrongCode = true
            return
        }

        modelContext.delete(player)
        try? modelContext.save()
        reloadPlayersFromStore()

        playerPendingDelete = nil
        showDeletePrompt = false
    }

    private func cancelDelete() {
        playerPendingDelete = nil
        deleteCode = ""
        showDeletePrompt = false
    }

    private func gradeNamesArray(for player: Player) -> [String] {
        let map = Dictionary(uniqueKeysWithValues: orderedGrades.map { ($0.id, $0.name) })
        return player.gradeIDs.compactMap { map[$0] }
    }

    private func gradeNames(for player: Player) -> String {
        let names = gradeNamesArray(for: player)
        return names.isEmpty ? "No grades selected" : names.joined(separator: ", ")
    }

    // MARK: - CSV Import

    private func csvAllowedTypes() -> [UTType] {
        [.commaSeparatedText, .plainText]
    }

    private func runCSVImportIfPossible() {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil

        do {
            let result = try importPlayersCSV(from: url, mode: importMode)
            importResult = result
            showImportResult = true
        } catch {
            importErrorMessage = error.localizedDescription
            showImportError = true
        }
    }

    private func importPlayersCSV(from url: URL, mode: CSVImportMode) throws -> CSVImportResult {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)

        var text: String
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else if let fallback = String(data: data, encoding: .isoLatin1) {
            text = fallback
        } else {
            throw CSVImportError.invalidEncoding
        }

        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")

        let table = CSVParser.parse(text)
        guard !table.isEmpty else { throw CSVImportError.emptyFile }

        let headerRow = table[0].map { $0.trimmedLowercased }
        let headerMap = CSVHeaderMap(header: headerRow)

        guard headerMap.hasAnyRecognizedColumn else {
            throw CSVImportError.missingHeaders(expected: CSVHeaderMap.expectedColumnsDisplay)
        }

        let gradeLookup = GradeLookup(grades: resolvedGrades)

        // Always start from the persisted source of truth, not an in-memory snapshot.
        let persistedPlayers = fetchPlayersFromStore()
        var existingByName: [String: Player] = persistedPlayers.reduce(into: [:]) { partial, player in
            partial[normalizeName(player.name)] = player
        }

        var result = CSVImportResult(mode: mode)

        var parsedRows: [CSVPlayerRow] = []

        for (index, row) in table.enumerated() {
            if index == 0 { continue }
            if row.allSatisfy({ $0.trimmed.isEmpty }) { continue }

            do {
                let playerRow = try CSVPlayerRow.from(row, headerMap: headerMap, lineNumber: index + 1)
                parsedRows.append(playerRow)
            } catch let e as CSVImportError {
                result.errors.append(e.pretty)
            } catch {
                result.errors.append("Line \(index + 1): Unknown row error.")
            }
        }

        guard !parsedRows.isEmpty else {
            throw CSVImportError.noValidRows(details: result.errors.isEmpty ? nil : result.errors)
        }

        if mode == .replaceAll {
            for p in persistedPlayers { modelContext.delete(p) }
        }

        for row in parsedRows {
            let fullName = row.fullName
            let normName = normalizeName(fullName)
            if normName.isEmpty {
                result.skipped += 1
                result.errors.append("Line \(row.line): First/last name was empty after trimming.")
                continue
            }

            let number = row.number
            let parsedGradeIDs = gradeLookup.ids(forRawGradeField: row.gradesRaw, unknownCollector: &result.unknownGradeNames)
            let gradeIDs: [UUID]
            if parsedGradeIDs.isEmpty, let selectedGradeID = effectiveSelectedGradeID {
                // If importing while a grade filter is active, default missing grade rows
                // into that visible grade so imported players appear immediately.
                gradeIDs = [selectedGradeID]
            } else {
                gradeIDs = parsedGradeIDs
            }

            if let existing = existingByName[normName], mode != .replaceAll {
                switch mode {
                case .skipDuplicates:
                    result.skipped += 1
                    continue
                case .updateExisting:
                    existing.setName(firstName: row.firstName, lastName: row.lastName)
                    existing.number = number
                    existing.gradeIDs = gradeIDs
                    result.updated += 1
                case .replaceAll:
                    break
                }
            } else {
                let newPlayer = Player(
                    firstName: row.firstName,
                    lastName: row.lastName,
                    number: number,
                    gradeIDs: gradeIDs,
                    isActive: true
                )
                modelContext.insert(newPlayer)
                existingByName[normName] = newPlayer
                result.imported += 1
            }
        }

        do { try modelContext.save() }
        catch { throw CSVImportError.saveFailed(error.localizedDescription) }

        reloadPlayersFromStore()
        return result
    }

    private func defaultImportGradeID() -> UUID? {
        if let firstActive = activeGrades.first {
            return firstActive.id
        }
        return orderedGrades.first?.id
    }

    private func normalizeName(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func createAndSavePlayer(name: String, number: Int?, gradeIDs: [UUID]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalized = normalizeName(trimmed)
        let persistedPlayers = fetchPlayersFromStore()
        guard !persistedPlayers.contains(where: { normalizeName($0.name) == normalized }) else {
            return
        }

        let p = Player(name: trimmed, number: number, gradeIDs: gradeIDs)
        modelContext.insert(p)

        do {
            try modelContext.save()
            reloadPlayersFromStore()
        } catch {
            modelContext.delete(p)
            addErrorMessage = error.localizedDescription
            showAddError = true
        }
    }

    private func reloadPlayersFromStore() {
        playersForDisplay = fetchPlayersFromStore()
    }

    private func fetchPlayersFromStore() -> [Player] {
        var descriptor = FetchDescriptor<Player>(
            sortBy: [SortDescriptor(\Player.name, order: .forward)]
        )
        // Force a read from persisted storage so the UI reflects what was truly saved.
        descriptor.includePendingChanges = false
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

// MARK: - AFL Row UI

private struct PlayerRowAFL: View {
    let name: String
    let number: Int?
    let gradeNames: [String]

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(ClubTheme.yellow)
                Text(numberText)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(ClubTheme.navy)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(gradeNames.prefix(2), id: \.self) { g in
                    GradePill(text: g)
                }
                if gradeNames.count > 2 {
                    GradePill(text: "+\(gradeNames.count - 2)")
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .premiumGlassCard(cornerRadius: 16)
        .contentShape(Rectangle())
    }

    private var numberText: String {
        if let n = number, n > 0 { return "\(n)" }
        return "—"
    }
}

private struct GradePill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(ClubTheme.navy.opacity(0.85))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .lineLimit(1)
    }
}
