import SwiftUI

/// The colour of what everyone has to read or do — the steps after an
/// update. Kept for that, so it still stands out.
extension Color {
    static let signal = Color.orange
    static let signalGround = Color.orange.opacity(0.14)
}

extension View {
    /// Set apart on a card in the signal colour, outside a list.
    func signalCard() -> some View {
        padding(14)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.signalGround)
                    .strokeBorder(Color.signal.opacity(0.5), lineWidth: 1)
            }
    }
}
