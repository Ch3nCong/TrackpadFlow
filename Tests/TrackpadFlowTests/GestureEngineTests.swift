#if PORTABLE_TESTS
import Foundation
#else
import XCTest
@testable import TrackpadFlow
#endif
import CoreGraphics

final class PinchEngineTests: XCTestCase {
    private func points(scale: Double = 1, dx: Double = 0, dy: Double = 0) -> [Contact] {
        [(0.3, 0.4), (0.7, 0.4), (0.5, 0.7)].enumerated().map { index, point in
            Contact(id: Int32(index), x: 0.5 + (point.0 - 0.5) * scale + dx,
                    y: 0.5 + (point.1 - 0.5) * scale + dy)
        }
    }
    func testInwardOutwardAndContinuousReversal() {
        var engine = PinchEngine()
        XCTAssertNil(engine.consume(points(), at: 1))
        XCTAssertEqual(engine.consume(points(scale: 0.8), at: 1.1)?.phase, .began)
        XCTAssertTrue(abs(engine.consume(points(scale: 0.65), at: 1.2)!.scale - 0.65) < 0.001)
        let reversed = engine.consume(points(scale: 1.3), at: 1.3)
        XCTAssertEqual(reversed?.phase, .changed)
        XCTAssertTrue(abs(reversed!.scale - 1.3) < 0.001)
        XCTAssertEqual(engine.consume([], at: 1.4)?.phase, .ended)
    }
    func testTranslationAndSmallJitterAreNotPinches() {
        var engine = PinchEngine()
        _ = engine.consume(points(), at: 1)
        XCTAssertNil(engine.consume(points(dx: 0.08), at: 1.1))
        XCTAssertNil(engine.consume(points(dx: 0.17), at: 1.2))
        _ = engine.consume([], at: 1.3)
        _ = engine.consume(points(), at: 2)
        XCTAssertNil(engine.consume(points(scale: 1.04), at: 2.1))
    }
    func testRotationPreservesDistances() {
        var engine = PinchEngine()
        _ = engine.consume(points(), at: 1)
        let rotated = points().map { Contact(id: $0.id, x: 0.5 - ($0.y - 0.5), y: 0.5 + ($0.x - 0.5)) }
        XCTAssertNil(engine.consume(rotated, at: 1.1))
    }
    func testPartialLiftEndsAndWaitsForAllFingers() {
        var engine = PinchEngine()
        _ = engine.consume(points(), at: 1)
        _ = engine.consume(points(scale: 1.2), at: 1.1)
        XCTAssertEqual(engine.consume(Array(points(scale: 1.2).prefix(2)), at: 1.2)?.phase, .ended)
        XCTAssertNil(engine.consume(points(scale: 1.4), at: 1.3))
        _ = engine.consume([], at: 1.4)
        _ = engine.consume(points(), at: 1.5)
        XCTAssertEqual(engine.consume(points(scale: 0.8), at: 1.6)?.phase, .began)
    }
    func testFourthFingerCancelsActivePinch() {
        var engine = PinchEngine()
        _ = engine.consume(points(), at: 1)
        _ = engine.consume(points(scale: 1.2), at: 1.1)
        let four = points(scale: 1.2) + [Contact(id: 4, x: 0.5, y: 0.8)]
        XCTAssertEqual(engine.consume(four, at: 1.2)?.phase, .cancelled)
        XCTAssertNil(engine.consume(points(scale: 0.8), at: 1.3))
    }
    func testFingerIdentityChangeAndFrameGapCancel() {
        var engine = PinchEngine()
        _ = engine.consume(points(), at: 1)
        _ = engine.consume(points(scale: 1.2), at: 1.1)
        let changed = points(scale: 1.3).map { Contact(id: $0.id + 5, x: $0.x, y: $0.y) }
        XCTAssertEqual(engine.consume(changed, at: 1.2)?.phase, .cancelled)
        _ = engine.consume([], at: 1.3)
        _ = engine.consume(points(), at: 2)
        _ = engine.consume(points(scale: 1.2), at: 2.1)
        XCTAssertEqual(engine.consume(points(scale: 1.3), at: 2.5)?.phase, .cancelled)
    }
    func testTwoFingerPinchIgnoredButStaggeredPlacementAllowed() {
        var engine = PinchEngine()
        XCTAssertNil(engine.consume(Array(points().prefix(2)), at: 1))
        XCTAssertNil(engine.consume(Array(points(scale: 0.8).prefix(2)), at: 1.1))
        XCTAssertNil(engine.consume(points(), at: 1.2))
        XCTAssertEqual(engine.consume(points(scale: 0.8), at: 1.3)?.phase, .began)
    }
    func testPinchCanContinueLongerThanSwipeTimeout() {
        var engine = PinchEngine()
        _ = engine.consume(points(), at: 1)
        _ = engine.consume(points(scale: 0.8), at: 1.1)
        for tick in 2...40 {
            XCTAssertEqual(engine.consume(points(scale: 0.8 + Double(tick) * 0.005), at: 1 + Double(tick) * 0.1)?.phase, .changed)
        }
    }
    func testCloseContactsAndInvalidCoordinatesIgnored() {
        var engine = PinchEngine()
        let close = [Contact(id: 1, x: 0.5, y: 0.5), Contact(id: 2, x: 0.51, y: 0.5), Contact(id: 3, x: 0.5, y: 0.51)]
        _ = engine.consume(close, at: 1)
        XCTAssertNil(engine.consume(close, at: 1.1))
        _ = engine.consume([], at: 1.2)
        XCTAssertNil(engine.consume([Contact(id: 1, x: .nan, y: 0.5), Contact(id: 2, x: 0.4, y: 0.4), Contact(id: 3, x: 0.6, y: 0.6)], at: 2))
        XCTAssertNil(engine.consume(points(scale: 1.3), at: 2.1))
    }
    func testPinchedGeometryKeepsCenterAspectAndBounds() {
        let initial = CGRect(x: 300, y: 250, width: 800, height: 600)
        let visible = CGRect(x: 0, y: 0, width: 1600, height: 1100)
        let half = WindowGeometry.pinched(initial: initial, scale: 0.5, visible: visible, gap: 8)
        XCTAssertEqual(half.midX, initial.midX); XCTAssertEqual(half.midY, initial.midY)
        XCTAssertEqual(half.width, 400); XCTAssertEqual(half.height, 300)
        let large = WindowGeometry.pinched(initial: initial, scale: 10, visible: visible, gap: 8)
        XCTAssertTrue(visible.insetBy(dx: 8, dy: 8).contains(large))
        XCTAssertTrue(abs(large.width / large.height - initial.width / initial.height) < 0.001)
    }
    func testPinchedGeometryHandlesSmallAndNegativeCoordinateScreens() {
        let visible = CGRect(x: -1200, y: -900, width: 1200, height: 800)
        let initial = CGRect(x: -1150, y: -850, width: 1000, height: 600)
        let tiny = WindowGeometry.pinched(initial: initial, scale: 0.001, visible: visible, gap: 8)
        XCTAssertTrue(tiny.width >= 240 && tiny.height >= 160)
        XCTAssertTrue(visible.contains(tiny))
        XCTAssertEqual(WindowGeometry.pinched(initial: initial, scale: .nan, visible: visible, gap: 8), initial)
    }
}

