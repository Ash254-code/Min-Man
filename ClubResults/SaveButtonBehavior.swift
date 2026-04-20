import SwiftUI

extension View {
    /// Standardized save-button behavior:
    /// - gray pill when disabled
    /// - blue pill when enabled
    /// - disabled state driven by `isEnabled`
    func saveButtonBehavior(isEnabled: Bool) -> some View {
        self
            .buttonStyle(.borderedProminent)
            .tint(isEnabled ? .blue : .gray)
            .disabled(!isEnabled)
    }
}
