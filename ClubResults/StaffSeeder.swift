import Foundation
import SwiftData

enum StaffSeeder {
    static func seedIfNeeded(modelContext: ModelContext, grades: [Grade]) {
        let key = "didSeedStaff_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard !grades.isEmpty else { return }

        // Helper: get gradeID by grade name (matches how you name grades)
        func gid(_ name: String) -> UUID? {
            grades.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.id
        }

        // ✅ Put your default names here (edit freely)
        let seed: [(gradeName: String, role: StaffRole, names: [String])] = [
            ("A Grade", .headCoach, ["Angus Bruggemann"]),
            ("A Grade", .assistantCoach, ["Tim Packer"]),
            ("A Grade", .teamManager, ["Steve Hadley"]),
            ("A Grade", .runner, ["Ash Winders"]),
            ("A Grade", .goalUmpire, ["Andrew Mitchell"]),
            ("A Grade", .trainer, ["Steve Rohde", "Shawn Deal", "Brett Holland", "Kerry Hadley"]),

            ("B Grade", .headCoach, ["Shawn Deal"]),
            ("B Grade", .assistantCoach, ["Brett Holland"]),
            ("B Grade", .teamManager, ["David Ingham"]),
            ("B Grade", .goalUmpire, ["Graham Couch"]),
            ("B Grade", .trainer, ["Steve Rohde", "Shawn Deal", "Brett Holland", "Kerry Hadley"]),
            
            ("Under 17's", .headCoach, ["Shawn Deal"]),
            ("Under 17's", .assistantCoach, ["Brett Holland"]),
            ("Under 17's", .teamManager, ["David Ingham"]),
            ("Under 17's",.goalUmpire, ["Graham Couch"]),
            ("Under 17's", .trainer, ["Steve Rohde", "Shawn Deal", "Brett Holland", "Kerry Hadley"]),

            ("Under 14's", .headCoach, ["Shawn Deal"]),
            ("Under 14's", .assistantCoach, ["Brett Holland"]),
            ("Under 14's", .teamManager, ["David Ingham"]),
            ("Under 14's", .goalUmpire, ["Graham Couch"]),
            ("Under 14's", .trainer, ["Steve Rohde", "Shawn Deal", "Brett Holland", "Kerry Hadley"]),
            
            ("Under 12's", .headCoach, ["Shawn Deal"]),
            ("Under 12's", .assistantCoach, ["Brett Holland"]),
            ("Under 12's", .teamManager, ["David Ingham"]),
            ("Under 12's", .goalUmpire, ["Graham Couch"]),
            
            ("Under 9's", .headCoach, ["Shawn Deal"]),
            ("Under 9's", .assistantCoach, ["Brett Holland"]),
            ("Under 9's", .teamManager, ["David Ingham"]),
            ("Under 9's", .goalUmpire, ["Graham Couch"]),
        
            
        ]

        for item in seed {
            guard let gradeID = gid(item.gradeName) else { continue }
            for name in item.names {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                modelContext.insert(
                    StaffMember(name: trimmed, role: item.role, gradeID: gradeID)
                )
            }
        }

        do {
            try modelContext.save()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            print("❌ Staff seed save failed: \(error)")
        }
    }
}
