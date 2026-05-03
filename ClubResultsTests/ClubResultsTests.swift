//
//  ClubResultsTests.swift
//  ClubResultsTests
//
//  Created by Ashley Williams on 11/2/2026.
//

import Testing
import SwiftData
@testable import ClubResults

struct ClubResultsTests {

    @Test func gradeLookupSupportsCommaSeparatedMultiGrades() async throws {
        let a = Grade(name: "A Grade")
        let b = Grade(name: "B Grade")
        let lookup = GradeLookup(grades: [a, b])
        var unknown = Set<String>()

        let ids = lookup.ids(forRawGradeField: "A Grade, B Grade", unknownCollector: &unknown)

        #expect(ids.count == 2)
        #expect(Set(ids) == Set([a.id, b.id]))
        #expect(unknown.isEmpty)
    }

    @Test func gradeLookupSupportsSemicolonSeparatedMultiGrades() async throws {
        let a = Grade(name: "A Grade")
        let u12 = Grade(name: "Under 12's")
        let lookup = GradeLookup(grades: [a, u12])
        var unknown = Set<String>()

        let ids = lookup.ids(forRawGradeField: "A Grade; U12", unknownCollector: &unknown)

        #expect(ids.count == 2)
        #expect(Set(ids) == Set([a.id, u12.id]))
        #expect(unknown.isEmpty)
    }

    @Test func gradeLookupMatchesSmartApostropheAgeGrades() async throws {
        let u14 = Grade(name: "Under 14's")
        let u17 = Grade(name: "Under 17's")
        let lookup = GradeLookup(grades: [u14, u17])
        var unknown = Set<String>()

        let ids = lookup.ids(forRawGradeField: "Under 14’s; Under 17’s", unknownCollector: &unknown)

        #expect(ids.count == 2)
        #expect(Set(ids) == Set([u14.id, u17.id]))
        #expect(unknown.isEmpty)
    }

    @Test func backupEnvelopeDecodeSupportsLegacyMissingMetadataAndSettings() async throws {
        let legacyJSON = """
        {
          "appName": "ClubResults",
          "backupFormatVersion": 1,
          "exportedAt": "2026-02-10T12:34:56Z",
          "itemCounts": {
            "grades": 0,
            "players": 0,
            "games": 0,
            "contacts": 0,
            "reportRecipients": 0,
            "customReportTemplates": 0,
            "staffMembers": 0,
            "staffDefaults": 0
          },
          "payload": {
            "grades": [],
            "players": [],
            "games": [],
            "contacts": [],
            "reportRecipients": [],
            "customReportTemplates": [],
            "staffMembers": [],
            "staffDefaults": [],
            "appSettings": {
              "clubConfiguration": {
                "clubTeam": {
                  "name": "Min Man",
                  "primaryColorHex": "#0D2759",
                  "secondaryColorHex": "#FFD100",
                  "tertiaryColorHex": null,
                  "venues": ["Mintaro"]
                },
                "oppositions": []
              }
            }
          }
        }
        """

        let data = try #require(legacyJSON.data(using: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let envelope = try decoder.decode(AppBackupEnvelope.self, from: data)

        #expect(envelope.appVersion == "unknown")
        #expect(envelope.buildNumber == "unknown")
        #expect(envelope.platform == "unknown")
        #expect(envelope.schemaVersion == 1)
        #expect(envelope.itemCounts.lastStaffSelections == 0)
        #expect(envelope.itemCounts.draftResumeFlags == 0)
        #expect(envelope.payload.appSettings.boundaryUmpireGradeMappings.isEmpty)
        #expect(envelope.payload.appSettings.lastStaffSelections.isEmpty)
        #expect(envelope.payload.appSettings.draftResumeOpenLiveFlags.isEmpty)
        #expect(envelope.payload.appSettings.legacyGradesBackup.isEmpty)
        #expect(envelope.payload.appSettings.legacyContactsBackup.isEmpty)
    }

