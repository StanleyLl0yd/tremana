import Foundation
import Testing
@testable import TreManaCore

@Suite("Content-driven window heights")
struct AdaptiveWindowHeightTests {
    @Test func actualContentIsUsedInsteadOfHardcodedWindowSize() {
        #expect(AdaptiveWindowHeight.fitted(contentHeight: 480, visibleHeight: 900) == 480)
        #expect(AdaptiveWindowHeight.fitted(contentHeight: 610, visibleHeight: 900) == 610)
    }

    @Test func newlyVisibleErrorMessageCanGrowWindow() {
        let before = AdaptiveWindowHeight.fitted(contentHeight: 450, visibleHeight: 900)
        let after = AdaptiveWindowHeight.fitted(contentHeight: 515, visibleHeight: 900)
        #expect(after > before)
    }

    @Test func intrinsicHeightChangeTriggersGrowthAndShrink() {
        #expect(AdaptiveWindowHeight.shouldUpdate(previous: 500, measured: 615))
        #expect(AdaptiveWindowHeight.shouldUpdate(previous: 615, measured: 485))
        #expect(!AdaptiveWindowHeight.shouldUpdate(previous: 500, measured: 500.3))
        #expect(!AdaptiveWindowHeight.shouldUpdate(previous: 500, measured: 0))
        #expect(!AdaptiveWindowHeight.shouldUpdate(previous: 500, measured: .nan))
        #expect(!AdaptiveWindowHeight.shouldUpdate(previous: 500, measured: .infinity))
    }

    @Test func shortContentDoesNotCreatePointlessOversizedWindow() {
        #expect(AdaptiveWindowHeight.fitted(contentHeight: 240, visibleHeight: 900) == 320)
    }

    @Test func shortScreenClampsWindowButNeverExceedsAvailableSpace() {
        let target = AdaptiveWindowHeight.fitted(contentHeight: 880, visibleHeight: 600)
        #expect(target == 538)
        #expect(target < 600)
    }

    @Test func smallestScreensRemainBoundedAndFinite() {
        for height in [100.0, 250, 450] {
            let value = AdaptiveWindowHeight.fitted(contentHeight: 800, visibleHeight: height)
            #expect(value.isFinite)
            #expect(value > 0)
            #expect(value <= height)
        }
    }

    @Test func compactConnectionCanShrinkBelowPriorHardMinimum() {
        let short = AdaptiveWindowHeight.fitted(
            contentHeight: 228, visibleHeight: 900,
            minimum: 260, chromeHeight: 38, screenMargin: 26
        )
        let expanded = AdaptiveWindowHeight.fitted(
            contentHeight: 540, visibleHeight: 900,
            minimum: 260, chromeHeight: 38, screenMargin: 26
        )
        #expect(short == 260)
        #expect(expanded == 540)
        #expect(expanded > short)
    }

    @Test func compactSettingsAndScreenBounds() {
        let normal = AdaptiveWindowHeight.fitted(
            contentHeight: 410, visibleHeight: 820,
            minimum: 300, chromeHeight: 38, screenMargin: 26
        )
        let smallScreen = AdaptiveWindowHeight.fitted(
            contentHeight: 410, visibleHeight: 430,
            minimum: 300, chromeHeight: 38, screenMargin: 26
        )
        #expect(normal == 410)
        #expect(smallScreen == 366)
    }

    @Test func scrollingOnlyWhenContentExceedsPhysicalWindow() {
        let normal = AdaptiveWindowHeight.fitted(
            contentHeight: 475, visibleHeight: 900,
            minimum: 300, chromeHeight: 38, screenMargin: 26
        )
        #expect(normal == 475)
        #expect(!AdaptiveWindowHeight.needsScrolling(contentHeight: 475, fittedHeight: normal))

        let expanded = AdaptiveWindowHeight.fitted(
            contentHeight: 1040, visibleHeight: 900,
            minimum: 260, chromeHeight: 38, screenMargin: 26
        )
        #expect(expanded == 836)
        #expect(AdaptiveWindowHeight.needsScrolling(contentHeight: 1040, fittedHeight: expanded))
        #expect(!AdaptiveWindowHeight.needsScrolling(contentHeight: .nan, fittedHeight: expanded))
    }

    @Test func connectionNavigationAllowanceAddsRoomOrEnablesScrollAtScreenLimit() {
        // Measured form height excludes a small amount of NavigationStack layout.
        let measured = 710.0
        let required = measured + 20.0
        let normal = AdaptiveWindowHeight.fitted(
            contentHeight: required, visibleHeight: 1000,
            minimum: 260, chromeHeight: 38, screenMargin: 26
        )
        #expect(normal == 730)
        #expect(!AdaptiveWindowHeight.needsScrolling(contentHeight: required, fittedHeight: normal))

        // At a physical screen bound, the missing bottom is scrollable instead
        // of being clipped or solved by reducing font/control dimensions.
        let constrained = AdaptiveWindowHeight.fitted(
            contentHeight: required, visibleHeight: 760,
            minimum: 260, chromeHeight: 38, screenMargin: 26
        )
        #expect(constrained == 696)
        #expect(AdaptiveWindowHeight.needsScrolling(
            contentHeight: required, fittedHeight: constrained
        ))
    }

    @Test func malformedMetricsFallBackSafely() {
        for content in [Double.nan, -.infinity, .infinity, -5.0] {
            let value = AdaptiveWindowHeight.fitted(contentHeight: content, visibleHeight: 700)
            #expect(value == 320)
        }
    }
}
