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
    let parseStatus: VoiceParseStatus
    let confidence: Double
    let failureReason: String?
    let candidatePlayerIds: [UUID]
    let candidateStatTypeIds: [UUID]
    let detectedStatCandidates: [String]
    let detectedPlayerCandidates: [String]
    let matchedStatName: String?
    let matchedPlayerName: String?
    let shouldOfferReview: Bool
}

struct StatsVoiceParser {
    private let minConfidence: Double = 0.86
    private let reviewConfidence: Double = 0.74

    func parse(
        transcript rawTranscript: String,
        statTypes: [VoiceStatTypeDescriptor],
        roster: [VoiceRosterPlayer]
    ) -> VoiceParseResult {
        let normalizedTranscript = normalize(rawTranscript)
        guard !normalizedTranscript.isEmpty else {
            return VoiceParseResult(
                rawTranscript: rawTranscript,
                normalizedTranscript: normalizedTranscript,
                matchedStatTypeId: nil,
                matchedPlayerId: nil,
                parseStatus: .emptyTranscript,
                confidence: 0,
                failureReason: "empty transcript",
                candidatePlayerIds: [],
                candidateStatTypeIds: [],
                detectedStatCandidates: [],
                detectedPlayerCandidates: [],
                matchedStatName: nil,
                matchedPlayerName: nil,
                shouldOfferReview: false
            )
        }

        guard let statMatch = matchStatType(in: normalizedTranscript, statTypes: statTypes) else {
            return VoiceParseResult(
                rawTranscript: rawTranscript,
                normalizedTranscript: normalizedTranscript,
                matchedStatTypeId: nil,
                matchedPlayerId: nil,
                parseStatus: .noStatFound,
                confidence: 0,
                failureReason: "stat type not recognised",
                candidatePlayerIds: [],
                candidateStatTypeIds: [],
                detectedStatCandidates: [],
                detectedPlayerCandidates: [],
                matchedStatName: nil,
                matchedPlayerName: nil,
                shouldOfferReview: false
            )
        }

        if statMatch.isAmbiguous {
            return VoiceParseResult(
                rawTranscript: rawTranscript,
                normalizedTranscript: normalizedTranscript,
                matchedStatTypeId: nil,
                matchedPlayerId: nil,
                parseStatus: .ambiguousStat,
                confidence: statMatch.confidence,
                failureReason: "multiple stat types matched",
                candidatePlayerIds: [],
                candidateStatTypeIds: statMatch.candidateStatIds,
                detectedStatCandidates: statMatch.detectedAliases,
                detectedPlayerCandidates: [],
                matchedStatName: nil,
                matchedPlayerName: nil,
                shouldOfferReview: false
            )
        }

        let remaining = removePhrase(statMatch.aliasUsed, from: normalizedTranscript)
        let playerResolution = resolvePlayer(reference: remaining, roster: roster)

        switch playerResolution.status {
        case .success:
            let combined = min(statMatch.confidence, playerResolution.confidence)
            guard combined >= minConfidence, let matchedPlayerId = playerResolution.player?.id else {
                return VoiceParseResult(
                    rawTranscript: rawTranscript,
                    normalizedTranscript: normalizedTranscript,
                    matchedStatTypeId: statMatch.statType?.id,
                    matchedPlayerId: nil,
                    parseStatus: .lowConfidence,
                    confidence: combined,
                    failureReason: "could not confidently interpret command",
                    candidatePlayerIds: playerResolution.candidates.map(\.id),
                    candidateStatTypeIds: [],
                    detectedStatCandidates: statMatch.detectedAliases,
                    detectedPlayerCandidates: playerResolution.candidates.map(\.fullName),
                    matchedStatName: statMatch.statType?.canonicalName,
                    matchedPlayerName: playerResolution.player?.fullName,
                    shouldOfferReview: playerResolution.player != nil && combined >= reviewConfidence
                )
            }

            return VoiceParseResult(
                rawTranscript: rawTranscript,
                normalizedTranscript: normalizedTranscript,
                matchedStatTypeId: statMatch.statType?.id,
                matchedPlayerId: matchedPlayerId,
                parseStatus: .success,
                confidence: combined,
                failureReason: nil,
                candidatePlayerIds: [],
                candidateStatTypeIds: [],
                detectedStatCandidates: statMatch.detectedAliases,
                detectedPlayerCandidates: playerResolution.player.map { [$0.fullName] } ?? [],
                matchedStatName: statMatch.statType?.canonicalName,
                matchedPlayerName: playerResolution.player?.fullName,
                shouldOfferReview: false
            )
        case .noPlayerFound:
            let likelyReview = playerResolution.player != nil && min(statMatch.confidence, playerResolution.confidence) >= reviewConfidence
            return VoiceParseResult(
                rawTranscript: rawTranscript,
                normalizedTranscript: normalizedTranscript,
                matchedStatTypeId: statMatch.statType?.id,
                matchedPlayerId: nil,
                parseStatus: .noPlayerFound,
                confidence: statMatch.confidence,
                failureReason: "player not found",
                candidatePlayerIds: [],
                candidateStatTypeIds: [],
                detectedStatCandidates: statMatch.detectedAliases,
                detectedPlayerCandidates: playerResolution.candidates.map(\.fullName),
                matchedStatName: statMatch.statType?.canonicalName,
                matchedPlayerName: playerResolution.player?.fullName,
                shouldOfferReview: likelyReview
            )
        case .ambiguousPlayer:
            return VoiceParseResult(
                rawTranscript: rawTranscript,
                normalizedTranscript: normalizedTranscript,
                matchedStatTypeId: statMatch.statType?.id,
                matchedPlayerId: nil,
                parseStatus: .ambiguousPlayer,
                confidence: min(statMatch.confidence, playerResolution.confidence),
                failureReason: "multiple players match",
                candidatePlayerIds: playerResolution.candidates.map(\.id),
                candidateStatTypeIds: [],
                detectedStatCandidates: statMatch.detectedAliases,
                detectedPlayerCandidates: playerResolution.candidates.map(\.fullName),
                matchedStatName: statMatch.statType?.canonicalName,
                matchedPlayerName: nil,
                shouldOfferReview: false
            )
        }
    }

