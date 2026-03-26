import SwiftUI

struct GradeFilterButton: View {
    let grades: [Grade]                 // already ordered + active
    @Binding var selectedGradeID: UUID? // nil = All
    var includeAll: Bool = true

    /// If true, show only the icon in the toolbar (useful when you also show the filter pill next to the title)
    var iconOnly: Bool = true

    private func gradeName(for id: UUID?) -> String {
        guard let id else { return "All" }
        return grades.first(where: { $0.id == id })?.name ?? "All"
    }

    var body: some View {
        Menu {
            if includeAll {
                Button {
                    selectedGradeID = nil
                } label: {
                    HStack {
                        Text("All")
                        if selectedGradeID == nil {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            if includeAll { Divider() }

            ForEach(grades, id: \.id) { g in
                Button {
                    selectedGradeID = g.id
                } label: {
                    HStack {
                        Text(g.name)
                        if selectedGradeID == g.id {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            if iconOnly {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityLabel("Filter by grade: \(gradeName(for: selectedGradeID))")
            } else {
                Label(gradeName(for: selectedGradeID),
                      systemImage: "line.3.horizontal.decrease.circle")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityLabel("Filter by grade: \(gradeName(for: selectedGradeID))")
            }
        }
        .contentShape(Rectangle())
    }
}
