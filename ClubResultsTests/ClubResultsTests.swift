//
//  ClubResultsTests.swift
//  ClubResultsTests
//
//  Created by Ashley Williams on 11/2/2026.
//

import Testing
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
        #expect(decoded.allowsLiveGameView == false)
        #expect(decoded.quarterLengthMinutes == 20)
    }

}