    func normalize(_ raw: String) -> String {
        let lowered = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty else { return "" }

        var working = lowered
            .replacingOccurrences(of: "no.", with: "number")
            .replacingOccurrences(of: "#", with: " number ")

        working = working.replacingOccurrences(
            of: "[^a-z0-9\\s]",
            with: " ",
            options: .regularExpression
        )

        let fillers: Set<String> = ["um", "uh", "please", "thanks", "thank", "you"]
        let tokens = working.split(separator: " ").map(String.init).filter { !fillers.contains($0) }

        var converted: [String] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if (token == "number" || token == "no"), index + 1 < tokens.count {
                if let value = parseSpokenNumber(tokens: Array(tokens[(index + 1)...])) {
                    converted.append(String(value.number))
                    index = index + 1 + value.consumed
                    continue
                }
                converted.append(tokens[index + 1])
                index += 2
                continue
            }
            if let value = parseSpokenNumber(tokens: Array(tokens[index...])) {
                converted.append(String(value.number))
                index += value.consumed
                continue
            }
            converted.append(token)
            index += 1
        }

        return converted.joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let wordToNumber: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30,
        "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
        "eighty": 80, "ninety": 90
    ]
    private let connectorWords: Set<String> = ["to", "for", "by", "on", "at", "with", "from"]

    private func parseSpokenNumber(tokens: [String]) -> (number: Int, consumed: Int)? {
        guard let first = tokens.first else { return nil }
        if let direct = Int(first) {
            return (direct, 1)
        }
        guard let firstValue = wordToNumber[first] else { return nil }
        if firstValue >= 20, firstValue % 10 == 0, tokens.count > 1, let second = wordToNumber[tokens[1]], second < 10 {
            return (firstValue + second, 2)
        }
        return (firstValue, 1)
    }

    private struct StatMatch {
        let statType: VoiceStatTypeDescriptor?
        let aliasUsed: String
        let confidence: Double
        let candidateStatIds: [UUID]
        let isAmbiguous: Bool
        let detectedAliases: [String]
    }

    private func matchStatType(in transcript: String, statTypes: [VoiceStatTypeDescriptor]) -> StatMatch? {
        let tokens = transcript.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return nil }

        var candidates: [(VoiceStatTypeDescriptor, String, Double)] = []
        var fuzzyCandidates: [(VoiceStatTypeDescriptor, String, Double)] = []
        for stat in statTypes {
            for alias in stat.aliases {
                let normalizedAlias = normalize(alias)
                guard !normalizedAlias.isEmpty else { continue }
                let aliasTokens = normalizedAlias.split(separator: " ").map(String.init)
                if containsPhrase(tokens: tokens, phraseTokens: aliasTokens) {
                    let confidence = normalizedAlias == normalize(stat.canonicalName) ? 1.0 : 0.95
                    candidates.append((stat, normalizedAlias, confidence))
                } else if aliasTokens.count == 1 {
                    for token in tokens {
                        let score = similarity(token, normalizedAlias)
                        if score >= 0.84 {
                            fuzzyCandidates.append((stat, normalizedAlias, min(0.82, score)))
                        }
                    }
                }
            }
        }

        if candidates.isEmpty {
            candidates = fuzzyCandidates
        }
        guard !candidates.isEmpty else { return nil }

        let sorted = candidates.sorted {
            let lhsLen = $0.1.split(separator: " ").count
            let rhsLen = $1.1.split(separator: " ").count
            if lhsLen != rhsLen { return lhsLen > rhsLen }
            if $0.2 != $1.2 { return $0.2 > $1.2 }
            return $0.0.canonicalName < $1.0.canonicalName
        }

        guard let best = sorted.first else { return nil }
        let sameTier = sorted.filter {
            $0.1.split(separator: " ").count == best.1.split(separator: " ").count && abs($0.2 - best.2) < 0.001
        }
        let uniqueStatIds = Array(Set(sameTier.map { $0.0.id }))
        if uniqueStatIds.count > 1 {
            return StatMatch(
                statType: nil,
                aliasUsed: "",
                confidence: best.2,
                candidateStatIds: uniqueStatIds,
                isAmbiguous: true,
                detectedAliases: sorted.map(\.1)
            )
        }

        return StatMatch(
            statType: best.0,
            aliasUsed: best.1,
            confidence: best.2,
            candidateStatIds: [],
            isAmbiguous: false,
            detectedAliases: sorted.map(\.1)
        )
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
    }

    private func resolvePlayer(reference rawReference: String, roster: [VoiceRosterPlayer]) -> PlayerResolution {
        let reference = normalize(rawReference)
        guard !reference.isEmpty else {
            return PlayerResolution(status: .noPlayerFound, player: nil, candidates: [], confidence: 0)
        }

        let cleaned = reference.split(separator: " ").map(String.init).filter { !connectorWords.contains($0) }.joined(separator: " ")
        let numbers = cleaned.split(separator: " ").compactMap { Int($0) }
        if let number = numbers.first {
            let matches = roster.filter { $0.number == number }
            if matches.count == 1 {
                return PlayerResolution(status: .success, player: matches[0], candidates: [], confidence: 1.0)
            }
            return PlayerResolution(status: .noPlayerFound, player: nil, candidates: [], confidence: 0)
        }

        let normalized = cleaned
        let fullMatches = roster.filter { normalize($0.fullName) == normalized }
        if fullMatches.count == 1 {
            return PlayerResolution(status: .success, player: fullMatches[0], candidates: [], confidence: 0.98)
        }
        if fullMatches.count > 1 {
            return PlayerResolution(status: .ambiguousPlayer, player: nil, candidates: fullMatches, confidence: 0.6)
        }

        let surnameMatches = roster.filter { normalize($0.lastName) == normalized }
        if surnameMatches.count == 1 {
            return PlayerResolution(status: .success, player: surnameMatches[0], candidates: [], confidence: 0.95)
        }
        if surnameMatches.count > 1 {
            return PlayerResolution(status: .ambiguousPlayer, player: nil, candidates: surnameMatches, confidence: 0.6)
        }

        let firstMatches = roster.filter { normalize($0.firstName) == normalized }
        if firstMatches.count == 1 {
            return PlayerResolution(status: .success, player: firstMatches[0], candidates: [], confidence: 0.90)
        }
        if firstMatches.count > 1 {
            return PlayerResolution(status: .ambiguousPlayer, player: nil, candidates: firstMatches, confidence: 0.6)
        }

        let fuzzy = fuzzyResolve(reference: normalized, roster: roster)
        switch fuzzy {
        case .none:
            return PlayerResolution(status: .noPlayerFound, player: nil, candidates: [], confidence: 0)
        case .ambiguous(let candidates):
            return PlayerResolution(status: .ambiguousPlayer, player: nil, candidates: candidates, confidence: 0.7)
        case .single(let player, let confidence):
            return PlayerResolution(status: .success, player: player, candidates: [], confidence: confidence)
        }
    }

    private enum FuzzyResult {
        case none
        case single(VoiceRosterPlayer, Double)
        case ambiguous([VoiceRosterPlayer])
    }

    private func fuzzyResolve(reference: String, roster: [VoiceRosterPlayer]) -> FuzzyResult {
        let scored: [(VoiceRosterPlayer, Double, String)] = roster.map { player in
            let full = similarity(reference, normalize(player.fullName))
            let surname = similarity(reference, normalize(player.lastName))
            let first = similarity(reference, normalize(player.firstName))
            if surname >= full, surname >= first {
                return (player, surname, "surname")
            }
            if first >= full {
                return (player, first, "first")
            }
            return (player, full, "full")
        }.sorted { $0.1 > $1.1 }

        guard let best = scored.first, best.1 >= 0.88 else { return .none }
        let secondScore = scored.dropFirst().first?.1 ?? 0
        if best.1 - secondScore < 0.08 {
            return .ambiguous(scored.filter { $0.1 >= best.1 - 0.05 }.map { $0.0 })
        }
        let confidenceFloor: Double = best.2 == "surname" ? 0.80 : 0.74
        let confidenceCap: Double = best.2 == "surname" ? 0.88 : 0.82
        let confidence = min(max(best.1, confidenceFloor), confidenceCap)
        return .single(best.0, confidence)
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

    private func removePhrase(_ phrase: String, from transcript: String) -> String {
        guard !phrase.isEmpty else { return transcript }
        let range = transcript.range(of: phrase)
        guard let range else { return transcript }
        let removed = transcript.replacingCharacters(in: range, with: " ")
        return normalize(removed)
    }
}

@MainActor
final class PressHoldSpeechService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var liveTranscript = ""
    @Published private(set) var finalTranscript = ""
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
        let transcript = finalTranscript.isEmpty ? liveTranscript : finalTranscript
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
        guard recognizer?.isAvailable == true else {
            lastErrorMessage = "Speech recognizer is not currently available"
            return
        }
#if targetEnvironment(simulator)
        lastErrorMessage = "Speech recognition testing must run on a real device"
        return
#endif

        task?.cancel()
        task = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = false
        let seedVocabulary = ["kick", "handball", "mark", "tackle", "goal", "behind"]
        let expandedContext = Array(Set(seedVocabulary + vocabulary + vocabulary.flatMap { $0.split(separator: " ").map(String.init) }))
        request.contextualStrings = Array(expandedContext.prefix(400))

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
            finalTranscript = ""
            self.request = request
            task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    if result.isFinal {
                        let transcript = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.liveTranscript = transcript
                        self.finalTranscript = transcript
                        print("Heard: \(transcript)")
                    }
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
