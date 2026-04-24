import SwiftUI
import SwiftData
import UIKit
import PDFKit

@Model
final class StatType {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, isEnabled: Bool = true, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
    }
}

extension StatType {
    var voiceAliases: [String] {
        let canonical = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if canonical.isEmpty { return [] }
        let lowercase = canonical.lowercased()
        let builtIn: [String: [String]] = [
            "kick": ["kick", "kicks", "cake", "click"],
            "handball": ["handball", "hand ball", "handpass", "hand pass", "hamble", "ambo", "ammo", "cambell"],
            "mark": ["mark", "marks"],
            "tackle": ["tackle", "tackles"],
            "goal": ["goal", "goals", "go", "no", "cow", "call"],
            "behind": ["behind", "behinds", "point", "points", "rushed behind", "time", "holland"]
        ]
        let aliases = builtIn[lowercase] ?? [canonical]
        let detectedWords = SpeechDetectedWordsStore.words(for: id)
        return SpeechDetectedWordsStore.mergedAliases(
            canonical: canonical,
            builtIn: aliases,
            detected: detectedWords
        )
    }
}

private enum SpeechDetectedWordsStore {
    static let storageKey = "speech_setup_detected_words"

    static func words(for statTypeID: UUID) -> [String] {
        let key = "builtin::\(statTypeID.uuidString)"
        let map = load()
        return map[key] ?? []
    }

    static func words(forSectionKey sectionKey: String) -> [String] {
        let map = load()
        return map[sectionKey] ?? []
    }

    static func mergedAliases(canonical: String, builtIn: [String], detected: [String]) -> [String] {
        let canonicalTrimmed = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = [canonicalTrimmed] + builtIn + detected
        var seen: Set<String> = []
        var ordered: [String] = []

        for alias in combined {
            let normalized = alias
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                ordered.append(normalized)
            }
        }

        return ordered
    }

    private static func load() -> [String: [String]] {
        guard let json = UserDefaults.standard.string(forKey: storageKey),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            return [:]
        }

        return decoded.mapValues { values in
            values.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            .filter { !$0.isEmpty }
        }
    }
}

private enum SpeechVoteSection {
    static let contestedKey = "meta::contested"
    static let uncontestedKey = "meta::uncontested"
    static let effectiveKey = "meta::effective"
    static let ineffectiveKey = "meta::ineffective"

    static let all: [(key: String, name: String, defaultAliases: [String])] = [
        (contestedKey, "Contested", ["contested"]),
        (uncontestedKey, "Uncontested", ["uncontested"]),
        (effectiveKey, "Effective", ["effective", "efficient", "effecient"]),
        (ineffectiveKey, "Ineffective", ["ineffective", "inefficient", "ineffecient", "non effective", "noneffective"])
    ]
}

@Model
final class StatsSession {
    var sessionId: UUID
    var gradeId: UUID
    var opposition: String
    var date: Date
    var venue: String
    var createdAt: Date

    init(sessionId: UUID = UUID(), gradeId: UUID, opposition: String, date: Date, venue: String, createdAt: Date = Date()) {
        self.sessionId = sessionId
        self.gradeId = gradeId
        self.opposition = opposition
        self.date = date
        self.venue = venue
        self.createdAt = createdAt
    }
}

@Model
final class StatEvent {
    var id: UUID
    var sessionId: UUID
    var playerId: UUID
    var statTypeId: UUID
    var quarter: String
    var timestamp: Date
    var sourceRaw: String
    var transcript: String?
    var normalizedTranscript: String?
    var parserConfidence: Double?
    var efficiencyVoteRaw: String?
    var contestedVoteRaw: String?

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        playerId: UUID,
        statTypeId: UUID,
        quarter: String,
        timestamp: Date = Date(),
        sourceRaw: String,
        transcript: String? = nil,
        normalizedTranscript: String? = nil,
        parserConfidence: Double? = nil,
        efficiencyVoteRaw: String? = nil,
        contestedVoteRaw: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.playerId = playerId
        self.statTypeId = statTypeId
        self.quarter = quarter
        self.timestamp = timestamp
        self.sourceRaw = sourceRaw
        self.transcript = transcript
        self.normalizedTranscript = normalizedTranscript
        self.parserConfidence = parserConfidence
        self.efficiencyVoteRaw = efficiencyVoteRaw
        self.contestedVoteRaw = contestedVoteRaw
    }
}

enum StatsEventSource: String, CaseIterable {
    case manual
    case voice
}

private enum EfficiencyVote: String {
    case thumbsUp
    case thumbsDown
}

private enum ContestedPossessionVote: String {
    case contested
    case uncontested
}

private struct StatRecordBanner: Equatable {
    let text: String
    let isSuccess: Bool
}

