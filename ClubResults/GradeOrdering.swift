import Foundation

func orderedGradesForDisplay(_ grades: [Grade], includeInactive: Bool = false) -> [Grade] {
    let candidates: [Grade]
    if includeInactive {
        candidates = grades
    } else {
        let active = grades.filter(\.isActive)
        // Fallback for legacy data where grades may have been persisted as inactive.
        // If there are no active grades, still show configured grades throughout the app.
        candidates = active.isEmpty ? grades : active
    }

    return candidates.sorted {
        if $0.displayOrder != $1.displayOrder {
            return $0.displayOrder < $1.displayOrder
        }
        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
}
