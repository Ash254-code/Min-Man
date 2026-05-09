import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Players List

struct PlayersView: View {
    @Environment(\EnvironmentValues.modelContext) private var dataContext: ModelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    @State private var showDeleteReferenceWarning = false
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
    @State private var exportURL: URL? = nil
    @State private var showExportSheet = false
    @State private var exportErrorMessage: String? = nil
    @State private var showExportError = false
    @State private var addErrorMessage: String? = nil
    @State private var showAddError = false
    let returnToCallerOnSave: Bool
    let onSaveAndClose: (() -> Void)?

    @State private var pendingDuplicateGroup: DuplicatePlayerGroup?
    @State private var mergeErrorMessage: String?

    init(returnToCallerOnSave: Bool = false, onSaveAndClose: (() -> Void)? = nil) {
        self.returnToCallerOnSave = returnToCallerOnSave
        self.onSaveAndClose = onSaveAndClose
    }

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

    private var duplicateGroupLookup: [UUID: DuplicatePlayerGroup] {
        PlayerDuplicateService.duplicateGroupLookup(in: playersForDisplay)
    }

    private var isDuplicateMergeAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingDuplicateGroup != nil },
            set: { if !$0 { pendingDuplicateGroup = nil } }
        )
    }

    private var isMergeErrorAlertPresented: Binding<Bool> {
        Binding(
            get: { mergeErrorMessage != nil },
            set: { if !$0 { mergeErrorMessage = nil } }
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            playersList
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search players")
        .onAppear { reloadPlayersFromStore() }
        .onChange(of: queriedPlayers.count) { _, _ in
            reloadPlayersFromStore()
        }
    }

    private var playersList: some View {
        playersListBase
            .sheet(isPresented: $showAdd) {
                addPlayerSheetContent
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: csvAllowedTypes(),
                allowsMultipleSelection: false
            ) { result in
                handleImportFileSelection(result)
            }
            .confirmationDialog(
                "Import Players from CSV",
                isPresented: $showImportOptions,
                titleVisibility: .visible
            ) {
                Button("Skip duplicates (recommended)") {
                    importMode = .skipDuplicates
                    runCSVImportIfPossible()
                }
                Button("Update existing (match by first and surname)") {
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
                    Text("Choose what happens when a player with the same first name and surname already exists. Rows without a grade will default to \(selected.name). You can import multiple grades in one cell using commas or semicolons.")
                } else {
                    Text("Choose what happens when a player with the same first name and surname already exists. You can import multiple grades in one cell using commas or semicolons.")
                }
            }
            .alert("Player used in saved games", isPresented: $showDeleteReferenceWarning) {
                Button("Delete", role: .destructive) {
                    showDeletePrompt = true
                }
                Button("Cancel", role: .cancel) {
                    cancelDelete()
                }
            } message: {
                Text("This player appears in previously saved games. Do you wish to proceed? This cannot be undone.")
            }
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
            .alert("Import complete", isPresented: $showImportResult) {
                Button("OK", role: .cancel) { importResult = nil }
            } message: {
                Text(importResult?.prettySummary ?? "Done.")
            }
            .alert("Import failed", isPresented: $showImportError) {
                Button("OK", role: .cancel) { importErrorMessage = nil }
            } message: {
                Text(importErrorMessage ?? "Unknown error.")
            }
            .sheet(isPresented: $showExportSheet) {
                if let exportURL {
                    ShareSheet(items: [exportURL])
                }
            }
            .alert("Export failed", isPresented: $showExportError) {
                Button("OK", role: .cancel) { exportErrorMessage = nil }
            } message: {
                Text(exportErrorMessage ?? "Unknown error.")
            }
            .alert("Could not save player", isPresented: $showAddError) {
                Button("OK", role: .cancel) { addErrorMessage = nil }
            } message: {
                Text(addErrorMessage ?? "Unknown error.")
            }
            .alert(
                "Duplicate players found",
                isPresented: isDuplicateMergeAlertPresented,
                presenting: pendingDuplicateGroup
            ) { group in
                Button("Cancel", role: .cancel) {
                    pendingDuplicateGroup = nil
                }
                Button("Merge", role: .destructive) {
                    mergeDuplicateGroup(group)
                }
            } message: { group in
                Text(duplicateMergeMessage(for: group))
            }
            .alert(
                "Could not merge players",
                isPresented: isMergeErrorAlertPresented
            ) {
                Button("OK", role: .cancel) {
                    mergeErrorMessage = nil
                }
            } message: {
                Text(mergeErrorMessage ?? "Unknown error.")
            }
    }

    private var addPlayerSheetContent: some View {
        NavigationStack {
            PlayerAddView(
                activeGrades: activeGrades,
                existingPlayers: playersForDisplay,
                preselectedGradeID: effectiveSelectedGradeID,
                onSave: { firstName, lastName, preferredName, number, gradeIDs in
                    createAndSavePlayer(
                        firstName: firstName,
                        lastName: lastName,
                        preferredName: preferredName,
                        number: number,
                        gradeIDs: gradeIDs
                    )
                },
                onSaveComplete: handleExternalSaveCompletion
            )
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .appPopupStyle()
    }

    private var playersListBase: some View {
        List {
            playersSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .toolbarBackground(.hidden, for: .navigationBar)

        .navigationTitle(horizontalSizeClass == .compact ? "Players" : "")
        .navigationBarTitleDisplayMode(horizontalSizeClass == .compact ? .inline : .large)

        .toolbar { playersToolbar }
    }

    // MARK: - Players Section

    private var playersSection: some View {
        Section {
            ForEach(filteredPlayers) { player in
                playerRow(for: player)
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

    @ViewBuilder
    private func playerRow(for player: Player) -> some View {
        if let duplicateGroup = duplicateGroupLookup[player.id] {
            Button {
                pendingDuplicateGroup = duplicateGroup
            } label: {
                playerRowCard(for: player, isDuplicate: true)
            }
            .playerListRowStyle()
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                deletePlayerButton(for: player)
            }
        } else {
            NavigationLink {
                PlayerEditView(
                    player: player,
                    orderedGrades: orderedGrades,
                    existingPlayers: playersForDisplay,
                    onSaveComplete: handleExternalSaveCompletion
                )
            } label: {
                playerRowCard(for: player, isDuplicate: false)
            }
            .buttonStyle(.plain)
            .playerListRowChrome()
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                deletePlayerButton(for: player)
            }
        }
    }

    private func playerRowCard(for player: Player, isDuplicate: Bool) -> some View {
        PlayerRowAFL(
            name: player.name,
            number: player.number,
            gradeNames: gradeNamesArray(for: player),
            isActive: player.isActive,
            isDuplicate: isDuplicate
        )
    }

    private func deletePlayerButton(for player: Player) -> some View {
        Button(role: .destructive) {
            requestDelete(player)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var playersToolbar: some ToolbarContent {
        // ✅ Title + grade pill (left side, large-title area)
        if horizontalSizeClass != .compact {
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
        }

        // ✅ Actions on the right
        ToolbarItemGroup(placement: .navigationBarTrailing) {

            GradeFilterButton(
                grades: activeGrades,
                selectedGradeID: $selectedGradeID,
                includeAll: true
            )

            Button { exportPlayersCSV() } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Export Players")
            Button { showImporter = true } label: { Image(systemName: "square.and.arrow.down") }
                .accessibilityLabel("Import Players")
            Button { showAdd = true } label: { Image(systemName: "plus") }
        }
    }

    // MARK: - Delete

    private func requestDelete(_ player: Player) {
        playerPendingDelete = player
        deleteCode = ""
        if playerAppearsInSavedGames(player) {
            showDeleteReferenceWarning = true
        } else {
            showDeletePrompt = true
        }
    }

    private func confirmDelete() {
        let trimmedCode = deleteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DeleteCodeStore.verify(trimmedCode), let player = playerPendingDelete else {
            showDeletePrompt = false
            showWrongCode = true
            return
        }

        dataContext.delete(player)
        try? dataContext.save()
        reloadPlayersFromStore()

        playerPendingDelete = nil
        showDeletePrompt = false
    }

    private func cancelDelete() {
        playerPendingDelete = nil
        deleteCode = ""
        showDeleteReferenceWarning = false
        showDeletePrompt = false
    }

    private func handleExternalSaveCompletion() {
        guard returnToCallerOnSave else { return }
        if let onSaveAndClose {
            onSaveAndClose()
        } else {
            dismiss()
        }
    }

    private func playerAppearsInSavedGames(_ player: Player) -> Bool {
        let savedGames = fetchSavedGamesFromStore()
        guard !savedGames.isEmpty else { return false }

        let candidateNames = Set([
            player.name,
            player.fullName
        ]
        .map { normalizedPersonName($0) }
        .filter { !$0.isEmpty })

        return savedGames.contains { game in
            if game.bestPlayersRanked.contains(player.id) { return true }
            if game.guestVotesRanked.contains(where: { $0.playerID == player.id }) { return true }
            if game.goalKickers.contains(where: { $0.playerID == player.id }) { return true }

            let roleNames = [
                game.headCoachName,
                game.assistantCoachName,
                game.teamManagerName,
                game.runnerName,
                game.goalUmpireName,
                game.timeKeeperName,
                game.fieldUmpireName,
                game.boundaryUmpire1Name,
                game.boundaryUmpire2Name,
                game.waterBoy1Name,
                game.waterBoy2Name,
                game.waterBoy3Name,
                game.waterBoy4Name
            ]

            if roleNames.contains(where: { candidateNames.contains(normalizedPersonName($0)) }) {
                return true
            }

            return game.trainers.contains(where: { candidateNames.contains(normalizedPersonName($0)) })
        }
    }

    private func fetchSavedGamesFromStore() -> [Game] {
        var descriptor = FetchDescriptor<Game>()
        descriptor.includePendingChanges = false
        return ((try? dataContext.fetch(descriptor)) ?? []).filter { !$0.isDraft }
    }

    private func normalizedPersonName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
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
        var allowedTypes: [UTType] = [.commaSeparatedText, .plainText, .text]
        if let csvType = UTType(filenameExtension: "csv") {
            allowedTypes.insert(csvType, at: 0)
        }
        return allowedTypes
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

    private func handleImportFileSelection(_ result: Result<[URL], Error>) {
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

    private func exportPlayersCSV() {
        let allPlayers = fetchPlayersFromStore()
        let csv = makePlayersCSV(from: allPlayers)
        let fileName = playersExportFileName()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            showExportSheet = true
        } catch {
            exportErrorMessage = error.localizedDescription
            showExportError = true
        }
    }

    private func makePlayersCSV(from players: [Player]) -> String {
        let header = ["First Name", "Surname", "Preferred Name", "Number", "Grade"]
        let rows = players.map { player in
            [
                csvEscape(player.firstName),
                csvEscape(player.lastName),
                csvEscape(player.preferredName),
                csvEscape(player.number.map(String.init) ?? ""),
                csvEscape(gradeNames(for: player))
            ].joined(separator: ",")
        }

        return ([header.joined(separator: ",")] + rows).joined(separator: "\n") + "\n"
    }

    private func playersExportFileName() -> String {
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        let dateStamp = String(format: "%04d-%02d-%02d", year, month, day)
        return "Players_\(dateStamp).csv"
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
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
            partial[player.duplicateMatchKey] = player
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
            for p in persistedPlayers { dataContext.delete(p) }
        }

        for row in parsedRows {
            let duplicateKey = Player.duplicateMatchKey(firstName: row.firstName, lastName: row.lastName)
            if duplicateKey == "|" {
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

            if let existing = existingByName[duplicateKey], mode != .replaceAll {
                switch mode {
                case .skipDuplicates:
                    result.skipped += 1
                    continue
                case .updateExisting:
                    let previousDuplicateKey = existing.duplicateMatchKey
                    existing.setName(
                        firstName: row.firstName,
                        lastName: row.lastName,
                        preferredName: row.preferredName
                    )
                    if previousDuplicateKey != duplicateKey {
                        existingByName.removeValue(forKey: previousDuplicateKey)
                    }
                    existingByName[duplicateKey] = existing
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
                    preferredName: row.preferredName,
                    number: number,
                    gradeIDs: gradeIDs,
                    isActive: true
                )
                dataContext.insert(newPlayer)
                existingByName[duplicateKey] = newPlayer
                result.imported += 1
            }
        }

        do { try dataContext.save() }
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

    private func createAndSavePlayer(
        firstName: String,
        lastName: String,
        preferredName: String,
        number: Int?,
        gradeIDs: [UUID]
    ) {
        guard !Player.combineName(first: firstName, last: lastName).isEmpty else { return }

        let duplicateKey = Player.duplicateMatchKey(firstName: firstName, lastName: lastName)
        let persistedPlayers = fetchPlayersFromStore()
        guard !persistedPlayers.contains(where: { $0.duplicateMatchKey == duplicateKey }) else {
            return
        }

        let p = Player(
            firstName: firstName,
            lastName: lastName,
            preferredName: preferredName,
            number: number,
            gradeIDs: gradeIDs
        )
        dataContext.insert(p)

        do {
            try dataContext.save()
            reloadPlayersFromStore()
        } catch {
            dataContext.delete(p)
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
        return (try? dataContext.fetch(descriptor)) ?? []
    }

    private func duplicateMergeMessage(for group: DuplicatePlayerGroup) -> String {
        let playerList = group.players
            .map(\.name)
            .joined(separator: ", ")
        return "There are \(group.players.count) players with the same surname and first name: \(playerList). Would you like to merge them?"
    }

    private func mergeDuplicateGroup(_ group: DuplicatePlayerGroup) {
        do {
            _ = try PlayerDuplicateService.merge(players: group.players, modelContext: dataContext)
            pendingDuplicateGroup = nil
            reloadPlayersFromStore()
        } catch {
            pendingDuplicateGroup = nil
            mergeErrorMessage = error.localizedDescription
        }
    }
}

// MARK: - AFL Row UI

private struct PlayerRowAFL: View {
    let name: String
    let number: Int?
    let gradeNames: [String]
    let isActive: Bool
    let isDuplicate: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(numberPillColor)
                Text(numberText)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(numberTextColor)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            if horizontalSizeClass == .compact && displayedGradePills.count > 1 {
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(displayedGradePills, id: \.self) { gradeText in
                        GradePill(text: gradeText)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(displayedGradePills, id: \.self) { gradeText in
                        GradePill(text: gradeText)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isDuplicate ? Color.red.opacity(0.22) : Color.clear)
        )
        .premiumGlassCard(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isDuplicate ? Color.red.opacity(0.65) : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }

    private var numberText: String {
        if let n = number, n > 0 { return "\(n)" }
        return "—"
    }

    private var numberPillColor: Color {
        isActive ? ClubTheme.yellow : Color.gray.opacity(0.6)
    }

    private var numberTextColor: Color {
        isActive ? ClubTheme.navy : Color.white.opacity(0.9)
    }

    private var displayedGradePills: [String] {
        if horizontalSizeClass == .compact, gradeNames.count >= 3 {
            return [gradeNames[0], "+\(gradeNames.count - 1)"]
        }

        var pills = Array(gradeNames.prefix(2))
        if gradeNames.count > 2 {
            pills.append("+\(gradeNames.count - 2)")
        }
        return pills
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

private extension View {
    func playerListRowChrome() -> some View {
        listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    func playerListRowStyle() -> some View {
        buttonStyle(.plain)
            .playerListRowChrome()
    }
}