final class CornerTapEngineTests: XCTestCase {
    private func point(_ x: Double, _ y: Double, id: Int32 = 1) -> [Contact] { [Contact(id: id, x: x, y: y)] }
    func testAllFourCornersAndRepeatRelease() {
        for (x, y, corner) in [(0.05, 0.95, TrackpadCorner.topLeft), (0.95, 0.95, .topRight), (0.05, 0.05, .bottomLeft), (0.95, 0.05, .bottomRight)] {
            var engine = CornerTapEngine()
            XCTAssertNil(engine.consume(point(x, y), at: 1))
            XCTAssertEqual(engine.consume([], at: 1.1), corner)
            XCTAssertNil(engine.consume([], at: 1.11))
        }
    }
    func testCenterAndDriftingIntoCornerAreIgnored() {
        var engine = CornerTapEngine()
        _ = engine.consume(point(0.5, 0.5), at: 1)
        _ = engine.consume(point(0.05, 0.95), at: 1.1)
        XCTAssertNil(engine.consume([], at: 1.15))
    }
    func testLongHoldAndDragAreIgnored() {
        var engine = CornerTapEngine()
        _ = engine.consume(point(0.05, 0.95), at: 1)
        _ = engine.consume(point(0.05, 0.95), at: 1.2)
        _ = engine.consume(point(0.05, 0.95), at: 1.4)
        XCTAssertNil(engine.consume([], at: 1.5))
        _ = engine.consume(point(0.05, 0.95), at: 2)
        _ = engine.consume(point(0.10, 0.95), at: 2.1)
        XCTAssertNil(engine.consume([], at: 2.15))
    }
    func testAddingFingerCancelsEvenAfterItLifts() {
        var engine = CornerTapEngine()
        _ = engine.consume(point(0.05, 0.95), at: 1)
        _ = engine.consume([Contact(id: 1, x: 0.05, y: 0.95), Contact(id: 2, x: 0.06, y: 0.96)], at: 1.05)
        _ = engine.consume(point(0.05, 0.95), at: 1.1)
        XCTAssertNil(engine.consume([], at: 1.15))
    }
    func testMultiFingerStartCannotBecomeCornerTap() {
        var engine = CornerTapEngine()
        _ = engine.consume([Contact(id: 1, x: 0.05, y: 0.95), Contact(id: 2, x: 0.06, y: 0.96)], at: 1)
        _ = engine.consume(point(0.05, 0.95), at: 1.05)
        XCTAssertNil(engine.consume([], at: 1.1))
    }
    func testCustomZoneWidthAndHeightAndDisable() {
        var zones = CornerZone.defaults
        zones["topLeft"] = CornerZone(width: 0.30, height: 0.35)
        var engine = CornerTapEngine(zones: zones)
        _ = engine.consume(point(0.25, 0.7), at: 1)
        XCTAssertEqual(engine.consume([], at: 1.1), .topLeft)
        zones["topLeft"]?.enabled = false
        engine = CornerTapEngine(zones: zones)
        _ = engine.consume(point(0.05, 0.95), at: 2)
        XCTAssertNil(engine.consume([], at: 2.1))
    }
    func testLeavingZoneCancelsEvenIfFingerReturns() {
        var zones = CornerZone.defaults
        zones["topLeft"] = CornerZone(width: 0.05, height: 0.22)
        var engine = CornerTapEngine(zones: zones)
        _ = engine.consume(point(0.045, 0.95), at: 1)
        _ = engine.consume(point(0.055, 0.95), at: 1.04)
        _ = engine.consume(point(0.045, 0.95), at: 1.08)
        XCTAssertNil(engine.consume([], at: 1.12))
    }
    func testChangedFingerIDAndMissingFramesCancel() {
        var engine = CornerTapEngine()
        _ = engine.consume(point(0.05, 0.95), at: 1)
        _ = engine.consume(point(0.05, 0.95, id: 2), at: 1.05)
        XCTAssertNil(engine.consume([], at: 1.1))
        _ = engine.consume(point(0.05, 0.95), at: 2)
        XCTAssertNil(engine.consume([], at: 2.29))
    }
    func testZonesClampAndNeverOverlap() {
        let invalid = CornerZone(width: 0.99, height: .nan).clamped
        XCTAssertEqual(invalid.width, 0.45); XCTAssertEqual(invalid.height, 0.22)
        let large = CornerZone(width: 0.45, height: 0.45)
        for x in stride(from: 0.0, through: 1.0, by: 0.05) {
            for y in stride(from: 0.0, through: 1.0, by: 0.05) {
                let point = Contact(id: 1, x: x, y: y)
                XCTAssertTrue(TrackpadCorner.allCases.filter { large.contains(point, corner: $0) }.count <= 1)
            }
        }
        XCTAssertTrue(!large.contains(Contact(id: 1, x: .nan, y: 0.9), corner: .topLeft))
    }
    func testZoneConfigurationRoundTrips() {
        var zones = CornerZone.defaults
        zones["bottomLeft"] = CornerZone(width: 0.12, height: 0.31, enabled: false)
        let data = try! JSONEncoder().encode(zones)
        XCTAssertEqual(try! JSONDecoder().decode([String: CornerZone].self, from: data), zones)
    }
}

