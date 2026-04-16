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

}