    @Test func gradeRecordDecodeSupportsLegacyMissingNewFields() async throws {
        let legacyGradeJSON = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "A Grade",
          "isActive": true,
          "displayOrder": 1,
          "asksHeadCoach": true,
          "asksAssistantCoach": true,
          "asksTeamManager": true,
          "asksRunner": true,
          "asksGoalUmpire": true,
          "asksFieldUmpire": true,
          "asksBoundaryUmpire1": true,
          "asksBoundaryUmpire2": true,
          "asksTrainers": true,
          "asksTrainer1": true,
          "asksTrainer2": true,
          "asksTrainer3": false,
          "asksTrainer4": false,
          "asksNotes": true,
          "asksScore": true,
          "asksLiveGameView": true,
          "asksGoalKickers": true,
          "bestPlayersCount": 6
        }
        """

        let data = try #require(legacyGradeJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(GradeRecord.self, from: data)

        #expect(decoded.asksGuestBestFairestVotesScan == false)
        #expect(decoded.guestBestPlayersCount == 3)
        #expect(decoded.allowsLiveGameView == false)
        #expect(decoded.quarterLengthMinutes == 20)
    }

    @Test func playerDuplicateKeyMatchesSurnameAndFirstName() async throws {
        let firstKey = Player.duplicateMatchKey(firstName: " Sam ", lastName: "O'Brien")
        let secondKey = Player.duplicateMatchKey(firstName: "sam", lastName: "o’brien")

        #expect(firstKey == secondKey)
    }

    @Test func mergingDuplicatePlayersPreservesReferencesAndClearsConflictingNumbers() async throws {
        let container = try ModelContainer(
            for: Schema([
                Player.self,
                Game.self,
                StatEvent.self
            ]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let first = Player(
            firstName: "Sam",
            lastName: "Taylor",
            preferredName: "Sammy",
            number: 12,
            gradeIDs: [UUID()],
            isActive: true
        )
        let secondGradeID = UUID()
        let second = Player(
            firstName: "sam",
            lastName: "taylor",
            preferredName: "",
            number: 24,
            gradeIDs: [secondGradeID],
            isActive: false
        )

        let game = Game(
            gradeID: UUID(),
            date: Date(),
            opponent: "Rivals",
            venue: "Ground",
            ourGoals: 0,
            ourBehinds: 0,
            theirGoals: 0,
            theirBehinds: 0,
            goalKickers: [
                GameGoalKickerEntry(playerID: first.id, goals: 2),
                GameGoalKickerEntry(playerID: second.id, goals: 1)
            ],
            bestPlayersRanked: [second.id],
            guestVotesRanked: [GameGuestVoteEntry(rank: 1, playerID: second.id)],
            notes: "Test"
        )
        let event = StatEvent(
            sessionId: UUID(),
            playerId: second.id,
            statTypeId: UUID(),
            quarter: "Q1",
            sourceRaw: "manual"
        )

        context.insert(first)
        context.insert(second)
        context.insert(game)
        context.insert(event)
        try context.save()

        let merged = try PlayerDuplicateService.merge(players: [first, second], modelContext: context)

        let players = try context.fetch(FetchDescriptor<Player>())
        let games = try context.fetch(FetchDescriptor<Game>())
        let events = try context.fetch(FetchDescriptor<StatEvent>())

        #expect(players.count == 1)
        #expect(players.first?.id == merged.id)
        #expect(merged.number == nil)
        #expect(Set(merged.gradeIDs).count == 2)
        #expect(merged.preferredName == "Sammy")
        #expect(games.first?.bestPlayersRanked == [merged.id])
        #expect(games.first?.guestVotesRanked.first?.playerID == merged.id)
        #expect(games.first?.goalKickers.count == 1)
        #expect(games.first?.goalKickers.first?.playerID == merged.id)
        #expect(games.first?.goalKickers.first?.goals == 3)
        #expect(events.first?.playerId == merged.id)
    }

}
