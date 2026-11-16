import CoreGraphics

enum RemoteVerticalPlacement {
    case center
    case bottom
}

enum RemoteWheelDirection: Equatable {
    case up, down, left, right
}

enum RemoteGeometry {
    static let minimumZoomScale: CGFloat = 1
    static let maximumZoomScale: CGFloat = 4

    static func aspectFitRect(
        imageSize: CGSize,
        in bounds: CGRect,
        placement: RemoteVerticalPlacement = .center
    ) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return .zero
        }

        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let y: CGFloat = switch placement {
        case .center:
            bounds.midY - size.height / 2
        case .bottom:
            bounds.maxY - size.height
        }

        return CGRect(
            x: bounds.midX - size.width / 2,
            y: y,
            width: size.width,
            height: size.height
        )
    }

    /// `displayScale` is the local screen scale (1, 2, or 3). View deltas are already
    /// in points, and the remote pointer space is framebuffer pixels. Dividing this
    /// result by `displayScale` stops the pointer at `1/scale` of the desktop.
    static func framebufferDelta(
        fromViewDelta delta: CGPoint,
        framebufferSize: CGSize,
        viewSize: CGSize,
        sensitivity: CGFloat = 1.6,
        zoomScale: CGFloat = minimumZoomScale,
        displayScale: CGFloat = 1,
        bitmapPixelSize: CGSize? = nil
    ) -> CGPoint {
        let pixels = pointerPixelSize(
            reportedSize: framebufferSize,
            displayScale: displayScale,
            bitmapPixelSize: bitmapPixelSize
        )
        guard pixels.width > 0,
              pixels.height > 0,
              viewSize.width > 0,
              viewSize.height > 0 else {
            return .zero
        }

        let scale = max(pixels.width / viewSize.width, pixels.height / viewSize.height)
            / clampedZoomScale(zoomScale)
        return CGPoint(x: delta.x * scale * sensitivity, y: delta.y * scale * sensitivity)
    }

    static func clamp(_ point: CGPoint, to size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGPoint(
            x: min(max(point.x, 0), size.width - 1),
            y: min(max(point.y, 0), size.height - 1)
        )
    }

    /// Pointer space for a VNC framebuffer.
    ///
    /// `reportedSize` is the size the protocol advertised. A bitmap that is a clean
    /// integer multiple of that size (2x, 3x, …) is the pixel framebuffer, and the
    /// pointer has to be able to reach its far edges. The local screen scale must
    /// not invent that multiple, and it must not shrink the space to `size / scale`.
    static func pointerPixelSize(
        reportedSize: CGSize,
        displayScale: CGFloat = 1,
        bitmapPixelSize: CGSize? = nil
    ) -> CGSize {
        let scale = sanitizedDisplayScale(displayScale)
        if let bitmap = bitmapPixelSize,
           let multiple = integerPixelScale(reported: reportedSize, bitmap: bitmap) {
            return CGSize(
                width: reportedSize.width * CGFloat(multiple),
                height: reportedSize.height * CGFloat(multiple)
            )
        }
        guard reportedSize.width > 0, reportedSize.height > 0, scale >= 1 else {
            return bitmapPixelSize ?? .zero
        }
        return reportedSize
    }

    /// Folds a pixel-space pointer back into the protocol framebuffer.
    /// RoyalVNC drops coordinates past the advertised size, so a 2x bitmap has to be
    /// scaled back proportionally. The pixel edge maps to the protocol edge, not to
    /// the center of the desktop.
    static func protocolPoint(
        fromPixelPoint point: CGPoint,
        pixelSize: CGSize,
        protocolSize: CGSize
    ) -> CGPoint {
        guard pixelSize.width > 0,
              pixelSize.height > 0,
              protocolSize.width > 0,
              protocolSize.height > 0 else {
            return .zero
        }
        return clamp(
            CGPoint(
                x: (point.x * protocolSize.width / pixelSize.width).rounded(),
                y: (point.y * protocolSize.height / pixelSize.height).rounded()
            ),
            to: protocolSize
        )
    }

    static func sanitizedDisplayScale(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite, scale >= 1 else { return 1 }
        return scale
    }

    /// Both axes must share one integer multiple of at least 2. A mismatched or
    /// fractional bitmap is not a Retina framebuffer.
    static func integerPixelScale(reported: CGSize, bitmap: CGSize) -> Int? {
        guard reported.width > 0,
              reported.height > 0,
              bitmap.width > 0,
              bitmap.height > 0 else {
            return nil
        }
        let widthScale = bitmap.width / reported.width
        let heightScale = bitmap.height / reported.height
        guard widthScale.isFinite, heightScale.isFinite else { return nil }
        let multiple = widthScale.rounded()
        guard multiple >= 2,
              abs(widthScale - multiple) < 0.01,
              abs(heightScale - multiple) < 0.01,
              abs(bitmap.width - reported.width * multiple) < 1,
              abs(bitmap.height - reported.height * multiple) < 1 else {
            return nil
        }
        return Int(multiple)
    }

    static func clampedZoomScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minimumZoomScale), maximumZoomScale)
    }

    static func clampedPanOffset(
        _ offset: CGPoint,
        baseRect: CGRect,
        viewportRect: CGRect,
        zoomScale: CGFloat
    ) -> CGPoint {
        let scale = clampedZoomScale(zoomScale)
        let maximumX = max((baseRect.width * scale - viewportRect.width) / 2, 0)
        let maximumY = max((baseRect.height * scale - viewportRect.height) / 2, 0)

        return CGPoint(
            x: min(max(offset.x, -maximumX), maximumX),
            y: min(max(offset.y, -maximumY), maximumY)
        )
    }

    static func panOffsetFollowingCursor(
        normalizedCursorPoint: CGPoint,
        currentOffset: CGPoint,
        baseRect: CGRect,
        viewportRect: CGRect,
        zoomScale: CGFloat
    ) -> CGPoint {
        let imageRect = zoomedRect(
            baseRect: baseRect,
            zoomScale: zoomScale,
            panOffset: currentOffset
        )
        let cursor = CGPoint(
            x: imageRect.minX + normalizedCursorPoint.x * imageRect.width,
            y: imageRect.minY + normalizedCursorPoint.y * imageRect.height
        )
        var offset = currentOffset

        if cursor.x < viewportRect.minX {
            offset.x += viewportRect.minX - cursor.x
        } else if cursor.x > viewportRect.maxX {
            offset.x += viewportRect.maxX - cursor.x
        }

        if cursor.y < viewportRect.minY {
            offset.y += viewportRect.minY - cursor.y
        } else if cursor.y > viewportRect.maxY {
            offset.y += viewportRect.maxY - cursor.y
        }

        return clampedPanOffset(
            offset,
            baseRect: baseRect,
            viewportRect: viewportRect,
            zoomScale: zoomScale
        )
    }

    static func panOffsetKeepingFocalPointStable(
        currentOffset: CGPoint,
        focalPoint: CGPoint,
        baseCenter: CGPoint,
        oldScale: CGFloat,
        newScale: CGFloat
    ) -> CGPoint {
        guard oldScale > 0 else { return currentOffset }
        let scaleChange = newScale / oldScale

        return CGPoint(
            x: focalPoint.x - baseCenter.x
                - (focalPoint.x - baseCenter.x - currentOffset.x) * scaleChange,
            y: focalPoint.y - baseCenter.y
                - (focalPoint.y - baseCenter.y - currentOffset.y) * scaleChange
        )
    }

    static func zoomedRect(
        baseRect: CGRect,
        zoomScale: CGFloat,
        panOffset: CGPoint
    ) -> CGRect {
        let scale = clampedZoomScale(zoomScale)
        let size = CGSize(width: baseRect.width * scale, height: baseRect.height * scale)

        return CGRect(
            x: baseRect.midX + panOffset.x - size.width / 2,
            y: baseRect.midY + panOffset.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Maps a point in the view onto the remote framebuffer. Points in the letterbox
    /// clamp to the nearest desktop edge so a pointer can still reach that edge.
    ///
    /// `displayScale` must not change the result. Dividing the mapped point by the
    /// screen scale clamps it to the top-left `1/scale` of the desktop.
    static func framebufferPoint(
        fromViewPoint point: CGPoint,
        imageRect: CGRect,
        framebufferSize: CGSize,
        displayScale: CGFloat = 1,
        bitmapPixelSize: CGSize? = nil
    ) -> CGPoint {
        guard imageRect.width > 0, imageRect.height > 0 else { return .zero }
        let pixels = pointerPixelSize(
            reportedSize: framebufferSize,
            displayScale: displayScale,
            bitmapPixelSize: bitmapPixelSize
        )
        guard pixels.width > 0, pixels.height > 0 else { return .zero }
        return clamp(
            CGPoint(
                x: (point.x - imageRect.minX) / imageRect.width * pixels.width,
                y: (point.y - imageRect.minY) / imageRect.height * pixels.height
            ),
            to: pixels
        )
    }
}

enum RemoteScroll {
    /// Finger points that produce one wheel detent. A long swipe is not capped.
    static let pointsPerDetent: CGFloat = 4
    /// Scroll mode uses the same wheel path at twice the speed.
    static let scrollModePointsPerDetent: CGFloat = pointsPerDetent / 2
    /// Trackpad and mouse-wheel travel uses the historical 10-point step size.
    static let pointsPerStep: CGFloat = 10
    /// Historical per-event cap for the older finger-swipe path. Pointer scroll does not use it.
    static let touchStepCap = 6

    typealias Direction = RemoteWheelDirection

    struct Tick: Equatable {
        var direction: RemoteWheelDirection
        var steps: Int
    }

    struct Event: Equatable {
        var direction: Direction
        var steps: UInt32
    }

    static func consume(
        _ translation: CGPoint,
        remainder: inout CGPoint,
        pointsPerDetent: CGFloat = pointsPerDetent
    ) -> Tick? {
        remainder.x += translation.x
        remainder.y += translation.y
        let vertical = abs(remainder.y) >= abs(remainder.x)
        let distance = vertical ? remainder.y : remainder.x
        let steps = Int(abs(distance) / pointsPerDetent)
        guard steps > 0 else { return nil }

        let consumed = CGFloat(steps) * pointsPerDetent
        let sign: CGFloat = distance < 0 ? -1 : 1
        let leftover = sign * (abs(distance) - consumed)
        if vertical {
            remainder.y = leftover
            return Tick(direction: distance < 0 ? .down : .up, steps: steps)
        }
        remainder.x = leftover
        return Tick(direction: distance < 0 ? .right : .left, steps: steps)
    }

    /// Finger swipes keep the original 6-step cap. Distance below one step sends nothing.
    static func touchSteps(forDistance distance: CGFloat) -> UInt32 {
        guard abs(distance) >= pointsPerStep else { return 0 }
        return UInt32(min(max(Int(abs(distance) / pointsPerStep), 1), touchStepCap))
    }

    /// Trackpad and mouse-wheel travel. Whole steps are sent with no upper cap, and the
    /// fractional remainder stays so a later event can complete the next step.
    static func pointerSteps(delta: CGPoint, remainder: inout CGPoint) -> [Event] {
        remainder.x += delta.x
        remainder.y += delta.y
        var events: [Event] = []
        if let vertical = consumeAxis(&remainder.y, negative: .down, positive: .up) {
            events.append(vertical)
        }
        if let horizontal = consumeAxis(&remainder.x, negative: .right, positive: .left) {
            events.append(horizontal)
        }
        return events
    }

    private static func consumeAxis(
        _ axis: inout CGFloat,
        negative: Direction,
        positive: Direction
    ) -> Event? {
        let raw = Int(axis / pointsPerStep)
        guard raw != 0 else { return nil }
        axis -= CGFloat(raw) * pointsPerStep
        return Event(direction: raw < 0 ? negative : positive, steps: UInt32(abs(raw)))
    }
}
