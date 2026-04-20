import Foundation
import Speech
import AVFoundation
internal import Combine

struct VoiceStatTypeDescriptor: Identifiable, Hashable {
    let id: UUID
    let canonicalName: String
    let aliases: [String]
}

struct VoiceRosterPlayer: Identifiable, Hashable {
    let id: UUID
    let number: Int?
    let firstName: String
    let lastName: String
    let fullName: String
}

enum VoiceParseStatus: Equatable {
    case success
    case emptyTranscript
    case noStatFound
    case ambiguousStat
    case noPlayerFound
    case ambiguousPlayer
    case lowConfidence
}

struct VoiceParseResult {
    let rawTranscript: String
    let normalizedTranscript: String
    let matchedStatTypeId: UUID?
    let matchedPlayerId: UUID?
    let matchedStatName: String?
    let matchedPlayerName: String?
    let parseStatus: VoiceParseStatus
    let confidence: Double
    let failureReason: String?
    let candidatePlayerIds: [UUID]
    let candidatePlayerNames: [String]
    let candidateStatTypeIds: [UUID]
    let candidateStatNames: [String]
    let bestGuessStatTypeId: UUID?
    let bestGuessPlayerId: UUID?
    let debugLog: String
}

struct StatsVoiceParser {
    private let minConfidence: Double = 0.90
    private let reviewConfidenceFloor: Double = 0.80

    func parse(
        transcript rawTranscript: String,
        statTypes: [VoiceStatTypeDescriptor],
        roster: [VoiceRosterPlayer]
    ) -> VoiceParseResult {
        let normalizedTranscript = normalize(rawTranscript)
        guard !normalizedTranscript.isEmpty else {
            return makeResult(
                raw: rawTranscript,
                normalized: normalizedTranscript,
                status: .emptyTranscript,
                failure: "empty transcript",
                confidence: 0,
                diagnostics: "Raw: \(rawTranscript) | Normalized: <empty>"
            )
        }

        let statMatch = matchStatType(in: normalizedTranscript, statTypes: statTypes)
        guard let stat = statMatch.bestStat else {
            return makeResult(
                raw: rawTranscript,
                normalized: normalizedTranscript,
                status: .noStatFound,
                failure: "stat type not recognised",
                confidence: 0,
                candidateStatNames: statMatch.candidateStats.map(\.canonicalName),
                candidateStatIds: statMatch.candidateStats.map(\.id),
                diagnostics: diagnosticsText(
                    raw: rawTranscript,
                    normalized: normalizedTranscript,
                    statCandidates: statMatch.candidateStats.map(\.canonicalName),
                    playerCandidates: [],
                    matchedStat: nil,
                    matchedPlayer: nil,
                    confidence: 0,
                    failure: "noStatFound"
                )
            )
        }

        if statMatch.isAmbiguous {
            return makeResult(
                raw: rawTranscript,
                normalized: normalizedTranscript,
                status: .ambiguousStat,
                failure: "multiple stat types matched",
                confidence: stat.confidence,
                candidateStatNames: statMatch.candidateStats.map(\.canonicalName),
                candidateStatIds: statMatch.candidateStats.map(\.id),
                diagnostics: diagnosticsText(
                    raw: rawTranscript,
                    normalized: normalizedTranscript,
                    statCandidates: statMatch.candidateStats.map(\.canonicalName),
                    playerCandidates: [],
                    matchedStat: nil,
                    matchedPlayer: nil,
                    confidence: stat.confidence,
                    failure: "ambiguousStat"
                )
            )
        }

        let playerReference = playerReferenceText(byRemoving: stat.aliasUsed, from: normalizedTranscript)
        let playerResolution = resolvePlayer(reference: playerReference, roster: roster)
        let combinedConfidence = min(stat.confidence, playerResolution.confidence)

        let baseDiagnostics = diagnosticsText(
            raw: rawTranscript,
            normalized: normalizedTranscript,
            statCandidates: statMatch.candidateStats.map(\.canonicalName),
            playerCandidates: playerResolution.candidates.map(\.fullName),
            matchedStat: stat.statType.canonicalName,
            matchedPlayer: playerResolution.player?.fullName,
            confidence: combinedConfidence,
            failure: playerResolution.failureHint
        )

        switch playerResolution.status {
        case .success:
            guard let matchedPlayer = playerResolution.player else {
                return makeResult(
                    raw: rawTranscript,
                    normalized: normalizedTranscript,
                    status: .noPlayerFound,
                    failure: "player not found",
                    confidence: combinedConfidence,
                    diagnostics: baseDiagnostics
                )
            }

            if combinedConfidence >= minConfidence {
                return makeResult(
                    raw: rawTranscript,
                    normalized: normalizedTranscript,
                    status: .success,
                    confidence: combinedConfidence,
                    matchedStat: stat.statType,
                    matchedPlayer: matchedPlayer,
                    diagnostics: baseDiagnostics
                )
            }

            if combinedConfidence >= reviewConfidenceFloor {
                return makeResult(
                    raw: rawTranscript,
                    normalized: normalizedTranscript,
                    status: .lowConfidence,
                    failure: "near miss - review suggested",
                    confidence: combinedConfidence,
                    matchedStat: stat.statType,
                    matchedPlayer: matchedPlayer,
                    bestGuessStatId: stat.statType.id,
                    bestGuessPlayerId: matchedPlayer.id,
                    diagnostics: baseDiagnostics
                )
            }

            return makeResult(
                raw: rawTranscript,
                normalized: normalizedTranscript,
                status: .lowConfidence,
                failure: "could not confidently interpret command",
                confidence: combinedConfidence,
                matchedStat: stat.statType,
                matchedPlayer: nil,
                candidatePlayerNames: playerResolution.candidates.map(\.fullName),
                candidatePlayerIds: playerResolution.candidates.map(\.id),
                diagnostics: baseDiagnostics
            )

        case .ambiguousPlayer:
            return makeResult(
                raw: rawTranscript,
                normalized: normalizedTranscript,
                status: .ambiguousPlayer,
                failure: "multiple players match",
                confidence: combinedConfidence,
                matchedStat: stat.statType,
                candidatePlayerNames: playerResolution.candidates.map(\.fullName),
                candidatePlayerIds: playerResolution.candidates.map(\.id),
                diagnostics: baseDiagnostics
            )

        case .noPlayerFound:
            return makeResult(
                raw: rawTranscript,
                normalized: normalizedTranscript,
                status: .noPlayerFound,
                failure: "player not found",
                confidence: combinedConfidence,
                matchedStat: stat.statType,
                diagnostics: baseDiagnostics
            )
        }
    }

