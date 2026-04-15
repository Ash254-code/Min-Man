import SwiftUI
import SwiftData
import UIKit
import AVFoundation
import VisionKit

// Local model for goal kickers used by this wizard
private struct WizardGoalKickerEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var playerID: UUID?
    var goals: Int
}

struct NewGameWizardView: View {
    let initialGradeID: UUID?

    init(initialGradeID: UUID? = nil) {
        self.initialGradeID = initialGradeID
    }

    // MARK: - Club Colours
    private let clubNavy = Color(red: 0.05, green: 0.15, blue: 0.35)
    private let clubYellow = Color(red: 1.0, green: 0.82, blue: 0.0)

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss   // ✅ allow Cancel / dismiss sheet

    @Query private var grades: [Grade]
    @Query(sort: \Player.name) private var players: [Player]

    // ✅ stored defaults per grade + role
    @Query private var staffDefaults: [StaffDefault]

    // ✅ UPDATED: first screen is Setup (grade + date + opponent + venue)
    enum Step: Int { case setup, staff, medical, score, goals, best, votes, review }
    @State private var step: Step = .setup

    // MARK: Setup
    @State private var gradeID: UUID?
    @State private var date = Date()

    // ✅ Opponent list (ONLY these 7)
    private let opponents: [String] = [
        "BSR", "BBH", "RSMU", "North Clare", "South Clare", "Southern Saints", "Blyth/Snowtown"
    ]

    // ✅ Venue depends on opponent (ONLY from this)
    private let venueOptionsByOpponent: [String: [String]] = [
        "South Clare": ["Clare", "Mintaro", "Manoora"],
        "North Clare": ["Clare", "Mintaro", "Manoora"],
        "RSMU": ["Riverton", "Mintaro", "Manoora"],
        "BSR": ["Mintaro", "Manoora", "Brinkworth", "Spalding", "Redhill"],
        "BBH": ["Burra", "Mintaro", "Manoora"],
        "Southern Saints": ["Mintaro", "Manoora", "Eudunda", "Robertstown"],
        "Blyth/Snowtown": ["Mintaro", "Manoora", "Blyth", "Snowtown"]
    ]

    // MARK: Selections (dropdowns)
    @State private var opponentName: String = ""
    @State private var venueName: String = ""

    // MARK: Staff
    @State private var headCoachName: String = ""
    @State private var assCoachName: String = ""
    @State private var teamManagerName: String = ""
    @State private var runnerName: String = ""

    @State private var goalUmpireName: String = ""

    // Boundary umpires are chosen from a configured grade's players, or entered manually.
    @State private var boundaryUmpire1ID: UUID?
    @State private var boundaryUmpire2ID: UUID?
    @State private var boundaryUmpire1CustomName: String = ""
    @State private var boundaryUmpire2CustomName: String = ""
    @State private var boundaryUmpireNamePrompt: BoundaryUmpireSlot?
    @State private var boundaryUmpireNameDraft: String = ""

    @State private var trainer1Name: String = ""
    @State private var trainer2Name: String = ""
    @State private var trainer3Name: String = ""
    @State private var trainer4Name: String = ""

    @State private var notes = ""

    // MARK: Score (AFL: goals * 6 + behinds)
    @State private var ourGoals = 0
    @State private var ourBehinds = 0
    @State private var theirGoals = 0
    @State private var theirBehinds = 0

    private var ourScore: Int { ourGoals * 6 + ourBehinds }
    private var theirScore: Int { theirGoals * 6 + theirBehinds }

    // MARK: Goals + best players
    @State private var goalKickers: [WizardGoalKickerEntry] = []
    @State private var bestRanked: [UUID?] = Array(repeating: nil, count: 6)
    @State private var guestBestFairestVotesScanPDF: Data?
    @State private var showVotesScanner = false
    @State private var scannerErrorMessage: String?
    @State private var hasAppliedInitialGrade = false

    // MARK: Helpers
    private func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var finalOpponent: String { clean(opponentName) }
    private var finalVenue: String { clean(venueName) }

