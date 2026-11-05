import Foundation

/// Geometry policy for the resizable torrent/inspector panes.
/// Fractions are persisted, so the chosen layout scales with the window.
public struct InspectorSplitSizing: Equatable, Sendable {
    public static let storageKey = "com.sl.tremana.inspector-fraction.v1"
    public static let defaultFraction = 0.66
    public static let dividerHeight = 8.0
    public static let minimumTorrentsHeight = 120.0
    public static let minimumInspectorHeight = 220.0

    public let torrentsHeight: Double
    public let inspectorHeight: Double

    public init(totalHeight: Double, preferredFraction: Double) {
        let available = max(0, totalHeight.isFinite ? totalHeight - Self.dividerHeight : 0)
        let minInspector = min(Self.minimumInspectorHeight, available / 2)
        let minTorrents = min(Self.minimumTorrentsHeight, available / 2)
        let fraction = preferredFraction.isFinite ? preferredFraction : Self.defaultFraction
        let desired = fraction * available
        inspectorHeight = min(max(desired, minInspector), max(minInspector, available - minTorrents))
        torrentsHeight = max(0, available - inspectorHeight)
    }

    /// Convert the dragged inspector height into a bounded, durable fraction.
    public static func fraction(forInspectorHeight height: Double, totalHeight: Double) -> Double {
        let available = max(0, totalHeight - dividerHeight)
        guard available.isFinite, available > 0 else { return defaultFraction }
        return InspectorSplitSizing(
            totalHeight: totalHeight,
            preferredFraction: height / available
        ).inspectorHeight / available
    }
}
