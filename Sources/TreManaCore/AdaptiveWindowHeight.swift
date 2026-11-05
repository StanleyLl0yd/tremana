import Foundation

/// Size a content-driven macOS auxiliary window while respecting screen bounds.
public enum AdaptiveWindowHeight {
    /// contentHeight is the measured SwiftUI content, including its own padding.
    /// visibleHeight includes the title bar; chromeHeight and margin remain free.
    public static func fitted(
        contentHeight: Double,
        visibleHeight: Double,
        minimum: Double = 320,
        chromeHeight: Double = 38,
        screenMargin: Double = 24
    ) -> Double {
        let space = visibleHeight.isFinite ? visibleHeight : 900
        let maximum = max(1, space - max(0, chromeHeight) - max(0, screenMargin))
        let desired = contentHeight.isFinite && contentHeight > 0
            ? contentHeight : minimum
        return min(max(desired, min(minimum, maximum)), maximum)
    }
}
