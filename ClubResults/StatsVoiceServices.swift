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
}

struct StatsVoiceParser {
    private let minConfidence: Double = 0.90

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
                candidateStatTypeIds: []
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
                candidateStatTypeIds: []
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
                candidateStatTypeIds: statMatch.candidateStatIds
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
                    candidateStatTypeIds: []
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
                candidateStatTypeIds: []
            )
        case .noPlayerFound:
            return VoiceParseResult(
                rawTranscript: rawTranscript,
                normalizedTranscript: normalizedTranscript,
                matchedStatTypeId: statMatch.statType?.id,
                matchedPlayerId: nil,
                parseStatus: .noPlayerFound,
                confidence: statMatch.confidence,
                failureReason: "player not found",
                candidatePlayerIds: [],
                candidateStatTypeIds: []
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
                candidateStatTypeIds: []
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
            if token == "number", index + 1 < tokens.count {
                converted.append(tokens[index + 1])
                index += 2
                continue
            }
            if let number = wordToNumber[token] {
                converted.append(String(number))
            } else {
                converted.append(token)
            }
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
        "eighteen": 18, "nineteen": 19, "twenty": 20, "twentyone": 21
    ]

    private struct StatMatch {
        let statType: VoiceStatTypeDescriptor?
        let aliasUsed: String
        let confidence: Double
        let candidateStatIds: [UUID]
        let isAmbiguous: Bool
    }

    private func matchStatType(in transcript: String, statTypes: [VoiceStatTypeDescriptor]) -> StatMatch? {
        let tokens = transcript.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return nil }

        var candidates: [(VoiceStatTypeDescriptor, String, Double)] = []
        for stat in statTypes {
            for alias in stat.aliases {
                let normalizedAlias = normalize(alias)
                guard !normalizedAlias.isEmpty else { continue }
                let aliasTokens = normalizedAlias.split(separator: " ").map(String.init)
                if containsPhrase(tokens: tokens, phraseTokens: aliasTokens) {
                    let confidence = normalizedAlias == normalize(stat.canonicalName) ? 1.0 : 0.95
                    candidates.append((stat, normalizedAlias, confidence))
                }
            }
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
            return StatMatch(statType: nil, aliasUsed: "", confidence: best.2, candidateStatIds: uniqueStatIds, isAmbiguous: true)
        }

        return StatMatch(statType: best.0, aliasUsed: best.1, confidence: best.2, candidateStatIds: [], isAmbiguous: false)
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

        let numbers = reference.split(separator: " ").compactMap { Int($0) }
        if let number = numbers.first {
            let matches = roster.filter { $0.number == number }
            if matches.count == 1 {
                return PlayerResolution(status: .success, player: matches[0], candidates: [], confidence: 1.0)
            }
            return PlayerResolution(status: .noPlayerFound, player: nil, candidates: [], confidence: 0)
        }

        let normalized = reference
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
        let scored: [(VoiceRosterPlayer, Double)] = roster.map { player in
            let full = similarity(reference, normalize(player.fullName))
            let surname = similarity(reference, normalize(player.lastName))
            let first = similarity(reference, normalize(player.firstName))
            return (player, max(full, surname, first))
        }.sorted { $0.1 > $1.1 }

        guard let best = scored.first, best.1 >= 0.88 else { return .none }
        let secondScore = scored.dropFirst().first?.1 ?? 0
        if best.1 - secondScore < 0.08 {
            return .ambiguous(scored.filter { $0.1 >= best.1 - 0.05 }.map { $0.0 })
        }
        let confidence = min(max(best.1, 0.75), 0.88)
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

    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_AU"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    func startListening(vocabulary: [String]) {
        guard !isRecording else { return }

        SFSpeechRecognizer.requestAuthorization { _ in }
        task?.cancel()
        task = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer?.supportsOnDeviceRecognition == true
        request.contextualStrings = vocabulary

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            liveTranscript = ""
            self.request = request
            task = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
                guard let self else { return }
                if let result {
                    self.liveTranscript = result.bestTranscription.formattedString
                }
            }
        } catch {
            stopListeningInternal()
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
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
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
