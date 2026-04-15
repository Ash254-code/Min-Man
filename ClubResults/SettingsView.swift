import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Grade.displayOrder), SortDescriptor(\Grade.name)])
    private var storedGrades: [Grade]

    @State private var saveErrorMessage: String?
    @State private var grades: [Grade] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Grades") {
                    ForEach(grades) { grade in
                        Text(grade.name)
                    }
                }
            }
            .navigationTitle("Settings")
            .task {
                seedInitialGradesIfNeeded()
                grades = storedGrades
            }
            .alert("Save failed", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "Unknown error")
            }
        }
    }

    private func seedInitialGradesIfNeeded() {
        let existing = (try? modelContext.fetch(FetchDescriptor<Grade>())) ?? []
        guard existing.isEmpty else {
            grades = storedGrades
            return
        }

        let defaults = ["A Grade", "B Grade", "Under 17's", "Under 14's", "Under 12's", "Under 9's"]
        for (index, name) in defaults.enumerated() {
            modelContext.insert(Grade(name: name, isActive: true, displayOrder: index))
        }

        do {
            try modelContext.save()
            grades = (try? modelContext.fetch(FetchDescriptor<Grade>())) ?? []
        } catch {
            saveErrorMessage = error.localizedDescription
            // Keep the local list in sync with currently stored data.
            grades = existing
        }
    }
}
