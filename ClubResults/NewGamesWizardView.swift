import SwiftUI
import SwiftData

// Local model for goal kickers used by this wizard
private struct WizardGoalKickerEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var playerID: UUID?
    var goals: Int
}

struct NewGameWizardView: View {
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
    enum Step: Int, CaseIterable { case setup, staff, score, goals, best, review }
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

    // Boundary umpires are chosen from players list (IDs)
    @State private var boundaryUmpire1ID: UUID?
    @State private var boundaryUmpire2ID: UUID?

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
    private var finalBoundary1: String { playerName(for: boundaryUmpire1ID) }
    private var finalBoundary2: String { playerName(for: boundaryUmpire2ID) }

    private var venuesForOpponent: [String] {
        guard !finalOpponent.isEmpty else { return [] }
        return venueOptionsByOpponent[finalOpponent] ?? []
    }

    // MARK: Defaults (from SwiftData)
    private func defaultStaffName(for role: StaffRole, gradeID: UUID?) -> String? {
        guard let gradeID else { return nil }
        return staffDefaults.first(where: { $0.gradeID == gradeID && $0.role == role })?.name
    }

    private func applyDefaultsIfNeeded(for gradeID: UUID?) {
        // Only set if empty so we never overwrite the user's choice
        if clean(headCoachName).isEmpty {
            headCoachName = defaultStaffName(for: .headCoach, gradeID: gradeID) ?? ""
        }
        if clean(assCoachName).isEmpty {
            assCoachName = defaultStaffName(for: .assistantCoach, gradeID: gradeID) ?? ""
        }
        if clean(teamManagerName).isEmpty {
            teamManagerName = defaultStaffName(for: .teamManager, gradeID: gradeID) ?? ""
        }
        if clean(runnerName).isEmpty {
            runnerName = defaultStaffName(for: .runner, gradeID: gradeID) ?? ""
        }
    }

    // MARK: Ordering helpers
    private var orderedGrades: [Grade] {
        orderedGradesForDisplay(grades)
    }

    private var eligiblePlayers: [Player] {
        guard let gid = gradeID else { return [] }
        return players.filter { $0.isActive && $0.gradeIDs.contains(gid) }
    }

