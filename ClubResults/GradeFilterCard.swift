import SwiftUI

struct GradeFilterCard: View {
    let title: String          // e.g. "Filter"
    let label: String          // e.g. "Grade"
    @Binding var selection: UUID?   // nil = All
    let grades: [Grade]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.75))

            HStack(spacing: 10) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Picker("", selection: $selection) {
                    Text("All").tag(UUID?.none)
                    ForEach(grades) { g in
                        Text(g.name).tag(UUID?.some(g.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
        .padding(4) // ✅ compact outer padding
        .premiumGlassCard(cornerRadius: 20, contentPadding: 2) // ✅ compact glass padding
    }
}
