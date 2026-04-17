import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct StaffImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var grades: [Grade]
    @Query private var staff: [StaffMember]

    @State private var showingImporter = false
    @State private var log: [String] = []
    @State private var importedCount = 0
    @State private var skippedCount = 0

    var body: some View {
        NavigationStack {
            List {
                Section("Import staff from CSV") {
                    Button("Choose CSV file…") {
                        showingImporter = true
                    }

                    Text("CSV columns must be: grade,role,name")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Roles: headCoach, assistantCoach, teamManager, runner, goalUmpire, fieldUmpire, boundaryUmpire, trainer")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if importedCount + skippedCount > 0 {
                    Section("Result") {
                        HStack { Text("Imported"); Spacer(); Text("\(importedCount)") }
                        HStack { Text("Skipped"); Spacer(); Text("\(skippedCount)") }
                    }
                }

                if !log.isEmpty {
                    Section("Log") {
                        ForEach(log.indices, id: \.self) { i in
                            Text(log[i])
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Import Staff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importCSV(from: url)
                case .failure(let error):
                    log.insert("❌ Import cancelled/failed: \(error.localizedDescription)", at: 0)
                }
            }
        }
    }

    private func importCSV(from url: URL) {
        importedCount = 0
        skippedCount = 0
        log.removeAll()

        guard url.startAccessingSecurityScopedResource() else {
            log.insert("❌ Could not access file.", at: 0)
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let raw = try String(contentsOf: url, encoding: .utf8)
            let rows = parseCSV(raw)

            guard !rows.isEmpty else {
                log.insert("❌ CSV appears empty.", at: 0)
                return
            }

            // Expect header row
            let header = rows[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            guard header.count >= 3,
                  header[0] == "grade",
                  header[1] == "role",
                  header[2] == "name"
            else {
                log.insert("❌ Header must be exactly: grade,role,name", at: 0)
                return
            }

            // Build quick lookup for grades
            let gradeLookup: [String: Grade] = Dictionary(
                uniqueKeysWithValues: grades.map { (normalize($0.name), $0) }
            )

            // Existing staff set to prevent duplicates: gradeID + role + normalized name
            var existing = Set<String>()
            for s in staff {
                existing.insert("\(s.gradeID.uuidString)|\(s.role.rawValue)|\(normalize(s.name))")
            }

            var toInsert: [StaffMember] = []

            for (idx, row) in rows.dropFirst().enumerated() {
                if row.allSatisfy({ normalize($0).isEmpty }) { continue } // skip blank lines
                if row.count < 3 {
                    skippedCount += 1
                    log.append("⚠️ Row \(idx+2): not enough columns")
                    continue
                }

                let gradeName = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let roleStr   = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let name      = row[2].trimmingCharacters(in: .whitespacesAndNewlines)

                guard !normalize(gradeName).isEmpty, !normalize(roleStr).isEmpty, !normalize(name).isEmpty else {
                    skippedCount += 1
                    log.append("⚠️ Row \(idx+2): missing grade/role/name")
                    continue
                }

                guard let grade = gradeLookup[normalize(gradeName)] else {
                    skippedCount += 1
                    log.append("⚠️ Row \(idx+2): grade not found: \(gradeName)")
                    continue
                }

                guard let role = StaffRole(rawValue: roleStr) else {
                    skippedCount += 1
                    log.append("⚠️ Row \(idx+2): invalid role: \(roleStr)")
                    continue
                }

                let key = "\(grade.id.uuidString)|\(role.rawValue)|\(normalize(name))"
                guard !existing.contains(key) else {
                    skippedCount += 1
                    continue
                }

                existing.insert(key)
                toInsert.append(StaffMember(name: name, role: role, gradeID: grade.id))
            }

            for item in toInsert { modelContext.insert(item) }

            do {
                try modelContext.save()
                importedCount = toInsert.count
                log.insert("✅ Imported \(importedCount) staff names.", at: 0)
            } catch {
                log.insert("❌ Save failed: \(error)", at: 0)
            }

        } catch {
            log.insert("❌ Could not read CSV: \(error.localizedDescription)", at: 0)
        }
    }

    // Simple CSV parser: handles commas + quotes
    private func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]

            if ch == "\"" {
                // double quote escape inside quoted field
                let next = text.index(after: i)
                if inQuotes, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    i = next
                } else {
                    inQuotes.toggle()
                }
            } else if ch == "," && !inQuotes {
                row.append(field)
                field = ""
            } else if (ch == "\n" || ch == "\r") && !inQuotes {
                // handle CRLF or LF
                if ch == "\r" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\n" {
                        i = next
                    }
                }
                row.append(field)
                field = ""
                rows.append(row)
                row = []
            } else {
                field.append(ch)
            }

            i = text.index(after: i)
        }

        // flush last field/row
        row.append(field)
        if !(row.count == 1 && normalize(row[0]).isEmpty) {
            rows.append(row)
        }
        return rows
    }

    private func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
