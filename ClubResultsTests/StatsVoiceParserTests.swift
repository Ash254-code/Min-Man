import Testing
@testable import ClubResults

struct StatsVoiceParserTests {
    private let parser = StatsVoiceParser()

    private var statTypes: [VoiceStatTypeDescriptor] {
        [
            VoiceStatTypeDescriptor(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, canonicalName: "Kick", aliases: ["kick", "kicks"]),
            VoiceStatTypeDescriptor(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, canonicalName: "Handball", aliases: ["handball", "hand ball", "handpass", "hand pass"]),
            VoiceStatTypeDescriptor(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, canonicalName: "Goal", aliases: ["goal", "goals"]),
            VoiceStatTypeDescriptor(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, canonicalName: "Tackle", aliases: ["tackle", "tackles"])
        ]
    }

    private var roster: [VoiceRosterPlayer] {
        [
            VoiceRosterPlayer(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, number: 7, firstName: "Joe", lastName: "Bloggs", fullName: "Joe Bloggs"),
            VoiceRosterPlayer(id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!, number: 4, firstName: "Jack", lastName: "Smith", fullName: "Jack Smith"),
            VoiceRosterPlayer(id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!, number: 8, firstName: "John", lastName: "Smith", fullName: "John Smith"),
            VoiceRosterPlayer(id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!, number: 12, firstName: "John", lastName: "Taylor", fullName: "John Taylor")
        ]
    }

    @Test func parsesKickNumberForms() {
        let r1 = parser.parse(transcript: "kick 7", statTypes: statTypes, roster: roster)
        #expect(r1.parseStatus == .success)

        let r2 = parser.parse(transcript: "kick number 7", statTypes: statTypes, roster: roster)
        #expect(r2.parseStatus == .success)
    }

    @Test func parsesFullAndSurnameAndAlias() {
        #expect(parser.parse(transcript: "kick joe bloggs", statTypes: statTypes, roster: roster).parseStatus == .success)
        #expect(parser.parse(transcript: "kick bloggs", statTypes: statTypes, roster: roster).parseStatus == .success)
        #expect(parser.parse(transcript: "handball smith", statTypes: statTypes, roster: roster).parseStatus == .ambiguousPlayer)
        #expect(parser.parse(transcript: "hand ball 7", statTypes: statTypes, roster: roster).parseStatus == .success)
    }

    @Test func parsesGoalByNumberAndPlayerFirstStatLast() {
        #expect(parser.parse(transcript: "goal 4", statTypes: statTypes, roster: roster).parseStatus == .success)
        #expect(parser.parse(transcript: "bloggs kick", statTypes: statTypes, roster: roster).parseStatus == .success)
    }

    @Test func handlesAmbiguousAndFailures() {
        #expect(parser.parse(transcript: "kick smith", statTypes: statTypes, roster: roster).parseStatus == .ambiguousPlayer)
        #expect(parser.parse(transcript: "john kick", statTypes: statTypes, roster: roster).parseStatus == .ambiguousPlayer)
        #expect(parser.parse(transcript: "7", statTypes: statTypes, roster: roster).parseStatus == .noStatFound)
        #expect(parser.parse(transcript: "kick", statTypes: statTypes, roster: roster).parseStatus == .noPlayerFound)
        #expect(parser.parse(transcript: "banana 7", statTypes: statTypes, roster: roster).parseStatus == .noStatFound)
        #expect(parser.parse(transcript: "tackle 99", statTypes: statTypes, roster: roster).parseStatus == .noPlayerFound)
        #expect(parser.parse(transcript: "", statTypes: statTypes, roster: roster).parseStatus == .emptyTranscript)
    }

    @Test func resolvesConservativeFuzzyName() {
        let result = parser.parse(transcript: "kick blogs", statTypes: statTypes, roster: roster)
        #expect(result.parseStatus == .lowConfidence || result.parseStatus == .success)
    }
}