    private var finalHeadCoach: String { clean(headCoachName) }
    private var finalAssCoach: String { clean(assCoachName) }
    private var finalTeamManager: String { clean(teamManagerName) }
    private var finalRunner: String { clean(runnerName) }

    private var finalGoalUmpire: String { clean(goalUmpireName) }

    private func playerName(for id: UUID?) -> String {
        guard let id else { return "" }
        return players.first(where: { $0.id == id })?.name ?? ""
    }
    private var finalBoundary1: String {
        let custom = clean(boundaryUmpire1CustomName)
        return custom.isEmpty ? playerName(for: boundaryUmpire1ID) : custom
    }
    private var finalBoundary2: String {
        let custom = clean(boundaryUmpire2CustomName)
        return custom.isEmpty ? playerName(for: boundaryUmpire2ID) : custom
    }

    private var venuesForOpponent: [String] {
        guard !finalOpponent.isEmpty else { return [] }
        return venueOptionsByOpponent[finalOpponent] ?? []
    }

    // MARK: Defaults (from SwiftData)
    private func defaultStaffName(for role: StaffRole, gradeID: UUID?) -> String? {
        guard let gradeID else { return nil }
        return staffDefaults.first(where: { $0.gradeID == gradeID && $0.role == role })?.name
    }

    private enum StaffFieldKey: String, CaseIterable {
        case headCoach
        case assistantCoach
        case teamManager
        case runner
        case goalUmpire
        case trainer1
        case trainer2
        case trainer3
        case trainer4
    }

    private func persistedLastSelection(for field: StaffFieldKey, gradeID: UUID?) -> String? {
        guard let gradeID else { return nil }
        let key = "lastStaffSelection.\(gradeID.uuidString).\(field.rawValue)"
        let saved = UserDefaults.standard.string(forKey: key) ?? ""
        let cleaned = clean(saved)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func saveLastSelection(_ value: String, for field: StaffFieldKey, gradeID: UUID?) {
        guard let gradeID else { return }
        let key = "lastStaffSelection.\(gradeID.uuidString).\(field.rawValue)"
        let cleaned = clean(value)
        if cleaned.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(cleaned, forKey: key)
        }
    }

    private func assignDefault(for field: StaffFieldKey, role: StaffRole, gradeID: UUID?, assign: (String) -> Void) {
        let lastSelected = persistedLastSelection(for: field, gradeID: gradeID)
        let roleDefault = defaultStaffName(for: role, gradeID: gradeID)
        assign(lastSelected ?? roleDefault ?? "")
    }

    private func applyDefaults(for gradeID: UUID?) {
        assignDefault(for: .headCoach, role: .headCoach, gradeID: gradeID) { headCoachName = $0 }
        assignDefault(for: .assistantCoach, role: .assistantCoach, gradeID: gradeID) { assCoachName = $0 }
        assignDefault(for: .teamManager, role: .teamManager, gradeID: gradeID) { teamManagerName = $0 }
        assignDefault(for: .runner, role: .runner, gradeID: gradeID) { runnerName = $0 }
        assignDefault(for: .goalUmpire, role: .goalUmpire, gradeID: gradeID) { goalUmpireName = $0 }
        assignDefault(for: .trainer1, role: .trainer, gradeID: gradeID) { trainer1Name = $0 }
        assignDefault(for: .trainer2, role: .trainer, gradeID: gradeID) { trainer2Name = $0 }
        assignDefault(for: .trainer3, role: .trainer, gradeID: gradeID) { trainer3Name = $0 }
        assignDefault(for: .trainer4, role: .trainer, gradeID: gradeID) { trainer4Name = $0 }
    }

