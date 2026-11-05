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

    @Test func malformedMetricsFallBackSafely() {
        for content in [Double.nan, -.infinity, .infinity, -5.0] {
            let value = AdaptiveWindowHeight.fitted(contentHeight: content, visibleHeight: 700)
            #expect(value == 320)
        }
    }
}
