import Foundation

// Runs the exact XCTest cases with Command Line Tools when XCTest is unavailable.
class XCTestCase {}
private var failures = 0
func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if value != nil { failures += 1; print("FAIL \(file):\(line): expected nil, got \(String(describing: value))") }
}
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { failures += 1; print("FAIL \(file):\(line): \(actual) != \(expected)") }
}
func XCTAssertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !value { failures += 1; print("FAIL \(file):\(line): expected true") }
}
@main struct PortableTestRunner {
    static func main() {
        let suite = GestureEngineTests()
        let corners = CornerTapEngineTests()
        let pinch = PinchEngineTests()
        let cases: [(String, () -> Void)] = [
            ("all directions, one action per sequence", suite.testAllDirectionsAndOneActionUntilLift),
            ("two-finger scrolling ignored", suite.testTwoFingerScrollNeverTriggers),
            ("extra finger cancels until release", suite.testAddedFourthFingerCancelsUntilRelease),
            ("staggered lift-off ignored", suite.testLiftOffDoesNotCreateCentroidJump),
            ("pinch and opposing fingers ignored", suite.testPinchAndOpposingFingersDoNotTrigger),
            ("diagonal and tiny movement ignored", suite.testDiagonalNoiseAndTinyMovementDoNotTrigger),
            ("four-finger mode", suite.testFourFingerMode),
            ("finger identity changes rejected", suite.testTouchIDsCannotChangeMidGesture),
            ("missing release recovery", suite.testMissingReleaseFrameResetsAfterGap),
            ("invalid data rejected", suite.testInvalidContactsDoNotCrashOrTrigger),
            ("multi-display coordinates", suite.testDisplayCoordinatesAboveAndBelowPrimary),
            ("half-screen spacing and bounds", suite.testHalfScreenGapAndCenterDoNotExceedVisibleArea),
            ("four corner taps, no repeat on release", corners.testAllFourCornersAndRepeatRelease),
            ("outside start and drifting into corner ignored", corners.testCenterAndDriftingIntoCornerAreIgnored),
            ("long corner hold and drag ignored", corners.testLongHoldAndDragAreIgnored),
            ("adding a finger cancels corner tap", corners.testAddingFingerCancelsEvenAfterItLifts),
            ("multi-finger start cannot become corner tap", corners.testMultiFingerStartCannotBecomeCornerTap),
            ("custom corner dimensions and disable", corners.testCustomZoneWidthAndHeightAndDisable),
            ("leaving and returning to zone ignored", corners.testLeavingZoneCancelsEvenIfFingerReturns),
            ("changed finger and missing frame ignored", corners.testChangedFingerIDAndMissingFramesCancel),
            ("corner bounds, invalid input, non-overlap", corners.testZonesClampAndNeverOverlap),
            ("corner settings serialization", corners.testZoneConfigurationRoundTrips),
            ("pinch inward, outward and reverse continuously", pinch.testInwardOutwardAndContinuousReversal),
            ("translation and jitter are not pinches", pinch.testTranslationAndSmallJitterAreNotPinches),
            ("rotation does not resize", pinch.testRotationPreservesDistances),
            ("partial lift ends pinch until full release", pinch.testPartialLiftEndsAndWaitsForAllFingers),
            ("fourth finger cancels pinch", pinch.testFourthFingerCancelsActivePinch),
            ("identity changes and missing frames cancel pinch", pinch.testFingerIdentityChangeAndFrameGapCancel),
            ("two-finger pinch ignored, staggered three fingers allowed", pinch.testTwoFingerPinchIgnoredButStaggeredPlacementAllowed),
            ("continuous pinch beyond swipe timeout", pinch.testPinchCanContinueLongerThanSwipeTimeout),
            ("close fingers and invalid data rejected", pinch.testCloseContactsAndInvalidCoordinatesIgnored),
            ("pinch keeps center, aspect and screen bounds", pinch.testPinchedGeometryKeepsCenterAspectAndBounds),
            ("pinch minimum size and negative display coordinates", pinch.testPinchedGeometryHandlesSmallAndNegativeCoordinateScreens)
        ]
        for (name, test) in cases {
            let before = failures; test(); print("\(failures == before ? "PASS" : "FAIL") \(name)")
        }
        print("\(cases.count) cases, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