    private func persistCurrentStaffSelections(for gradeID: UUID?) {
        saveLastSelection(headCoachName, for: .headCoach, gradeID: gradeID)
        saveLastSelection(assCoachName, for: .assistantCoach, gradeID: gradeID)
        saveLastSelection(teamManagerName, for: .teamManager, gradeID: gradeID)
        saveLastSelection(runnerName, for: .runner, gradeID: gradeID)
        saveLastSelection(goalUmpireName, for: .goalUmpire, gradeID: gradeID)
        saveLastSelection(trainer1Name, for: .trainer1, gradeID: gradeID)
        saveLastSelection(trainer2Name, for: .trainer2, gradeID: gradeID)
        saveLastSelection(trainer3Name, for: .trainer3, gradeID: gradeID)
        saveLastSelection(trainer4Name, for: .trainer4, gradeID: gradeID)
    }

    // MARK: Ordering helpers
    private var resolvedGrades: [Grade] {
        resolvedConfiguredGrades(from: grades)
    }

    private var selectedGradeName: String {
        guard let gid = gradeID else { return "Not selected" }
        return resolvedGrades.first(where: { $0.id == gid })?.name ?? "Unknown grade"
    }

    private var eligiblePlayers: [Player] {
        guard let gid = gradeID else { return [] }
        return players.filter { $0.isActive && $0.gradeIDs.contains(gid) }
    }

    private var boundaryUmpireSourceGradeIDs: [UUID] {
        guard let gid = gradeID else { return [] }
        let configured = SettingsBackupStore.loadBoundaryUmpireGradeMappings()[gid] ?? [gid]
        return configured.isEmpty ? [gid] : configured
    }

    private var boundaryUmpirePlayers: [Player] {
        let sourceGradeIDs = Set(boundaryUmpireSourceGradeIDs)
        guard !sourceGradeIDs.isEmpty else { return [] }
        return players.filter { player in
            player.isActive && !sourceGradeIDs.isDisjoint(with: Set(player.gradeIDs))
        }
    }

    private enum BoundaryUmpireSlot {
        case one
        case two
    }

    private var selectedGrade: Grade? {
        guard let gid = gradeID else { return nil }
        return resolvedGrades.first(where: { $0.id == gid })
    }

    private var requiredBestPlayersCount: Int {
        min(max(selectedGrade?.bestPlayersCount ?? 6, 0), 10)
    }

    private var activeSteps: [Step] {
        guard let grade = selectedGrade else { return [.setup] }

        var steps: [Step] = [.setup]
        if grade.asksHeadCoach ||
            grade.asksAssistantCoach ||
            grade.asksTeamManager ||
            grade.asksRunner ||
            grade.asksGoalUmpire ||
            grade.asksBoundaryUmpire1 ||
            grade.asksBoundaryUmpire2 {
            steps.append(.staff)
        }
        if grade.asksTrainers || grade.asksNotes {
            steps.append(.medical)
        }
        steps.append(.score)
        if grade.asksGoalKickers { steps.append(.goals) }
        if grade.bestPlayersCount > 0 { steps.append(.best) }
        if grade.asksGuestBestFairestVotesScan { steps.append(.votes) }
        steps.append(.review)
        return steps
    }