final class GestureEngineTests: XCTestCase {
    func points(_ dx: Double = 0, _ dy: Double = 0, count: Int = 3) -> [Contact] {
        (0..<count).map { Contact(id: Int32($0), x: 0.25 + Double($0) * 0.15 + dx, y: 0.4 + dy) }
    }
    func testAllDirectionsAndOneActionUntilLift() {
        for (dx, dy, expected) in [(-0.17, 0.0, SwipeDirection.left), (0.17, 0.0, .right), (0, 0.17, .up), (0, -0.17, .down)] {
            var engine = GestureEngine()
            XCTAssertNil(engine.consume(points(), at: 1))
            XCTAssertEqual(engine.consume(points(dx, dy), at: 1.1), expected)
            XCTAssertNil(engine.consume(points(dx * 1.2, dy * 1.2), at: 1.2))
            XCTAssertNil(engine.consume([], at: 1.3))
            XCTAssertNil(engine.consume(points(), at: 1.6))
            XCTAssertEqual(engine.consume(points(dx, dy), at: 1.7), expected)
        }
    }
    func testTwoFingerScrollNeverTriggers() {
        var engine = GestureEngine()
        XCTAssertNil(engine.consume(points(count: 2), at: 1))
        XCTAssertNil(engine.consume(points(0.25, count: 2), at: 1.1))
    }
    func testAddedFourthFingerCancelsUntilRelease() {
        var engine = GestureEngine()
        _ = engine.consume(points(), at: 1)
        XCTAssertNil(engine.consume(points(count: 4), at: 1.05))
        XCTAssertNil(engine.consume(points(0.2), at: 1.1))
        _ = engine.consume([], at: 1.2)
        _ = engine.consume(points(), at: 1.3)
        XCTAssertEqual(engine.consume(points(0.2), at: 1.4), .right)
    }
    func testLiftOffDoesNotCreateCentroidJump() {
        var engine = GestureEngine()
        _ = engine.consume(points(), at: 1)
        XCTAssertNil(engine.consume(Array(points(0.05).dropFirst()), at: 1.1))
        XCTAssertNil(engine.consume(points(0.2), at: 1.2))
    }
    func testPinchAndOpposingFingersDoNotTrigger() {
        var engine = GestureEngine()
        _ = engine.consume(points(), at: 1)
        let pinch = [Contact(id: 0, x: 0.5, y: 0.4), Contact(id: 1, x: 0.65, y: 0.4), Contact(id: 2, x: 0.45, y: 0.4)]
        XCTAssertNil(engine.consume(pinch, at: 1.1))
    }
    func testDiagonalNoiseAndTinyMovementDoNotTrigger() {
        var engine = GestureEngine()
        _ = engine.consume(points(), at: 1)
        XCTAssertNil(engine.consume(points(0.04), at: 1.1))
        XCTAssertNil(engine.consume(points(0.16, 0.16), at: 1.2))
    }
    func testFourFingerMode() {
        var engine = GestureEngine(fingerCount: 4)
        _ = engine.consume(points(count: 4), at: 1)
        XCTAssertEqual(engine.consume(points(-0.17, count: 4), at: 1.1), .left)
    }
    func testTouchIDsCannotChangeMidGesture() {
        var engine = GestureEngine()
        _ = engine.consume(points(), at: 1)
        let changed = points(0.2).map { Contact(id: $0.id + 1, x: $0.x, y: $0.y) }
        XCTAssertNil(engine.consume(changed, at: 1.1))
    }
    func testMissingReleaseFrameResetsAfterGap() {
        var engine = GestureEngine()
        _ = engine.consume(points(), at: 1)
        XCTAssertNil(engine.consume(points(0.2), at: 2))
        XCTAssertEqual(engine.consume(points(0.0), at: 2.1), .left)
    }
    func testInvalidContactsDoNotCrashOrTrigger() {
        var engine = GestureEngine()
        let duplicate = Array(repeating: Contact(id: 1, x: 0.4, y: 0.4), count: 3)
        XCTAssertNil(engine.consume(duplicate, at: 1))
        _ = engine.consume([], at: 1.1)
        XCTAssertNil(engine.consume(points(), at: .nan))
    }
    func testDisplayCoordinatesAboveAndBelowPrimary() {
        XCTAssertEqual(WindowGeometry.axRect(from: CGRect(x: -1200, y: 1000, width: 1200, height: 800), primaryHeight: 1000), CGRect(x: -1200, y: -800, width: 1200, height: 800))
        XCTAssertEqual(WindowGeometry.axRect(from: CGRect(x: 0, y: -800, width: 1200, height: 800), primaryHeight: 1000).minY, 1000)
    }
    func testHalfScreenGapAndCenterDoNotExceedVisibleArea() {
        let area = CGRect(x: -1440, y: -900, width: 1440, height: 850)
        let current = CGRect(x: 0, y: 0, width: 2000, height: 1200)
        let left = WindowGeometry.target(.leftHalf, visible: area, current: current, gap: 8)
        let right = WindowGeometry.target(.rightHalf, visible: area, current: current, gap: 8)
        XCTAssertEqual(right.minX - left.maxX, 8)
        XCTAssertTrue(area.contains(left)); XCTAssertTrue(area.contains(right))
        XCTAssertTrue(area.contains(WindowGeometry.target(.center, visible: area, current: current, gap: 8)))
    }
}
