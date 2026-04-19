import SwiftUI

extension View {
    /// Standardized save-button behavior:
    /// - gray when disabled
    /// - blue when enabled
    /// - disabled state driven by `isEnabled`
    func saveButtonBehavior(isEnabled: Bool) -> some View {
        self
            .tint(isEnabled ? .blue : .gray)
            .disabled(!isEnabled)
    }
}