    // MARK: - Uniform row styling
    private func rowLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .regular))
    }

    private func rowValue(_ text: String) -> some View {
        Text(text.isEmpty ? "Select…" : text)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(text.isEmpty ? .secondary : .primary)
    }

    // MARK: Goal allocation helpers
    private var totalAllocatedGoals: Int { goalKickers.reduce(0) { $0 + $1.goals } }

    private func maxAllowedGoals(for entry: WizardGoalKickerEntry) -> Int {
        let remaining = ourGoals - (totalAllocatedGoals - entry.goals)
        return max(0, remaining)
    }

    // MARK: Validation
    private var canProceed: Bool {
        switch step {

        case .setup:
            return gradeID != nil &&
                   !finalOpponent.isEmpty &&
                   !finalVenue.isEmpty

        case .staff:
            let asksHeadCoach = selectedGrade?.asksHeadCoach ?? true
            let asksAssistantCoach = selectedGrade?.asksAssistantCoach ?? true
            let asksTeamManager = selectedGrade?.asksTeamManager ?? true
            let asksRunner = selectedGrade?.asksRunner ?? true
            let asksGoalUmpire = selectedGrade?.asksGoalUmpire ?? true
            let asksBoundaryUmpire1 = selectedGrade?.asksBoundaryUmpire1 ?? true
            let asksBoundaryUmpire2 = selectedGrade?.asksBoundaryUmpire2 ?? true

            let coachingOK =
                (!asksHeadCoach || !finalHeadCoach.isEmpty) &&
                (!asksAssistantCoach || !finalAssCoach.isEmpty) &&
                (!asksTeamManager || !finalTeamManager.isEmpty) &&
                (!asksRunner || !finalRunner.isEmpty)

            let officialsOK =
                (!asksGoalUmpire || !finalGoalUmpire.isEmpty) &&
                (!asksBoundaryUmpire1 || !finalBoundary1.isEmpty) &&
                (!asksBoundaryUmpire2 || !finalBoundary2.isEmpty) &&
                (!(asksBoundaryUmpire1 && asksBoundaryUmpire2) || finalBoundary1 != finalBoundary2)

            return coachingOK && officialsOK

        case .medical:
            return true

        case .score:
            return true

        case .goals:
            return remainingGoalsToAllocate == 0
                && !hasDuplicateGoalKickers
                && (goalKickers.isEmpty || allGoalKickersSelected)

        case .best:
            let ids = bestRanked.compactMap { $0 }
            return ids.count == requiredBestPlayersCount && Set(ids).count == requiredBestPlayersCount

        case .votes:
            return guestBestFairestVotesScanPDF != nil

        case .review:
            return true
        }
    }

    // MARK: Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                ProgressView(
                    value: Double(activeSteps.firstIndex(of: step) ?? 0),
                    total: Double(max(activeSteps.count - 1, 1))
                )
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 6)

                ZStack {
                    switch step {
                    case .setup: setupStep
                    case .staff: staffStep
                    case .medical: medicalStep
                    case .score: scoreStep
                    case .goals: goalsStep
                    case .best: bestStep
                    case .votes: votesStep
                    case .review: reviewStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack {
                    // ✅ hide Back entirely on the first step
                    if step != .setup {
                        Button("Back") { back() }
                    }

                    Spacer()

                    Button(step == .review ? "Save" : "Next") {
                        if step == .review { saveGame() }
                        else { next() }
                    }
                    .disabled(!canProceed)
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle(step == .setup ? "" : "New Game")
            .navigationBarTitleDisplayMode(step == .setup ? .inline : .large)

            // ✅ Cancel in top-left ONLY on first step
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if step == .setup {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        // ✅ Seed staff + defaults once
        .onAppear {
            StaffSeeder.seedIfNeeded(modelContext: modelContext, grades: grades)
            applyDefaults(for: gradeID)
        }
        // ✅ When user changes grade, auto-fill defaults from last selected values (or seeded defaults)
        .onChange(of: gradeID) { _, newGrade in
            applyDefaults(for: newGrade)
            syncBestPlayersSelectionCount()
            step = .setup
        }
        .onAppear {
            guard !hasAppliedInitialGrade else { return }
            hasAppliedInitialGrade = true
            if let initialGradeID {
                gradeID = initialGradeID
                applyDefaults(for: initialGradeID)
                syncBestPlayersSelectionCount()
            }
        }
    }

    private func next() {
        guard let currentIndex = activeSteps.firstIndex(of: step) else { return }
        let nextIndex = currentIndex + 1
        guard activeSteps.indices.contains(nextIndex) else { return }
        step = activeSteps[nextIndex]
    }

    private func back() {
        guard let currentIndex = activeSteps.firstIndex(of: step), currentIndex > 0 else { return }
        step = activeSteps[currentIndex - 1]
    }

    // MARK: Steps

    // ✅ NEW: Setup step (Grade + Date + Opponent + Venue)
    // Uses the SAME Form styling you had on the Grade screen.
    private var setupStep: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("New Game")
                    .font(.system(size: 44, weight: .bold))
                Spacer()
                Text(selectedGradeName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 8)

            Form {
                if let _ = gradeID, eligiblePlayers.isEmpty {
                    Section {
                        Text("No active players assigned to this grade yet. Add players first.")
                            .foregroundStyle(.secondary)
                    }
                } else if gradeID != nil {
                    Section {
                        Text("\(eligiblePlayers.count) eligible players")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Game details") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    Picker("Opponent", selection: $opponentName) {
                        Text("Select…").tag("")
                        ForEach(opponents, id: \.self) { o in
                            Text(o).tag(o)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: opponentName) { _, _ in
                        venueName = ""
                    }

                    Picker("Venue", selection: $venueName) {
                        Text("Select…").tag("")
                        ForEach(venuesForOpponent, id: \.self) { v in
                            Text(v).tag(v)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(finalOpponent.isEmpty || venuesForOpponent.isEmpty)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    // ✅ Staff step (unchanged)
    private var staffStep: some View {
        ScrollView {
            VStack(spacing: 14) {

                StaffCard(title: "Coaching", systemImage: "person.2.fill") {
                    if selectedGrade?.asksHeadCoach ?? true {
                        StaffPickerField(title: "Head Coach", role: .headCoach, gradeID: gradeID, value: $headCoachName)
                    }
                    if selectedGrade?.asksAssistantCoach ?? true {
                        StaffPickerField(title: "Assistant Coach", role: .assistantCoach, gradeID: gradeID, value: $assCoachName)
                    }
                    if selectedGrade?.asksTeamManager ?? true {
                        StaffPickerField(title: "Team Manager", role: .teamManager, gradeID: gradeID, value: $teamManagerName)
                    }
                    if selectedGrade?.asksRunner ?? true {
                        StaffPickerField(title: "Runner", role: .runner, gradeID: gradeID, value: $runnerName)
                    }
                }

                StaffCard(title: "Officials", systemImage: "flag.fill") {
                    if selectedGrade?.asksGoalUmpire ?? true {
                        StaffPickerField(title: "Goal Umpire", role: .goalUmpire, gradeID: gradeID, value: $goalUmpireName)
                    }

                    let asksBoundaryUmpire1 = selectedGrade?.asksBoundaryUmpire1 ?? true
                    let asksBoundaryUmpire2 = selectedGrade?.asksBoundaryUmpire2 ?? true

                    if asksBoundaryUmpire1 {
                        HStack(spacing: 12) {
                            rowLabel("Boundary Umpire 1")
                            Spacer()
                            Menu {
                                Button("Select…") {
                                    boundaryUmpire1ID = nil
                                    boundaryUmpire1CustomName = ""
                                }
                                Divider()
                                ForEach(boundaryUmpirePlayers) { person in
                                    if person.id != boundaryUmpire2ID {
                                        Button(person.name) {
                                            boundaryUmpire1ID = person.id
                                            boundaryUmpire1CustomName = ""
                                        }
                                    }
                                }
                                Divider()
                                Button("Enter different name…") {
                                    boundaryUmpireNameDraft = boundaryUmpire1CustomName
                                    boundaryUmpireNamePrompt = .one
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    rowValue(finalBoundary1)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if asksBoundaryUmpire2 {
                        HStack(spacing: 12) {
                            rowLabel("Boundary Umpire 2")
                            Spacer()
                            Menu {
                                Button("Select…") {
                                    boundaryUmpire2ID = nil
                                    boundaryUmpire2CustomName = ""
                                }
                                Divider()
                                ForEach(boundaryUmpirePlayers) { person in
                                    if person.id != boundaryUmpire1ID {
                                        Button(person.name) {
                                            boundaryUmpire2ID = person.id
                                            boundaryUmpire2CustomName = ""
                                        }
                                    }
                                }
                                Divider()
                                Button("Enter different name…") {
                                    boundaryUmpireNameDraft = boundaryUmpire2CustomName
                                    boundaryUmpireNamePrompt = .two
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    rowValue(finalBoundary2)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if asksBoundaryUmpire1, asksBoundaryUmpire2, boundaryUmpire1ID != nil, boundaryUmpire1ID == boundaryUmpire2ID {
                        Text("Boundary Umpire 1 and 2 can’t be the same.")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.top, 6)
                    }
                }

            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .alert(
            boundaryUmpireNamePrompt == .one ? "Boundary Umpire 1" : "Boundary Umpire 2",
            isPresented: Binding(
                get: { boundaryUmpireNamePrompt != nil },
                set: { if !$0 { boundaryUmpireNamePrompt = nil } }
            )
        ) {
            TextField("Name", text: $boundaryUmpireNameDraft)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {
                boundaryUmpireNamePrompt = nil
            }
            Button("Save") {
                let enteredName = clean(boundaryUmpireNameDraft)
                if boundaryUmpireNamePrompt == .one {
                    boundaryUmpire1CustomName = enteredName
                    boundaryUmpire1ID = nil
                } else if boundaryUmpireNamePrompt == .two {
                    boundaryUmpire2CustomName = enteredName
                    boundaryUmpire2ID = nil
                }
                boundaryUmpireNamePrompt = nil
            }
        } message: {
            Text("Enter a name if no listed player was the boundary umpire.")
        }
    }

    private var medicalStep: some View {
        ScrollView {
            VStack(spacing: 14) {
                StaffCard(title: "Medical & Trainers", systemImage: "cross.case.fill") {
                    if selectedGrade?.asksTrainers ?? true {
                        StaffPickerField(title: "Trainer 1", role: .trainer, gradeID: gradeID, value: $trainer1Name)
                        StaffPickerField(title: "Trainer 2", role: .trainer, gradeID: gradeID, value: $trainer2Name)
                        StaffPickerField(title: "Trainer 3", role: .trainer, gradeID: gradeID, value: $trainer3Name)
                        StaffPickerField(title: "Trainer 4", role: .trainer, gradeID: gradeID, value: $trainer4Name)
                    } else {
                        Text("Trainer fields are disabled for this grade.")
                            .foregroundStyle(.secondary)
                    }
                }

                if selectedGrade?.asksNotes ?? true {
                    StaffCard(title: "Notes", systemImage: "note.text") {
                        TextField("Notes (optional)", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var scoreStep: some View {
        Form {
            Section {
                Stepper("Goals: \(ourGoals)", value: $ourGoals, in: 0...50)
                Stepper("Behinds: \(ourBehinds)", value: $ourBehinds, in: 0...50)

                HStack {
                    Text("Total")
                    Spacer()
                    Text("\(ourScore)")
                        .font(.headline)
                        .monospacedDigit()
                }

            } header: {
                HStack(alignment: .center) {
                    ScorePill.minMan()
                    Spacer()
                    Text("\(ourGoals).\(ourBehinds) (\(ourScore))")
                        .font(.system(size: 24, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }

            Section {
                Stepper("Goals: \(theirGoals)", value: $theirGoals, in: 0...50)
                Stepper("Behinds: \(theirBehinds)", value: $theirBehinds, in: 0...50)

                HStack {
                    Text("Total")
                    Spacer()
                    Text("\(theirScore)")
                        .font(.headline)
                        .monospacedDigit()
                }

            } header: {
                HStack(alignment: .center) {
                    ScorePill.opponent(finalOpponent)
                    Spacer()
                    Text("\(theirGoals).\(theirBehinds) (\(theirScore))")
                        .font(.system(size: 24, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var goalsStep: some View {
        Form {
            Section("Goals summary") {
                HStack { Text("Our goals (from score)"); Spacer(); Text("\(ourGoals)").font(.headline) }
                HStack { Text("Allocated to kickers"); Spacer(); Text("\(totalGoalsKicked)").font(.headline) }
                HStack {
                    Text(overAllocatedGoals ? "Over allocated" : "Remaining to allocate")
                    Spacer()
                    Text("\(abs(remainingGoalsToAllocate))")
                        .font(.headline)
                        .foregroundStyle(overAllocatedGoals ? .red : .primary)
                }
                if hasDuplicateGoalKickers {
                    Text("Same player selected more than once.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Goal kickers") {
                if eligiblePlayers.isEmpty {
                    Text("Add players to this grade first.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($goalKickers) { $entry in
                        HStack(spacing: 12) {
                            Picker("Player", selection: $entry.playerID) {
                                Text("Select player…").tag(UUID?.none)
                                ForEach(eligiblePlayers) { p in
                                    Text(p.name).tag(UUID?.some(p.id))
                                }
                            }

                            Spacer(minLength: 8)

                            Text("\(entry.goals)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(clubYellow)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(clubNavy)
                                )

                            Stepper(value: $entry.goals, in: 0...maxAllowedGoals(for: entry)) {
                                EmptyView()
                            }
                            .labelsHidden()
                        }
                    }
                    .onDelete { idx in goalKickers.remove(atOffsets: idx) }

                    Button("Add goal kicker") {
                        goalKickers.append(WizardGoalKickerEntry(playerID: nil, goals: 1))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var bestStep: some View {
        Form {
            Section("Best players (ranked 1–\(requiredBestPlayersCount))") {
                if eligiblePlayers.isEmpty {
                    Text("Add players to this grade first.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(0..<requiredBestPlayersCount, id: \.self) { idx in
                        Picker(bestLabel(for: idx), selection: Binding(
                            get: { bestRanked[idx] ?? UUID() },
                            set: { newID in setBestPlayer(newID, at: idx) }
                        )) {
                            Text("Select…").tag(UUID())
                            ForEach(eligiblePlayers) { p in
                                Text(p.name).tag(p.id)
                            }
                        }
                    }
                    if hasDuplicateBestPlayers {
                        Text("Duplicate players selected. Each rank must be a different player.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var reviewStep: some View {
        Form {
            Section("Game Summary") {
                Text("Opponent: \(finalOpponent)")
                Text("Venue: \(finalVenue)")
                Text("Date: \(date.formatted(date: .abbreviated, time: .omitted))")

                if let gid = gradeID, let g = resolvedGrades.first(where: { $0.id == gid }) {
                    Text("Grade: \(g.name)")
                }

                Text("\(ourGoals).\(ourBehinds) (\(ourScore))  –  \(theirGoals).\(theirBehinds) (\(theirScore))")
                    .font(.headline)
            }

            if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Notes") { Text(notes) }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var votesStep: some View {
        Form {
            Section("Guest Best & Fairest votes") {
                if guestBestFairestVotesScanPDF == nil {
                    Text("Scan the paper votes before saving.")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Votes scan captured", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Button(guestBestFairestVotesScanPDF == nil ? "Scan votes" : "Rescan votes") {
                    openVotesScanner()
                }
            }
        }
        .sheet(isPresented: $showVotesScanner) {
            VotesScannerSheet { data in
                guestBestFairestVotesScanPDF = data
                showVotesScanner = false
            } onCancel: {
                showVotesScanner = false
            }
        }
        .alert("Scanner unavailable", isPresented: Binding(
            get: { scannerErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    scannerErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                scannerErrorMessage = nil
            }
        } message: {
            Text(scannerErrorMessage ?? "")
        }
        .scrollContentBackground(.hidden)
    }

    private func openVotesScanner() {
        guard VNDocumentCameraViewController.isSupported else {
            scannerErrorMessage = "This device does not support document scanning."
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showVotesScanner = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showVotesScanner = true
                    } else {
                        scannerErrorMessage = "Camera access is required to scan guest votes. Enable camera access in Settings."
                    }
                }
            }
        case .denied, .restricted:
            scannerErrorMessage = "Camera access is required to scan guest votes. Enable camera access in Settings."
        @unknown default:
            scannerErrorMessage = "Unable to access the camera right now. Please try again."
        }
    }

    // MARK: Logic helpers
    private var hasDuplicateBestPlayers: Bool {
        let ids = Array(bestRanked.prefix(requiredBestPlayersCount)).compactMap { $0 }
        return ids.count != Set(ids).count
    }

    private func setBestPlayer(_ id: UUID, at index: Int) {
        bestRanked[index] = id
        for i in 0..<requiredBestPlayersCount where i != index {
            if bestRanked[i] == id { bestRanked[i] = nil }
        }
    }

    private func bestLabel(for idx: Int) -> String {
        let position = idx + 1
        switch position {
        case 1: return "Best"
        case 2: return "2nd"
        case 3: return "3rd"
        default:
            let suffix = (11...13).contains(position % 100) ? "th" : ([1: "st", 2: "nd", 3: "rd"][position % 10] ?? "th")
            return "\(position)\(suffix)"
        }
    }

    private func syncBestPlayersSelectionCount() {
        let targetCount = requiredBestPlayersCount
        if bestRanked.count < targetCount {
            bestRanked.append(contentsOf: Array(repeating: nil, count: targetCount - bestRanked.count))
        } else if bestRanked.count > targetCount {
            bestRanked = Array(bestRanked.prefix(targetCount))
        }
    }

    private var totalGoalsKicked: Int { goalKickers.reduce(0) { $0 + $1.goals } }
    private var remainingGoalsToAllocate: Int { ourGoals - totalGoalsKicked }
    private var overAllocatedGoals: Bool { remainingGoalsToAllocate < 0 }

    private var hasDuplicateGoalKickers: Bool {
        let ids = goalKickers.compactMap { $0.playerID }
        return ids.count != Set(ids).count
    }

    private var allGoalKickersSelected: Bool {
        goalKickers.allSatisfy { $0.playerID != nil }
    }

    // MARK: Save
    private func saveGame() {
        guard let gid = gradeID else { return }
        guard !finalOpponent.isEmpty else { return }
        guard !finalVenue.isEmpty else { return }

        let bestPlayersCount = requiredBestPlayersCount
        let asksGoalKickers = selectedGrade?.asksGoalKickers ?? true
        let asksNotes = selectedGrade?.asksNotes ?? true
        let asksVotesScan = selectedGrade?.asksGuestBestFairestVotesScan ?? false

        let bestIDs = bestPlayersCount > 0 ? Array(bestRanked.prefix(bestPlayersCount)).compactMap { $0 } : []
        if bestPlayersCount > 0 {
            guard bestIDs.count == bestPlayersCount, Set(bestIDs).count == bestPlayersCount else { return }
        }
        if asksVotesScan {
            guard guestBestFairestVotesScanPDF != nil else { return }
        }

        let cleanedNotes = asksNotes ? notes.trimmingCharacters(in: .whitespacesAndNewlines) : ""

        let modelGoalKickers: [GameGoalKickerEntry] = asksGoalKickers ? goalKickers.compactMap { entry in
            guard let pid = entry.playerID, entry.goals > 0 else { return nil }
            return GameGoalKickerEntry(playerID: pid, goals: entry.goals)
        } : []

        let game = Game(
            id: UUID(),
            gradeID: gid,
            date: date,
            opponent: finalOpponent,
            venue: finalVenue,
            ourGoals: ourGoals,
            ourBehinds: ourBehinds,
            theirGoals: theirGoals,
            theirBehinds: theirBehinds,
            goalKickers: modelGoalKickers,
            bestPlayersRanked: bestIDs,
            notes: cleanedNotes,
            guestBestFairestVotesScanPDF: guestBestFairestVotesScanPDF
        )

        modelContext.insert(game)

        // Persist the last selected staff for this grade so new entries can default to them.
        persistCurrentStaffSelections(for: gid)

        do { try modelContext.save() }
        catch { print("❌ Failed to save game: \(error)"); return }

        // ✅ dismiss after successful save
        dismiss()
    }

    // MARK: - AFL-ish card container
    private struct StaffCard<Content: View>: View {
        let title: String
        let systemImage: String
        @ViewBuilder var content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                    Text(title.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.9)
                    Spacer()
                }
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(12)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
                )
            }
        }
    }
}