    // MARK: - Required styling helpers for Boundary rows
    private func requiredLabel(_ title: String, isMissing: Bool) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isMissing ? Color.red : Color.primary)
    }

    private func requiredValue(_ text: String, isMissing: Bool) -> some View {
        Text(text.isEmpty ? "Select…" : text)
            .font(.system(size: 16, weight: isMissing ? .regular : .semibold))
            .foregroundStyle(isMissing ? Color.red : Color.accentColor)
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
            let coachingOK =
                !finalHeadCoach.isEmpty &&
                !finalAssCoach.isEmpty &&
                !finalTeamManager.isEmpty &&
                !finalRunner.isEmpty

            let officialsOK =
                !finalGoalUmpire.isEmpty &&
                boundaryUmpire1ID != nil &&
                boundaryUmpire2ID != nil &&
                boundaryUmpire1ID != boundaryUmpire2ID

            return coachingOK && officialsOK

        case .score:
            return true

        case .goals:
            return remainingGoalsToAllocate == 0
                && !hasDuplicateGoalKickers
                && (goalKickers.isEmpty || allGoalKickersSelected)

        case .best:
            let ids = bestRanked.compactMap { $0 }
            return ids.count == 6 && Set(ids).count == 6

        case .review:
            return true
        }
    }

    // MARK: Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                ProgressView(
                    value: Double(step.rawValue),
                    total: Double(Step.allCases.count - 1)
                )
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 6)

                ZStack {
                    switch step {
                    case .setup: setupStep
                    case .staff: staffStep
                    case .score: scoreStep
                    case .goals: goalsStep
                    case .best: bestStep
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
            .navigationTitle("New Game")
            .navigationBarTitleDisplayMode(.large)

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
            applyDefaultsIfNeeded(for: gradeID)
        }
        // ✅ When user changes grade, auto-fill defaults (only if empty)
        .onChange(of: gradeID) { _, newGrade in
            applyDefaultsIfNeeded(for: newGrade)
        }
    }

    private func next() {
        if let n = Step(rawValue: step.rawValue + 1) {
            step = n
        }
    }

    private func back() {
        if let p = Step(rawValue: step.rawValue - 1) { step = p }
    }

    // MARK: Steps

    // ✅ NEW: Setup step (Grade + Date + Opponent + Venue)
    // Uses the SAME Form styling you had on the Grade screen.
    private var setupStep: some View {
        Form {
            Section {
                Picker("Grade", selection: $gradeID) {
                    Text("Select…").tag(UUID?.none)
                    ForEach(orderedGrades) { g in
                        Text(g.name).tag(UUID?.some(g.id))
                    }
                }
                .pickerStyle(.menu)

                if let _ = gradeID, eligiblePlayers.isEmpty {
                    Text("No active players assigned to this grade yet. Add players first.")
                        .foregroundStyle(.secondary)
                } else if gradeID != nil {
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
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    // ✅ Staff step (unchanged)
    private var staffStep: some View {
        ScrollView {
            VStack(spacing: 14) {

                StaffCard(title: "Coaching", systemImage: "person.2.fill") {
                    StaffPickerField(title: "Head Coach", role: .headCoach, gradeID: gradeID, value: $headCoachName)
                    StaffPickerField(title: "Assistant Coach", role: .assistantCoach, gradeID: gradeID, value: $assCoachName)
                    StaffPickerField(title: "Team Manager", role: .teamManager, gradeID: gradeID, value: $teamManagerName)
                    StaffPickerField(title: "Runner", role: .runner, gradeID: gradeID, value: $runnerName)
                }

                StaffCard(title: "Officials", systemImage: "flag.fill") {
                    StaffPickerField(title: "Goal Umpire", role: .goalUmpire, gradeID: gradeID, value: $goalUmpireName)

                    // ✅ Boundary Umpire 1
                    HStack(spacing: 12) {
                        requiredLabel("Boundary Umpire 1", isMissing: boundaryUmpire1ID == nil)
                        Spacer()
                        Menu {
                            Button("Select…") { boundaryUmpire1ID = nil }
                            Divider()
                            ForEach(players) { person in
                                if person.id != boundaryUmpire2ID {
                                    Button(person.name) { boundaryUmpire1ID = person.id }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                requiredValue(playerName(for: boundaryUmpire1ID), isMissing: boundaryUmpire1ID == nil)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                    .padding(.vertical, 6)

                    Divider().opacity(0.6)

                    // ✅ Boundary Umpire 2
                    HStack(spacing: 12) {
                        requiredLabel("Boundary Umpire 2", isMissing: boundaryUmpire2ID == nil)
                        Spacer()
                        Menu {
                            Button("Select…") { boundaryUmpire2ID = nil }
                            Divider()
                            ForEach(players) { person in
                                if person.id != boundaryUmpire1ID {
                                    Button(person.name) { boundaryUmpire2ID = person.id }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                requiredValue(playerName(for: boundaryUmpire2ID), isMissing: boundaryUmpire2ID == nil)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                    .padding(.vertical, 6)

                    if boundaryUmpire1ID != nil, boundaryUmpire1ID == boundaryUmpire2ID {
                        Text("Boundary Umpire 1 and 2 can’t be the same.")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.top, 6)
                    }
                }

                StaffCard(title: "Medical & Trainers", systemImage: "cross.case.fill") {
                    StaffPickerField(title: "Trainer 1", role: .trainer, gradeID: gradeID, value: $trainer1Name)
                    StaffPickerField(title: "Trainer 2", role: .trainer, gradeID: gradeID, value: $trainer2Name)
                    StaffPickerField(title: "Trainer 3", role: .trainer, gradeID: gradeID, value: $trainer3Name)
                    StaffPickerField(title: "Trainer 4", role: .trainer, gradeID: gradeID, value: $trainer4Name)
                }

                StaffCard(title: "Notes", systemImage: "note.text") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(12)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            Section("Best players (ranked 1–6)") {
                if eligiblePlayers.isEmpty {
                    Text("Add players to this grade first.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(0..<6, id: \.self) { idx in
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

                if let gid = gradeID, let g = grades.first(where: { $0.id == gid }) {
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

    // MARK: Logic helpers
    private var hasDuplicateBestPlayers: Bool {
        let ids = bestRanked.compactMap { $0 }
        return ids.count != Set(ids).count
    }

    private func setBestPlayer(_ id: UUID, at index: Int) {
        bestRanked[index] = id
        for i in 0..<bestRanked.count where i != index {
            if bestRanked[i] == id { bestRanked[i] = nil }
        }
    }

    private func bestLabel(for idx: Int) -> String {
        switch idx {
        case 0: return "Best"
        case 1: return "2nd"
        case 2: return "3rd"
        case 3: return "4th"
        case 4: return "5th"
        case 5: return "6th"
        default: return ""
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

        let bestIDs = bestRanked.compactMap { $0 }
        guard bestIDs.count == 6, Set(bestIDs).count == 6 else { return }

        let cleanedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let modelGoalKickers: [GameGoalKickerEntry] = goalKickers.compactMap { entry in
            guard let pid = entry.playerID, entry.goals > 0 else { return nil }
            return GameGoalKickerEntry(playerID: pid, goals: entry.goals)
        }

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
            notes: cleanedNotes
        )

        modelContext.insert(game)

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
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                    Text(title.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.9)
                    Spacer()
                }
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
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
