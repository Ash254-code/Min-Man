import Foundation

// MARK: - Import Types

enum CSVImportMode: String, CaseIterable {
    case skipDuplicates
    case updateExisting
    case replaceAll

    var displayName: String {
        switch self {
        case .skipDuplicates: return "Skip duplicates"
        case .updateExisting: return "Update existing"
        case .replaceAll: return "Replace all"
        }
    }
}

struct CSVImportResult {
    let mode: CSVImportMode
    var imported: Int = 0
    var updated: Int = 0
    var skipped: Int = 0
    var errors: [String] = []
    var unknownGradeNames: Set<String> = []

    var prettySummary: String {
        var parts: [String] = []
        parts.append("Mode: \(mode.displayName)")
        parts.append("Imported: \(imported)")
        parts.append("Updated: \(updated)")
        parts.append("Skipped: \(skipped)")

        if !unknownGradeNames.isEmpty {
            let list = unknownGradeNames.sorted().joined(separator: ", ")
            parts.append("Unknown grades: \(list)")
        }

        if !errors.isEmpty {
            let firstFew = errors.prefix(5).joined(separator: "\n• ")
            parts.append("Errors (\(errors.count)):\n• \(firstFew)\(errors.count > 5 ? "\n• …" : "")")
        }

        return parts.joined(separator: "\n")
    }
}

enum CSVImportError: LocalizedError {
    case invalidEncoding
    case emptyFile
    case missingHeaders(expected: String)
    case noValidRows(details: [String]?)
    case saveFailed(String)
    case badRow(line: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "Could not read the CSV text (unsupported encoding). Save as UTF-8 and try again."
        case .emptyFile:
            return "The CSV file is empty."
        case .missingHeaders(let expected):
            return "Missing/unknown headers. Expected columns like: \(expected)"
        case .noValidRows(let details):
            if let d = details, !d.isEmpty {
                return "No valid rows were found.\n\n\(d.prefix(5).joined(separator: "\n"))"
            }
            return "No valid rows were found."
        case .saveFailed(let msg):
            return "Import parsed OK, but saving failed: \(msg)"
        case .badRow(let line, let message):
            return "Line \(line): \(message)"
        }
    }

    var pretty: String {
        errorDescription ?? "Unknown error"
    }
}

// MARK: - Header Mapping

struct CSVHeaderMap {
    let firstNameIndex: Int?
    let lastNameIndex: Int?
    let legacyNameIndex: Int?
    let numberIndex: Int?
    let gradesIndex: Int?

    static let expectedColumnsDisplay = "First Name, Last Name, Number, Grade"

    var hasAnyRecognizedColumn: Bool { firstNameIndex != nil || lastNameIndex != nil || legacyNameIndex != nil }

    init(header: [String]) {
        func find(_ candidates: [String]) -> Int? {
            for c in candidates {
                if let idx = header.firstIndex(of: c) { return idx }
            }
            return nil
        }

        firstNameIndex = find(["first name", "firstname", "first"])
        lastNameIndex = find(["last name", "lastname", "last", "surname"])
        legacyNameIndex = find(["name", "player", "playername", "player name"])
        numberIndex = find(["number", "no", "guernsey", "jumper", "jumper number", "guernsey number"])
        gradesIndex = find(["grades", "grade", "grade(s)", "teams", "team"])
    }
}

struct CSVPlayerRow {
    let line: Int
    let firstName: String
    let lastName: String
    let number: Int?
    let gradesRaw: String?

    var fullName: String {
        Player.combineName(first: firstName, last: lastName)
    }

    static func from(_ row: [String], headerMap: CSVHeaderMap, lineNumber: Int) throws -> CSVPlayerRow {
        guard headerMap.hasAnyRecognizedColumn else {
            throw CSVImportError.missingHeaders(expected: CSVHeaderMap.expectedColumnsDisplay)
        }

        func value(at idx: Int?) -> String? {
            guard let i = idx, i < row.count else { return nil }
            let v = row[i].trimmed
            return v.isEmpty ? nil : v
        }

        let first = value(at: headerMap.firstNameIndex)
        let last = value(at: headerMap.lastNameIndex)
        let legacyName = value(at: headerMap.legacyNameIndex)

        let resolvedFirst: String
        let resolvedLast: String

        if let first, let last {
            resolvedFirst = first.cleanedName
            resolvedLast = last.cleanedName
        } else if let legacyName {
            let split = Player.splitName(legacyName)
            resolvedFirst = split.first
            resolvedLast = split.last
        } else {
            throw CSVImportError.badRow(line: lineNumber, message: "Missing first/last name.")
        }

        guard !Player.combineName(first: resolvedFirst, last: resolvedLast).isEmpty else {
            throw CSVImportError.badRow(line: lineNumber, message: "Missing first/last name.")
        }

        let numberString = value(at: headerMap.numberIndex)
        let number = numberString.flatMap { Int($0.filter { $0.isNumber }) }
        let grades = value(at: headerMap.gradesIndex)

        return CSVPlayerRow(line: lineNumber, firstName: resolvedFirst, lastName: resolvedLast, number: number, gradesRaw: grades)
    }
}

