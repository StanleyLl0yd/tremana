import Foundation
import Testing
@testable import TreManaCore

@Suite("Inspector pane sizing")
struct InspectorSplitSizingTests {
    @Test func defaultProportionsFitAvailableHeight() {
        let layout = InspectorSplitSizing(
            totalHeight: 680,
            preferredFraction: InspectorSplitSizing.defaultFraction
        )
        #expect(layout.torrentsHeight >= InspectorSplitSizing.minimumTorrentsHeight)
        #expect(layout.inspectorHeight >= InspectorSplitSizing.minimumInspectorHeight)
        #expect(abs(
            layout.torrentsHeight + layout.inspectorHeight
                + InspectorSplitSizing.dividerHeight - 680
        ) < 0.001)
    }

    @Test func boundsKeepBothPanesUsable() {
        for fraction in [-100.0, -1.0, 0.0, 1.0, 100.0] {
            let layout = InspectorSplitSizing(totalHeight: 560, preferredFraction: fraction)
            #expect(layout.torrentsHeight >= InspectorSplitSizing.minimumTorrentsHeight)
            #expect(layout.inspectorHeight >= InspectorSplitSizing.minimumInspectorHeight)
            #expect(abs(layout.torrentsHeight + layout.inspectorHeight + 8 - 560) < 0.001)
        }
    }

    @Test func preferredDividerFractionSurvivesWindowResize() {
        let saved = InspectorSplitSizing.fraction(
            forInspectorHeight: 430, totalHeight: 700
        )
        let initial = InspectorSplitSizing(totalHeight: 700, preferredFraction: saved)
        #expect(abs(initial.inspectorHeight - 430) < 0.001)
        let resized = InspectorSplitSizing(totalHeight: 900, preferredFraction: saved)
        #expect(abs(resized.inspectorHeight / (900 - 8) - saved) < 0.001)
    }

    @Test func storedValueRoundTripsWithoutSensitiveInformation() throws {
        let suite = "TreMana.Split.Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let desired = InspectorSplitSizing.fraction(forInspectorHeight: 480, totalHeight: 720)
        defaults.set(desired, forKey: InspectorSplitSizing.storageKey)
        let restored = InspectorSplitSizing(
            totalHeight: 720, preferredFraction: defaults.double(forKey: InspectorSplitSizing.storageKey)
        )
        #expect(abs(restored.inspectorHeight - 480) < 0.001)
    }

    @Test func malformedValuesCannotProduceNanGeometry() {
        for fraction in [Double.nan, .infinity, -.infinity] {
            let layout = InspectorSplitSizing(totalHeight: 700, preferredFraction: fraction)
            #expect(layout.torrentsHeight.isFinite)
            #expect(layout.inspectorHeight.isFinite)
            #expect(layout.torrentsHeight > 0)
            #expect(layout.inspectorHeight > 0)
        }
    }

    @Test func narrowWindowIsHandledWithoutNegativeSizes() {
        let layout = InspectorSplitSizing(totalHeight: 240, preferredFraction: 0.96)
        #expect(layout.torrentsHeight >= 0)
        #expect(layout.inspectorHeight >= 0)
        #expect(abs(layout.torrentsHeight + layout.inspectorHeight + 8 - 240) < 0.001)
    }
}
