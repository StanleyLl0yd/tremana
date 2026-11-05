import SwiftUI

/// Shared macOS glass background, gently muted for secondary Settings windows.
struct TreManaWindowTint: View {
    var intensity: Double = 1.0

    var body: some View {
        LinearGradient(
            colors: [
                Color.pink.opacity(0.085 * intensity),
                Color.purple.opacity(0.055 * intensity),
                Color.blue.opacity(0.035 * intensity)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
