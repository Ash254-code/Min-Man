import Foundation

func orderedGradesForDisplay(_ grades: [Grade], includeInactive: Bool = false) -> [Grade] {
    grades
        .filter { includeInactive || $0.isActive }
        .sorted {
            if $0.displayOrder != $1.displayOrder {
                return $0.displayOrder < $1.displayOrder
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
}
