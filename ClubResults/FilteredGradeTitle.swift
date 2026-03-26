import SwiftUI

struct FilteredGradeTitle: View {
    let selectedGradeID: UUID?
    let grades: [Grade]   // pass ordered/active list

    private var label: String {
        guard let id = selectedGradeID,
              let g = grades.first(where: { $0.id == id }) else {
            return "All"
        }
        return g.name
    }

    var body: some View {
        Text(label)
            .font(.footnote.weight(.semibold))      // smaller than title
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(.secondarySystemBackground).opacity(0.7))
            )
    }
}