    func normalize(_ raw: String) -> String {
        let lowered = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty else { return "" }

        var working = lowered
            .replacingOccurrences(of: "no.", with: "number")
            .replacingOccurrences(of: "no ", with: "number ")
            .replacingOccurrences(of: "#", with: " number ")
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        let fillers: Set<String> = ["um", "uh", "please", "thanks", "thank", "you"]
        var tokens = working.split(separator: " ").map(String.init).filter { !fillers.contains($0) }

        tokens = combineNumberTokens(tokens)

        var converted: [String] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token == "number", index + 1 < tokens.count {
                converted.append(tokens[index + 1])
                index += 2
                continue
            }
            converted.append(token)
            index += 1
        }

        working = converted.joined(separator: " ")
        return working.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let wordToNumber: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30
    ]

    private func combineNumberTokens(_ tokens: [String]) -> [String] {
        var output: [String] = []
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            if let first = wordToNumber[token] {
                if i + 1 < tokens.count, let second = wordToNumber[tokens[i + 1]], first >= 20, second < 10 {
                    output.append(String(first + second))
                    i += 2
                    continue
                }
                output.append(String(first))
            } else {
                output.append(token)
            }
            i += 1
        }
        return output
    }

    private struct MatchedStat {
        let statType: VoiceStatTypeDescriptor
        let aliasUsed: String
        let confidence: Double
    }

    private struct StatMatchResult {
        let bestStat: MatchedStat?
        let isAmbiguous: Bool
        let candidateStats: [VoiceStatTypeDescriptor]
    }

    private func matchStatType(in transcript: String, statTypes: [VoiceStatTypeDescriptor]) -> StatMatchResult {
        let tokens = transcript.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return StatMatchResult(bestStat: nil, isAmbiguous: false, candidateStats: []) }

        var candidates: [MatchedStat] = []

        for stat in statTypes {
            for alias in Array(Set(stat.aliases + [stat.canonicalName])) {
                let aliasNormalized = normalize(alias)
                guard !aliasNormalized.isEmpty else { continue }
                let aliasTokens = aliasNormalized.split(separator: " ").map(String.init)
                if containsPhrase(tokens: tokens, phraseTokens: aliasTokens) {
                    let confidence = aliasNormalized == normalize(stat.canonicalName) ? 1.0 : 0.96
                    candidates.append(MatchedStat(statType: stat, aliasUsed: aliasNormalized, confidence: confidence))
                    continue
                }

                if let fuzzyScore = fuzzyPhraseScore(in: tokens, phraseTokens: aliasTokens), fuzzyScore >= 0.88 {
                    candidates.append(MatchedStat(statType: stat, aliasUsed: aliasNormalized, confidence: min(0.90, fuzzyScore)))
                }
            }
        }

        guard !candidates.isEmpty else { return StatMatchResult(bestStat: nil, isAmbiguous: false, candidateStats: []) }

        let sorted = candidates.sorted {
            let lhsCount = $0.aliasUsed.split(separator: " ").count
            let rhsCount = $1.aliasUsed.split(separator: " ").count
            if lhsCount != rhsCount { return lhsCount > rhsCount }
            if abs($0.confidence - $1.confidence) > 0.0001 { return $0.confidence > $1.confidence }
            return $0.statType.canonicalName < $1.statType.canonicalName
        }

        guard let best = sorted.first else { return StatMatchResult(bestStat: nil, isAmbiguous: false, candidateStats: []) }
        let top = sorted.filter {
            let sameLength = $0.aliasUsed.split(separator: " ").count == best.aliasUsed.split(separator: " ").count
            let closeConfidence = abs($0.confidence - best.confidence) < 0.03
            return sameLength && closeConfidence
        }
        let uniqueTop = Dictionary(grouping: top, by: { $0.statType.id }).compactMap { $0.value.first }
        if uniqueTop.count > 1 {
            return StatMatchResult(bestStat: nil, isAmbiguous: true, candidateStats: uniqueTop.map(\.statType))
        }

        return StatMatchResult(bestStat: best, isAmbiguous: false, candidateStats: [best.statType])
    }

    private enum PlayerResolutionStatus {
        case success
        case noPlayerFound
        case ambiguousPlayer
    }

    private struct PlayerResolution {
        let status: PlayerResolutionStatus
        let player: VoiceRosterPlayer?
        let candidates: [VoiceRosterPlayer]
        let confidence: Double
        let failureHint: String?
    }

    private func resolvePlayer(reference rawReference: String, roster: [VoiceRosterPlayer]) -> PlayerResolution {
        var reference = normalize(rawReference)
        reference = reference.replacingOccurrences(of: "\\b(to|for|by)\\b", with: " ", options: .regularExpression)
        reference = reference.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !reference.isEmpty else {
            return PlayerResolution(status: .noPlayerFound, player: nil, candidates: [], confidence: 0, failureHint: "noPlayerReference")
        }

        let numbers = reference.split(separator: " ").compactMap { Int($0) }
        if let number = numbers.first {
            let matches = roster.filter { $0.number == number }
            if matches.count == 1 {
                return PlayerResolution(status: .success, player: matches[0], candidates: [], confidence: 1.0, failureHint: nil)
            }
            return PlayerResolution(status: .noPlayerFound, player: nil, candidates: [], confidence: 0, failureHint: "numberNoMatch")
        }

        let fullMatches = roster.filter { normalize($0.fullName) == reference }
        if fullMatches.count == 1 {
            return PlayerResolution(status: .success, player: fullMatches[0], candidates: [], confidence: 0.98, failureHint: nil)
        }
        if fullMatches.count > 1 {
            return PlayerResolution(status: .ambiguousPlayer, player: nil, candidates: fullMatches, confidence: 0.60, failureHint: "fullNameAmbiguous")
        }

        let surnameMatches = roster.filter { normalize($0.lastName) == reference }
        if surnameMatches.count == 1 {
            return PlayerResolution(status: .success, player: surnameMatches[0], candidates: [], confidence: 0.95, failureHint: nil)
        }
        if surnameMatches.count > 1 {
            return PlayerResolution(status: .ambiguousPlayer, player: nil, candidates: surnameMatches, confidence: 0.62, failureHint: "surnameAmbiguous")
        }

        let firstMatches = roster.filter { normalize($0.firstName) == reference }
        if firstMatches.count == 1 {
            return PlayerResolution(status: .success, player: firstMatches[0], candidates: [], confidence: 0.91, failureHint: nil)
        }
        if firstMatches.count > 1 {
            return PlayerResolution(status: .ambiguousPlayer, player: nil, candidates: firstMatches, confidence: 0.60, failureHint: "firstNameAmbiguous")
        }

        let fuzzy = fuzzyResolve(reference: reference, roster: roster)
        switch fuzzy {
        case .none:
            return PlayerResolution(status: .noPlayerFound, player: nil, candidates: [], confidence: 0, failureHint: "fuzzyNoMatch")
        case .ambiguous(let candidates):
            return PlayerResolution(status: .ambiguousPlayer, player: nil, candidates: candidates, confidence: 0.70, failureHint: "fuzzyAmbiguous")
        case .single(let player, let confidence):
            return PlayerResolution(status: .success, player: player, candidates: [], confidence: confidence, failureHint: nil)
        }
    }

    private enum FuzzyResult {
        case none
        case single(VoiceRosterPlayer, Double)
        case ambiguous([VoiceRosterPlayer])
    }

    private func fuzzyResolve(reference: String, roster: [VoiceRosterPlayer]) -> FuzzyResult {
        let scored: [(VoiceRosterPlayer, Double)] = roster.map { player in
            let full = similarity(reference, normalize(player.fullName))
            let surname = similarity(reference, normalize(player.lastName))
            let first = similarity(reference, normalize(player.firstName))
            let best = max(full, surname, first)
            return (player, best)
        }.sorted { $0.1 > $1.1 }

        guard let best = scored.first, best.1 >= 0.86 else { return .none }
        let second = scored.dropFirst().first?.1 ?? 0
        if best.1 - second < 0.07 {
            return .ambiguous(scored.filter { $0.1 >= best.1 - 0.03 }.map { $0.0 })
        }

        let confidence = min(max(best.1, 0.80), 0.88)
        return .single(best.0, confidence)
    }

    private func fuzzyPhraseScore(in tokens: [String], phraseTokens: [String]) -> Double? {
        guard !phraseTokens.isEmpty, phraseTokens.count <= tokens.count else { return nil }
        var best: Double = 0
        for start in 0...(tokens.count - phraseTokens.count) {
            let window = Array(tokens[start..<(start + phraseTokens.count)])
            let pairScore = zip(window, phraseTokens).map { similarity($0, $1) }
            let score = pairScore.reduce(0, +) / Double(pairScore.count)
            best = max(best, score)
        }
        return best
    }

    private func similarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let distance = levenshtein(a, b)
        let maxLen = max(a.count, b.count)
        return 1.0 - (Double(distance) / Double(maxLen))
    }

    private func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        var dist = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)

        for i in 0...a.count { dist[i][0] = i }
        for j in 0...b.count { dist[0][j] = j }

        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                dist[i][j] = min(
                    dist[i - 1][j] + 1,
                    dist[i][j - 1] + 1,
                    dist[i - 1][j - 1] + cost
                )
            }
        }

        return dist[a.count][b.count]
    }

    private func containsPhrase(tokens: [String], phraseTokens: [String]) -> Bool {
        guard !phraseTokens.isEmpty, phraseTokens.count <= tokens.count else { return false }
        for start in 0...(tokens.count - phraseTokens.count) {
            if Array(tokens[start..<(start + phraseTokens.count)]) == phraseTokens {
                return true
            }
        }
        return false
    }

    private func playerReferenceText(byRemoving alias: String, from transcript: String) -> String {
        guard !alias.isEmpty, let range = transcript.range(of: alias) else { return transcript }
        let removed = transcript.replacingCharacters(in: range, with: " ")
        return normalize(removed)
    }

    private func diagnosticsText(
        raw: String,
        normalized: String,
        statCandidates: [String],
        playerCandidates: [String],
        matchedStat: String?,
        matchedPlayer: String?,
        confidence: Double,
        failure: String?
    ) -> String {
        [
            "Raw: \(raw)",
            "Normalized: \(normalized)",
            "Stat candidates: \(statCandidates.joined(separator: ", "))",
            "Player candidates: \(playerCandidates.joined(separator: ", "))",
            "Matched stat: \(matchedStat ?? "none")",
            "Matched player: \(matchedPlayer ?? "none")",
            "Confidence: \(String(format: "%.2f", confidence))",
            "Failure: \(failure ?? "none")"
        ].joined(separator: " | ")
    }

    private func makeResult(
        raw: String,
        normalized: String,
        status: VoiceParseStatus,
        failure: String? = nil,
        confidence: Double,
        matchedStat: VoiceStatTypeDescriptor? = nil,
        matchedPlayer: VoiceRosterPlayer? = nil,
        candidatePlayerNames: [String] = [],
        candidatePlayerIds: [UUID] = [],
        candidateStatNames: [String] = [],
        candidateStatIds: [UUID] = [],
        bestGuessStatId: UUID? = nil,
        bestGuessPlayerId: UUID? = nil,
        diagnostics: String
    ) -> VoiceParseResult {
        VoiceParseResult(
            rawTranscript: raw,
            normalizedTranscript: normalized,
            matchedStatTypeId: matchedStat?.id,
            matchedPlayerId: matchedPlayer?.id,
            matchedStatName: matchedStat?.canonicalName,
            matchedPlayerName: matchedPlayer?.fullName,
            parseStatus: status,
            confidence: confidence,
            failureReason: failure,
            candidatePlayerIds: candidatePlayerIds,
            candidatePlayerNames: candidatePlayerNames,
            candidateStatTypeIds: candidateStatIds,
            candidateStatNames: candidateStatNames,
            bestGuessStatTypeId: bestGuessStatId,
            bestGuessPlayerId: bestGuessPlayerId,
            debugLog: diagnostics
        )
    }
}

