import Testing
@testable import ClubResults

struct StatsVoiceParserTests {
    private let parser = StatsVoiceParser()

    private var statTypes: [VoiceStatTypeDescriptor] {
        [
            VoiceStatTypeDescriptor(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, canonicalName: "Kick", aliases: ["kick", "kicks"]),
            VoiceStatTypeDescriptor(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, canonicalName: "Handball", aliases: ["handball", "hand ball", "handpass", "hand pass"]),
            VoiceStatTypeDescriptor(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, canonicalName: "Mark", aliases: ["mark", "marks"]),
            VoiceStatTypeDescriptor(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, canonicalName: "Goal", aliases: ["goal", "goals"]),
            VoiceStatTypeDescriptor(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, canonicalName: "Tackle", aliases: ["tackle", "tackles"]),
            VoiceStatTypeDescriptor(id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!, canonicalName: "Behind", aliases: ["behind", "point", "rushed behind"])
        ]
    }

    private var roster: [VoiceRosterPlayer] {
        [
            VoiceRosterPlayer(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, number: 7, firstName: "Joe", lastName: "Bloggs", fullName: "Joe Bloggs"),
            VoiceRosterPlayer(id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!, number: 4, firstName: "Jack", lastName: "Smith", fullName: "Jack Smith"),
            VoiceRosterPlayer(id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!, number: 8, firstName: "John", lastName: "Smith", fullName: "John Smith"),
            VoiceRosterPlayer(id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!, number: 12, firstName: "John", lastName: "Taylor", fullName: "John Taylor"),
            VoiceRosterPlayer(id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!, number: 20, firstName: "Liam", lastName: "McShane", fullName: "Liam McShane")
        ]
    }

    @Test func parsesStatVariantsAndNaturalPhrases() {
        let r1 = parser.parse(transcript: "kick 7", statTypes: statTypes, roster: roster)
        #expect(r1.parseStatus == .success)

        #expect(parser.parse(transcript: "kicks 7", statTypes: statTypes, roster: roster).parseStatus == .success)
        #expect(parser.parse(transcript: "handball 12", statTypes: statTypes, roster: roster).parseStatus == .success)
        #expect(parser.parse(transcript: "hand ball 7", statTypes: statTypes, roster: roster).parseStatus == .success)
        #expect(parser.parse(transcript: "handpass 12", statTypes: statTypes, roster: roster).parseStatus == .success)
        #expect(parser.parse(transcript: "mark smith", statTypes: statTypes, roster: roster).parseStatus == .ambiguousPlayer)
        #expect(parser.parse(transcript: "goal 4", statTypes: statTypes, roster: roster).parseStatus == .success)
        #expect(parser.parse(transcript: "point 7", statTypes: statTypes, roster: roster).parseStatus == .success)
        #expect(parser.parse(transcript: "kick to 7", statTypes: statTypes, roster: roster).parseStatus == .success)
        #expect(parser.parse(transcript: "kick for 7", statTypes: statTypes, roster: roster).parseStatus == .success)
        #expect(parser.parse(transcript: "mark by bloggs", statTypes: statTypes, roster: roster).parseStatus == .success)
        #expect(parser.parse(transcript: "handball by joe", statTypes: statTypes, roster: roster).parseStatus == .success)
    }

    @Test func parsesNumberFormsAndSpokenNumbers() {
        #expect(parser.parse(transcript: "kick number 7", statTypes: statTypes, roster: roster).parseStatus == .success)
        #expect(parser.parse(transcript: "kick no 7", statTypes: statTypes, roster: roster).parseStatus == .success)
        #expect(parser.parse(transcript: "kick number seven", statTypes: statTypes, roster: roster).parseStatus == .success)
        #expect(parser.parse(transcript: "kick twenty", statTypes: statTypes, roster: roster).parseStatus == .success)
    }

    @Test func parsesFullNameSurnameFirstNameAndPlayerFirstStatLast() {
        #expect(parser.parse(transcript: "kick joe bloggs", statTypes: statTypes, roster: roster).parseStatus == .success)
        #expect(parser.parse(transcript: "kick bloggs", statTypes: statTypes, roster: roster).parseStatus == .success)
        #expect(parser.parse(transcript: "kick joe", statTypes: statTypes, roster: roster).parseStatus == .success)
        #expect(parser.parse(transcript: "bloggs kick", statTypes: statTypes, roster: roster).parseStatus == .success)
        #expect(parser.parse(transcript: "joe kick", statTypes: statTypes, roster: roster).parseStatus == .success)
    }

    @Test func handlesFuzzyVariantsConservatively() {
        let blogs = parser.parse(transcript: "kick blogs", statTypes: statTypes, roster: roster)
        #expect(blogs.parseStatus == .success || blogs.parseStatus == .lowConfidence)

        let mcshane = parser.parse(transcript: "kick macshane", statTypes: statTypes, roster: roster)
        #expect(mcshane.parseStatus == .success || mcshane.parseStatus == .lowConfidence)
    }

    @Test func handlesAmbiguousAndFailures() {
        #expect(parser.parse(transcript: "kick smith", statTypes: statTypes, roster: roster).parseStatus == .ambiguousPlayer)
        #expect(parser.parse(transcript: "kick john", statTypes: statTypes, roster: roster).parseStatus == .ambiguousPlayer)
        #expect(parser.parse(transcript: "john kick", statTypes: statTypes, roster: roster).parseStatus == .ambiguousPlayer)
        #expect(parser.parse(transcript: "handball smith", statTypes: statTypes, roster: roster).parseStatus == .ambiguousPlayer)
        #expect(parser.parse(transcript: "7", statTypes: statTypes, roster: roster).parseStatus == .noStatFound)
        #expect(parser.parse(transcript: "kick", statTypes: statTypes, roster: roster).parseStatus == .noPlayerFound)
        #expect(parser.parse(transcript: "banana 7", statTypes: statTypes, roster: roster).parseStatus == .noStatFound)
        #expect(parser.parse(transcript: "tackle 99", statTypes: statTypes, roster: roster).parseStatus == .noPlayerFound)
        #expect(parser.parse(transcript: "", statTypes: statTypes, roster: roster).parseStatus == .emptyTranscript)
    }

    @Test func normalizesFillersAndPunctuation() {
        let result = parser.parse(transcript: "Um, please... hand ball no twelve!", statTypes: statTypes, roster: roster)
        #expect(result.parseStatus == .success)
    }
}