private struct QuickStatPieSlice: Shape {
    let startAngle: CGFloat
    let endAngle: CGFloat
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = Angle(degrees: startAngle)
        let end = Angle(degrees: endAngle)

        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

private enum StatsDefaults {
    static let statNames = ["Kick", "Handball", "Mark", "Tackle", "Goal", "Behind", "Inside 50"]
}

struct StatsRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StatsSession.createdAt, order: .reverse) private var sessions: [StatsSession]
    @Query(sort: \Grade.displayOrder) private var grades: [Grade]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        StatsSessionSetupView()
                    } label: {
                        Label("New Stats Session", systemImage: "plus.circle.fill")
                    }
                }

                Section("Recent Sessions") {
                    if sessions.isEmpty {
                        Text("No sessions yet")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(sessions) { session in
                        NavigationLink {
                            LiveStatsView(session: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(gradeName(for: session.gradeId))
                                    .font(.headline)
                                Text("vs \(session.opposition) • \(session.date, format: Date.FormatStyle(date: .abbreviated, time: .omitted))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stats")
            .task {
                seedDefaultStatTypesIfNeeded()
            }
        }
    }

    private func gradeName(for id: UUID) -> String {
        grades.first(where: { $0.id == id })?.name ?? "Unknown Grade"
    }

    private func seedDefaultStatTypesIfNeeded() {
        let existing = (try? modelContext.fetch(FetchDescriptor<StatType>())) ?? []
        guard existing.isEmpty else { return }

        for (index, name) in StatsDefaults.statNames.enumerated() {
            modelContext.insert(StatType(name: name, isEnabled: true, sortOrder: index))
        }

        try? modelContext.save()
    }
}

struct StatsTypesSettingsView: View {
    private enum StatsSide {
        case ourClub
        case opposition
    }

    private enum StatsLayoutOption: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case edge = "Edge"
        case centre = "Centre"

        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StatType.sortOrder) private var statTypes: [StatType]
    @State private var newName = ""
    @AppStorage("trackDisposalEfficiency") private var trackDisposalEfficiency = true
    @AppStorage("trackContestedPossessions") private var trackContestedPossessions = true
    @AppStorage("trackIndividualTracking") private var trackIndividualTracking = true
    @AppStorage("oppTrackDisposalEfficiency") private var oppositionTrackDisposalEfficiency = true
    @AppStorage("oppTrackContestedPossessions") private var oppositionTrackContestedPossessions = true
    @AppStorage("oppTrackPossessions") private var oppositionTrackPossessions = true
    @AppStorage("statsLayout") private var statsLayout = StatsLayoutOption.standard.rawValue

    var body: some View {
        GeometryReader { geometry in
            let paneWidth = max((geometry.size.width - 16) / 2, 0)

            VStack(alignment: .leading, spacing: 16) {
                sharedControlsPane

                HStack(alignment: .top, spacing: 16) {
                    statsPane(title: "Our Club", side: .ourClub)
                        .frame(width: paneWidth)
                    statsPane(title: "Opposition", side: .opposition)
                        .frame(width: paneWidth)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .navigationTitle("Stats")
        .toolbar {
            EditButton()
        }
        .task {
            seedDefaultStatTypesIfNeeded()
            ensureAlwaysOnStatTypesIfNeeded()
            removeDeprecatedStatTypesIfNeeded()
            ensureGoalAndBehindStatTypesIfNeeded()
            enforceOppositionTrackingDependency()
        }
    }

    @ViewBuilder
    private func statsPane(title: String, side: StatsSide) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 8)

            List {
                Section("Tracking") {
                    if side == .ourClub {
                        Toggle("Individual Tracking", isOn: trackingBinding(for: side, type: .individualTracking))
                        Toggle("Track Disposal Efficiency", isOn: trackingBinding(for: side, type: .disposalEfficiency))
                        Toggle("Track Contested Possessions", isOn: trackingBinding(for: side, type: .contestedPossessions))
                    } else {
                        Toggle("Track Possesions", isOn: trackingBinding(for: side, type: .oppositionPossessions))
                        Toggle("Track Disposal Efficiency", isOn: trackingBinding(for: side, type: .disposalEfficiency))
                            .disabled(!oppositionTrackPossessions)
                        Toggle("Track Contested Possessions", isOn: trackingBinding(for: side, type: .contestedPossessions))
                            .disabled(!oppositionTrackPossessions)
                    }
                }

                Section("Add Stat Type") {
                    TextField("Stat name", text: $newName)
                    Button("Add") {
                        addStatType()
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if side == .ourClub {
                    Section("Stat Types") {
                        ForEach(configurableStatTypes(), id: \.id) { type in
                            HStack {
                                TextField("Name", text: Binding(
                                    get: { type.name },
                                    set: {
                                        type.name = $0
                                        save()
                                    }
                                ))

                                Toggle("Enabled", isOn: statTypeEnabledBinding(for: type, side: side))
                                    .labelsHidden()
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    modelContext.delete(type)
                                    resequence()
                                    save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .moveDisabled(false)
                        }
                        .onMove(perform: moveConfigurable)
                    }
                }

            }
            .frame(maxWidth: .infinity, minHeight: 560)
            .listStyle(.insetGrouped)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var sharedControlsPane: some View {
        List {
            Section("Layout") {
                Picker("Layout", selection: $statsLayout) {
                    ForEach(StatsLayoutOption.allCases) { layout in
                        Text(layout.rawValue).tag(layout.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Speech") {
                NavigationLink {
                    SpeechSetupView()
                } label: {
                    Label("Speech Setup", systemImage: "waveform.badge.mic")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 220)
        .listStyle(.insetGrouped)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func addStatType() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(StatType(name: trimmed, isEnabled: true, sortOrder: statTypes.count))
        newName = ""
        save()
    }

    private func move(from source: IndexSet, to destination: Int) {
        var arranged = statTypes
        arranged.move(fromOffsets: source, toOffset: destination)
        for (index, type) in arranged.enumerated() {
            type.sortOrder = index
        }
        save()
    }

    private func resequence() {
        for (index, type) in statTypes.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
            type.sortOrder = index
        }
    }

    private func save() {
        try? modelContext.save()
    }

    private func seedDefaultStatTypesIfNeeded() {
        let existing = (try? modelContext.fetch(FetchDescriptor<StatType>())) ?? []
        guard existing.isEmpty else { return }
        for (index, name) in StatsDefaults.statNames.enumerated() {
            modelContext.insert(StatType(name: name, isEnabled: true, sortOrder: index))
        }
        save()
    }

    private enum TrackingType {
        case disposalEfficiency
        case contestedPossessions
        case individualTracking
        case oppositionPossessions
    }

    private func trackingBinding(for side: StatsSide, type: TrackingType) -> Binding<Bool> {
        Binding(
            get: {
                switch (side, type) {
                case (.ourClub, .disposalEfficiency): return trackDisposalEfficiency
                case (.ourClub, .contestedPossessions): return trackContestedPossessions
                case (.ourClub, .individualTracking): return trackIndividualTracking
                case (.ourClub, .oppositionPossessions): return trackContestedPossessions
                case (.opposition, .disposalEfficiency): return oppositionTrackPossessions ? oppositionTrackDisposalEfficiency : false
                case (.opposition, .contestedPossessions): return oppositionTrackPossessions ? oppositionTrackContestedPossessions : false
                case (.opposition, .individualTracking): return oppositionTrackPossessions
                case (.opposition, .oppositionPossessions): return oppositionTrackPossessions
                }
            },
            set: { newValue in
                switch (side, type) {
                case (.ourClub, .disposalEfficiency): trackDisposalEfficiency = newValue
                case (.ourClub, .contestedPossessions): trackContestedPossessions = newValue
                case (.ourClub, .individualTracking): trackIndividualTracking = newValue
                case (.ourClub, .oppositionPossessions): trackContestedPossessions = newValue
                case (.opposition, .disposalEfficiency):
                    oppositionTrackDisposalEfficiency = oppositionTrackPossessions ? newValue : false
                case (.opposition, .contestedPossessions):
                    oppositionTrackContestedPossessions = oppositionTrackPossessions ? newValue : false
                case (.opposition, .individualTracking): oppositionTrackPossessions = newValue
                case (.opposition, .oppositionPossessions):
                    oppositionTrackPossessions = newValue
                    if !newValue {
                        oppositionTrackDisposalEfficiency = false
                        oppositionTrackContestedPossessions = false
                    }
                }
            }
        )
    }

    private func enforceOppositionTrackingDependency() {
        guard !oppositionTrackPossessions else { return }
        oppositionTrackDisposalEfficiency = false
        oppositionTrackContestedPossessions = false
    }

    private func statTypeEnabledBinding(for type: StatType, side: StatsSide) -> Binding<Bool> {
        Binding(
            get: {
                if side == .ourClub { return type.isEnabled }
                return true
            },
            set: { newValue in
                if side == .ourClub {
                    type.isEnabled = newValue
                    save()
                }
            }
        )
    }

    private func configurableStatTypes() -> [StatType] {
        statTypes
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .filter { !isAlwaysOnHiddenStatType($0.name) }
    }

    private func moveConfigurable(from source: IndexSet, to destination: Int) {
        var configurable = configurableStatTypes()
        configurable.move(fromOffsets: source, toOffset: destination)

        let alwaysOn = statTypes
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .filter { isAlwaysOnHiddenStatType($0.name) }

        let reordered = configurable + alwaysOn
        for (index, type) in reordered.enumerated() {
            type.sortOrder = index
        }
        save()
    }

    private func ensureAlwaysOnStatTypesIfNeeded() {
        var existing = (try? modelContext.fetch(FetchDescriptor<StatType>())) ?? []
        let alwaysOnNames = ["Inside 50"]

        for name in alwaysOnNames {
            if let match = existing.first(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
                match.isEnabled = true
            } else {
                let type = StatType(name: name, isEnabled: true, sortOrder: existing.count)
                modelContext.insert(type)
                existing.append(type)
            }
        }
        save()
    }

    private func isAlwaysOnHiddenStatType(_ name: String) -> Bool {
        ["inside 50"].contains(name.lowercased())
    }

    private func removeDeprecatedStatTypesIfNeeded() {
        let deprecatedNames = Set(["scores", "clearance", "clearances"])
        let existing = (try? modelContext.fetch(FetchDescriptor<StatType>())) ?? []
        let deprecated = existing.filter { deprecatedNames.contains($0.name.lowercased()) }
        guard !deprecated.isEmpty else { return }

        deprecated.forEach { modelContext.delete($0) }
        resequence()
        save()
    }

    private func ensureGoalAndBehindStatTypesIfNeeded() {
        var existing = (try? modelContext.fetch(FetchDescriptor<StatType>())) ?? []
        let requiredNames = ["Goal", "Behind"]

        var didChange = false
        for name in requiredNames {
            if existing.contains(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
                continue
            }
            let type = StatType(name: name, isEnabled: true, sortOrder: existing.count)
            modelContext.insert(type)
            existing.append(type)
            didChange = true
        }

        if didChange {
            resequence()
            save()
        }
    }
}

private struct CustomSpeechStatSection: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
}

struct SpeechSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StatType.sortOrder) private var allStatTypes: [StatType]

    @StateObject private var speechService = PressHoldSpeechService()
    @State private var activeSectionID: String?
    @State private var newSectionName = ""
    @State private var showUnsavedChangesAlert = false

    @AppStorage("speech_setup_custom_sections") private var customSectionsData = ""
    @AppStorage("speech_setup_detected_words") private var detectedWordsData = ""

    @State private var customSections: [CustomSpeechStatSection] = []
    @State private var detectedWordsBySection: [String: [String]] = [:]
    @State private var savedCustomSections: [CustomSpeechStatSection] = []
    @State private var savedDetectedWordsBySection: [String: [String]] = [:]

    var body: some View {
        List {
            Section("Add Custom Stat Type") {
                TextField("New stat type", text: $newSectionName)
                Button {
                    addCustomSection()
                } label: {
                    Label("Add Section", systemImage: "plus.circle.fill")
                }
                .disabled(newSectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ForEach(allSections) { section in
                Section(section.name) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(activeSectionID == section.storageKey ? "Listening…" : "Hold to speak")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Press and hold the mic button to capture words.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            TextField(
                                "Add words manually, or speak and edit the result.",
                                text: editableWordsBinding(for: section.storageKey),
                                axis: .vertical
                            )
                            .textFieldStyle(.roundedBorder)

                            let words = detectedWordsBySection[section.storageKey] ?? []
                            if !words.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(words, id: \.self) { word in
                                            HStack(spacing: 6) {
                                                Text(word)
                                                    .font(.subheadline)
                                                Button {
                                                    removeWord(word, from: section.storageKey)
                                                } label: {
                                                    Image(systemName: "xmark")
                                                        .font(.caption.weight(.bold))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 10)
                                            .background(
                                                Capsule()
                                                    .fill(Color(.secondarySystemBackground))
                                            )
                                        }
                                    }
                                }
                            }

                            HStack {
                                Spacer()
                                Button("Clear") {
                                    clearWords(for: section.storageKey)
                                }
                                .disabled((detectedWordsBySection[section.storageKey] ?? []).isEmpty)
                            }
                        }

                        Button {
                            // press-and-hold only
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(activeSectionID == section.storageKey ? .red : .blue)
                                Image(systemName: "mic.fill")
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 74, height: 74)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                        .onLongPressGesture(minimumDuration: 0.01, maximumDistance: .infinity, pressing: { isPressing in
                            if isPressing {
                                activeSectionID = section.storageKey
                                speechService.startListening(vocabulary: sectionVocabulary(for: section))
                            } else if activeSectionID == section.storageKey {
                                speechService.stopListening { transcript in
                                    appendDetectedWords(transcript, to: section.storageKey)
                                    activeSectionID = nil
                                }
                            }
                        }, perform: {})
                    }
                }
            }
        }
        .navigationTitle("Speech Recognition")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    handleBackButtonPressed()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saveAllChanges()
                }
                .saveButtonBehavior(isEnabled: hasUnsavedChanges)
            }
        }
        .alert("Unsaved Changes", isPresented: $showUnsavedChangesAlert) {
            Button("Discard Changes", role: .destructive) {
                dismiss()
            }
            Button("Save and Leave") {
                saveAllChanges()
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved changes. Save before leaving this page?")
        }
        .onAppear {
            loadCustomSections()
            loadDetectedWords()
            snapshotSavedState()
        }
    }

    private var hasUnsavedChanges: Bool {
        customSections != savedCustomSections || detectedWordsBySection != savedDetectedWordsBySection
    }

    private var allSections: [SpeechSection] {
        let builtIn = allStatTypes
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .map { SpeechSection(storageKey: "builtin::\($0.id.uuidString)", name: $0.name, defaultVocabulary: []) }

        let voteSections = SpeechVoteSection.all.map {
            SpeechSection(storageKey: $0.key, name: $0.name, defaultVocabulary: $0.defaultAliases)
        }

        let custom = customSections.map {
            SpeechSection(storageKey: "custom::\($0.id.uuidString)", name: $0.name, defaultVocabulary: [])
        }

        return builtIn + voteSections + custom
    }

    private var allDetectedWords: [String] {
        Array(Set(detectedWordsBySection.values.flatMap { $0 }))
            .sorted()
    }

    private func sectionVocabulary(for section: SpeechSection) -> [String] {
        Array(Set([section.name] + section.defaultVocabulary + allDetectedWords))
    }

    private func handleBackButtonPressed() {
        if hasUnsavedChanges {
            showUnsavedChangesAlert = true
        } else {
            dismiss()
        }
    }

    private func saveAllChanges() {
        persistCustomSections()
        persistDetectedWords()
        snapshotSavedState()
    }

    private func snapshotSavedState() {
        savedCustomSections = customSections
        savedDetectedWordsBySection = detectedWordsBySection
    }

    private func appendDetectedWords(_ transcript: String, to storageKey: String) {
        let newTokens = parseWords(from: transcript)
        guard !newTokens.isEmpty else { return }

        let existing = detectedWordsBySection[storageKey] ?? []
        detectedWordsBySection[storageKey] = deduplicatedWords(existing + newTokens)
    }

    private func removeWord(_ word: String, from storageKey: String) {
        let existing = detectedWordsBySection[storageKey] ?? []
        detectedWordsBySection[storageKey] = existing.filter { $0 != word }
    }

    private func clearWords(for storageKey: String) {
        detectedWordsBySection[storageKey] = []
    }

    private func editableWordsBinding(for storageKey: String) -> Binding<String> {
        Binding(
            get: {
                (detectedWordsBySection[storageKey] ?? []).joined(separator: ", ")
            },
            set: { rawValue in
                detectedWordsBySection[storageKey] = parseWords(from: rawValue)
            }
        )
    }

    private func parseWords(from rawValue: String) -> [String] {
        let tokens = rawValue
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return deduplicatedWords(tokens)
    }

    private func deduplicatedWords(_ words: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for word in words {
            guard seen.insert(word).inserted else { continue }
            result.append(word)
        }

        return result
    }

    private func addCustomSection() {
        let trimmed = newSectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        customSections.append(CustomSpeechStatSection(id: UUID(), name: trimmed))
        customSections.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        newSectionName = ""
    }

    private func loadCustomSections() {
        guard !customSectionsData.isEmpty,
              let data = customSectionsData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([CustomSpeechStatSection].self, from: data)
        else {
            customSections = []
            return
        }
        customSections = decoded
    }

    private func persistCustomSections() {
        guard let data = try? JSONEncoder().encode(customSections),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        customSectionsData = json
    }

    private func loadDetectedWords() {
        guard !detectedWordsData.isEmpty,
              let data = detectedWordsData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            detectedWordsBySection = [:]
            return
        }
        detectedWordsBySection = decoded
    }

    private func persistDetectedWords() {
        guard let data = try? JSONEncoder().encode(detectedWordsBySection),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        detectedWordsData = json
    }
}

private struct SpeechSection: Identifiable {
    let storageKey: String
    let name: String
    let defaultVocabulary: [String]

    var id: String { storageKey }
}

struct StatsSessionSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Grade.displayOrder) private var grades: [Grade]

    @State private var selectedGradeId: UUID?
    @State private var opposition = ""
    @State private var date = Date()
    @State private var venue = ""
    @State private var createdSession: StatsSession?
    @State private var showLiveStats = false
    @State private var clubConfiguration = ClubConfigurationStore.load()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                setupCard(title: "Session Setup", systemImage: "sportscourt") {
                    HStack(spacing: 12) {
                        rowLabel("Grade")
                        Spacer()
                        Menu {
                            Button("Select…") { selectedGradeId = nil }
                            ForEach(grades.filter { $0.isActive }) { grade in
                                Button(grade.name) {
                                    selectedGradeId = grade.id
                                }
                            }
                        } label: {
                            setupMenuLabel(title: selectedGradeName ?? "Select…")
                        }
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .font(.body)

                    HStack(spacing: 12) {
                        rowLabel("Opponent")
                        Spacer()
                        Menu {
                            Button("Select…") {
                                opposition = ""
                                if !venueOptions.contains(venue) {
                                    venue = ""
                                }
                            }
                            ForEach(oppositionNames, id: \.self) { name in
                                Button(name) {
                                    opposition = name
                                    if !venueOptions.contains(venue) {
                                        venue = ""
                                    }
                                }
                            }
                        } label: {
                            setupMenuLabel(title: opposition.isEmpty ? "Select…" : opposition)
                        }
                    }

                    HStack(spacing: 12) {
                        rowLabel("Venue")
                        Spacer()
                        Menu {
                            Button("Select…") { venue = "" }
                            ForEach(venueOptions, id: \.self) { name in
                                Button(name) {
                                    venue = name
                                }
                            }
                        } label: {
                            setupMenuLabel(title: venue.isEmpty ? "Select…" : venue)
                        }
                        .disabled(venueOptions.isEmpty)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            Button {
                startSession()
            } label: {
                Text("Start Session")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(canStart ? Color.accentColor : Color.gray.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .disabled(!canStart)
        }
        .navigationTitle("New Stats Session")
        .onAppear {
            clubConfiguration = ClubConfigurationStore.load()
        }
        .navigationDestination(isPresented: $showLiveStats) {
            if let createdSession {
                LiveStatsView(session: createdSession)
            }
        }
    }

    private var canStart: Bool {
        selectedGradeId != nil && !opposition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedGradeName: String? {
        grades.first(where: { $0.id == selectedGradeId })?.name
    }

    private var oppositionNames: [String] {
        clubConfiguration.sortedOppositions.map(\.name)
    }

    private var selectedOpposition: OppositionTeamProfile? {
        clubConfiguration.sortedOppositions.first(where: { $0.name == opposition })
    }

    private var venueOptions: [String] {
        let combined = clubConfiguration.clubTeam.sanitizedVenues + (selectedOpposition?.sanitizedVenues ?? [])
        return Array(Set(combined)).sorted()
    }

    private func rowLabel(_ title: String) -> some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
    }

    private func setupMenuLabel(title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.body)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func setupCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func startSession() {
        guard let selectedGradeId else { return }
        let session = StatsSession(
            gradeId: selectedGradeId,
            opposition: opposition.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date,
            venue: venue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(session)
        try? modelContext.save()
        createdSession = session
        showLiveStats = true
    }
}

private struct TotalsRow: Identifiable {
    let id = UUID()
    let player: Player
    let countsByStatId: [UUID: Int]
}

private enum PlayerGridOrder: String, CaseIterable, Identifiable {
    case number
    case firstName
    case lastName

    var id: String { rawValue }

    var title: String {
        switch self {
        case .number:
            return "Number"
        case .firstName:
            return "First Name"
        case .lastName:
            return "Last Name"
        }
    }
}

private struct ReportPreviewDocument: Identifiable {
    let id = UUID()
    let url: URL
}

struct LiveStatsView: View {
    private enum StatsLayoutOption: String {
        case standard = "Standard"
        case edge = "Edge"
        case centre = "Centre"
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("trackDisposalEfficiency") private var trackDisposalEfficiency = true
    @AppStorage("trackContestedPossessions") private var trackContestedPossessions = true
    @AppStorage("trackIndividualTracking") private var trackIndividualTracking = true
    @AppStorage("oppTrackPossessions") private var oppositionTrackPossessions = true
    @AppStorage("oppTrackDisposalEfficiency") private var oppositionTrackDisposalEfficiency = true
    @AppStorage("oppTrackContestedPossessions") private var oppositionTrackContestedPossessions = true
    @AppStorage("statsLayout") private var statsLayout = StatsLayoutOption.standard.rawValue

    let session: StatsSession

    @Query(sort: \Grade.displayOrder) private var grades: [Grade]
    @Query(sort: \Player.name) private var allPlayers: [Player]
    @Query(sort: \StatType.sortOrder) private var allStatTypes: [StatType]
    @Query(sort: \StatEvent.timestamp, order: .reverse) private var allEvents: [StatEvent]

    @State private var selectedQuarter = "Q1"
    @State private var selectedPlayerId: UUID?
    @State private var lastMessage: String?
    @State private var showEditEvent: StatEvent?
    @State private var reportPreviewDocument: ReportPreviewDocument?
    @State private var shareURL: URL?
    @State private var showTotals = false
    @State private var feedbackToken = UUID()
    @State private var lastHeardTranscript = ""
    @State private var lastVoiceDebug: VoiceParseResult?
    @State private var remainingQuarterSeconds = 0
    @State private var isQuarterTimerRunning = false
    @State private var quarterTimerTask: Task<Void, Never>?
    @State private var visiblePlayerIDs: Set<UUID> = []
    @State private var savedVisiblePlayerIDs: Set<UUID> = []
    @State private var playerGridOrder: PlayerGridOrder = .number
    @State private var savedPlayerGridOrder: PlayerGridOrder = .number
    @State private var showPlayerVisibilityEditor = false
    @State private var pendingEfficiencyEventID: UUID?
    @State private var showEfficiencyVotePrompt = false
    @State private var showAllPlayers = false
    @State private var statusBanner: StatRecordBanner?
    @State private var statusBannerTask: Task<Void, Never>?
    @State private var showStatsSettings = false
    @State private var showQuarterChangeReminder = false
    @State private var showQuarterPickerDialog = false
    @State private var showTimerModeEditor = false
    @State private var customQuarterMinutes = 20
    @State private var activeEfficiencyButtonKey: String?
    @State private var activeEfficiencyHoverVote: EfficiencyVote?
    @State private var activeContestedHoverVote: ContestedPossessionVote?
    @State private var suppressTapForButtonKey: String?
    @State private var activePlayerQuickStatsPlayerID: UUID?
    @State private var activePlayerQuickCardFrameGlobal: CGRect = .zero
    @State private var playerCardFramesGlobal: [UUID: CGRect] = [:]
    @State private var interfaceScreenWidth: CGFloat = 1024
    @State private var interfaceScreenHeight: CGFloat = 768
    @State private var hoveredPlayerQuickStatName: String?
    @State private var hoveredPlayerQuickEfficiencyVote: EfficiencyVote?
    @State private var hoveredPlayerQuickContestedVote: ContestedPossessionVote?
    @State private var lastHapticQuickStatName: String?
    @State private var lastHapticQuickContestedVote: ContestedPossessionVote?
    @State private var lastHapticQuickEfficiencyVote: EfficiencyVote?
    @State private var quarterCountsUp = false
    @State private var activeSideSpeakPresses = 0
    @StateObject private var speechService = PressHoldSpeechService()
    private let parser = StatsVoiceParser()
    private let ourTeamStatPlayerID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA") ?? UUID()
    private let oppositionTeamStatPlayerID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB") ?? UUID()
    private let longPressHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let stepHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let playerQuickStatsLongPressDuration: Double = 0.45

    var body: some View {
        GeometryReader { proxy in
            let _: CGFloat = 8
            let availableWidth = max(proxy.size.width - 24, 640)
            let leftWidthRatio: CGFloat = oppositionTrackPossessions ? 0.72 : 0.62
            let leftPanelWidth = min(max(availableWidth * leftWidthRatio, 420), availableWidth - 300)
            let rightPanelWidth = max(availableWidth - leftPanelWidth - 12, 290)
            Group {
                if isEdgeLayoutActive {
                    edgeLayoutContent(proxy: proxy)
                } else {
                    VStack(spacing: 12) {
                        headerBannerArea
                            .frame(height: 76)
                        combinedScoreAndActionsPanel
                            .frame(height: topPanelHeight)

                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 10) {
                                playerSelectionPanel
                            }
                            .frame(width: leftPanelWidth)

                            VStack(spacing: 12) {
                                if !oppositionTrackPossessions {
                                    statButtonsPanel
                                        .frame(height: rightStatActionsHeight)
                                }
                                recentEventsPanel
                            }
                            .frame(width: rightPanelWidth)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
            }
            .task(id: proxy.size.width) {
                interfaceScreenWidth = max(proxy.size.width, 1)
            }
            .task(id: proxy.size.height) {
                interfaceScreenHeight = max(proxy.size.height, 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Settings") {
                        showStatsSettings = true
                    }
                    Button("Generate Report") {
                        generateReport()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .sheet(item: $showEditEvent) { event in
            EditStatEventView(event: event, players: playersForGrade, statTypes: enabledStatTypes)
        }
        .fullScreenCover(isPresented: $showTotals) {
            StatsTotalsView(
                rows: totalsRows,
                statTypes: enabledStatTypes,
                sessionEvents: sessionEvents,
                ourTeamName: ourTeamName,
                oppositionName: session.opposition,
                ourStyle: ourStyle,
                oppositionStyle: oppositionStyle,
                ourScoreSummary: ourScoreSummary,
                oppositionScoreSummary: oppositionScoreSummary
            )
        }
        .sheet(item: $reportPreviewDocument) { document in
            StatsReportPreviewSheet(
                url: document.url,
                onShare: { shareURL = document.url }
            )
        }
        .sheet(item: $reportPreviewDocument) { document in
            StatsReportPreviewSheet(
                url: document.url,
                onShare: { shareURL = document.url }
            )
        }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
        .sheet(isPresented: $showStatsSettings) {
            NavigationStack {
                StatsTypesSettingsView()
            }
        }
        .sheet(isPresented: $showPlayerVisibilityEditor) {
            PlayerVisibilityEditorView(
                players: playersForGrade,
                initialSelection: savedVisiblePlayerIDs,
                initialGridOrder: savedPlayerGridOrder,
                onSave: { updatedSelection, updatedGridOrder in
                    savedVisiblePlayerIDs = updatedSelection
                    visiblePlayerIDs = updatedSelection
                    savedPlayerGridOrder = updatedGridOrder
                    playerGridOrder = updatedGridOrder
                    showAllPlayers = false
                    if let selectedPlayerId, !updatedSelection.contains(selectedPlayerId) {
                        self.selectedPlayerId = nil
                    }
                }
            )
        }
        .overlay {
            if showEfficiencyVotePrompt {
                efficiencyRatingPrompt
            }
        }
        .overlay(alignment: .bottom) {
            sideSpeakButtonsOverlay
        }
        .overlay {
            if shouldShowSideSpeakMicOverlay {
                sideSpeakMicOverlay
            }
        }
        .alert("Change quarter?", isPresented: $showQuarterChangeReminder) {
            Button("No", role: .cancel) { }
            Button("Yes") {
                advanceQuarter()
            }
        } message: {
            Text("Current: \(selectedQuarter). Move to the next quarter now?")
        }
        .onDisappear {
            statusBannerTask?.cancel()
            stopQuarterTimer()
            activeSideSpeakPresses = 0
            if speechService.isRecording {
                speechService.stopListening()
            }
        }
        .onAppear {
            if visiblePlayerIDs.isEmpty {
                let defaults = Set(playersForGrade.map(\.id))
                visiblePlayerIDs = defaults
                savedVisiblePlayerIDs = defaults
            }
            playerGridOrder = savedPlayerGridOrder
            showAllPlayers = false
            customQuarterMinutes = max(1, configuredQuarterLengthSeconds / 60)
            configureQuarterTimer(reset: true)
        }
        .onChange(of: selectedQuarter) { _, _ in
            configureQuarterTimer(reset: true)
        }
        .onChange(of: feedbackToken) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                if !speechService.isRecording {
                    withAnimation(.easeOut(duration: 0.2)) {
                        lastMessage = nil
                    }
                }
            }
        }
    }

    private var playersForGrade: [Player] {
        allPlayers.filter { $0.isActive && $0.gradeIDs.contains(session.gradeId) }
    }

    private var displayedPlayers: [Player] {
        let source = playersForGrade
        let filtered = visiblePlayerIDs.isEmpty ? source : source.filter { visiblePlayerIDs.contains($0.id) }
        return filtered.sorted(by: playerSortPredicate)
    }

    private func playerSortPredicate(lhs: Player, rhs: Player) -> Bool {
        switch playerGridOrder {
        case .number:
            let leftNumber = lhs.number ?? Int.max
            let rightNumber = rhs.number ?? Int.max
            if leftNumber != rightNumber {
                return leftNumber < rightNumber
            }
            if lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) != .orderedSame {
                return lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) == .orderedAscending
            }
            return lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) == .orderedAscending
        case .firstName:
            if lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) != .orderedSame {
                return lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) == .orderedAscending
            }
            if lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) != .orderedSame {
                return lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) == .orderedAscending
            }
            return (lhs.number ?? Int.max) < (rhs.number ?? Int.max)
        case .lastName:
            if lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) != .orderedSame {
                return lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) == .orderedAscending
            }
            if lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) != .orderedSame {
                return lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) == .orderedAscending
            }
            return (lhs.number ?? Int.max) < (rhs.number ?? Int.max)
        }
    }

    private var enabledStatTypes: [StatType] {
        allStatTypes.filter { $0.isEnabled }.sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    private var sessionEvents: [StatEvent] {
        allEvents.filter { $0.sessionId == session.sessionId }
    }

    private var selectedGrade: Grade? {
        grades.first(where: { $0.id == session.gradeId })
    }

    private var configuredQuarterLengthSeconds: Int {
        min(max(selectedGrade?.quarterLengthMinutes ?? 20, 10), 30) * 60
    }

    private var ourStyle: ClubStyle.Style {
        let configuration = ClubConfigurationStore.load()
        let teamName = configuration.clubTeam.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ClubStyle.style(for: teamName.isEmpty ? "Min Man" : teamName, configuration: configuration)
    }

    private var oppositionStyle: ClubStyle.Style {
        ClubStyle.style(for: session.opposition, configuration: ClubConfigurationStore.load())
    }

    private func scoreSummary(includeEvent: (StatEvent) -> Bool) -> (goals: Int, behinds: Int, points: Int) {
        let goalTypeIDs = Set(enabledStatTypes.filter { normalizedStatName($0.name) == "goal" }.map(\.id))
        let behindTypeIDs = Set(enabledStatTypes.filter { normalizedStatName($0.name) == "behind" }.map(\.id))
        let scoresTypeIDs = Set(enabledStatTypes.filter { normalizedStatName($0.name) == "scores" }.map(\.id))

        let goals: Int
        let behinds: Int

        if !goalTypeIDs.isEmpty || !behindTypeIDs.isEmpty {
            goals = sessionEvents.filter { includeEvent($0) && goalTypeIDs.contains($0.statTypeId) }.count
            behinds = sessionEvents.filter { includeEvent($0) && behindTypeIDs.contains($0.statTypeId) }.count
        } else {
            goals = sessionEvents.filter {
                includeEvent($0)
                    && scoresTypeIDs.contains($0.statTypeId)
                    && normalizedStatName($0.transcript ?? "") == "goal"
            }.count
            behinds = sessionEvents.filter {
                includeEvent($0)
                    && scoresTypeIDs.contains($0.statTypeId)
                    && normalizedStatName($0.transcript ?? "") == "behind"
            }.count
        }
        return (goals, behinds, goals * 6 + behinds)
    }

    private var ourScoreSummary: (goals: Int, behinds: Int, points: Int) {
        scoreSummary { $0.playerId != oppositionTeamStatPlayerID }
    }

    private var oppositionScoreSummary: (goals: Int, behinds: Int, points: Int) {
        scoreSummary { $0.playerId == oppositionTeamStatPlayerID }
    }

    private var ourTeamName: String {
        let name = ClubConfigurationStore.load().clubTeam.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Min Man" : name
    }

    private var formattedQuarterTime: String {
        let absolute = abs(remainingQuarterSeconds)
        let sign = remainingQuarterSeconds < 0 ? "-" : ""
        return sign + String(format: "%02d:%02d", absolute / 60, absolute % 60)
    }

    private var timerBackgroundColor: Color {
        if isQuarterTimerRunning {
            return remainingQuarterSeconds < 0 ? .red : .green
        }
        return .gray
    }

    private var isEdgeLayoutActive: Bool {
        statsLayout == StatsLayoutOption.edge.rawValue
    }

    private var topPanelHeight: CGFloat {
        oppositionTrackPossessions ? 472 : 168
    }

    private var rightStatActionsHeight: CGFloat {
        220
    }

    private var edgeIsPortrait: Bool {
        interfaceScreenHeight > interfaceScreenWidth
    }

    private var edgeTeamStatColumns: Int {
        (isEdgeLayoutActive && edgeIsPortrait) ? 2 : 4
    }

    private var headerBannerArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
            HStack(spacing: 10) {
                timerBadge

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Text(gradeName)
                        .font(.title.weight(.black))
                        .lineLimit(1)
                    Text("•")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(session.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                quarterBadge
            }
            .padding(.horizontal, 18)

            if let statusBanner {
                RoundedRectangle(cornerRadius: 12)
                    .fill(statusBanner.isSuccess ? Color.green : Color.red)
                    .overlay {
                        Text(statusBanner.text)
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 16)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: statusBanner)
        .confirmationDialog("Select Quarter", isPresented: $showQuarterPickerDialog, titleVisibility: .visible) {
            ForEach(["Q1", "Q2", "Q3", "Q4"], id: \.self) { quarter in
                Button(quarter) {
                    selectedQuarter = quarter
                }
            }
        }
    }

    private var combinedScoreAndActionsPanel: some View {
        Group {
            if oppositionTrackPossessions {
                comparisonScoreCardPanel
            } else {
                HStack(spacing: 8) {
                    combinedTeamPanel(
                        teamName: ourTeamName,
                        scoreText: "\(ourScoreSummary.goals).\(ourScoreSummary.behinds) (\(ourScoreSummary.points))",
                        style: ourStyle,
                        isOpposition: false
                    )
                    combinedTeamPanel(
                        teamName: session.opposition,
                        scoreText: "\(oppositionScoreSummary.goals).\(oppositionScoreSummary.behinds) (\(oppositionScoreSummary.points))",
                        style: oppositionStyle,
                        isOpposition: true
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: topPanelHeight, maxHeight: topPanelHeight)
    }

    private var ourTeamEfficiencyText: String {
        guard !displayedPlayers.isEmpty else { return "0%" }
        let totals = displayedPlayers.reduce((effective: 0, nonEffective: 0)) { partialResult, player in
            let counts = efficiencyVoteCounts(for: player.id, events: sessionEvents)
            return (
                effective: partialResult.effective + counts.effective,
                nonEffective: partialResult.nonEffective + counts.nonEffective
            )
        }
        let ratedCount = totals.effective + totals.nonEffective
        guard ratedCount > 0 else { return "0%" }
        let efficiency = Int(round((Double(totals.effective) / Double(ratedCount)) * 100))
        return "\(efficiency)%"
    }

    private func combinedTeamPanel(
        teamName: String,
        scoreText: String,
        style: ClubStyle.Style,
        isOpposition: Bool
    ) -> some View {
        let isOppositionTeam = isOpposition
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ScorePill(teamName, style: style)
                    .font(.title3.weight(.bold))
                Text(scoreText)
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if isEdgeLayoutActive && !isOppositionTeam {
                HStack(spacing: 8) {
                    Text("Team Efficiency")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(ourTeamEfficiencyText)
                        .font(.title3.weight(.black))
                        .monospacedDigit()
                }
                .padding(.horizontal, 4)
            }

            if oppositionTrackPossessions {
                teamStatsExpandedGrid(style: style, isOpposition: isOppositionTeam)
            } else {
                HStack(spacing: 8) {
                    teamStatButton("Goal", name: "Goal", style: style, isOpposition: isOppositionTeam)
                    teamStatButton("Behind", name: "Behind", style: style, isOpposition: isOppositionTeam)
                    teamStatButton("Clearance", name: "Clearance", style: style, isOpposition: isOppositionTeam, fallbackName: "Clearances")
                    teamStatButton("Inside 50", name: "Inside 50", style: style, isOpposition: isOppositionTeam, fallbackName: "Inside 50s")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            if !isEdgeLayoutActive && !isOppositionTeam {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Team Eff.")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(ourTeamEfficiencyText)
                        .font(.headline.weight(.black))
                        .monospacedDigit()
                }
                .padding(.top, 8)
                .padding(.trailing, 10)
            }
        }
    }

    private func teamStatsExpandedGrid(style: ClubStyle.Style, isOpposition: Bool) -> some View {
        let fixedEntries: [(title: String, name: String, fallback: String?)] = [
            ("Goal", "Goal", nil), ("Behind", "Behind", nil), ("Clearance", "Clearance", "Clearances"), ("Inside 50", "Inside 50", "Inside 50s"),
            ("Kick", "Kick", nil), ("Handball", "Handball", nil), ("Mark", "Mark", nil), ("Tackle", "Tackle", nil)
        ]
        let fixedNames = Set(fixedEntries.map { normalizedStatName($0.name) })
        let excludedThirdRowNames: Set<String> = fixedNames.union([
            "scores",
            "score",
            "clearances",
            "inside 50s"
        ])
        let thirdRowStats = enabledStatTypes
            .filter { !excludedThirdRowNames.contains(normalizedStatName($0.name)) }
            .prefix(4)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: edgeTeamStatColumns)
        let remainingSlots = max(edgeTeamStatColumns - (Array(thirdRowStats).count % edgeTeamStatColumns), 0) % edgeTeamStatColumns

        return VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(fixedEntries.enumerated()), id: \.offset) { _, entry in
                    teamStatButton(entry.title, name: entry.name, style: style, isOpposition: isOpposition, fallbackName: entry.fallback)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(thirdRowStats), id: \.id) { statType in
                    teamStatButton(statType.name, name: statType.name, style: style, isOpposition: isOpposition)
                }
                ForEach(0..<remainingSlots, id: \.self) { _ in
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var comparisonScoreCardPanel: some View {
        let metrics = scoreComparisonMetrics
        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                VStack(spacing: 6) {
                    ScorePill(ourTeamName, style: ourStyle)
                        .font(.title2.weight(.black))
                        .padding(.horizontal, 8)
                    Text("\(ourScoreSummary.goals).\(ourScoreSummary.behinds) (\(ourScoreSummary.points))")
                        .font(.system(size: 58, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(spacing: 6) {
                    ScorePill(session.opposition, style: oppositionStyle)
                        .font(.title2.weight(.black))
                        .padding(.horizontal, 8)
                    Text("\(oppositionScoreSummary.goals).\(oppositionScoreSummary.behinds) (\(oppositionScoreSummary.points))")
                        .font(.system(size: 58, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

            VStack(spacing: 8) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                    comparisonMetricRow(metric)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var scoreComparisonMetrics: [(label: String, ourValue: String, oppositionValue: String, ourNumeric: Double, oppositionNumeric: Double)] {
        let ourEfficiency = efficiencyComparisonValues(isOpposition: false)
        let oppositionEfficiency = efficiencyComparisonValues(isOpposition: true)
        let ourContested = contestedComparisonValues(isOpposition: false)
        let oppositionContested = contestedComparisonValues(isOpposition: true)
        let ourKicks = teamTotal(aliases: ["kick"], isOpposition: false)
        let oppositionKicks = teamTotal(aliases: ["kick"], isOpposition: true)
        let ourHandballs = teamTotal(aliases: ["handball"], isOpposition: false)
        let oppositionHandballs = teamTotal(aliases: ["handball"], isOpposition: true)
        let ourMarks = teamTotal(aliases: ["mark"], isOpposition: false)
        let oppositionMarks = teamTotal(aliases: ["mark"], isOpposition: true)
        let ourTackles = teamTotal(aliases: ["tackle"], isOpposition: false)
        let oppositionTackles = teamTotal(aliases: ["tackle"], isOpposition: true)
        let ourInside50 = teamTotal(aliases: ["inside 50", "inside50", "inside 50s"], isOpposition: false)
        let oppositionInside50 = teamTotal(aliases: ["inside 50", "inside50", "inside 50s"], isOpposition: true)
        let ourClearances = teamTotal(aliases: ["clearance", "clearances"], isOpposition: false)
        let oppositionClearances = teamTotal(aliases: ["clearance", "clearances"], isOpposition: true)

        var rows: [(label: String, ourValue: String, oppositionValue: String, ourNumeric: Double, oppositionNumeric: Double)] = []

        if shouldShowEfficiencyMetric {
            rows.append((
                label: "Efficiency",
                ourValue: ourEfficiency.text,
                oppositionValue: oppositionEfficiency.text,
                ourNumeric: ourEfficiency.percent,
                oppositionNumeric: oppositionEfficiency.percent
            ))
        }

        if shouldShowContestedMetric {
            rows.append((
                label: "Contested Possession",
                ourValue: ourContested.text,
                oppositionValue: oppositionContested.text,
                ourNumeric: ourContested.total,
                oppositionNumeric: oppositionContested.total
            ))
        }

        rows.append(contentsOf: [
            (
                label: "Kicks",
                ourValue: "\(ourKicks)",
                oppositionValue: "\(oppositionKicks)",
                ourNumeric: Double(ourKicks),
                oppositionNumeric: Double(oppositionKicks)
            ),
            (
                label: "Handball",
                ourValue: "\(ourHandballs)",
                oppositionValue: "\(oppositionHandballs)",
                ourNumeric: Double(ourHandballs),
                oppositionNumeric: Double(oppositionHandballs)
            ),
            (
                label: "Marks",
                ourValue: "\(ourMarks)",
                oppositionValue: "\(oppositionMarks)",
                ourNumeric: Double(ourMarks),
                oppositionNumeric: Double(oppositionMarks)
            ),
            (
                label: "Tackles",
                ourValue: "\(ourTackles)",
                oppositionValue: "\(oppositionTackles)",
                ourNumeric: Double(ourTackles),
                oppositionNumeric: Double(oppositionTackles)
            ),
            (
                label: "Inside 50",
                ourValue: "\(ourInside50)",
                oppositionValue: "\(oppositionInside50)",
                ourNumeric: Double(ourInside50),
                oppositionNumeric: Double(oppositionInside50)
            ),
            (
                label: "Clearance",
                ourValue: "\(ourClearances)",
                oppositionValue: "\(oppositionClearances)",
                ourNumeric: Double(ourClearances),
                oppositionNumeric: Double(oppositionClearances)
            )
        ])

        return rows
    }

    private var shouldShowEfficiencyMetric: Bool {
        trackDisposalEfficiency && (!oppositionTrackPossessions || oppositionTrackDisposalEfficiency)
    }

    private var shouldShowContestedMetric: Bool {
        trackContestedPossessions && (!oppositionTrackPossessions || oppositionTrackContestedPossessions)
    }

    private func comparisonMetricRow(_ metric: (label: String, ourValue: String, oppositionValue: String, ourNumeric: Double, oppositionNumeric: Double)) -> some View {
        let ourIsLeading = metric.ourNumeric > metric.oppositionNumeric
        let oppositionIsLeading = metric.oppositionNumeric > metric.ourNumeric
        let ourBackground = ourIsLeading ? Color.green.opacity(0.85) : (oppositionIsLeading ? Color.red.opacity(0.78) : Color.gray.opacity(0.45))
        let oppositionBackground = oppositionIsLeading ? Color.green.opacity(0.85) : (ourIsLeading ? Color.red.opacity(0.78) : Color.gray.opacity(0.45))
        let isTappableMetric = metric.label == "Inside 50" || metric.label == "Clearance"

        return HStack(spacing: 10) {
            comparisonMetricSide(
                label: metric.label,
                value: metric.ourValue,
                isOpposition: false,
                background: ourBackground,
                mirrored: false,
                isTappableMetric: isTappableMetric
            )

            comparisonMetricSide(
                label: metric.label,
                value: metric.oppositionValue,
                isOpposition: true,
                background: oppositionBackground,
                mirrored: true,
                isTappableMetric: isTappableMetric
            )
        }
    }

    private func comparisonMetricSide(
        label: String,
        value: String,
        isOpposition: Bool,
        background: Color,
        mirrored: Bool,
        isTappableMetric: Bool
    ) -> some View {
        let content = HStack(spacing: 6) {
            if mirrored {
                Text(value)
                    .font(.title3.weight(.black))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                Text(label)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
            } else {
                Text(label)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(value)
                    .font(.title3.weight(.black))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
        )

        return Group {
            if isTappableMetric {
                Button {
                    addTeamComparisonMetric(label: label, isOpposition: isOpposition)
                } label: { content }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private func addTeamComparisonMetric(label: String, isOpposition: Bool) {
        let aliases: [String]
        switch label {
        case "Inside 50":
            aliases = ["inside 50", "inside50", "inside 50s"]
        case "Clearance":
            aliases = ["clearance", "clearances"]
        default:
            return
        }
        guard let type = statTypeMatching(aliases: aliases) else { return }
        addTeamEvent(statTypeId: type.id, isOpposition: isOpposition)
    }

    private func efficiencyComparisonValues(isOpposition: Bool) -> (text: String, percent: Double) {
        let teamEvents = eventsForComparison(isOpposition: isOpposition)
        let effective = teamEvents.filter { $0.efficiencyVoteRaw == EfficiencyVote.thumbsUp.rawValue }.count
        let nonEffective = teamEvents.filter { $0.efficiencyVoteRaw == EfficiencyVote.thumbsDown.rawValue }.count
        let total = effective + nonEffective
        guard total > 0 else { return ("0%", 0) }
        let percent = (Double(effective) / Double(total)) * 100
        return ("\(Int(round(percent)))%", percent)
    }

    private func contestedComparisonValues(isOpposition: Bool) -> (text: String, total: Double) {
        let teamEvents = eventsForComparison(isOpposition: isOpposition)
        let contested = teamEvents.filter { $0.contestedVoteRaw == ContestedPossessionVote.contested.rawValue }.count
        return ("\(contested)", Double(contested))
    }

    private func eventsForComparison(isOpposition: Bool) -> [StatEvent] {
        sessionEvents.filter { event in
            let isOppositionEvent = event.playerId == oppositionTeamStatPlayerID
            return isOppositionEvent == isOpposition
        }
    }

    private func teamTotal(aliases: [String], isOpposition: Bool) -> Int {
        let normalizedAliases = Set(aliases.map(normalizedStatName))
        let matchingIDs = Set(enabledStatTypes.filter { normalizedAliases.contains(normalizedStatName($0.name)) }.map(\.id))
        guard !matchingIDs.isEmpty else { return 0 }
        return eventsForComparison(isOpposition: isOpposition)
            .filter { matchingIDs.contains($0.statTypeId) }
            .count
    }

    private var timerBadge: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(formattedQuarterTime)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(remainingQuarterSeconds <= 0 ? .red : .primary)
            Text(quarterCountsUp ? "Count up" : "Count down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(timerBackgroundColor.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            if isQuarterTimerRunning {
                stopQuarterTimer()
            } else {
                startQuarterTimer()
            }
        }
        .onLongPressGesture {
            showTimerModeEditor = true
        }
        .popover(isPresented: $showTimerModeEditor, attachmentAnchor: .point(.bottomLeading), arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Timer settings")
                    .font(.headline)
                Stepper("Minutes: \(customQuarterMinutes)", value: $customQuarterMinutes, in: 1...60, step: 1)
                Toggle("Count up instead", isOn: $quarterCountsUp)
                Button("Restart timer") {
                    stopQuarterTimer()
                    remainingQuarterSeconds = quarterCountsUp ? 0 : customQuarterMinutes * 60
                }
                .buttonStyle(.bordered)
                Button("Reset counter") {
                    configureQuarterTimer(reset: true)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(width: 260)
        }
    }

    private var quarterBadge: some View {
        Text(selectedQuarter)
            .font(.title2.weight(.black))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onLongPressGesture {
                showQuarterChangeReminder = true
            }
    }

    private var playerNumberRingColors: (stroke: Color, text: Color) {
        let team = ClubConfigurationStore.load().clubTeam
        return (
            stroke: Color(hex: team.secondaryColorHex!, fallback: ourStyle.text),
            text: Color(hex: team.primaryColorHex, fallback: ourStyle.background)
        )
    }

    private func playerCardContent(player: Player) -> some View {
        let ringColors = playerNumberRingColors
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(ringColors.stroke)
                    .frame(width: 38, height: 38)
                Circle()
                    .strokeBorder(ringColors.stroke, lineWidth: 2)
                    .frame(width: 38, height: 38)
                Text(player.number.map { String($0) } ?? "—")
                    .font(.headline.weight(.black))
                    .foregroundStyle(ringColors.text)
            }
            Text(player.lastName.uppercased())
                .font(.headline.weight(.semibold))
                .lineLimit(1)
            Text(player.firstName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var gridPlayers: [Player] {
        displayedPlayers
    }

    private var playerSelectionPanel: some View {
        GeometryReader { panelProxy in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Button {
                        showPlayerVisibilityEditor = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }

                let columnsCount = max(Int(panelProxy.size.width / 128), 3)
                let maxRows = 4
                let maxVisibleCards = columnsCount * maxRows
                let hasOverflow = !showAllPlayers && gridPlayers.count > maxVisibleCards
                let visiblePlayers = hasOverflow ? Array(gridPlayers.prefix(max(maxVisibleCards - 1, 0))) : gridPlayers
                let rowsCount = showAllPlayers
                    ? max(Int(ceil(Double(max(gridPlayers.count, 1)) / Double(columnsCount))), 1)
                    : maxRows
                let topFixedHeight = 40.0
                let usableGridHeight = max(panelProxy.size.height - topFixedHeight, 180)
                let cellHeight = max(72, min(132, (usableGridHeight - (CGFloat(rowsCount - 1) * 8)) / CGFloat(rowsCount)))
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: columnsCount)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(visiblePlayers) { player in
                        playerCardContent(player: player)
                            .frame(maxWidth: .infinity, minHeight: cellHeight)
                            .background(activePlayerQuickStatsPlayerID == player.id ? Color.blue : Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                        .background {
                            GeometryReader { cardProxy in
                                Color.clear
                                    .task(id: cardProxy.frame(in: .global)) {
                                        let frame = cardProxy.frame(in: .global)
                                        playerCardFramesGlobal[player.id] = frame

                                        if activePlayerQuickStatsPlayerID == player.id {
                                            activePlayerQuickCardFrameGlobal = frame
                                        }
                                    }
                            }
                        }
                        .highPriorityGesture(
                            LongPressGesture(minimumDuration: playerQuickStatsLongPressDuration)
                                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                                .onChanged { value in
                                    switch value {
                                    case .first(true):
                                        selectedPlayerId = player.id
                                        activePlayerQuickStatsPlayerID = player.id
                                        activePlayerQuickCardFrameGlobal = playerCardFramesGlobal[player.id] ?? .zero
                                        clearPendingPlayerQuickStat()
                                    case .second(true, let drag?):
                                        if activePlayerQuickStatsPlayerID != player.id {
                                            activePlayerQuickStatsPlayerID = player.id
                                            activePlayerQuickCardFrameGlobal = .zero
                                            clearPendingPlayerQuickStat()
                                        }
                                        activePlayerQuickStatsPlayerID = player.id
                                        let cardSize = activePlayerQuickCardFrameGlobal.size == .zero
                                            ? CGSize(width: panelProxy.size.width / CGFloat(columnsCount), height: cellHeight)
                                            : activePlayerQuickCardFrameGlobal.size
                                        updateQuickStatHover(location: drag.location, cardSize: cardSize)
                                    default:
                                        break
                                    }
                                }
                                .onEnded { _ in
                                    guard activePlayerQuickStatsPlayerID == player.id else {
                                        clearPendingPlayerQuickStat()
                                        activePlayerQuickStatsPlayerID = nil
                                        activePlayerQuickCardFrameGlobal = .zero
                                        return
                                    }
                                    commitPendingPlayerQuickStatIfValid(playerID: player.id)
                                    clearPendingPlayerQuickStat()
                                    activePlayerQuickStatsPlayerID = nil
                                    activePlayerQuickCardFrameGlobal = .zero
                                }
                        )
                        .onTapGesture {
                            // Intentionally no-op: quick stats should only respond to long press.
                        }
                    }

                    if hasOverflow {
                        Button {
                            showAllPlayers = true
                        } label: {
                            VStack {
                                Text("…")
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: cellHeight)
                            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .overlay {
                    GeometryReader { overlayProxy in
                        if activePlayerQuickStatsPlayerID != nil, activePlayerQuickCardFrameGlobal != .zero {
                            let overlayFrame = overlayProxy.frame(in: .global)
                            let cardFrame = activePlayerQuickCardFrameGlobal
                            playerQuickStatsFan(cardSize: cardFrame.size, globalMidX: cardFrame.midX)
                                .frame(width: cardFrame.width, height: cardFrame.height)
                                .position(
                                    x: cardFrame.midX - overlayFrame.minX,
                                    y: cardFrame.midY - overlayFrame.minY
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                                .zIndex(6000)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .zIndex(6000)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func edgeLayoutContent(proxy: GeometryProxy) -> some View {
        let sideWidth = min(max(proxy.size.width * 0.16, 128), 180)
        let centerWidth = max(proxy.size.width - (sideWidth * 2) - 48, 320)
        let splitIndex = Int(ceil(Double(gridPlayers.count) / 2.0))
        let leftPlayers = Array(gridPlayers.prefix(splitIndex).prefix(12))
        let rightPlayers = Array(gridPlayers.dropFirst(splitIndex).prefix(12))
        let recentAreaHeight = max(280, min(proxy.size.height * 0.33, 360))

        return VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 10) {
                    edgePlayerColumn(players: leftPlayers, isTrailingSide: false)
                }
                .frame(width: sideWidth)

                VStack(spacing: 8) {
                    headerBannerArea
                        .frame(height: 76)
                        .frame(maxWidth: centerWidth)

                    VStack(spacing: 8) {
                        combinedScoreAndActionsPanel
                            .frame(maxHeight: 472, alignment: .top)

                        if !oppositionTrackPossessions {
                            statButtonsPanel
                                .frame(height: rightStatActionsHeight)
                        }

                        Spacer(minLength: 6)

                        recentEventsPanel
                            .frame(height: recentAreaHeight)
                    }
                    .padding(.top, 40)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(width: centerWidth)
                .frame(maxHeight: .infinity, alignment: .top)

                VStack(spacing: 10) {
                    edgePlayerColumn(players: rightPlayers, isTrailingSide: true)
                }
                .frame(width: sideWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var sideSpeakButtonSize: CGFloat { 138 }

    private func edgePlayerColumn(players: [Player], isTrailingSide: Bool) -> some View {
        GeometryReader { panelProxy in
            let topControlsHeight = sideSpeakButtonSize + 56
            let listVerticalSpacing: CGFloat = 8
            let availableHeight = max(0, panelProxy.size.height - topControlsHeight)
            let estimatedHeight = (availableHeight - (listVerticalSpacing * 11)) / 12
            let cardHeight = max(58, min(82, estimatedHeight))

            VStack(spacing: 10) {
                HStack {
                    if isTrailingSide {
                        Button {
                            showPlayerVisibilityEditor = true
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        speakButton(isOpposition: true)
                    } else {
                        speakButton(isOpposition: false)
                        Spacer()
                        Button {
                            showPlayerVisibilityEditor = true
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)

                edgePlayerColumnList(
                    players: players,
                    panelProxy: panelProxy,
                    cardHeight: cardHeight,
                    spacing: listVerticalSpacing
                )
                .frame(maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .top) {
                    if players.count < 12 {
                        VStack(spacing: listVerticalSpacing) {
                            ForEach(0..<(12 - players.count), id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.black.opacity(0.04))
                                    .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }
                .overlay {
                    GeometryReader { overlayProxy in
                        if activePlayerQuickStatsPlayerID != nil, activePlayerQuickCardFrameGlobal != .zero {
                            let overlayFrame = overlayProxy.frame(in: .global)
                            let cardFrame = activePlayerQuickCardFrameGlobal
                            playerQuickStatsFan(cardSize: cardFrame.size, globalMidX: cardFrame.midX)
                                .frame(width: cardFrame.width, height: cardFrame.height)
                                .position(
                                    x: cardFrame.midX - overlayFrame.minX,
                                    y: cardFrame.midY - overlayFrame.minY
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                                .zIndex(6000)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .zIndex(6000)
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func edgePlayerColumnList(
        players: [Player],
        panelProxy: GeometryProxy,
        cardHeight: CGFloat,
        spacing: CGFloat
    ) -> some View {
        return VStack(spacing: spacing) {
            ForEach(Array(players.enumerated()), id: \.element.id) { _, player in
                edgePlayerCard(player: player, panelProxy: panelProxy, minHeight: cardHeight)
            }
        }
    }

    private func edgePlayerCard(player: Player, panelProxy: GeometryProxy, minHeight: CGFloat) -> some View {
        playerCardContent(player: player)
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight)
            .background(
                activePlayerQuickStatsPlayerID == player.id ? Color.blue : Color.black.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 10)
            )
        .background {
            GeometryReader { cardProxy in
                Color.clear
                    .task(id: cardProxy.frame(in: .global)) {
                        let frame = cardProxy.frame(in: .global)
                        playerCardFramesGlobal[player.id] = frame

                        if activePlayerQuickStatsPlayerID == player.id {
                            activePlayerQuickCardFrameGlobal = frame
                        }
                    }
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: playerQuickStatsLongPressDuration)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                .onChanged { value in
                    switch value {
                    case .first(true):
                        selectedPlayerId = player.id
                        activePlayerQuickStatsPlayerID = player.id
                        activePlayerQuickCardFrameGlobal = playerCardFramesGlobal[player.id] ?? .zero
                        clearPendingPlayerQuickStat()
                        triggerStrongHaptic()
                    case .second(true, let drag?):
                        if activePlayerQuickStatsPlayerID != player.id {
                            activePlayerQuickStatsPlayerID = player.id
                            activePlayerQuickCardFrameGlobal = .zero
                            clearPendingPlayerQuickStat()
                            triggerStrongHaptic()
                        }
                        activePlayerQuickStatsPlayerID = player.id
                        let fallbackWidth = max(panelProxy.size.width - 8, 120)
                        let cardSize = activePlayerQuickCardFrameGlobal.size == .zero
                            ? CGSize(width: fallbackWidth, height: 82)
                            : activePlayerQuickCardFrameGlobal.size
                        updateQuickStatHover(location: drag.location, cardSize: cardSize)
                    default:
                        break
                    }
                }
                .onEnded { _ in
                    guard activePlayerQuickStatsPlayerID == player.id else {
                        clearPendingPlayerQuickStat()
                        activePlayerQuickStatsPlayerID = nil
                        activePlayerQuickCardFrameGlobal = .zero
                        return
                    }
                    commitPendingPlayerQuickStatIfValid(playerID: player.id)
                    clearPendingPlayerQuickStat()
                    activePlayerQuickStatsPlayerID = nil
                    activePlayerQuickCardFrameGlobal = .zero
                }
        )
        .onTapGesture {
            // Intentionally no-op: quick stats should only respond to long press.
        }
    }

    private var statButtonsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Stat Actions")
                    .font(.title3.bold())

                if selectedPlayerId == nil {
                    Text("Select a player first")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(playerStatTypes) { type in
                    Button {
                        addManualEvent(statTypeId: type.id)
                    } label: {
                        Text(type.name)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(selectedPlayerId == nil ? Color.accentColor : Color.white)
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .background(
                                selectedPlayerId == nil ? Color.accentColor.opacity(0.16) : Color.blue,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedPlayerId == nil)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func teamStatButton(
        _ title: String,
        name: String,
        style: ClubStyle.Style,
        isOpposition: Bool,
        fallbackName: String? = nil
    ) -> AnyView {
        let statType = statType(
            named: name,
            fallbackName: fallbackName,
            extraFallbackNames: ["Scores"]
        )
        let normalizedName = normalizedStatName(name)
        let scoreKind: String? = (normalizedName == "goal" || normalizedName == "behind") ? normalizedName : nil
        let isOptionalUsStat = normalizedName == "clearance"
            || normalizedName == "clearances"
            || normalizedName == "inside 50"
            || normalizedName == "inside 50s"
        let buttonKey = "\(normalizedName)-\(isOpposition ? "opp" : "our")"
        let supportsEfficiencyLongPress = supportsEfficiencyLongPress(for: normalizedName, isOpposition: isOpposition)
        let showEfficiencyVote = trackDisposalEfficiency && statRequiresEfficiencyVote(normalizedName)
        let showContestedVote = trackContestedPossessions && statSupportsContestedVote(normalizedName)
        let baseButton = Button {
            if suppressTapForButtonKey == buttonKey {
                suppressTapForButtonKey = nil
                return
            }
            guard let statType else { return }
            handleTeamStatAction(
                statTypeId: statType.id,
                isOpposition: isOpposition,
                scoreKind: scoreKind,
                isOptionalUsStat: isOptionalUsStat,
                efficiencyVote: nil
            )
        } label: {
            Text(title)
                .font(.title3.weight(.black))
                .foregroundStyle(style.text)
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(style.background.opacity(statType == nil ? 0.35 : 1))
                )
        }
        .overlay(alignment: .top) {
            GeometryReader { proxy in
                if activeEfficiencyButtonKey == buttonKey {
                    let popupShift = popupHorizontalShift(for: proxy.frame(in: .global).midX)
                    if showEfficiencyVote && showContestedVote {
                        ZStack {
                            contestedSlidePopup
                                .offset(y: 46)
                            efficiencySlidePopup
                                .offset(x: efficiencyPopupHorizontalOffset, y: -46)
                        }
                        .offset(x: popupShift, y: -132)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    } else {
                        VStack(spacing: 8) {
                            if showEfficiencyVote {
                                efficiencySlidePopup
                            }
                            if showContestedVote {
                                contestedSlidePopup
                            }
                        }
                        .offset(x: popupShift, y: -88)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .buttonStyle(.plain)
        .disabled(statType == nil)
        .zIndex(activeEfficiencyButtonKey == buttonKey ? 2000 : 0)

        if supportsEfficiencyLongPress {
            return AnyView(baseButton.highPriorityGesture(
                LongPressGesture(minimumDuration: 0.28)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onChanged { value in
                        switch value {
                        case .first(true):
                            activeEfficiencyButtonKey = buttonKey
                            activeEfficiencyHoverVote = nil
                            activeContestedHoverVote = nil
                            triggerStrongHaptic()
                        case .second(true, let drag?):
                            let previousEfficiencyVote = activeEfficiencyHoverVote
                            let previousContestedVote = activeContestedHoverVote
                            if showEfficiencyVote && showContestedVote {
                                if drag.location.y < -76 {
                                    activeEfficiencyHoverVote = drag.location.x < 110 ? .thumbsUp : .thumbsDown
                                } else {
                                    activeContestedHoverVote = drag.location.x < 110 ? .contested : .uncontested
                                }
                            } else if showEfficiencyVote {
                                activeEfficiencyHoverVote = drag.location.x < 110 ? .thumbsUp : .thumbsDown
                            } else if showContestedVote {
                                activeContestedHoverVote = drag.location.x < 110 ? .contested : .uncontested
                            }
                            if previousEfficiencyVote != activeEfficiencyHoverVote || previousContestedVote != activeContestedHoverVote {
                                triggerSelectionStepHaptic()
                            }
                        default:
                            break
                        }
                    }
                    .onEnded { value in
                        guard let statType else {
                            activeEfficiencyButtonKey = nil
                            activeEfficiencyHoverVote = nil
                            activeContestedHoverVote = nil
                            return
                        }
                        var didCommit = false
                        switch value {
                        case .second(true, _):
                            let vote = activeEfficiencyHoverVote
                            let contestedVote = activeContestedHoverVote
                            let hasRequiredEfficiency = !showEfficiencyVote || vote != nil
                            let hasRequiredContested = !showContestedVote || contestedVote != nil
                            if hasRequiredEfficiency && hasRequiredContested {
                                suppressTapForButtonKey = buttonKey
                                handleTeamStatAction(
                                    statTypeId: statType.id,
                                    isOpposition: isOpposition,
                                    scoreKind: scoreKind,
                                    isOptionalUsStat: isOptionalUsStat,
                                    efficiencyVote: vote,
                                    contestedVote: contestedVote
                                )
                                didCommit = true
                            }
                        default:
                            break
                        }
                        if !didCommit {
                            suppressTapForButtonKey = nil
                        }
                        activeEfficiencyButtonKey = nil
                        activeEfficiencyHoverVote = nil
                        activeContestedHoverVote = nil
                    }
            ))
        } else {
            return AnyView(baseButton)
        }
    }

    private var efficiencySlidePopup: some View {
        HStack(spacing: 8) {
            efficiencySlideOption(title: "Effective", vote: .thumbsUp, tint: .green)
            efficiencySlideOption(title: "Non effective", vote: .thumbsDown, tint: .red)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 3)
    }

    private func efficiencySlideOption(title: String, vote: EfficiencyVote, tint: Color) -> some View {
        let isSelected = activeEfficiencyHoverVote == vote
        return Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .frame(width: 102, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? tint : Color.gray.opacity(0.35))
            )
    }

    private var contestedSlidePopup: some View {
        HStack(spacing: 8) {
            contestedSlideOption(title: "Contested", vote: .contested, tint: .orange)
            contestedSlideOption(title: "Uncontested", vote: .uncontested, tint: .blue)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 3)
    }

    private var efficiencyPopupHorizontalOffset: CGFloat {
        switch activeContestedHoverVote {
        case .contested:
            return -55
        case .uncontested:
            return 55
        default:
            return 0
        }
    }

    private func popupHorizontalShift(for buttonMidX: CGFloat) -> CGFloat {
        let screenWidth = interfaceScreenWidth
        let edgePadding: CGFloat = 12
        let halfWidth: CGFloat = (trackDisposalEfficiency && trackContestedPossessions) ? 170 : 112
        let leftOverflow = max(0, (edgePadding + halfWidth) - buttonMidX)
        let rightOverflow = max(0, buttonMidX + halfWidth - (screenWidth - edgePadding))
        return leftOverflow - rightOverflow
    }

    private func contestedSlideOption(title: String, vote: ContestedPossessionVote, tint: Color) -> some View {
        let isSelected = activeContestedHoverVote == vote
        return Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .frame(width: 102, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? tint : Color.gray.opacity(0.35))
            )
    }

    private func supportsEfficiencyLongPress(for normalizedName: String, isOpposition: Bool) -> Bool {
        guard supportsLongPressVotes(for: normalizedName) else { return false }
        guard !isOpposition else { return false }
        return true
    }

    private func supportsLongPressVotes(for normalizedName: String) -> Bool {
        let supportsEfficiency = trackDisposalEfficiency && statRequiresEfficiencyVote(normalizedName)
        let supportsContested = trackContestedPossessions && statSupportsContestedVote(normalizedName)
        return supportsEfficiency || supportsContested
    }

    private func statRequiresEfficiencyVote(_ normalizedName: String) -> Bool {
        normalizedName == "kick" || normalizedName == "handball"
    }

    private func statSupportsContestedVote(_ normalizedName: String) -> Bool {
        normalizedName == "kick" || normalizedName == "handball" || normalizedName == "mark"
    }

    private func handleTeamStatAction(
        statTypeId: UUID,
        isOpposition: Bool,
        scoreKind: String?,
        isOptionalUsStat: Bool,
        efficiencyVote: EfficiencyVote?,
        contestedVote: ContestedPossessionVote? = nil
    ) {
        let requiresSelectedPlayer = !isOpposition && trackIndividualTracking && !isOptionalUsStat
        if isOpposition {
            addTeamEvent(
                statTypeId: statTypeId,
                isOpposition: true,
                scoreKind: scoreKind,
                efficiencyVote: efficiencyVote,
                contestedVote: contestedVote
            )
            return
        }

        if !trackIndividualTracking {
            addTeamEvent(statTypeId: statTypeId, isOpposition: false, scoreKind: scoreKind, efficiencyVote: efficiencyVote, contestedVote: contestedVote)
        } else if isOptionalUsStat {
            if selectedPlayerId == nil {
                addTeamEvent(statTypeId: statTypeId, isOpposition: false, scoreKind: scoreKind, efficiencyVote: efficiencyVote, contestedVote: contestedVote)
            } else {
                addManualEvent(statTypeId: statTypeId, transcript: scoreKind, efficiencyVote: efficiencyVote, contestedVote: contestedVote)
            }
        } else if requiresSelectedPlayer {
            addManualEvent(statTypeId: statTypeId, transcript: scoreKind, efficiencyVote: efficiencyVote, contestedVote: contestedVote)
        } else {
            addTeamEvent(statTypeId: statTypeId, isOpposition: false, scoreKind: scoreKind, efficiencyVote: efficiencyVote, contestedVote: contestedVote)
        }
    }

    private func efficiencyEmojiForRecentEvent(_ event: StatEvent) -> String? {
        guard let vote = event.efficiencyVoteRaw else { return nil }
        return vote == EfficiencyVote.thumbsUp.rawValue ? "👍" : "👎"
    }

    private var recentEventsPanel: some View {
        let recent = Array(sessionEvents.prefix(6))
        return VStack(alignment: .leading, spacing: 8) {
            LazyVStack(spacing: 6) {
                ForEach(recent) { event in
                    Button {
                        showEditEvent = event
                    } label: {
                        HStack(spacing: 6) {
                            Spacer(minLength: 0)
                            Text(playerNameForRecentEvent(for: event.playerId))
                                .font(.title.weight(.medium))
                                .lineLimit(1)
                            Text("-")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text(recentEventStatLabel(event))
                                .font(.title.weight(.black))
                                .lineLimit(1)
                            if let efficiencyEmoji = efficiencyEmojiForRecentEvent(event) {
                                Text(efficiencyEmoji)
                                    .font(.title)
                                    .lineLimit(1)
                            }
                            Text("-")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.title)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .transition(
                        .asymmetric(
                            insertion: .modifier(
                                active: RollingInModifier(rotation: -18, xOffset: 56, yOffset: -10, opacity: 0),
                                identity: RollingInModifier(rotation: 0, xOffset: 0, yOffset: 0, opacity: 1)
                            ),
                            removal: .opacity
                        )
                    )
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: recent.map(\.id))

            if sessionEvents.isEmpty {
                Text("No events yet")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 300, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private struct RollingInModifier: ViewModifier {
        let rotation: Double
        let xOffset: CGFloat
        let yOffset: CGFloat
        let opacity: Double

        func body(content: Content) -> some View {
            content
                .rotationEffect(.degrees(rotation))
                .offset(x: xOffset, y: yOffset)
                .opacity(opacity)
        }
    }

    private func speakButton(isOpposition: Bool) -> some View {
        Button {
            // press-and-hold driven
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill((isOpposition ? oppositionStyle.background : ourStyle.background).opacity(speechService.isRecording ? 0.72 : 0.94))
                    .frame(width: sideSpeakButtonSize, height: sideSpeakButtonSize)
                Text("Speak")
                    .font(.title2.bold())
                    .foregroundStyle(isOpposition ? oppositionStyle.text : ourStyle.text)
            }
        }
        .onLongPressGesture(minimumDuration: 0.01, maximumDistance: .infinity, pressing: { isPressing in
            if isPressing {
                activeSideSpeakPresses += 1
                triggerStrongHaptic()
                speechService.startListening(vocabulary: speechVocabulary)
            } else if speechService.isRecording {
                activeSideSpeakPresses = max(0, activeSideSpeakPresses - 1)
                speechService.stopListening { transcript in
                    if isOpposition {
                        handleTeamVoiceTranscript(transcript, isOpposition: true)
                    } else {
                        handleVoiceTranscript(transcript)
                    }
                }
            } else {
                activeSideSpeakPresses = max(0, activeSideSpeakPresses - 1)
            }
        }, perform: {})
        .buttonStyle(.plain)
    }

    private var shouldShowSideSpeakMicOverlay: Bool {
        activeSideSpeakPresses > 0
    }

    private var sideSpeakMicOverlay: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 150, weight: .black))
            .foregroundStyle(.red)
            .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .animation(.easeInOut(duration: 0.12), value: shouldShowSideSpeakMicOverlay)
    }

    private func addRushedBehindForOurTeam() {
        guard let behindType = statType(named: "Behind", fallbackName: "Scores", extraFallbackNames: ["Goal"]) else {
            showStatusBanner(text: "ERROR • Behind stat unavailable", isSuccess: false)
            return
        }
        addTeamEvent(
            statTypeId: behindType.id,
            isOpposition: false,
            scoreKind: "rushed behind"
        )
    }

    private var gradeName: String {
        grades.first(where: { $0.id == session.gradeId })?.name ?? "Unknown Grade"
    }

    private func recentEventStatLabel(_ event: StatEvent) -> String {
        let base = statName(for: event.statTypeId)
        guard normalizedStatName(base) == "scores" else { return base }
        let normalizedTranscript = normalizedStatName(event.transcript ?? "")
        if normalizedTranscript == "goal" { return "Goal" }
        if normalizedTranscript == "behind" || normalizedTranscript == "rushed behind" { return "Behind" }
        return base
    }

    private var speechVocabulary: [String] {
        let statPhrases = enabledStatTypes.flatMap { $0.voiceAliases }
        let votePhrases = SpeechVoteSection.all.flatMap { section in
            section.defaultAliases + SpeechDetectedWordsStore.words(forSectionKey: section.key)
        }
        let rosterPhrases = playersForGrade.flatMap { player -> [String] in
            var values = [player.name, player.firstName, player.lastName]
            if let number = player.number {
                values.append("number \(number)")
                values.append("no \(number)")
                values.append(String(number))
            }
            return values
        }
        return Array(Set(statPhrases + votePhrases + rosterPhrases)).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var totalsRows: [TotalsRow] {
        displayedPlayers.map { player in
            let events = sessionEvents.filter { $0.playerId == player.id }
            var counts: [UUID: Int] = [:]
            for event in events {
                counts[event.statTypeId, default: 0] += 1
            }
            return TotalsRow(player: player, countsByStatId: counts)
        }
    }

    private var playerStatTypes: [StatType] {
        let teamOnly = Set(["goal", "behind", "clearance", "clearances", "inside 50", "inside 50s"])
        return enabledStatTypes.filter { !teamOnly.contains($0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
    }

    private func statType(named name: String, fallbackName: String? = nil, extraFallbackNames: [String] = []) -> StatType? {
        let target = normalizedStatName(name)
        if let primary = enabledStatTypes.first(where: { normalizedStatName($0.name) == target }) {
            return primary
        }
        let fallbacks = ([fallbackName].compactMap { $0 } + extraFallbackNames).map(normalizedStatName)
        for fallback in fallbacks {
            if let stat = enabledStatTypes.first(where: { normalizedStatName($0.name) == fallback }) {
                return stat
            }
        }
        return nil
    }

    private func normalizedStatName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func playerDisplay(_ player: Player) -> String {
        if let number = player.number {
            return "\(number) \(player.name)"
        }
        return player.name
    }

    private func playerLabel(for id: UUID) -> String {
        guard let player = allPlayers.first(where: { $0.id == id }) else { return "Unknown" }
        return playerDisplay(player)
    }

    private func playerNameForRecentEvent(for id: UUID) -> String {
        if id == ourTeamStatPlayerID {
            return ourTeamName
        }
        if id == oppositionTeamStatPlayerID {
            return session.opposition
        }
        guard let player = allPlayers.first(where: { $0.id == id }) else { return "Unknown" }
        return player.name
    }

    private func playerShortLabel(for id: UUID) -> String {
        if id == ourTeamStatPlayerID {
            return ourTeamName
        }
        if id == oppositionTeamStatPlayerID {
            return session.opposition
        }
        guard let player = allPlayers.first(where: { $0.id == id }) else { return "Unknown" }
        if let number = player.number {
            return "\(number) \(player.lastName)"
        }
        return player.lastName
    }

    private struct PlayerQuickStatOption: Identifiable {
        let id: String
        let title: String
        let transcript: String?
        let statType: StatType?
    }

    private var playerQuickStatOptions: [PlayerQuickStatOption] {
        [
            PlayerQuickStatOption(
                id: "kick",
                title: "Kick",
                transcript: nil,
                statType: statType(named: "Kick")
            ),
            PlayerQuickStatOption(
                id: "handball",
                title: "Handball",
                transcript: nil,
                statType: statType(named: "Handball")
            ),
            PlayerQuickStatOption(
                id: "mark",
                title: "Mark",
                transcript: nil,
                statType: statType(named: "Mark")
            ),
            PlayerQuickStatOption(
                id: "tackle",
                title: "Tackle",
                transcript: nil,
                statType: statType(named: "Tackle")
            ),
            PlayerQuickStatOption(
                id: "goal",
                title: "Goal",
                transcript: "goal",
                statType: statType(named: "Goal", fallbackName: "Scores", extraFallbackNames: ["Behind"])
            ),
            PlayerQuickStatOption(
                id: "behind",
                title: "Point",
                transcript: "behind",
                statType: statType(named: "Behind", fallbackName: "Scores", extraFallbackNames: ["Goal"])
            )
        ]
    }

    private func playerQuickStatsFan(cardSize: CGSize, globalMidX: CGFloat) -> some View {
        let layout = quickStatPieLayout(cardSize: cardSize, globalMidX: globalMidX)
        let selectedFirstTierAngle = selectedQuickStatMidAngle(layout: layout)
        let contestedLayout = votePopupPieLayout(primaryLayout: layout, selectedAngle: selectedFirstTierAngle, tier: 1)
        let selectedSecondTierAngle = selectedVoteMidAngle(
            layout: contestedLayout,
            leftSelected: hoveredPlayerQuickContestedVote == .contested,
            rightSelected: hoveredPlayerQuickContestedVote == .uncontested
        )
        let efficiencyLayout = votePopupPieLayout(primaryLayout: layout, selectedAngle: selectedSecondTierAngle, tier: 2)
        return ZStack {
            ForEach(Array(playerQuickStatOptions.enumerated()), id: \.element.id) { index, option in
                let isHovered = hoveredPlayerQuickStatName == option.id
                let segment = quickStatSegmentAngles(index: index, total: playerQuickStatOptions.count, spanStart: layout.startAngle, spanEnd: layout.endAngle)
                let midAngle = (segment.start + segment.end) / 2
                let labelRadius = (layout.innerRadius + layout.outerRadius) / 2
                let labelWidth = quickStatLabelWidth(radius: labelRadius, startAngle: segment.start, endAngle: segment.end, minimum: 88, maximum: 126)

                QuickStatPieSlice(startAngle: segment.start, endAngle: segment.end, innerRadius: layout.innerRadius, outerRadius: layout.outerRadius)
                    .fill(isHovered ? Color.blue : (option.statType == nil ? Color.gray.opacity(0.32) : Color.gray.opacity(0.56)))
                    .overlay {
                        QuickStatPieSlice(startAngle: segment.start, endAngle: segment.end, innerRadius: layout.innerRadius, outerRadius: layout.outerRadius)
                            .stroke(Color.white.opacity(isHovered ? 0.8 : 0.45), lineWidth: isHovered ? 2.5 : 1.2)
                    }
                    .overlay {
                        sliceLabel(
                            option.title,
                            center: layout.center,
                            radius: labelRadius,
                            angle: midAngle,
                            width: labelWidth,
                            font: .headline.weight(.semibold)
                        )
                    }
            }

            if shouldShowContestedPopup {
                votePiePopup(
                    leftTitle: "Contested",
                    leftActive: hoveredPlayerQuickContestedVote == .contested,
                    rightTitle: "Uncontested",
                    rightActive: hoveredPlayerQuickContestedVote == .uncontested,
                    layout: contestedLayout
                )
            }

            if shouldShowEfficiencyPopup {
                votePiePopup(
                    leftTitle: "Effective",
                    leftActive: hoveredPlayerQuickEfficiencyVote == .thumbsUp,
                    rightTitle: "Non Effective",
                    rightActive: hoveredPlayerQuickEfficiencyVote == .thumbsDown,
                    layout: efficiencyLayout
                )
            }
        }
    }

    private func votePiePopup(
        leftTitle: String,
        leftActive: Bool,
        rightTitle: String,
        rightActive: Bool,
        layout: (center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, startAngle: CGFloat, endAngle: CGFloat)
    ) -> some View {
        return ZStack {
            ForEach(0..<2, id: \.self) { idx in
                let segment = quickStatSegmentAngles(index: idx, total: 2, spanStart: layout.startAngle, spanEnd: layout.endAngle)
                let isActive = idx == 0 ? leftActive : rightActive
                let title = idx == 0 ? leftTitle : rightTitle
                let midAngle = (segment.start + segment.end) / 2
                let labelRadius = (layout.innerRadius + layout.outerRadius) / 2
                let labelWidth = quickStatLabelWidth(radius: labelRadius, startAngle: segment.start, endAngle: segment.end, minimum: 88, maximum: 112)
                QuickStatPieSlice(startAngle: segment.start, endAngle: segment.end, innerRadius: layout.innerRadius, outerRadius: layout.outerRadius)
                    .fill(isActive ? Color.blue : Color.gray.opacity(0.56))
                    .overlay {
                        QuickStatPieSlice(startAngle: segment.start, endAngle: segment.end, innerRadius: layout.innerRadius, outerRadius: layout.outerRadius)
                            .stroke(Color.white.opacity(isActive ? 0.8 : 0.45), lineWidth: isActive ? 2.3 : 1.1)
                    }
                    .overlay {
                        sliceLabel(
                            title,
                            center: layout.center,
                            radius: labelRadius,
                            angle: midAngle,
                            width: labelWidth,
                            font: .subheadline.weight(.bold)
                        )
                    }
            }
        }
    }

    private var shouldShowContestedPopup: Bool {
        guard let statID = hoveredPlayerQuickStatName else { return false }
        let contestedEnabled = activePlayerQuickStatsPlayerID == oppositionTeamStatPlayerID
            ? oppositionTrackContestedPossessions
            : trackContestedPossessions
        return needsQuickStatContestedVote(for: statID, trackingEnabled: nil) && contestedEnabled
    }

    private var shouldShowEfficiencyPopup: Bool {
        guard let statID = hoveredPlayerQuickStatName else { return false }
        let efficiencyEnabled = activePlayerQuickStatsPlayerID == oppositionTeamStatPlayerID
            ? oppositionTrackDisposalEfficiency
            : trackDisposalEfficiency
        let contestedEnabled = activePlayerQuickStatsPlayerID == oppositionTeamStatPlayerID
            ? oppositionTrackContestedPossessions
            : trackContestedPossessions
        guard needsQuickStatEfficiencyVote(for: statID, trackingEnabled: nil), efficiencyEnabled else { return false }
        if contestedEnabled {
            return hoveredPlayerQuickContestedVote != nil
        }
        return true
    }

    private func quickStatPieLayout(cardSize: CGSize, globalMidX: CGFloat) -> (center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, startAngle: CGFloat, endAngle: CGFloat) {
        let innerRadius: CGFloat = 82
        let outerRadius: CGFloat = 182

        // Anchor the pie to the pressed player button center.
        let center = CGPoint(x: cardSize.width / 2, y: cardSize.height / 2)
        if globalMidX < 210 {
            return (center, innerRadius, outerRadius, -95, 95)
        }
        if globalMidX > interfaceScreenWidth - 210 {
            return (center, innerRadius, outerRadius, 85, 275)
        }
        return (center, innerRadius, outerRadius, -180, 0)
    }

    private func quickStatLabelWidth(radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        let spanRadians = abs(endAngle - startAngle) * (.pi / 180)
        let arcLength = radius * spanRadians
        return min(maximum, max(minimum, arcLength * 0.72))
    }

    private func quickStatSegmentAngles(index: Int, total: Int, spanStart: CGFloat, spanEnd: CGFloat) -> (start: CGFloat, end: CGFloat) {
        let span = (spanEnd - spanStart) / CGFloat(max(total, 1))
        let start = spanStart + (span * CGFloat(index))
        return (start, start + span)
    }

    private func votePopupPieLayout(
        primaryLayout: (center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, startAngle: CGFloat, endAngle: CGFloat),
        selectedAngle: CGFloat,
        tier: Int
    ) -> (center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, startAngle: CGFloat, endAngle: CGFloat) {
        let ringThickness: CGFloat = 78
        let ringSpacing: CGFloat = 2
        let inner = primaryLayout.outerRadius + ringSpacing + (CGFloat(max(tier - 1, 0)) * (ringThickness + ringSpacing))
        let outer = inner + ringThickness
        let halfSpan: CGFloat = 34
        return (center: primaryLayout.center, innerRadius: inner, outerRadius: outer, startAngle: selectedAngle - halfSpan, endAngle: selectedAngle + halfSpan)
    }

    private func polarPoint(center: CGPoint, radius: CGFloat, angleDegrees: CGFloat) -> CGPoint {
        let radians = angleDegrees * (.pi / 180)
        return CGPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
    }

    private func sliceLabel(
        _ text: String,
        center: CGPoint,
        radius: CGFloat,
        angle: CGFloat,
        width: CGFloat,
        font: Font
    ) -> some View {
        let point = polarPoint(center: center, radius: radius, angleDegrees: angle)
        return Text(text)
            .font(font)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .allowsTightening(true)
            .lineLimit(2)
            .minimumScaleFactor(0.68)
            .frame(width: width)
            .rotationEffect(labelRotation(for: angle))
            .position(x: point.x, y: point.y)
    }

    private func labelRotation(for angle: CGFloat) -> Angle {
        let tangent = angle + 90
        let normalized = normalizedAngle(tangent)
        let upright = (normalized > 90 && normalized < 270) ? tangent + 180 : tangent
        return .degrees(upright)
    }

    private func sliceLockedLabel(
        _ text: String,
        center: CGPoint,
        radius: CGFloat,
        angle: CGFloat,
        width: CGFloat,
        font: Font,
        segment: (start: CGFloat, end: CGFloat),
        innerRadius: CGFloat,
        outerRadius: CGFloat
    ) -> some View {
        sliceLabel(text, center: center, radius: radius, angle: angle, width: width, font: font)
            .clipShape(
                QuickStatPieSlice(
                    startAngle: segment.start,
                    endAngle: segment.end,
                    innerRadius: innerRadius,
                    outerRadius: outerRadius
                )
            )
    }

    private func selectedQuickStatMidAngle(layout: (center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, startAngle: CGFloat, endAngle: CGFloat)) -> CGFloat {
        guard let idx = hoveredQuickStatIndex else { return (layout.startAngle + layout.endAngle) / 2 }
        let segment = quickStatSegmentAngles(index: idx, total: playerQuickStatOptions.count, spanStart: layout.startAngle, spanEnd: layout.endAngle)
        return (segment.start + segment.end) / 2
    }

    private func selectedVoteMidAngle(
        layout: (center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, startAngle: CGFloat, endAngle: CGFloat),
        leftSelected: Bool,
        rightSelected: Bool
    ) -> CGFloat {
        if leftSelected {
            let segment = quickStatSegmentAngles(index: 0, total: 2, spanStart: layout.startAngle, spanEnd: layout.endAngle)
            return (segment.start + segment.end) / 2
        }
        if rightSelected {
            let segment = quickStatSegmentAngles(index: 1, total: 2, spanStart: layout.startAngle, spanEnd: layout.endAngle)
            return (segment.start + segment.end) / 2
        }
        return (layout.startAngle + layout.endAngle) / 2
    }

    private func unitDirection(angleDegrees: CGFloat) -> CGVector {
        let radians = angleDegrees * (.pi / 180)
        return CGVector(dx: cos(radians), dy: sin(radians))
    }

    private func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        return normalized
    }

    private func angleIsWithinSpan(_ angle: CGFloat, start: CGFloat, end: CGFloat) -> Bool {
        let currentAngle = normalizedAngle(angle)
        let normalizedStart = normalizedAngle(start)
        let normalizedEnd = normalizedAngle(end)
        if normalizedStart <= normalizedEnd {
            return currentAngle >= normalizedStart && currentAngle <= normalizedEnd
        }
        return currentAngle >= normalizedStart || currentAngle <= normalizedEnd
    }

    private func hoveredQuickStatAnchor(layout: (center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, startAngle: CGFloat, endAngle: CGFloat)) -> CGPoint {
        guard let idx = hoveredQuickStatIndex else {
            return polarPoint(
                center: layout.center,
                radius: (layout.innerRadius + layout.outerRadius) / 2,
                angleDegrees: (layout.startAngle + layout.endAngle) / 2
            )
        }
        let segment = quickStatSegmentAngles(index: idx, total: playerQuickStatOptions.count, spanStart: layout.startAngle, spanEnd: layout.endAngle)
        return polarPoint(center: layout.center, radius: (layout.innerRadius + layout.outerRadius) / 2, angleDegrees: (segment.start + segment.end) / 2)
    }

    private var hoveredQuickStatIndex: Int? {
        guard let hoveredPlayerQuickStatName else { return nil }
        return playerQuickStatOptions.firstIndex(where: { $0.id == hoveredPlayerQuickStatName })
    }

    private func updateQuickStatHover(location: CGPoint, cardSize: CGSize) {
        let previousQuickStatName = hoveredPlayerQuickStatName
        let previousContestedVote = hoveredPlayerQuickContestedVote
        let previousEfficiencyVote = hoveredPlayerQuickEfficiencyVote
        let isOppositionQuick = activePlayerQuickStatsPlayerID == oppositionTeamStatPlayerID
        let contestedEnabled = isOppositionQuick ? oppositionTrackContestedPossessions : trackContestedPossessions
        let efficiencyEnabled = isOppositionQuick ? oppositionTrackDisposalEfficiency : trackDisposalEfficiency
        let globalMidX = activePlayerQuickCardFrameGlobal == .zero ? (interfaceScreenWidth / 2) : activePlayerQuickCardFrameGlobal.midX
        let layout = quickStatPieLayout(cardSize: cardSize, globalMidX: globalMidX)
        let distance = hypot(location.x - layout.center.x, location.y - layout.center.y)
        let angle = atan2(location.y - layout.center.y, location.x - layout.center.x) * 180 / .pi
        let inPieBand = distance >= layout.innerRadius && distance <= layout.outerRadius

        if inPieBand,
           let statIndex = (0..<playerQuickStatOptions.count).first(where: { idx in
               let segment = quickStatSegmentAngles(index: idx, total: playerQuickStatOptions.count, spanStart: layout.startAngle, spanEnd: layout.endAngle)
               return angleIsWithinSpan(angle, start: segment.start, end: segment.end)
           }) {
            hoveredPlayerQuickStatName = playerQuickStatOptions[statIndex].id
            hoveredPlayerQuickContestedVote = nil
            hoveredPlayerQuickEfficiencyVote = nil
            triggerQuickSelectionHapticIfNeeded(
                previousQuickStatName: previousQuickStatName,
                previousContestedVote: previousContestedVote,
                previousEfficiencyVote: previousEfficiencyVote
            )
            return
        }

        guard let statID = hoveredPlayerQuickStatName, needsQuickStatVotes(for: statID) else { return }
        let requiresContestedVote = needsQuickStatContestedVote(for: statID, trackingEnabled: contestedEnabled)
        let requiresEfficiencyVote = needsQuickStatEfficiencyVote(for: statID, trackingEnabled: efficiencyEnabled)

        let selectedFirstTierAngle = selectedQuickStatMidAngle(layout: layout)
        let contestedLayout = votePopupPieLayout(primaryLayout: layout, selectedAngle: selectedFirstTierAngle, tier: 1)
        if contestedEnabled && requiresContestedVote {
            let selection = votePopupSelectionIndex(location: location, layout: contestedLayout)
            if selection == 0 {
                hoveredPlayerQuickContestedVote = .contested
            } else if selection == 1 {
                hoveredPlayerQuickContestedVote = .uncontested
            }
        }

        if !requiresEfficiencyVote { return }
        if contestedEnabled && requiresContestedVote && hoveredPlayerQuickContestedVote == nil { return }

        let selectedSecondTierAngle = selectedVoteMidAngle(
            layout: contestedLayout,
            leftSelected: hoveredPlayerQuickContestedVote == .contested,
            rightSelected: hoveredPlayerQuickContestedVote == .uncontested
        )
        let efficiencyLayout = votePopupPieLayout(primaryLayout: layout, selectedAngle: selectedSecondTierAngle, tier: 2)
        let efficiencySelection = votePopupSelectionIndex(location: location, layout: efficiencyLayout)
        if efficiencySelection == 0 {
            hoveredPlayerQuickEfficiencyVote = .thumbsUp
        } else if efficiencySelection == 1 {
            hoveredPlayerQuickEfficiencyVote = .thumbsDown
        }
        triggerQuickSelectionHapticIfNeeded(
            previousQuickStatName: previousQuickStatName,
            previousContestedVote: previousContestedVote,
            previousEfficiencyVote: previousEfficiencyVote
        )
    }

    private func votePopupSelectionIndex(
        location: CGPoint,
        layout: (center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, startAngle: CGFloat, endAngle: CGFloat)
    ) -> Int? {
        let distance = hypot(location.x - layout.center.x, location.y - layout.center.y)
        guard distance >= layout.innerRadius && distance <= layout.outerRadius else { return nil }
        let angle = atan2(location.y - layout.center.y, location.x - layout.center.x) * 180 / .pi
        return (0..<2).first { idx in
            let segment = quickStatSegmentAngles(index: idx, total: 2, spanStart: layout.startAngle, spanEnd: layout.endAngle)
            return angleIsWithinSpan(angle, start: segment.start, end: segment.end)
        }
    }

    private func needsQuickStatVotes(for statID: String) -> Bool {
        needsQuickStatEfficiencyVote(for: statID, trackingEnabled: nil)
            || needsQuickStatContestedVote(for: statID, trackingEnabled: nil)
    }

    private func needsQuickStatEfficiencyVote(for statID: String, trackingEnabled: Bool?) -> Bool {
        let trackingEnabled = trackingEnabled ?? trackDisposalEfficiency
        return (statID == "kick" || statID == "handball") && trackingEnabled
    }

    private func needsQuickStatContestedVote(for statID: String, trackingEnabled: Bool?) -> Bool {
        let trackingEnabled = trackingEnabled ?? trackContestedPossessions
        return (statID == "kick" || statID == "mark" || statID == "handball") && trackingEnabled
    }

    private func commitPendingPlayerQuickStatIfValid(playerID: UUID) {
        guard
            let statID = hoveredPlayerQuickStatName,
            let option = playerQuickStatOptions.first(where: { $0.id == statID }),
            let statType = option.statType
        else {
            clearPendingPlayerQuickStat()
            return
        }

        let isOppositionQuick = playerID == oppositionTeamStatPlayerID
        let efficiencyEnabled = isOppositionQuick ? oppositionTrackDisposalEfficiency : trackDisposalEfficiency
        let contestedEnabled = isOppositionQuick ? oppositionTrackContestedPossessions : trackContestedPossessions
        let hasRequiredEfficiency = !needsQuickStatEfficiencyVote(for: statID, trackingEnabled: efficiencyEnabled) || hoveredPlayerQuickEfficiencyVote != nil
        let hasRequiredContested = !needsQuickStatContestedVote(for: statID, trackingEnabled: contestedEnabled) || hoveredPlayerQuickContestedVote != nil
        guard hasRequiredEfficiency && hasRequiredContested else { return }

        if playerID == oppositionTeamStatPlayerID {
            addTeamEvent(
                statTypeId: statType.id,
                isOpposition: true,
                scoreKind: option.transcript,
                efficiencyVote: hoveredPlayerQuickEfficiencyVote,
                contestedVote: hoveredPlayerQuickContestedVote
            )
        } else {
            addManualEvent(
                statTypeId: statType.id,
                playerID: playerID,
                transcript: option.transcript,
                efficiencyVote: hoveredPlayerQuickEfficiencyVote,
                contestedVote: hoveredPlayerQuickContestedVote
            )
        }
        clearPendingPlayerQuickStat()
        activePlayerQuickStatsPlayerID = nil
    }

    private func clearPendingPlayerQuickStat() {
        hoveredPlayerQuickStatName = nil
        hoveredPlayerQuickEfficiencyVote = nil
        hoveredPlayerQuickContestedVote = nil
        lastHapticQuickStatName = nil
        lastHapticQuickContestedVote = nil
        lastHapticQuickEfficiencyVote = nil
    }

    private func triggerStrongHaptic() {
        longPressHaptic.prepare()
        longPressHaptic.impactOccurred(intensity: 1.0)
    }

    private func triggerSelectionStepHaptic() {
        stepHaptic.prepare()
        stepHaptic.impactOccurred(intensity: 1.0)
    }

    private func triggerQuickSelectionHapticIfNeeded(
        previousQuickStatName: String?,
        previousContestedVote: ContestedPossessionVote?,
        previousEfficiencyVote: EfficiencyVote?
    ) {
        let didChangeQuickStat = hoveredPlayerQuickStatName != previousQuickStatName
        let didChangeContested = hoveredPlayerQuickContestedVote != previousContestedVote
        let didChangeEfficiency = hoveredPlayerQuickEfficiencyVote != previousEfficiencyVote
        guard didChangeQuickStat || didChangeContested || didChangeEfficiency else { return }

        let isSameAsLastHaptic =
            lastHapticQuickStatName == hoveredPlayerQuickStatName &&
            lastHapticQuickContestedVote == hoveredPlayerQuickContestedVote &&
            lastHapticQuickEfficiencyVote == hoveredPlayerQuickEfficiencyVote
        guard !isSameAsLastHaptic else { return }

        lastHapticQuickStatName = hoveredPlayerQuickStatName
        lastHapticQuickContestedVote = hoveredPlayerQuickContestedVote
        lastHapticQuickEfficiencyVote = hoveredPlayerQuickEfficiencyVote
        triggerSelectionStepHaptic()
    }

    private func configureQuarterTimer(reset: Bool) {
        if reset {
            stopQuarterTimer()
            remainingQuarterSeconds = quarterCountsUp ? 0 : customQuarterMinutes * 60
        } else if !quarterCountsUp && remainingQuarterSeconds <= 0 {
            remainingQuarterSeconds = customQuarterMinutes * 60
        }
    }

    private func startQuarterTimer() {
        if !quarterCountsUp && remainingQuarterSeconds == 0 {
            remainingQuarterSeconds = customQuarterMinutes * 60
        }
        guard !isQuarterTimerRunning else { return }
        isQuarterTimerRunning = true
        quarterTimerTask?.cancel()
        quarterTimerTask = Task {
            while !Task.isCancelled && isQuarterTimerRunning {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    guard isQuarterTimerRunning else { return }
                    if quarterCountsUp {
                        remainingQuarterSeconds += 1
                    } else {
                        remainingQuarterSeconds -= 1
                    }
                }
            }
        }
    }

    private func stopQuarterTimer() {
        isQuarterTimerRunning = false
        quarterTimerTask?.cancel()
        quarterTimerTask = nil
    }

    private func statName(for id: UUID) -> String {
        allStatTypes.first(where: { $0.id == id })?.name ?? "Unknown"
    }

    private func addManualEvent(
        statTypeId: UUID,
        playerID: UUID? = nil,
        transcript: String? = nil,
        efficiencyVote: EfficiencyVote? = nil,
        contestedVote: ContestedPossessionVote? = nil
    ) {
        guard let currentSelectedPlayerId = playerID ?? selectedPlayerId else {
            lastMessage = "Select a player first"
            showStatusBanner(text: "ERROR • Select a player first", isSuccess: false)
            feedbackToken = UUID()
            return
        }

        let event = StatEvent(
            sessionId: session.sessionId,
            playerId: currentSelectedPlayerId,
            statTypeId: statTypeId,
            quarter: selectedQuarter,
            sourceRaw: StatsEventSource.manual.rawValue,
            transcript: transcript
        )
        if let efficiencyVote {
            event.efficiencyVoteRaw = efficiencyVote.rawValue
        }
        if let contestedVote {
            event.contestedVoteRaw = contestedVote.rawValue
        }
        modelContext.insert(event)
        try? modelContext.save()

        let shouldDelaySuccessBanner = promptEfficiencyVoteIfNeeded(for: event, preselectedVote: efficiencyVote)
        selectedPlayerId = nil

        lastMessage = "Added: \(statName(for: statTypeId)) — \(playerLabel(for: currentSelectedPlayerId)) — \(selectedQuarter)"
        if !shouldDelaySuccessBanner {
            showSuccessBanner(for: event)
        }
        feedbackToken = UUID()
    }

    private func addTeamEvent(
        statTypeId: UUID,
        isOpposition: Bool,
        scoreKind: String? = nil,
        efficiencyVote: EfficiencyVote? = nil,
        contestedVote: ContestedPossessionVote? = nil
    ) {
        let playerID = isOpposition ? oppositionTeamStatPlayerID : ourTeamStatPlayerID
        let event = StatEvent(
            sessionId: session.sessionId,
            playerId: playerID,
            statTypeId: statTypeId,
            quarter: selectedQuarter,
            sourceRaw: StatsEventSource.manual.rawValue,
            transcript: scoreKind
        )
        if let efficiencyVote {
            event.efficiencyVoteRaw = efficiencyVote.rawValue
        }
        if let contestedVote {
            event.contestedVoteRaw = contestedVote.rawValue
        }
        modelContext.insert(event)
        try? modelContext.save()
        lastMessage = "Added: \(statName(for: statTypeId)) — \(isOpposition ? session.opposition : ourTeamName) — \(selectedQuarter)"
        let shouldDelaySuccessBanner = promptEfficiencyVoteIfNeeded(for: event, preselectedVote: efficiencyVote)
        if !shouldDelaySuccessBanner {
            showSuccessBanner(for: event)
        }
        feedbackToken = UUID()
    }

    private func undoLastEvent() {
        guard let latest = sessionEvents.first else { return }
        modelContext.delete(latest)
        try? modelContext.save()
        lastMessage = "Undid last event"
        showStatusBanner(text: "UNDO • Last event removed", isSuccess: false)
        feedbackToken = UUID()
    }

    private func advanceQuarter() {
        let order = ["Q1", "Q2", "Q3", "Q4"]
        guard let index = order.firstIndex(of: selectedQuarter) else {
            selectedQuarter = "Q1"
            configureQuarterTimer(reset: true)
            return
        }
        selectedQuarter = order[min(index + 1, order.count - 1)]
        configureQuarterTimer(reset: true)
    }

    private func handleTeamVoiceTranscript(_ transcript: String, isOpposition: Bool) {
        let normalizedTranscript = normalizedStatName(transcript)
        guard !normalizedTranscript.isEmpty else { return }
        let rankedTypes = enabledStatTypes.sorted { lhs, rhs in
            let leftLen = lhs.voiceAliases.map { normalizedStatName($0).count }.max() ?? 0
            let rightLen = rhs.voiceAliases.map { normalizedStatName($0).count }.max() ?? 0
            return leftLen > rightLen
        }
        guard let matchedType = rankedTypes.first(where: { type in
            type.voiceAliases.contains { alias in
                let normalizedAlias = normalizedStatName(alias)
                return !normalizedAlias.isEmpty && normalizedTranscript.contains(normalizedAlias)
            }
        }) else {
            showStatusBanner(text: "ERROR • Stat type not recognised", isSuccess: false)
            return
        }

        let normalizedName = normalizedStatName(matchedType.name)
        let scoreKind = normalizedName == "scores" ? voiceScoreKind(in: normalizedTranscript) : nil
        addTeamEvent(statTypeId: matchedType.id, isOpposition: isOpposition, scoreKind: scoreKind)
    }

    private func handleVoiceTranscript(_ transcript: String) {
        lastHeardTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
#if DEBUG
        print("Heard: \(lastHeardTranscript)")
#endif
        guard !lastHeardTranscript.isEmpty else {
            lastMessage = "Heard: (empty)"
            showStatusBanner(text: "ERROR • Heard empty input", isSuccess: false)
            feedbackToken = UUID()
            return
        }

        let descriptors = enabledStatTypes.map {
            VoiceStatTypeDescriptor(id: $0.id, canonicalName: $0.name, aliases: $0.voiceAliases)
        }
        let roster = playersForGrade.map {
            VoiceRosterPlayer(
                id: $0.id,
                number: $0.number,
                firstName: $0.firstName,
                lastName: $0.lastName,
                fullName: $0.name
            )
        }

        let result = parser.parse(transcript: transcript, statTypes: descriptors, roster: roster)
        lastVoiceDebug = result

#if DEBUG
        print("VOICE_PARSE raw='\(result.rawTranscript)' normalized='\(result.normalizedTranscript)' status='\(result.parseStatus)' confidence='\(result.confidence)' statCandidates='\(result.detectedStatCandidates)' playerCandidates='\(result.detectedPlayerCandidates)' matchedStat='\(result.matchedStatName ?? "nil")' matchedPlayer='\(result.matchedPlayerName ?? "nil")' reason='\(result.failureReason ?? "none")'")
#endif

        guard result.parseStatus == .success,
              let statTypeId = result.matchedStatTypeId,
              let playerId = result.matchedPlayerId else {
            if result.shouldOfferReview,
               let guessedStat = result.matchedStatName,
               let guessedPlayer = result.matchedPlayerName {
                lastMessage = "Did you mean \(guessedStat) — \(guessedPlayer)?"
                showStatusBanner(text: "ERROR • Did you mean \(guessedPlayer) \(guessedStat)?", isSuccess: false)
            } else {
            lastMessage = parseFailureMessage(result)
                showStatusBanner(text: "ERROR • \(parseFailureMessage(result))", isSuccess: false)
            }
            feedbackToken = UUID()
            return
        }

        let scoreKind = normalizedStatName(statName(for: statTypeId)) == "scores"
            ? voiceScoreKind(in: result.normalizedTranscript)
            : nil

        let event = StatsEventCreationService.makeVoiceEvent(
            sessionId: session.sessionId,
            playerId: playerId,
            statTypeId: statTypeId,
            quarter: selectedQuarter,
            transcript: scoreKind ?? result.rawTranscript,
            normalizedTranscript: result.normalizedTranscript,
            confidence: result.confidence
        )
        let supportsEfficiencyVoiceVotes = statSupportsVoiceEfficiencyVote(statTypeId)
        let supportsContestedVoiceVotes = statSupportsVoiceContestedVote(statTypeId)
        let efficiencyVote = supportsEfficiencyVoiceVotes && trackDisposalEfficiency
            ? voiceEfficiencyVote(in: result.normalizedTranscript)
            : nil
        let contestedVote = supportsContestedVoiceVotes && trackContestedPossessions
            ? voiceContestedVote(in: result.normalizedTranscript)
            : nil
        if let efficiencyVote {
            event.efficiencyVoteRaw = efficiencyVote.rawValue
        }
        if let contestedVote {
            event.contestedVoteRaw = contestedVote.rawValue
        }
        modelContext.insert(event)
        try? modelContext.save()
        let shouldDelaySuccessBanner = promptEfficiencyVoteIfNeeded(for: event, preselectedVote: efficiencyVote)
        selectedPlayerId = nil

        let playerText = playerLabel(for: playerId)
        let statText = statName(for: statTypeId)
        lastMessage = "Added: \(statText) — \(playerText) — \(selectedQuarter)"
        if !shouldDelaySuccessBanner {
            showSuccessBanner(for: event)
        }
        feedbackToken = UUID()
    }

    private func promptEfficiencyVoteIfNeeded(for event: StatEvent, preselectedVote: EfficiencyVote? = nil) -> Bool {
        if let preselectedVote {
            event.efficiencyVoteRaw = preselectedVote.rawValue
            try? modelContext.save()
            return false
        }
        guard trackDisposalEfficiency else { return false }
        let normalized = statName(for: event.statTypeId).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized == "kick" || normalized == "handball" else { return false }
        pendingEfficiencyEventID = event.id
        showEfficiencyVotePrompt = true
        return true
    }

    private func applyEfficiencyVote(_ vote: EfficiencyVote) {
        guard let eventID = pendingEfficiencyEventID,
              let event = sessionEvents.first(where: { $0.id == eventID }) else {
            pendingEfficiencyEventID = nil
            showEfficiencyVotePrompt = false
            return
        }
        event.efficiencyVoteRaw = vote.rawValue
        try? modelContext.save()
        showSuccessBanner(for: event)
        pendingEfficiencyEventID = nil
        showEfficiencyVotePrompt = false
    }

    private func dismissEfficiencyVotePrompt() {
        if let eventID = pendingEfficiencyEventID,
           let event = sessionEvents.first(where: { $0.id == eventID }) {
            showSuccessBanner(for: event)
        }
        pendingEfficiencyEventID = nil
        showEfficiencyVotePrompt = false
    }

    private func showSuccessBanner(for event: StatEvent) {
        showStatusBanner(text: successBannerText(for: event), isSuccess: true)
    }

    private func showStatusBanner(text: String, isSuccess: Bool) {
        statusBannerTask?.cancel()
        withAnimation {
            statusBanner = StatRecordBanner(text: text, isSuccess: isSuccess)
        }
        statusBannerTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    statusBanner = nil
                }
            }
        }
    }

    private func successBannerText(for event: StatEvent) -> String {
        let playerText = playerBannerLabel(for: event.playerId)
        let statText = statName(for: event.statTypeId)
        var segments = [playerText, statText]

        if let contestedEmoji = contestedEmojiForBanner(event) {
            segments.append(contestedEmoji)
        }

        if let effectivenessEmoji = effectivenessEmojiForBanner(event) {
            segments.append(effectivenessEmoji)
        }

        return segments.joined(separator: " - ")
    }

    private func contestedEmojiForBanner(_ event: StatEvent) -> String? {
        guard let vote = event.contestedVoteRaw else { return nil }
        return vote == ContestedPossessionVote.contested.rawValue ? "😣" : "🙂"
    }

    private func effectivenessEmojiForBanner(_ event: StatEvent) -> String? {
        guard let vote = event.efficiencyVoteRaw else { return nil }
        return vote == EfficiencyVote.thumbsUp.rawValue ? "✅" : "❌"
    }

    private func playerBannerLabel(for id: UUID) -> String {
        if id == ourTeamStatPlayerID {
            return ourTeamName.uppercased()
        }
        if id == oppositionTeamStatPlayerID {
            return session.opposition.uppercased()
        }
        guard let player = allPlayers.first(where: { $0.id == id }) else { return "UNKNOWN" }
        return player.lastName.uppercased()
    }

    private var efficiencyRatingPrompt: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissEfficiencyVotePrompt()
                }

            VStack(spacing: 14) {
                Text("Efficiency Rating")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Was this kick/handball effective?")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.88))

                VStack(spacing: 10) {
                    efficiencyVoteButton(emoji: "👍", color: .green, vote: .thumbsUp)
                    efficiencyVoteButton(emoji: "👎", color: .red, vote: .thumbsDown)

                    Button("Skip") {
                        dismissEfficiencyVotePrompt()
                    }
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(ClubTheme.navy)
                    .background(Capsule().fill(Color.white.opacity(0.17)))
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: 460)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 8)
            .padding(.horizontal, 20)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func efficiencyVoteButton(emoji: String, color: Color, vote: EfficiencyVote) -> some View {
        Button {
            applyEfficiencyVote(vote)
        } label: {
            Text(emoji)
                .font(.system(size: 84))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(color)
                .background(Capsule().fill(Color.white.opacity(0.17)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var sideSpeakButtonsOverlay: some View {
        Group {
            if isEdgeLayoutActive {
                EmptyView()
            } else {
                HStack {
                    speakButton(isOpposition: false)
                    Spacer()
                    speakButton(isOpposition: true)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .allowsHitTesting(true)
            }
        }
    }

    private func parseFailureMessage(_ result: VoiceParseResult) -> String {
        let heardTranscript = result.normalizedTranscript.isEmpty
            ? result.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            : result.normalizedTranscript

        func withHeard(_ message: String) -> String {
            let cleaned = heardTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return message }
            return "\(message). Heard: \"\(cleaned)\""
        }

        switch result.parseStatus {
        case .emptyTranscript:
            return "No speech detected"
        case .noStatFound:
            let cleaned = heardTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "Nothing heard" : "Heard: \"\(cleaned)\""
        case .noPlayerFound:
            if let guessed = result.matchedPlayerName {
                return withHeard("Player not found. Closest: \(guessed)")
            }
            return withHeard("Player not found")
        case .ambiguousPlayer:
            if let first = result.candidatePlayerIds.first {
                return withHeard("Multiple players match '\(playerLabel(for: first))'")
            }
            return withHeard("Multiple players match")
        case .ambiguousStat:
            return withHeard("Multiple stat types matched")
        case .lowConfidence:
            return withHeard("Could not confidently interpret command")
        case .success:
            return ""
        }
    }

    private func statSupportsVoiceEfficiencyVote(_ statTypeId: UUID) -> Bool {
        let normalized = normalizedStatName(statName(for: statTypeId))
        return normalized == "kick" || normalized == "handball"
    }

    private func statSupportsVoiceContestedVote(_ statTypeId: UUID) -> Bool {
        let normalized = normalizedStatName(statName(for: statTypeId))
        return normalized == "kick" || normalized == "handball" || normalized == "mark"
    }

    private func voiceContestedVote(in normalizedTranscript: String) -> ContestedPossessionVote? {
        let words = Set(normalizedTranscript.split(separator: " ").map(String.init))
        let contestedAliases = voteAliases(
            defaultAliases: SpeechVoteSection.all.first(where: { $0.key == SpeechVoteSection.contestedKey })?.defaultAliases ?? [],
            sectionKey: SpeechVoteSection.contestedKey
        )
        let uncontestedAliases = voteAliases(
            defaultAliases: SpeechVoteSection.all.first(where: { $0.key == SpeechVoteSection.uncontestedKey })?.defaultAliases ?? [],
            sectionKey: SpeechVoteSection.uncontestedKey
        )
        if uncontestedAliases.contains(where: { containsVoiceAlias($0, in: normalizedTranscript, words: words) }) {
            return .uncontested
        }
        if contestedAliases.contains(where: { containsVoiceAlias($0, in: normalizedTranscript, words: words) }) {
            return .contested
        }
        return nil
    }

    private func voiceEfficiencyVote(in normalizedTranscript: String) -> EfficiencyVote? {
        let words = Set(normalizedTranscript.split(separator: " ").map(String.init))
        let effectiveAliases = voteAliases(
            defaultAliases: SpeechVoteSection.all.first(where: { $0.key == SpeechVoteSection.effectiveKey })?.defaultAliases ?? [],
            sectionKey: SpeechVoteSection.effectiveKey
        )
        let ineffectiveAliases = voteAliases(
            defaultAliases: SpeechVoteSection.all.first(where: { $0.key == SpeechVoteSection.ineffectiveKey })?.defaultAliases ?? [],
            sectionKey: SpeechVoteSection.ineffectiveKey
        )
        if ineffectiveAliases.contains(where: { containsVoiceAlias($0, in: normalizedTranscript, words: words) }) {
            return .thumbsDown
        }
        if effectiveAliases.contains(where: { containsVoiceAlias($0, in: normalizedTranscript, words: words) }) {
            return .thumbsUp
        }
        return nil
    }

    private func voteAliases(defaultAliases: [String], sectionKey: String) -> [String] {
        let detected = SpeechDetectedWordsStore.words(forSectionKey: sectionKey)
        return Array(Set(defaultAliases + detected)).map { $0.lowercased() }
    }

    private func containsVoiceAlias(_ alias: String, in transcript: String, words: Set<String>) -> Bool {
        if alias.contains(" ") {
            return transcript.contains(alias)
        }
        return words.contains(alias)
    }

    private func voiceScoreKind(in normalizedTranscript: String) -> String? {
        let words = Set(normalizedTranscript.split(separator: " ").map(String.init))
        if words.contains("goal") || words.contains("goals") || words.contains("go") {
            return "goal"
        }
        if words.contains("behind") || words.contains("behinds") || words.contains("point") || words.contains("points") {
            return "behind"
        }
        if normalizedTranscript.contains("rushed behind") {
            return "behind"
        }
        return nil
    }

    private func generateReport() {
        let quarterOrder = ["Q1", "Q2", "Q3", "Q4"]
        let trackedStats: [(label: String, aliases: [String])] = [
            ("K", ["kick"]),
            ("H", ["handball", "hand ball", "handpass", "hand pass"]),
            ("M", ["mark"]),
            ("T", ["tackle"]),
            ("G", ["goal"]),
            ("B", ["behind"])
        ]
        let inside50Stat = statTypeMatching(aliases: ["inside 50", "inside50", "inside 50s"])
        let clearanceStat = statTypeMatching(aliases: ["clearance", "clearances"])

        let players = displayedPlayers
        let playerIDs = Set(players.map(\.id))
        let eventsForPlayers = sessionEvents.filter { playerIDs.contains($0.playerId) }
        let byPlayerQuarterAndStat = Dictionary(grouping: eventsForPlayers) { event in
            "\(event.playerId.uuidString)|\(event.quarter)|\(event.statTypeId.uuidString)"
        }

        let pageRect = CGRect(x: 0, y: 0, width: 842, height: 595) // A4 landscape points
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 20

            if let logo = UIImage(named: "club_logo") {
                logo.draw(in: CGRect(x: 24, y: y, width: 56, height: 56))
            }
            ("Stats Report" as NSString).draw(at: CGPoint(x: 96, y: y + 10), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 24)])
            y += 62
            let details = "Grade: \(gradeName)   Opposition: \(session.opposition)   Date: \(session.date.formatted(date: .abbreviated, time: .omitted))   Venue: \(session.venue)"
            (details as NSString).draw(
                in: CGRect(x: 24, y: y, width: pageRect.width - 48, height: 30),
                withAttributes: [.font: UIFont.systemFont(ofSize: 11)]
            )
            y += 24

            let inside50Us = teamStatCount(statType: inside50Stat, teamPlayerId: ourTeamStatPlayerID)
            let inside50Them = teamStatCount(statType: inside50Stat, teamPlayerId: oppositionTeamStatPlayerID)
            let clearancesUs = teamStatCount(statType: clearanceStat, teamPlayerId: ourTeamStatPlayerID)
            let clearancesThem = teamStatCount(statType: clearanceStat, teamPlayerId: oppositionTeamStatPlayerID)
            let inside50Summary = "Inside 50: \(ourTeamName) \(inside50Us)  |  \(session.opposition) \(inside50Them)"
            let clearancesSummary = "Clearances: \(ourTeamName) \(clearancesUs)  |  \(session.opposition) \(clearancesThem)"
            (inside50Summary as NSString).draw(
                at: CGPoint(x: 24, y: y),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 11)]
            )
            (clearancesSummary as NSString).draw(
                at: CGPoint(x: 24, y: y + 16),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 11)]
            )
            y += 42

            let leftMargin: CGFloat = 24
            let numberColumnWidth: CGFloat = 42
            let playerColumnWidth: CGFloat = 108
            let statColumnWidth: CGFloat = 19
            let efficiencyColumnWidth: CGFloat = 42
            let headerRowHeight: CGFloat = 20
            let maxPlayersPerPage: CGFloat = 26
            let footerReservedHeight: CGFloat = 18
            let availableHeightForDataRows = max(
                12 * maxPlayersPerPage,
                (pageRect.height - y - (headerRowHeight * 2) - footerReservedHeight)
            )
            let dataRowHeight = floor(availableHeightForDataRows / maxPlayersPerPage)
            let blockWidth = CGFloat(trackedStats.count) * statColumnWidth

            drawCell("No", x: leftMargin, y: y, width: numberColumnWidth, height: headerRowHeight, bold: true)
            drawCell("Player", x: leftMargin + numberColumnWidth, y: y, width: playerColumnWidth, height: headerRowHeight, bold: true)
            var x = leftMargin + numberColumnWidth + playerColumnWidth
            for quarter in quarterOrder {
                drawCell(quarter, x: x, y: y, width: blockWidth, height: headerRowHeight, bold: true)
                x += blockWidth
            }
            drawCell("Totals", x: x, y: y, width: blockWidth, height: headerRowHeight, bold: true)
            x += blockWidth
            drawCell("Eff %", x: x, y: y, width: efficiencyColumnWidth, height: headerRowHeight, bold: true)
            y += headerRowHeight

            drawCell("", x: leftMargin, y: y, width: numberColumnWidth, height: headerRowHeight, bold: true)
            drawCell("", x: leftMargin + numberColumnWidth, y: y, width: playerColumnWidth, height: headerRowHeight, bold: true)
            x = leftMargin + numberColumnWidth + playerColumnWidth
            for _ in quarterOrder {
                for stat in trackedStats {
                    drawCell(stat.label, x: x, y: y, width: statColumnWidth, height: headerRowHeight, bold: true)
                    x += statColumnWidth
                }
            }
            for stat in trackedStats {
                drawCell(stat.label, x: x, y: y, width: statColumnWidth, height: headerRowHeight, bold: true)
                x += statColumnWidth
            }
            drawCell("", x: x, y: y, width: efficiencyColumnWidth, height: headerRowHeight, bold: true)
            y += headerRowHeight

            for player in players {
                if y + dataRowHeight > pageRect.height - footerReservedHeight {
                    context.beginPage()
                    y = 24
                }

                let playerLabel = player.lastName.uppercased()
                drawCell(player.number.map { String($0) } ?? "", x: leftMargin, y: y, width: numberColumnWidth, height: dataRowHeight)
                drawCell(playerLabel, x: leftMargin + numberColumnWidth, y: y, width: playerColumnWidth, height: dataRowHeight)

                x = leftMargin + numberColumnWidth + playerColumnWidth
                for quarter in quarterOrder {
                    for stat in trackedStats {
                        let count = statCount(
                            for: player.id,
                            quarter: quarter,
                            aliases: stat.aliases,
                            lookup: byPlayerQuarterAndStat
                        )
                        drawCell("\(count)", x: x, y: y, width: statColumnWidth, height: dataRowHeight)
                        x += statColumnWidth
                    }
                }
                for stat in trackedStats {
                    let total = quarterOrder.reduce(0) { partialResult, quarter in
                        partialResult + statCount(
                            for: player.id,
                            quarter: quarter,
                            aliases: stat.aliases,
                            lookup: byPlayerQuarterAndStat
                        )
                    }
                    drawCell("\(total)", x: x, y: y, width: statColumnWidth, height: dataRowHeight, bold: true)
                    x += statColumnWidth
                }
                let efficiencyText: String
                let (effectiveCount, nonEffectiveCount) = efficiencyVoteCounts(for: player.id, events: eventsForPlayers)
                let totalRatedDisposals = effectiveCount + nonEffectiveCount
                if totalRatedDisposals > 0 {
                    let efficiency = Int(round((Double(effectiveCount) / Double(totalRatedDisposals)) * 100))
                    efficiencyText = "\(efficiency)%"
                } else {
                    efficiencyText = "-"
                }
                drawCell(efficiencyText, x: x, y: y, width: efficiencyColumnWidth, height: dataRowHeight, bold: true)
                y += dataRowHeight
            }

        }

        let safeDate = session.date.formatted(.dateTime.year().month().day())
        let fileName = "Stats_\(gradeName.replacingOccurrences(of: " ", with: "_"))_\(safeDate).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            reportPreviewDocument = ReportPreviewDocument(url: url)
            lastMessage = "Report generated"
        } catch {
            lastMessage = "Failed to build report"
        }
    }

    private func statTypeMatching(aliases: [String]) -> StatType? {
        let normalizedAliases = Set(aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return enabledStatTypes.first { statType in
            normalizedAliases.contains(statType.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }

    private func statCount(
        for playerID: UUID,
        quarter: String,
        aliases: [String],
        lookup: [String: [StatEvent]]
    ) -> Int {
        let matchingStatIDs = enabledStatTypes.filter { type in
            aliases.contains { alias in
                type.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == alias.lowercased()
            }
        }.map(\.id)

        return matchingStatIDs.reduce(0) { partialResult, statID in
            let key = "\(playerID.uuidString)|\(quarter)|\(statID.uuidString)"
            return partialResult + (lookup[key]?.count ?? 0)
        }
    }

    private func teamStatCount(statType: StatType?, teamPlayerId: UUID) -> Int {
        guard let statType else { return 0 }
        return sessionEvents.filter { $0.playerId == teamPlayerId && $0.statTypeId == statType.id }.count
    }

    private func efficiencyVoteCounts(for playerID: UUID, events: [StatEvent]) -> (effective: Int, nonEffective: Int) {
        let ratedEvents = events.filter { $0.playerId == playerID }
        let effective = ratedEvents.reduce(0) { partialResult, event in
            partialResult + (event.efficiencyVoteRaw == EfficiencyVote.thumbsUp.rawValue ? 1 : 0)
        }
        let nonEffective = ratedEvents.reduce(0) { partialResult, event in
            partialResult + (event.efficiencyVoteRaw == EfficiencyVote.thumbsDown.rawValue ? 1 : 0)
        }
        return (effective, nonEffective)
    }

    private func drawCell(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 20, bold: Bool = false, emphasize: Bool = false) {
        if emphasize {
            UIColor.systemGray6.setFill()
            UIBezierPath(rect: CGRect(x: x, y: y, width: width, height: height)).fill()
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: bold ? UIFont.boldSystemFont(ofSize: 10) : UIFont.systemFont(ofSize: 10)
        ]
        let textInsetY = max(1, (height - 14) / 2)
        (text as NSString).draw(in: CGRect(x: x + 2, y: y + textInsetY, width: width - 4, height: max(12, height - 2)), withAttributes: attributes)
        let path = UIBezierPath(rect: CGRect(x: x, y: y, width: width, height: height))
        UIColor.systemGray4.setStroke()
        path.stroke()
    }
}

private struct StatsReportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let onShare: () -> Void

    var body: some View {
        NavigationStack {
            StatsPDFPreview(url: url)
                .navigationTitle("Report Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Share") {
                            onShare()
                        }
                    }
                }
        }
    }
}

private struct StatsPDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}

private struct PlayerVisibilityEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let players: [Player]
    let initialSelection: Set<UUID>
    let initialGridOrder: PlayerGridOrder
    let onSave: (Set<UUID>, PlayerGridOrder) -> Void

    @State private var selectedIDs: Set<UUID>
    @State private var gridOrder: PlayerGridOrder
    @State private var showDiscardAlert = false

    init(
        players: [Player],
        initialSelection: Set<UUID>,
        initialGridOrder: PlayerGridOrder,
        onSave: @escaping (Set<UUID>, PlayerGridOrder) -> Void
    ) {
        self.players = players
        self.initialSelection = initialSelection
        self.initialGridOrder = initialGridOrder
        self.onSave = onSave
        _selectedIDs = State(initialValue: initialSelection)
        _gridOrder = State(initialValue: initialGridOrder)
    }

    private var hasUnsavedChanges: Bool {
        selectedIDs != initialSelection || gridOrder != initialGridOrder
    }

    private var orderedPlayers: [Player] {
        players.sorted(by: playerSortPredicate)
    }

    private func playerSortPredicate(lhs: Player, rhs: Player) -> Bool {
        switch gridOrder {
        case .number:
            let leftNumber = lhs.number ?? Int.max
            let rightNumber = rhs.number ?? Int.max
            if leftNumber != rightNumber {
                return leftNumber < rightNumber
            }
            if lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) != .orderedSame {
                return lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) == .orderedAscending
            }
            return lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) == .orderedAscending
        case .firstName:
            if lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) != .orderedSame {
                return lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) == .orderedAscending
            }
            if lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) != .orderedSame {
                return lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) == .orderedAscending
            }
            return (lhs.number ?? Int.max) < (rhs.number ?? Int.max)
        case .lastName:
            if lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) != .orderedSame {
                return lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) == .orderedAscending
            }
            if lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) != .orderedSame {
                return lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) == .orderedAscending
            }
            return (lhs.number ?? Int.max) < (rhs.number ?? Int.max)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Visible Players")
                        .font(.largeTitle.bold())
                    Spacer()
                    Text("\(selectedIDs.count) Included")
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                HStack {
                    Text("Grid order")
                        .font(.headline)
                    Spacer()
                    Picker("Grid order", selection: $gridOrder) {
                        ForEach(PlayerGridOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 6)

                List(orderedPlayers) { player in
                    Button {
                        if selectedIDs.contains(player.id) {
                            selectedIDs.remove(player.id)
                        } else {
                            selectedIDs.insert(player.id)
                        }
                    }
                    label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedIDs.contains(player.id) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(selectedIDs.contains(player.id) ? .blue : .secondary)
                            Text(player.number.map { "#\($0)" } ?? "—")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.lastName.uppercased())
                                    .font(.headline)
                                Text(player.firstName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        if hasUnsavedChanges {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(selectedIDs, gridOrder)
                        dismiss()
                    }
                    .saveButtonBehavior(isEnabled: hasUnsavedChanges)
                }
            }
            .alert("Discard unsaved changes?", isPresented: $showDiscardAlert) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard", role: .destructive) { dismiss() }
            } message: {
                Text("You have unsaved player visibility changes.")
            }
        }
    }
}

private struct EditStatEventView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let event: StatEvent
    let players: [Player]
    let statTypes: [StatType]

    @State private var playerId: UUID
    @State private var statTypeId: UUID
    @State private var quarter: String

    init(event: StatEvent, players: [Player], statTypes: [StatType]) {
        self.event = event
        self.players = players
        self.statTypes = statTypes
        _playerId = State(initialValue: event.playerId)
        _statTypeId = State(initialValue: event.statTypeId)
        _quarter = State(initialValue: event.quarter)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Player", selection: $playerId) {
                    ForEach(players) { player in
                        Text(player.name).tag(player.id)
                    }
                }

                Picker("Stat Type", selection: $statTypeId) {
                    ForEach(statTypes) { stat in
                        Text(stat.name).tag(stat.id)
                    }
                }

                Picker("Quarter", selection: $quarter) {
                    ForEach(["Q1", "Q2", "Q3", "Q4"], id: \.self) {
                        Text($0)
                    }
                }

                Button("Delete Event", role: .destructive) {
                    modelContext.delete(event)
                    try? modelContext.save()
                    dismiss()
                }
            }
            .navigationTitle("Edit Event")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        event.playerId = playerId
                        event.statTypeId = statTypeId
                        event.quarter = quarter
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PlayerSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let players: [Player]
    @Binding var selectedPlayerId: UUID?
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List(filteredPlayers) { player in
                Button {
                    selectedPlayerId = player.id
                    dismiss()
                } label: {
                    HStack {
                        Text(player.number.map { "#\($0)" } ?? "#–")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)
                        Text(player.name)
                        Spacer()
                        if selectedPlayerId == player.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "Find player")
            .navigationTitle("Select Player")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var filteredPlayers: [Player] {
        let base = players.sorted { lhs, rhs in
            if lhs.number != rhs.number {
                return (lhs.number ?? Int.max) < (rhs.number ?? Int.max)
            }
            return lhs.name < rhs.name
        }
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return base
        }
        let key = searchText.lowercased()
        return base.filter {
            $0.name.lowercased().contains(key)
            || $0.firstName.lowercased().contains(key)
            || $0.lastName.lowercased().contains(key)
            || ($0.number.map { String($0) }?.contains(key) ?? false)
        }
    }
}

private struct StatsTotalsView: View {
    @Environment(\.dismiss) private var dismiss
    let rows: [TotalsRow]
    let statTypes: [StatType]
    let sessionEvents: [StatEvent]
    let ourTeamName: String
    let oppositionName: String
    let ourStyle: ClubStyle.Style
    let oppositionStyle: ClubStyle.Style
    let ourScoreSummary: (goals: Int, behinds: Int, points: Int)
    let oppositionScoreSummary: (goals: Int, behinds: Int, points: Int)
    private let oppositionTeamStatPlayerID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB") ?? UUID()

    private struct TotalsSummaryRow: Identifiable {
        let id: UUID
        let playerLabel: String
        let kicks: Int
        let handballs: Int
        let possessions: Int
        let marks: Int
        let tackles: Int
        let goals: Int
        let behinds: Int
    }

    private var summaryRows: [TotalsSummaryRow] {
        rows.map { row in
            let kicks = count(for: "kick", in: row)
            let handballs = count(for: "handball", in: row)
            let possessions = kicks + handballs
            return TotalsSummaryRow(
                id: row.id,
                playerLabel: row.player.number.map { "\($0) \(row.player.name)" } ?? row.player.name,
                kicks: kicks,
                handballs: handballs,
                possessions: possessions,
                marks: count(for: "mark", in: row),
                tackles: count(for: "tackle", in: row),
                goals: count(for: "goal", in: row),
                behinds: count(for: "behind", in: row)
            )
        }
        .sorted { lhs, rhs in
            if lhs.possessions != rhs.possessions { return lhs.possessions > rhs.possessions }
            return lhs.playerLabel < rhs.playerLabel
        }
    }

    private var topPossessionRows: [TotalsSummaryRow] {
        Array(summaryRows.prefix(5))
    }

    private var topGoalKickers: [TotalsSummaryRow] {
        summaryRows
            .filter { $0.goals > 0 || $0.behinds > 0 }
            .sorted { lhs, rhs in
                if lhs.goals != rhs.goals { return lhs.goals > rhs.goals }
                if lhs.behinds != rhs.behinds { return lhs.behinds > rhs.behinds }
                return lhs.playerLabel < rhs.playerLabel
            }
            .prefix(5)
            .map { $0 }
    }

    private var inside50Stat: StatType? {
        statType(aliases: ["inside 50", "inside50", "inside 50s"])
    }

    private var clearanceStat: StatType? {
        statType(aliases: ["clearance", "clearances"])
    }

    private var ourInside50s: Int {
        teamCount(for: inside50Stat, isOpposition: false)
    }

    private var theirInside50s: Int {
        teamCount(for: inside50Stat, isOpposition: true)
    }

    private var ourClearances: Int {
        teamCount(for: clearanceStat, isOpposition: false)
    }

    private var theirClearances: Int {
        teamCount(for: clearanceStat, isOpposition: true)
    }

    private var ourTeamEfficiency: String {
        teamEfficiencyText(isOpposition: false)
    }

    private var oppositionTeamEfficiency: String {
        teamEfficiencyText(isOpposition: true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        scorePool(
                            teamName: ourTeamName,
                            goals: ourScoreSummary.goals,
                            behinds: ourScoreSummary.behinds,
                            points: ourScoreSummary.points,
                            style: ourStyle
                        )
                        scorePool(
                            teamName: oppositionName,
                            goals: oppositionScoreSummary.goals,
                            behinds: oppositionScoreSummary.behinds,
                            points: oppositionScoreSummary.points,
                            style: oppositionStyle
                        )
                    }

                    HStack(spacing: 12) {
                        teamStatPool(title: "Inside 50s", value: ourInside50s, style: ourStyle)
                        teamStatPool(title: "Clearances", value: ourClearances, style: ourStyle)
                        teamStatPool(title: "Inside 50s", value: theirInside50s, style: oppositionStyle)
                        teamStatPool(title: "Clearances", value: theirClearances, style: oppositionStyle)
                    }

                    HStack(spacing: 12) {
                        efficiencyPool(title: "\(ourTeamName) Efficiency", value: ourTeamEfficiency, style: ourStyle)
                        efficiencyPool(title: "\(oppositionName) Efficiency", value: oppositionTeamEfficiency, style: oppositionStyle)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        leaderboardPool(
                            title: "Top 5 Possession Getters",
                            entries: topPossessionRows.map {
                                ("\($0.playerLabel)", "\($0.possessions)", "K\($0.kicks) • H\($0.handballs)")
                            }
                        )
                        leaderboardPool(
                            title: "Top 5 Goal Kickers",
                            entries: topGoalKickers.map {
                                ("\($0.playerLabel)", "\($0.goals).\($0.behinds)", "Goals \($0.goals) • Behinds \($0.behinds)")
                            }
                        )
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Game Totals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func statType(aliases: [String]) -> StatType? {
        let normalizedAliases = Set(aliases.map { $0.lowercased() })
        return statTypes.first { type in
            normalizedAliases.contains(type.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }

    private func teamCount(for statType: StatType?, isOpposition: Bool) -> Int {
        guard let statType else { return 0 }
        return sessionEvents.filter { event in
            let isOppositionEvent = event.playerId == oppositionTeamStatPlayerID
            return isOppositionEvent == isOpposition && event.statTypeId == statType.id
        }.count
    }

    private func teamEfficiencyText(isOpposition: Bool) -> String {
        let relevant = sessionEvents.filter { event in
            let isOppositionEvent = event.playerId == oppositionTeamStatPlayerID
            return isOppositionEvent == isOpposition
        }
        let effective = relevant.filter { $0.efficiencyVoteRaw == EfficiencyVote.thumbsUp.rawValue }.count
        let nonEffective = relevant.filter { $0.efficiencyVoteRaw == EfficiencyVote.thumbsDown.rawValue }.count
        let total = effective + nonEffective
        guard total > 0 else { return "-" }
        return "\(Int(round((Double(effective) / Double(total)) * 100)))%"
    }

    private func count(for statName: String, in row: TotalsRow) -> Int {
        statTypes.first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == statName }).map {
            row.countsByStatId[$0.id, default: 0]
        } ?? 0
    }

    @ViewBuilder
    private func scorePool(teamName: String, goals: Int, behinds: Int, points: Int, style: ClubStyle.Style) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(teamName.uppercased())
                .font(.title3.weight(.black))
                .lineLimit(1)
            Text("\(goals).\(behinds) (\(points))")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("\(points) points")
                .font(.title2.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(style.text)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(style.border.opacity(0.75), lineWidth: 2)
        )
    }

    private func teamStatPool(title: String, value: Int, style: ClubStyle.Style) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
            Text("\(value)")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(style.text)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.background.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(style.border.opacity(0.75), lineWidth: 2)
        )
    }

    private func teamStatsPool(
        teamName: String,
        style: ClubStyle.Style,
        inside50s: Int,
        clearances: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(teamName.uppercased())
                .font(.headline.weight(.black))
                .lineLimit(1)

            HStack(spacing: 10) {
                teamStatPool(title: "Inside 50s", value: inside50s, style: style)
                teamStatPool(title: "Clearances", value: clearances, style: style)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func efficiencyPool(title: String, value: String, style: ClubStyle.Style) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.weight(.black))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 44, weight: .black, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(style.text)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(style.border.opacity(0.8), lineWidth: 2)
        )
    }

    private func leaderboardPool(title: String, entries: [(name: String, mainValue: String, subValue: String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.black))
            if entries.isEmpty {
                Text("No data yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .font(.headline.weight(.semibold))
                                .lineLimit(1)
                            Text(entry.subValue)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(entry.mainValue)
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