@MainActor
final class PressHoldSpeechService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var liveTranscript = ""
    @Published private(set) var lastErrorMessage: String?

    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_AU"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    func startListening(vocabulary: [String]) {
        guard !isRecording else { return }
        Task { [weak self] in
            await self?.startListeningAsync(vocabulary: vocabulary)
        }
    }

    func stopListening() -> String {
        let transcript = liveTranscript
        stopListeningInternal()
        return transcript
    }

    private func stopListeningInternal() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
    }

    private func startListeningAsync(vocabulary: [String]) async {
        guard !isRecording else { return }
        lastErrorMessage = nil

        do {
            let status = try await ensureSpeechAuthorization()
            guard status == .authorized else {
                lastErrorMessage = "Speech permission not granted"
                return
            }
        } catch {
            lastErrorMessage = "Speech permission failed"
            return
        }

        guard recognizer != nil else {
            lastErrorMessage = "Speech recognizer unavailable"
            return
        }

        task?.cancel()
        task = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 16, *) {
            request.addsPunctuation = false
        }
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        request.contextualStrings = Array(vocabulary.prefix(400))

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isRecording = true
            liveTranscript = ""
            self.request = request
            task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    self.liveTranscript = result.bestTranscription.formattedString
                }
                if error != nil {
                    self.stopListeningInternal()
                }
            }
        } catch {
            lastErrorMessage = "Could not start microphone"
            stopListeningInternal()
        }
    }

    private func ensureSpeechAuthorization() async throws -> SFSpeechRecognizerAuthorizationStatus {
        if authorizationStatus == .authorized { return .authorized }
        if authorizationStatus == .denied || authorizationStatus == .restricted { return authorizationStatus }

        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        authorizationStatus = status
        return status
    }
}

struct StatsEventCreationService {
    static func makeVoiceEvent(
        sessionId: UUID,
        playerId: UUID,
        statTypeId: UUID,
        quarter: String,
        transcript: String,
        normalizedTranscript: String,
        confidence: Double
    ) -> StatEvent {
        StatEvent(
            sessionId: sessionId,
            playerId: playerId,
            statTypeId: statTypeId,
            quarter: quarter,
            sourceRaw: StatsEventSource.voice.rawValue,
            transcript: transcript,
            normalizedTranscript: normalizedTranscript,
            parserConfidence: confidence
        )
    }
}
