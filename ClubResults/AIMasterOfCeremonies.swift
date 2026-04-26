import SwiftUI
import SwiftData
import AVFoundation

enum AIMCStorageKeys {
    static let selectedTemplateID = "aimc.settings.selectedTemplateID"
    static let selectedAppleVoiceID = "aimc.settings.selectedAppleVoiceID"
    static let preferredVoiceProvider = "aimc.settings.preferredVoiceProvider"
    static let includeWeather = "aimc.pres.includeWeather"
    static let includeKeyPoints = "aimc.pres.includeKeyPoints"
    static let includeAnnouncements = "aimc.pres.includeAnnouncements"
    static let keyPoints = "aimc.pres.keyPoints"
    static let announcementGradeID = "aimc.pres.announcementGradeID"
}

enum AIMCVoiceProvider: String, CaseIterable, Identifiable {
    case apple
    case personal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return "Apple Voices"
        case .personal: return "Personal Voice"
        }
    }
}

struct AIMCAppleVoiceOption: Identifiable {
    let id: String
    let displayName: String
    let locale: String
}

enum AIMCVoiceLibrary {
    static func appleVoices() -> [AIMCAppleVoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted {
                let left = "\($0.name) \($0.language)"
                let right = "\($1.name) \($1.language)"
                return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }
            .map {
                AIMCAppleVoiceOption(
                    id: $0.identifier,
                    displayName: $0.name,
                    locale: Locale.current.localizedString(forIdentifier: $0.language) ?? $0.language
                )
            }
    }
}

@MainActor
final class AIMCNarrator: NSObject, ObservableObject {
    @Published var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(text: String, appleVoiceID: String?) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        if let appleVoiceID,
           let selectedVoice = AVSpeechSynthesisVoice(identifier: appleVoiceID) {
            utterance.voice = selectedVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-AU") ?? AVSpeechSynthesisVoice(language: "en-US")
        }

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}

extension AIMCNarrator: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}

struct AIMasterOfCeremoniesSettingsView: View {
    @Query(sort: [SortDescriptor(\CustomReportTemplate.name)]) private var templates: [CustomReportTemplate]

    @AppStorage(AIMCStorageKeys.selectedTemplateID) private var selectedTemplateID = ""
    @AppStorage(AIMCStorageKeys.selectedAppleVoiceID) private var selectedAppleVoiceID = ""
    @AppStorage(AIMCStorageKeys.preferredVoiceProvider) private var preferredVoiceProviderRaw = AIMCVoiceProvider.apple.rawValue

    private var selectedTemplateName: String {
        templates.first(where: { $0.id.uuidString == selectedTemplateID })?.name ?? "No report selected"
    }

    private var appleVoiceOptions: [AIMCAppleVoiceOption] {
        AIMCVoiceLibrary.appleVoices()
    }

    var body: some View {
        Form {
            Section("AI Master of Ceremonies") {
                Picker("Report", selection: $selectedTemplateID) {
                    Text("None").tag("")
                    ForEach(templates) { template in
                        Text(template.name).tag(template.id.uuidString)
                    }
                }

                Picker("Voice Provider", selection: $preferredVoiceProviderRaw) {
                    ForEach(AIMCVoiceProvider.allCases) { provider in
                        Text(provider.title).tag(provider.rawValue)
                    }
                }

                if preferredVoiceProviderRaw == AIMCVoiceProvider.apple.rawValue {
                    Picker("Apple Voice", selection: $selectedAppleVoiceID) {
                        Text("System Default").tag("")
                        ForEach(appleVoiceOptions) { voice in
                            Text("\(voice.displayName) (\(voice.locale))").tag(voice.id)
                        }
                    }
                }

                Label("Personal Voice selection will be enabled in a future update.", systemImage: "waveform.badge.mic")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Selected report: \(selectedTemplateName). Apple voices are available now.")
            }
        }
        .navigationTitle("AI Master of Ceremonies")
    }
}
