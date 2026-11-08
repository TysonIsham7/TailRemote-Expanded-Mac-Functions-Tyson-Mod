import CoreGraphics
import XCTest
@testable import TailRemote

final class RemoteGeometryTests: XCTestCase {
    func testAspectFitCentersWideDesktop() {
        let rect = RemoteGeometry.aspectFitRect(
            imageSize: CGSize(width: 1920, height: 1080),
            in: CGRect(x: 0, y: 0, width: 390, height: 844)
        )

        XCTAssertEqual(rect.width, 390, accuracy: 0.001)
        XCTAssertEqual(rect.height, 219.375, accuracy: 0.001)
        XCTAssertEqual(rect.midY, 422, accuracy: 0.001)
    }

    func testKeyboardInsetPinsTheDesktopAboveTheKeyboard() {
        let screen = CGRect(x: 0, y: 0, width: 390, height: 844)
        let covered: CGFloat = 360
        let visible = screen.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: covered, right: 0))
        let rect = RemoteGeometry.aspectFitRect(
            imageSize: CGSize(width: 1920, height: 1080),
            in: visible,
            placement: .bottom
        )

        XCTAssertEqual(rect.maxY, visible.maxY, accuracy: 0.001)
        XCTAssertLessThanOrEqual(rect.maxY, screen.height - covered + 0.001)
        XCTAssertEqual(rect.width, visible.width, accuracy: 0.001)
    }

    func testCenteredInsetKeepsTheDesktopInTheOpenArea() {
        let screen = CGRect(x: 0, y: 0, width: 390, height: 844)
        let covered: CGFloat = 360
        let visible = screen.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: covered, right: 0))
        let rect = RemoteGeometry.aspectFitRect(
            imageSize: CGSize(width: 1920, height: 1080),
            in: visible
        )

        XCTAssertEqual(rect.midY, visible.midY, accuracy: 0.001)
        XCTAssertLessThanOrEqual(rect.maxY, screen.height - covered + 0.001)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
    }

    func testClampKeepsPointerInsideFramebuffer() {
        let point = RemoteGeometry.clamp(
            CGPoint(x: -20, y: 1400),
            to: CGSize(width: 1920, height: 1080)
        )

        XCTAssertEqual(point.x, 0)
        XCTAssertEqual(point.y, 1079)
    }

    func testPointerDeltaScalesToRemoteDesktop() {
        let delta = RemoteGeometry.framebufferDelta(
            fromViewDelta: CGPoint(x: 10, y: -5),
            framebufferSize: CGSize(width: 1920, height: 1080),
            viewSize: CGSize(width: 390, height: 844),
            sensitivity: 1
        )

        XCTAssertEqual(delta.x, 49.2307, accuracy: 0.001)
        XCTAssertEqual(delta.y, -24.6153, accuracy: 0.001)
    }

    func testZoomScaleIsLimitedToOneThroughFour() {
        XCTAssertEqual(RemoteGeometry.clampedZoomScale(0.5), 1)
        XCTAssertEqual(RemoteGeometry.clampedZoomScale(2.5), 2.5)
        XCTAssertEqual(RemoteGeometry.clampedZoomScale(8), 4)
    }

    func testPointerTravelOnScreenIsConsistentAtEveryZoomLevel() {
        let framebuffer = CGSize(width: 1920, height: 1080)
        let viewports = [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390)]
        let fingerDelta = CGPoint(x: 10, y: -5)

        for viewport in viewports {
            let baseRect = RemoteGeometry.aspectFitRect(
                imageSize: framebuffer,
                in: CGRect(origin: .zero, size: viewport)
            )
            for zoom: CGFloat in [1, 2, 4] {
                let delta = RemoteGeometry.framebufferDelta(
                    fromViewDelta: fingerDelta,
                    framebufferSize: framebuffer,
                    viewSize: baseRect.size,
                    zoomScale: zoom
                )
                XCTAssertEqual(delta.x * baseRect.width * zoom / framebuffer.width, 16, accuracy: 0.001)
                XCTAssertEqual(delta.y * baseRect.height * zoom / framebuffer.height, -8, accuracy: 0.001)
            }
        }
    }

    func testPointerDeltaClampsZoomAndHandlesEmptyGeometry() {
        let framebuffer = CGSize(width: 1920, height: 1080)
        let view = CGSize(width: 390, height: 219.375)
        let delta = CGPoint(x: 10, y: 5)

        for (requestedZoom, effectiveZoom): (CGFloat, CGFloat) in [(0, 1), (10, 4)] {
            XCTAssertEqual(
                RemoteGeometry.framebufferDelta(
                    fromViewDelta: delta, framebufferSize: framebuffer, viewSize: view, zoomScale: requestedZoom
                ),
                RemoteGeometry.framebufferDelta(
                    fromViewDelta: delta, framebufferSize: framebuffer, viewSize: view, zoomScale: effectiveZoom
                )
            )
        }
        XCTAssertEqual(
            RemoteGeometry.framebufferDelta(
                fromViewDelta: delta, framebufferSize: .zero, viewSize: view, zoomScale: 4
            ),
            .zero
        )
        XCTAssertEqual(
            RemoteGeometry.framebufferDelta(
                fromViewDelta: delta, framebufferSize: framebuffer, viewSize: .zero, zoomScale: 4
            ),
            .zero
        )
    }

    func testPanOffsetStaysInsideZoomedDesktop() {
        let offset = RemoteGeometry.clampedPanOffset(
            CGPoint(x: 500, y: -500),
            baseRect: CGRect(x: 0, y: 0, width: 390, height: 220),
            viewportRect: CGRect(x: 0, y: 0, width: 390, height: 844),
            zoomScale: 2
        )

        XCTAssertEqual(offset.x, 195)
        XCTAssertEqual(offset.y, 0)
    }

    func testPanOffsetSupportsBothAxesWhenContentExceedsViewport() {
        let offset = RemoteGeometry.clampedPanOffset(
            CGPoint(x: 900, y: -900),
            baseRect: CGRect(x: 0, y: 312, width: 390, height: 220),
            viewportRect: CGRect(x: 56, y: 88, width: 278, height: 668),
            zoomScale: 4
        )

        XCTAssertEqual(offset.x, 641)
        XCTAssertEqual(offset.y, -106)
    }

    func testViewportFollowsCursorAtZoomedEdge() {
        let offset = RemoteGeometry.panOffsetFollowingCursor(
            normalizedCursorPoint: CGPoint(x: 1, y: 1),
            currentOffset: .zero,
            baseRect: CGRect(x: 0, y: 312, width: 390, height: 220),
            viewportRect: CGRect(x: 56, y: 88, width: 278, height: 668),
            zoomScale: 4
        )

        XCTAssertEqual(offset.x, -641)
        XCTAssertEqual(offset.y, -106)
    }

    func testPinchKeepsFocalPointStationary() {
        let offset = RemoteGeometry.panOffsetKeepingFocalPointStable(
            currentOffset: .zero,
            focalPoint: CGPoint(x: 100, y: 300),
            baseCenter: CGPoint(x: 195, y: 422),
            oldScale: 1,
            newScale: 2
        )

        XCTAssertEqual(offset.x, 95)
        XCTAssertEqual(offset.y, 122)
    }

    func testOneFingerSwipeScrollsFortyDetents() {
        var remainder = CGPoint.zero
        let tick = RemoteScroll.consume(CGPoint(x: 0, y: -160), remainder: &remainder)

        XCTAssertEqual(tick, RemoteScroll.Tick(direction: .down, steps: 40))
        XCTAssertEqual(remainder, .zero)
    }

    func testScrollModeDoublesDetentsForTheSameSwipe() {
        var remainder = CGPoint.zero
        let tick = RemoteScroll.consume(
            CGPoint(x: 0, y: -160),
            remainder: &remainder,
            pointsPerDetent: RemoteScroll.scrollModePointsPerDetent
        )

        XCTAssertEqual(tick, RemoteScroll.Tick(direction: .down, steps: 80))
        XCTAssertEqual(remainder, .zero)
    }

    func testScrollDistanceSurvivesBeingSplitAcrossSamples() {
        var remainder = CGPoint.zero
        var steps = 0
        for _ in 0..<16 {
            if let tick = RemoteScroll.consume(CGPoint(x: 0, y: -10), remainder: &remainder) {
                XCTAssertEqual(tick.direction, .down)
                steps += tick.steps
            }
        }

        XCTAssertEqual(steps, 40, "Sixteen 10-point samples are the same 160-point swipe, not six detents")
        XCTAssertEqual(remainder, .zero)
    }

    func testShortTravelKeepsTheUnusedFractionForTheNextSample() {
        var remainder = CGPoint.zero
        XCTAssertNil(RemoteScroll.consume(CGPoint(x: 0, y: 3), remainder: &remainder))
        let tick = RemoteScroll.consume(CGPoint(x: 0, y: 5), remainder: &remainder)

        XCTAssertEqual(tick, RemoteScroll.Tick(direction: .up, steps: 2))
        XCTAssertEqual(remainder.y, 0, accuracy: 0.001)
    }

    func testHorizontalSwipeChoosesTheDominantAxis() {
        var remainder = CGPoint.zero
        let tick = RemoteScroll.consume(CGPoint(x: -80, y: 6), remainder: &remainder)

        XCTAssertEqual(tick, RemoteScroll.Tick(direction: .right, steps: 20))
        XCTAssertEqual(remainder.y, 6, accuracy: 0.001)
    }

    func testTrackpadTapClickAndCommandClick() {
        var remainder = CGPoint.zero
        XCTAssertEqual(
            RemoteTrackpad.actions(for: .tap, commandHeld: false, remainder: &remainder),
            [.click]
        )
        XCTAssertEqual(
            RemoteTrackpad.actions(for: .tap, commandHeld: true, remainder: &remainder),
            [.holdCommand(true), .click, .holdCommand(false)]
        )
        XCTAssertEqual(
            RemoteTrackpad.actions(for: .twoFingerTap, commandHeld: false, remainder: &remainder),
            [.rightClick]
        )
    }

    func testTrackpadMoveIsRelativeAndDragHoldsTheButton() {
        var remainder = CGPoint.zero
        let delta = CGPoint(x: 12, y: -4)
        XCTAssertEqual(
            RemoteTrackpad.actions(for: .move(delta), commandHeld: false, remainder: &remainder),
            [.move(delta)]
        )
        XCTAssertEqual(
            RemoteTrackpad.actions(for: .dragBegan, commandHeld: false, remainder: &remainder),
            [.buttonDown]
        )
        XCTAssertEqual(
            RemoteTrackpad.actions(for: .dragMoved(delta), commandHeld: false, remainder: &remainder),
            [.move(delta)]
        )
        XCTAssertEqual(
            RemoteTrackpad.actions(for: .dragEnded, commandHeld: false, remainder: &remainder),
            [.buttonUp]
        )
    }

    func testTrackpadCommandDragHoldsCommandAroundTheClick() {
        var remainder = CGPoint.zero
        XCTAssertEqual(
            RemoteTrackpad.actions(for: .dragBegan, commandHeld: true, remainder: &remainder),
            [.holdCommand(true), .buttonDown]
        )
        XCTAssertEqual(
            RemoteTrackpad.actions(for: .dragEnded, commandHeld: true, remainder: &remainder),
            [.buttonUp, .holdCommand(false)]
        )
    }

    func testTrackpadTwoFingerSwipeMapsToWheelDetents() {
        var remainder = CGPoint.zero
        XCTAssertEqual(
            RemoteTrackpad.actions(
                for: .twoFingerMove(CGPoint(x: 0, y: -16)),
                commandHeld: false,
                remainder: &remainder
            ),
            [.scroll(.down, 4)]
        )
        XCTAssertEqual(remainder, .zero)
    }

    func testTrackpadThreeFingerSwipesMapToMissionControlAndSpaces() {
        var remainder = CGPoint.zero
        XCTAssertEqual(
            RemoteTrackpad.actions(for: .threeFingerSwipe(.up), commandHeld: false, remainder: &remainder),
            [.missionControl]
        )
        XCTAssertEqual(
            RemoteTrackpad.actions(for: .threeFingerSwipe(.down), commandHeld: false, remainder: &remainder),
            [.appExpose]
        )
        XCTAssertEqual(
            RemoteTrackpad.actions(for: .threeFingerSwipe(.left), commandHeld: false, remainder: &remainder),
            [.previousSpace]
        )
        XCTAssertEqual(
            RemoteTrackpad.actions(for: .threeFingerSwipe(.right), commandHeld: false, remainder: &remainder),
            [.nextSpace]
        )
    }

    func testTapAndDragArmsOnlyJustAfterATap() {
        XCTAssertFalse(RemoteTrackpad.beginsDrag(secondsSinceTap: nil))
        XCTAssertTrue(RemoteTrackpad.beginsDrag(secondsSinceTap: 0.2))
        XCTAssertFalse(RemoteTrackpad.beginsDrag(secondsSinceTap: 1))
    }

    func testThreeFingerClassifierUsesTheDominantAxis() {
        XCTAssertEqual(RemoteTrackpad.threeFingerSwipe(translation: CGPoint(x: 4, y: -40)), .up)
        XCTAssertEqual(RemoteTrackpad.threeFingerSwipe(translation: CGPoint(x: 40, y: -4)), .right)
        XCTAssertEqual(RemoteTrackpad.threeFingerSwipe(translation: CGPoint(x: -30, y: 2)), .left)
        XCTAssertNil(RemoteTrackpad.threeFingerSwipe(translation: CGPoint(x: 8, y: -8)))
    }

    func testZoomedRectUsesScaleAndPanOffset() {
        let rect = RemoteGeometry.zoomedRect(
            baseRect: CGRect(x: 0, y: 300, width: 390, height: 220),
            zoomScale: 2,
            panOffset: CGPoint(x: 40, y: -20)
        )

        XCTAssertEqual(rect, CGRect(x: -155, y: 170, width: 780, height: 440))
    }
    func testAspectFitKeepsTheDesktopInsideEveryWindowShape() {
        let desktop = CGSize(width: 1920, height: 1080)
        let windows = [
            CGRect(x: 0, y: 0, width: 1366, height: 1024),
            CGRect(x: 0, y: 0, width: 1024, height: 1366),
            CGRect(x: 0, y: 0, width: 320, height: 800),
            CGRect(x: 40, y: 20, width: 800, height: 800),
            CGRect(x: 0, y: 0, width: 1400, height: 400),
        ]

        for window in windows {
            let rect = RemoteGeometry.aspectFitRect(imageSize: desktop, in: window)
            XCTAssertGreaterThan(rect.width, 0)
            XCTAssertGreaterThanOrEqual(rect.minX, window.minX - 0.001)
            XCTAssertGreaterThanOrEqual(rect.minY, window.minY - 0.001)
            XCTAssertLessThanOrEqual(rect.maxX, window.maxX + 0.001)
            XCTAssertLessThanOrEqual(rect.maxY, window.maxY + 0.001)
            XCTAssertEqual(rect.width / rect.height, desktop.width / desktop.height, accuracy: 0.001)
            XCTAssertEqual(rect.midX, window.midX, accuracy: 0.001)
            XCTAssertEqual(rect.midY, window.midY, accuracy: 0.001)
        }
    }

    func testFramebufferPointMapsThePointerOntoTheDesktop() {
        let image = CGRect(x: 10, y: 20, width: 200, height: 100)
        let desktop = CGSize(width: 1920, height: 1080)

        let origin = RemoteGeometry.framebufferPoint(
            fromViewPoint: CGPoint(x: 10, y: 20),
            imageRect: image,
            framebufferSize: desktop
        )
        XCTAssertEqual(origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(origin.y, 0, accuracy: 0.001)

        let center = RemoteGeometry.framebufferPoint(
            fromViewPoint: CGPoint(x: 110, y: 70),
            imageRect: image,
            framebufferSize: desktop
        )
        XCTAssertEqual(center.x, 960, accuracy: 0.001)
        XCTAssertEqual(center.y, 540, accuracy: 0.001)

        let outside = RemoteGeometry.framebufferPoint(
            fromViewPoint: CGPoint(x: 400, y: -10),
            imageRect: image,
            framebufferSize: desktop
        )
        XCTAssertEqual(outside.x, 1919, accuracy: 0.001)
        XCTAssertEqual(outside.y, 0, accuracy: 0.001)
    }

    func testPointerReachesAllFourEdgesAtEveryDisplayScale() {
        let pixels = CGSize(width: 3024, height: 1964)
        let image = CGRect(
            x: 16,
            y: 24,
            width: 900,
            height: 900 * pixels.height / pixels.width
        )

        for scale: CGFloat in [1, 2, 3] {
            let origin = RemoteGeometry.framebufferPoint(
                fromViewPoint: CGPoint(x: image.minX, y: image.minY),
                imageRect: image,
                framebufferSize: pixels,
                displayScale: scale
            )
            XCTAssertEqual(origin.x, 0, accuracy: 0.001)
            XCTAssertEqual(origin.y, 0, accuracy: 0.001)

            let far = RemoteGeometry.framebufferPoint(
                fromViewPoint: CGPoint(x: image.maxX, y: image.maxY),
                imageRect: image,
                framebufferSize: pixels,
                displayScale: scale
            )
            XCTAssertEqual(far.x, pixels.width - 1, accuracy: 0.001)
            XCTAssertEqual(far.y, pixels.height - 1, accuracy: 0.001)
            if scale > 1 {
                XCTAssertGreaterThan(far.x, pixels.width / scale)
                XCTAssertGreaterThan(far.y, pixels.height / scale)
            }

            let letterbox = RemoteGeometry.framebufferPoint(
                fromViewPoint: CGPoint(x: image.maxX + 80, y: -40),
                imageRect: image,
                framebufferSize: pixels,
                displayScale: scale
            )
            XCTAssertEqual(letterbox.x, pixels.width - 1, accuracy: 0.001)
            XCTAssertEqual(letterbox.y, 0, accuracy: 0.001)

            let drag = RemoteGeometry.framebufferDelta(
                fromViewDelta: CGPoint(x: image.width, y: image.height),
                framebufferSize: pixels,
                viewSize: image.size,
                sensitivity: 1,
                displayScale: scale
            )
            XCTAssertGreaterThanOrEqual(drag.x, pixels.width - 1)
            XCTAssertGreaterThanOrEqual(drag.y, pixels.height - 1)
            if scale > 1 {
                XCTAssertGreaterThan(drag.x, pixels.width / scale)
                XCTAssertGreaterThan(drag.y, pixels.height / scale)
            }

            let clamped = RemoteGeometry.clamp(
                CGPoint(x: pixels.width * 2, y: pixels.height * 2),
                to: pixels
            )
            XCTAssertEqual(clamped.x, pixels.width - 1)
            XCTAssertEqual(clamped.y, pixels.height - 1)
            if scale > 1 {
                XCTAssertGreaterThan(clamped.x, pixels.width / scale - 1)
                XCTAssertGreaterThan(clamped.y, pixels.height / scale - 1)
            }
        }
    }

    func testRetinaBitmapExpandsPointerSpaceWithoutUsingDeviceScale() {
        let points = CGSize(width: 1512, height: 982)
        let retina = CGSize(width: 3024, height: 1964)
        XCTAssertEqual(
            RemoteGeometry.pointerPixelSize(reportedSize: points, displayScale: 2, bitmapPixelSize: retina),
            retina
        )
        XCTAssertEqual(
            RemoteGeometry.pointerPixelSize(
                reportedSize: CGSize(width: 1000, height: 800),
                displayScale: 3,
                bitmapPixelSize: CGSize(width: 3000, height: 2400)
            ),
            CGSize(width: 3000, height: 2400)
        )

        let same = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(
            RemoteGeometry.pointerPixelSize(reportedSize: same, displayScale: 3, bitmapPixelSize: same),
            same
        )
        XCTAssertEqual(
            RemoteGeometry.pointerPixelSize(
                reportedSize: same,
                displayScale: 2,
                bitmapPixelSize: CGSize(width: 2000, height: 1100)
            ),
            same
        )
        XCTAssertEqual(RemoteGeometry.pointerPixelSize(reportedSize: same, displayScale: 3), same)

        let image = CGRect(x: 0, y: 0, width: 400, height: 260)
        let far = RemoteGeometry.framebufferPoint(
            fromViewPoint: CGPoint(x: image.maxX, y: image.maxY),
            imageRect: image,
            framebufferSize: points,
            displayScale: 2,
            bitmapPixelSize: retina
        )
        XCTAssertEqual(far.x, retina.width - 1, accuracy: 0.001)
        XCTAssertEqual(far.y, retina.height - 1, accuracy: 0.001)
        XCTAssertGreaterThan(far.x, points.width)
        XCTAssertGreaterThan(far.y, points.height)

        let wire = RemoteGeometry.protocolPoint(
            fromPixelPoint: far,
            pixelSize: retina,
            protocolSize: points
        )
        XCTAssertEqual(wire.x, points.width - 1, accuracy: 0.001)
        XCTAssertEqual(wire.y, points.height - 1, accuracy: 0.001)
        XCTAssertGreaterThan(wire.x, points.width / 2)
        XCTAssertGreaterThan(wire.y, points.height / 2)
    }

    /// A half-scale Screen Sharing picture is 1440×900 on a 2880×1800 Mac.
    /// Mapping the bottom of that picture and sending it on the full desktop
    /// stops the Mac cursor halfway down. Full resolution, Retina 2×/3×, and
    /// a non-Retina grid all stay on the far edge instead.
    func testFullResolutionEdgesStayPastTheHalfScaleHalfwayCursor() {
        let desktop = CGSize(width: 2880, height: 1800)
        let half = CGSize(width: desktop.width / 2, height: desktop.height / 2)
        let fullImage = CGRect(x: 8, y: 20, width: 360, height: 360 * desktop.height / desktop.width)
        let halfImage = CGRect(x: 8, y: 20, width: 360, height: 360 * half.height / half.width)
        let nonRetina = CGSize(width: 1920, height: 1080)
        let nonRetinaImage = CGRect(x: 0, y: 0, width: 480, height: 480 * nonRetina.height / nonRetina.width)
        let points3x = CGSize(width: 1000, height: 700)
        let pixels3x = CGSize(width: 3000, height: 2100)
        let image3x = CGRect(x: 0, y: 0, width: 300, height: 300 * pixels3x.height / pixels3x.width)

        for displayScale: CGFloat in [1, 2, 3] {
            let full = RemoteGeometry.framebufferPoint(
                fromViewPoint: CGPoint(x: fullImage.maxX, y: fullImage.maxY),
                imageRect: fullImage,
                framebufferSize: desktop,
                displayScale: displayScale
            )
            XCTAssertEqual(full.x, desktop.width - 1, accuracy: 0.001)
            XCTAssertEqual(full.y, desktop.height - 1, accuracy: 0.001)
            XCTAssertGreaterThan(full.y, desktop.height / 2)
            XCTAssertGreaterThan(full.x, desktop.width / 2)

            let shrunk = RemoteGeometry.framebufferPoint(
                fromViewPoint: CGPoint(x: halfImage.maxX, y: halfImage.maxY),
                imageRect: halfImage,
                framebufferSize: half,
                displayScale: displayScale
            )
            XCTAssertEqual(shrunk.x, half.width - 1, accuracy: 0.001)
            XCTAssertEqual(shrunk.y, half.height - 1, accuracy: 0.001)
            XCTAssertEqual(shrunk.y, desktop.height / 2 - 1, accuracy: 0.001)
            XCTAssertLessThan(shrunk.y, desktop.height * 0.6)
            XCTAssertGreaterThan(full.y - shrunk.y, desktop.height * 0.4)

            let fullDrag = RemoteGeometry.framebufferDelta(
                fromViewDelta: CGPoint(x: fullImage.width, y: fullImage.height),
                framebufferSize: desktop,
                viewSize: fullImage.size,
                sensitivity: 1,
                displayScale: displayScale
            )
            XCTAssertGreaterThanOrEqual(fullDrag.x, desktop.width - 1)
            XCTAssertGreaterThanOrEqual(fullDrag.y, desktop.height - 1)
            XCTAssertGreaterThan(fullDrag.y, desktop.height / 2)

            let halfDrag = RemoteGeometry.framebufferDelta(
                fromViewDelta: CGPoint(x: halfImage.width, y: halfImage.height),
                framebufferSize: half,
                viewSize: halfImage.size,
                sensitivity: 1,
                displayScale: displayScale
            )
            XCTAssertLessThan(halfDrag.y, desktop.height * 0.6)
            XCTAssertEqual(halfDrag.y, desktop.height / 2, accuracy: 0.001)

            let retinaPixel = RemoteGeometry.framebufferPoint(
                fromViewPoint: CGPoint(x: fullImage.maxX, y: fullImage.maxY),
                imageRect: fullImage,
                framebufferSize: half,
                displayScale: displayScale,
                bitmapPixelSize: desktop
            )
            XCTAssertEqual(retinaPixel.x, desktop.width - 1, accuracy: 0.001)
            XCTAssertEqual(retinaPixel.y, desktop.height - 1, accuracy: 0.001)
            let retinaWire = RemoteGeometry.protocolPoint(
                fromPixelPoint: retinaPixel,
                pixelSize: desktop,
                protocolSize: half
            )
            XCTAssertEqual(retinaWire.x, half.width - 1, accuracy: 0.001)
            XCTAssertEqual(retinaWire.y, half.height - 1, accuracy: 0.001)
            XCTAssertGreaterThan(retinaWire.y, half.height / 2)
            XCTAssertGreaterThan(retinaWire.x, half.width / 2)

            let scale3Pixel = RemoteGeometry.framebufferPoint(
                fromViewPoint: CGPoint(x: image3x.maxX, y: image3x.maxY),
                imageRect: image3x,
                framebufferSize: points3x,
                displayScale: displayScale,
                bitmapPixelSize: pixels3x
            )
            XCTAssertEqual(scale3Pixel.x, pixels3x.width - 1, accuracy: 0.001)
            XCTAssertEqual(scale3Pixel.y, pixels3x.height - 1, accuracy: 0.001)
            XCTAssertGreaterThan(scale3Pixel.y, pixels3x.height / 3)
            let scale3Wire = RemoteGeometry.protocolPoint(
                fromPixelPoint: scale3Pixel,
                pixelSize: pixels3x,
                protocolSize: points3x
            )
            XCTAssertEqual(scale3Wire.x, points3x.width - 1, accuracy: 0.001)
            XCTAssertEqual(scale3Wire.y, points3x.height - 1, accuracy: 0.001)
            XCTAssertGreaterThan(scale3Wire.y, points3x.height / 2)

            let plain = RemoteGeometry.framebufferPoint(
                fromViewPoint: CGPoint(x: nonRetinaImage.maxX, y: nonRetinaImage.maxY),
                imageRect: nonRetinaImage,
                framebufferSize: nonRetina,
                displayScale: displayScale
            )
            XCTAssertEqual(plain.x, nonRetina.width - 1, accuracy: 0.001)
            XCTAssertEqual(plain.y, nonRetina.height - 1, accuracy: 0.001)
            XCTAssertGreaterThan(plain.y, nonRetina.height / 2)
            let plainWire = RemoteGeometry.protocolPoint(
                fromPixelPoint: plain,
                pixelSize: nonRetina,
                protocolSize: nonRetina
            )
            XCTAssertEqual(plainWire.x, nonRetina.width - 1, accuracy: 0.001)
            XCTAssertEqual(plainWire.y, nonRetina.height - 1, accuracy: 0.001)
        }
    }

    func testFramebufferPointFollowsZoomAndPan() {
        let base = CGRect(x: 0, y: 0, width: 200, height: 100)
        let zoomed = RemoteGeometry.zoomedRect(baseRect: base, zoomScale: 2, panOffset: .zero)
        let desktop = CGSize(width: 1920, height: 1080)
        let point = RemoteGeometry.framebufferPoint(
            fromViewPoint: CGPoint(x: base.midX, y: base.midY),
            imageRect: zoomed,
            framebufferSize: desktop
        )

        XCTAssertEqual(point.x, 960, accuracy: 0.001)
        XCTAssertEqual(point.y, 540, accuracy: 0.001)
    }

    func testFingerScrollStaysCappedAtSixSteps() {
        XCTAssertEqual(RemoteScroll.touchSteps(forDistance: 9), 0)
        XCTAssertEqual(RemoteScroll.touchSteps(forDistance: 25), 2)
        XCTAssertEqual(RemoteScroll.touchSteps(forDistance: 100), 6)
        XCTAssertEqual(RemoteScroll.touchSteps(forDistance: -100), 6)
    }

    func testPointerScrollDoesNotCapLongMovement() {
        var remainder = CGPoint.zero
        let steps = RemoteScroll.pointerSteps(delta: CGPoint(x: 35, y: -100), remainder: &remainder)

        XCTAssertEqual(
            steps,
            [
                RemoteScroll.Event(direction: .down, steps: 10),
                RemoteScroll.Event(direction: .left, steps: 3),
            ]
        )
        XCTAssertEqual(remainder.x, 5, accuracy: 0.001)
        XCTAssertEqual(remainder.y, 0, accuracy: 0.001)
    }

    func testPointerScrollKeepsAFractionalRemainder() {
        var remainder = CGPoint.zero
        XCTAssertTrue(RemoteScroll.pointerSteps(delta: CGPoint(x: 0, y: -6), remainder: &remainder).isEmpty)
        let steps = RemoteScroll.pointerSteps(delta: CGPoint(x: 0, y: -8), remainder: &remainder)

        XCTAssertEqual(steps, [RemoteScroll.Event(direction: .down, steps: 1)])
        XCTAssertEqual(remainder.y, -4, accuracy: 0.001)
    }

}