// MARK: - String helpers

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedLowercased: String { trimmed.lowercased() }

    var cleanedName: String {
        trimmed
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
    }
}

// MARK: - Grade Lookup (aliases + normalization)

struct GradeLookup {
    private let keyToID: [String: UUID]

    init(grades: [Any]) {
        // This init exists only to prevent accidental use without the real Grade type.
        // Use init(grades: [Grade]) below.
        self.keyToID = [:]
    }

    init(grades: [Grade]) {
        var map: [String: UUID] = [:]
        for g in grades {
            for key in GradeLookup.matchKeys(forGradeName: g.name) {
                map[key] = g.id
            }
        }

        // Common footy-grade aliases.
        GradeLookup.addAlias("seniors", toAnyOf: ["a grade"], into: &map)
        GradeLookup.addAlias("reserves", toAnyOf: ["b grade"], into: &map)

        self.keyToID = map
    }

    func ids(forRawGradeField raw: String?, unknownCollector: inout Set<String>) -> [UUID] {
        guard let raw else { return [] }

        // Support multiple grades in a single cell separated by comma/semicolon.
        // We continue to accept "/" and "|" as legacy separators.
        let parts = raw
            .split(whereSeparator: { [",", ";", "/", "|"].contains($0) })
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }

        var ids: [UUID] = []
        for p in parts {
            let key = GradeLookup.normalize(p)
            if let id = keyToID[key] {
                ids.append(id)
            } else {
                unknownCollector.insert(p)
            }
        }

        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func normalize(_ s: String) -> String {
        s.trimmedLowercased
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            // Handle straight and “smart” apostrophes consistently.
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "‘", with: "")
            .replacingOccurrences(of: #"[^a-z0-9 ]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
    }

    private static func matchKeys(forGradeName name: String) -> Set<String> {
        let normalized = normalize(name)
        var keys: Set<String> = [normalized]

        let compact = normalized.replacingOccurrences(of: " ", with: "")
        if !compact.isEmpty {
            keys.insert(compact)
        }

        if let age = extractUnderAge(from: normalized) {
            keys.insert("u\(age)")
            keys.insert("u \(age)")
            keys.insert("under\(age)")
            keys.insert("under \(age)")
            keys.insert("under \(age)s")
        }

        // Letter-grade shorthand (A/B/C/D)
        if let short = shortLetterGrade(from: normalized) {
            keys.insert(short)
        }

        return keys
    }

    private static func extractUnderAge(from normalized: String) -> String? {
        guard normalized.hasPrefix("under ") else { return nil }
        let remainder = String(normalized.dropFirst("under ".count))
        let digits = remainder.prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    private static func shortLetterGrade(from normalized: String) -> String? {
        guard normalized.hasSuffix(" grade") else { return nil }
        let prefix = normalized.replacingOccurrences(of: " grade", with: "")
        guard prefix.count == 1 else { return nil }
        return prefix
    }

    private static func addAlias(_ alias: String, toAnyOf targetNames: [String], into map: inout [String: UUID]) {
        let normalizedAlias = normalize(alias)
        for targetName in targetNames {
            let targetKey = normalize(targetName)
            if let id = map[targetKey] {
                map[normalizedAlias] = id
                return
            }
        }
    }
}

// MARK: - CSV Parser (quotes, commas inside quotes, newlines inside quotes)

enum CSVParser {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""

        var inQuotes = false
        var i = text.startIndex

        func endField() {
            row.append(field)
            field = ""
        }

        func endRow() {
            rows.append(row)
            row = []
        }

        while i < text.endIndex {
            let c = text[i]

            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "\"" {
                        field.append("\"")
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                case ",":
                    endField()
                case "\n":
                    endField()
                    endRow()
                default:
                    field.append(c)
                }
            }

            i = text.index(after: i)
        }

        if !field.isEmpty || !row.isEmpty {
            endField()
            endRow()
        }

        return rows.map { $0.map { $0.trimmed } }.filter { !$0.isEmpty }
    }
}
