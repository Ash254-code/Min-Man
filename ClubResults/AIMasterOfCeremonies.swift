import SwiftUI
import AVFoundation
import Security
internal import Combine

enum AIMCStorageKeys {
    static let elevenLabsVoiceID = "aimc.settings.elevenLabsVoiceID"
    static let includeWeather = "aimc.pres.includeWeather"
    static let includeKeyPoints = "aimc.pres.includeKeyPoints"
    static let includeAnnouncements = "aimc.pres.includeAnnouncements"
    static let includeDates = "aimc.pres.includeDates"
    static let includeSectionHeaders = "aimc.pres.includeSectionHeaders"
    static let keyPoints = "aimc.pres.keyPoints"
    static let announcementGradeID = "aimc.pres.announcementGradeID"
}

enum AIMCSecrets {
    static let elevenLabsAPIKey = "aimc.secrets.elevenlabs.apiKey"
}

enum AIMCKeychainStore {
    static func loadSecret(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func saveSecret(_ value: String, for key: String) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            deleteSecret(for: key)
            return
        }

        let data = Data(cleaned.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertQuery = query
            insertQuery[kSecValueData as String] = data
            SecItemAdd(insertQuery as CFDictionary, nil)
        }
    }

    static func deleteSecret(for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct ElevenLabsTTSService {
    enum ElevenLabsError: LocalizedError {
        case invalidResponse
        case badStatusCode(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response from ElevenLabs."
            case .badStatusCode(let code, let body):
                return "ElevenLabs returned status code \(code): \(body)"
            }
        }
    }

    func requestSpeechAudio(text: String, apiKey: String, voiceID: String) async throws -> Data {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedVoiceID = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty, !cleanedVoiceID.isEmpty else { return Data() }

        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(cleanedVoiceID)") else {
            throw ElevenLabsError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.httpBody = try JSONEncoder().encode([
            "text": cleanedText,
            "model_id": "eleven_multilingual_v2"
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unable to decode response body (\(data.count) bytes)."
            print("❌ ElevenLabs API error. Status: \(httpResponse.statusCode). Body: \(errorBody)")
            throw ElevenLabsError.badStatusCode(httpResponse.statusCode, errorBody)
        }
        return data
    }
}

@MainActor
final class AIMCNarrator: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isSpeaking = false
    @Published var isPaused = false

    private let ttsService = ElevenLabsTTSService()
    private var audioPlayer: AVAudioPlayer?

    func speakApprovedReport(text: String, apiKey: String, voiceID: String) async throws {
        stop()
        isPaused = false
        let audioData = try await ttsService.requestSpeechAudio(text: text, apiKey: apiKey, voiceID: voiceID)
        guard !audioData.isEmpty else { return }

        let player = try AVAudioPlayer(data: audioData)
        player.delegate = self
        audioPlayer = player
        isSpeaking = true
        player.play()
    }

    func stop() {
        guard let audioPlayer else { return }
        audioPlayer.stop()
        self.audioPlayer = nil
        isSpeaking = false
        isPaused = false
    }

    func pause() {
        guard let audioPlayer, audioPlayer.isPlaying else { return }
        audioPlayer.pause()
        isPaused = true
    }

    func resume() {
        guard let audioPlayer, isPaused else { return }
        audioPlayer.play()
        isPaused = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        audioPlayer = nil
        isSpeaking = false
        isPaused = false
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        audioPlayer = nil
        isSpeaking = false
        isPaused = false
    }
}

struct AIMasterOfCeremoniesSettingsView: View {
    @AppStorage(AIMCStorageKeys.elevenLabsVoiceID) private var elevenLabsVoiceID = ""
    @State private var elevenLabsAPIKey = ""

    var body: some View {
        Form {
            Section {
                SecureField("API Key", text: $elevenLabsAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: elevenLabsAPIKey) { _, newValue in
                        AIMCKeychainStore.saveSecret(newValue, for: AIMCSecrets.elevenLabsAPIKey)
                    }

                TextField("Voice ID", text: $elevenLabsVoiceID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("ElevenLabs")
            } footer: {
                Text("Your ElevenLabs API key is stored securely in the iOS Keychain.")
            }
        }
        .navigationTitle("AI Master of Ceremonies")
        .onAppear {
            elevenLabsAPIKey = AIMCKeychainStore.loadSecret(for: AIMCSecrets.elevenLabsAPIKey) ?? ""
        }
    }
}
