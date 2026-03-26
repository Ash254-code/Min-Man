import SwiftUI
import SwiftData

struct LockedGradesView: View {
    @Query private var grades: [Grade]

    private var orderedGrades: [Grade] {
        LockedGradeSeed.orderedGradeNames.compactMap { name in
            grades.first(where: { $0.name == name && $0.isActive })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Grades (locked)") {
                    ForEach(orderedGrades) { g in
                        Text(g.name)
                            .listRowBackground(Color.clear)
                    }
                }
                Text("Grades are pre-filled and not editable in the app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Grades")
        }
    }
}
