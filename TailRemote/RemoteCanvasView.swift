import Combine
import CoreGraphics
import RoyalVNCKit
import SwiftUI
import UIKit

struct RemoteClickFeedback {
    let point: CGPoint
    let button: VNCMouseButton
    let count: Int
}

@MainActor
protocol RemoteCanvasInput: AnyObject {
    var cursorPoint: CGPoint { get }
    var clickFeedback: PassthroughSubject<RemoteClickFeedback, Never> { get }
    func movePointer(viewDelta: CGPoint, viewSize: CGSize, zoomScale: CGFloat, displayScale: CGFloat)
    func movePointer(toFramebufferPoint point: CGPoint)
    func mouseDown(_ button: VNCMouseButton)
    func mouseUp(_ button: VNCMouseButton)
    func click(_ button: VNCMouseButton, count: Int)
    func scroll(_ wheel: VNCMouseWheel, steps: UInt32)
    func endScrollGesture()
}

extension RemoteCanvasInput {
    func endScrollGesture() {}
}

struct RemoteCanvasView: UIViewRepresentable {
    @ObservedObject var session: VNCSession
    var bottomInset: CGFloat = 0
    var pinsContentToBottom = false
    var scrollMode = false

    func makeUIView(context: Context) -> RemoteCanvasUIView {
        let view = RemoteCanvasUIView()
        view.session = session
        return view
    }

    func updateUIView(_ view: RemoteCanvasUIView, context: Context) {
        view.session = session
        view.bottomInset = bottomInset
        view.pinsContentToBottom = pinsContentToBottom
        view.scrollMode = scrollMode
        view.update(
            image: session.framebufferImage,
            framebufferSize: session.framebufferSize,
            cursorPoint: session.cursorPoint
        )
    }
}

@MainActor
final class RemoteCanvasUIView: UIView, UIGestureRecognizerDelegate {
    var session: (any RemoteCanvasInput)? {
        didSet {
            guard oldValue !== session else { return }
            clickFeedbackLayer.removeAllAnimations()
            clickFeedbackSubscription = session?.clickFeedback.sink { [weak self] click in
                self?.showClickFeedback(click)
            }
        }
    }

    private let imageLayer = CALayer()
    private let cursorLayer = CAShapeLayer()
    private let clickFeedbackLayer = CAShapeLayer()
    private var clickFeedbackSubscription: AnyCancellable?
    private var clickFeedbackPoint: CGPoint?
    private var framebufferSize: CGSize = .zero
    private var cursorPoint: CGPoint = .zero
    private var previousDragLocation: CGPoint?
    private var zoomScale = RemoteGeometry.minimumZoomScale
    private var panOffset: CGPoint = .zero
    private var isPinching = false
    private var selectionDragActive = false
    private var selectionDragArmedUntil: TimeInterval = 0
    private var scrollRemainder: CGPoint = .zero
    private var pointerScrollRemainder: CGPoint = .zero
    private var pointerDragIsDown = false
    private var dragRecognizer: UILongPressGestureRecognizer?
    private var pointerDragRecognizer: UIPanGestureRecognizer?
    private var pointerScrollRecognizer: UIPanGestureRecognizer?

    var bottomInset: CGFloat = 0
    var pinsContentToBottom = false
    var scrollMode = false {
        didSet {
            guard scrollMode != oldValue else { return }
            // A long-press drag uses the same finger as one-finger scroll and
            // used to claim the swipe after a short hold, so most of the
            // travel never became wheel detents.
            dragRecognizer?.isEnabled = !scrollMode
            scrollRemainder = .zero
            if !scrollMode {
                session?.endScrollGesture()
            }
        }
    }

    private var contentBounds: CGRect {
        let inset = min(max(bottomInset, 0), max(bounds.height - 1, 0))
        return bounds.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: inset, right: 0))
    }

    private var interactionViewport: CGRect {
        let area = contentBounds
        let horizontalInset = min(56, area.width * 0.15)
        let verticalInset = min(88, area.height * 0.15)
        return area.insetBy(dx: horizontalInset, dy: verticalInset)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        isMultipleTouchEnabled = true

        imageLayer.contentsGravity = .resizeAspect
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .trilinear
        configureFramebufferLayer()
        layer.addSublayer(imageLayer)

        clickFeedbackLayer.bounds = CGRect(x: 0, y: 0, width: 36, height: 36)
        clickFeedbackLayer.path = UIBezierPath(ovalIn: clickFeedbackLayer.bounds.insetBy(dx: 2, dy: 2)).cgPath
        clickFeedbackLayer.lineWidth = 2.5
        clickFeedbackLayer.opacity = 0
        clickFeedbackLayer.shadowColor = UIColor.black.cgColor
        clickFeedbackLayer.shadowOpacity = 0.6
        clickFeedbackLayer.shadowRadius = 2
        clickFeedbackLayer.shadowOffset = .zero
        layer.addSublayer(clickFeedbackLayer)

        cursorLayer.bounds = CGRect(x: 0, y: 0, width: 14, height: 14)
        cursorLayer.path = UIBezierPath(ovalIn: cursorLayer.bounds).cgPath
        cursorLayer.fillColor = UIColor.white.withAlphaComponent(0.88).cgColor
        cursorLayer.strokeColor = UIColor.black.withAlphaComponent(0.55).cgColor
        cursorLayer.lineWidth = 1.5
        cursorLayer.shadowColor = UIColor.black.cgColor
        cursorLayer.shadowOpacity = 0.45
        cursorLayer.shadowRadius = 3
        cursorLayer.shadowOffset = .zero
        layer.addSublayer(cursorLayer)

        installGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutRemoteContent()
    }

    func update(image: CGImage?, framebufferSize: CGSize, cursorPoint: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        imageLayer.contents = image
        if self.framebufferSize != framebufferSize, self.framebufferSize != .zero {
            zoomScale = RemoteGeometry.minimumZoomScale
            panOffset = .zero
        }
        self.framebufferSize = framebufferSize
        self.cursorPoint = cursorPoint
        layoutRemoteContent()
    }

    private func layoutRemoteContent() {
        // These layers follow live input and frames, not implicit CA animations.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let baseImageRect = fittedImageRect()
        panOffset = RemoteGeometry.clampedPanOffset(
            panOffset,
            baseRect: baseImageRect,
            viewportRect: interactionViewport,
            zoomScale: zoomScale
        )
        let imageRect = RemoteGeometry.zoomedRect(
            baseRect: baseImageRect,
            zoomScale: zoomScale,
            panOffset: panOffset
        )
        imageLayer.frame = imageRect
        // The framebuffer CGImage is already pixels. Leaving contentsScale at 1
        // makes Core Animation scale that bitmap by the screen scale (2 or 3)
        // from the top-left. clipsToBounds then keeps only that corner, so the
        // pointer never reaches the real bottom or right edge. Matching the
        // screen scale shows the whole desktop at 1x, 2x, and 3x.
        configureFramebufferLayer()

        guard framebufferSize.width > 0, framebufferSize.height > 0 else {
            cursorLayer.isHidden = true
            clickFeedbackLayer.removeAllAnimations()
            return
        }

        cursorLayer.isHidden = false
        let x = imageRect.minX + (cursorPoint.x / framebufferSize.width) * imageRect.width
        let y = imageRect.minY + (cursorPoint.y / framebufferSize.height) * imageRect.height
        cursorLayer.position = CGPoint(x: x, y: y)
        if let clickFeedbackPoint {
            // Anchor to the clicked desktop location, not the finger or a cursor
            // that may already have moved. Keep the ring the same size at any zoom.
            clickFeedbackLayer.position = CGPoint(
                x: imageRect.minX + (clickFeedbackPoint.x / framebufferSize.width) * imageRect.width,
                y: imageRect.minY + (clickFeedbackPoint.y / framebufferSize.height) * imageRect.height
            )
        }
    }

    private func showClickFeedback(_ click: RemoteClickFeedback) {
        guard framebufferSize.width > 0, framebufferSize.height > 0 else { return }
        clickFeedbackPoint = click.point
        layoutRemoteContent()

        let color = UIColor(click.button == .right ? AppTheme.connected : AppTheme.tailBlue)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clickFeedbackLayer.strokeColor = color.cgColor
        clickFeedbackLayer.fillColor = color.withAlphaComponent(0.12).cgColor
        CATransaction.commit()

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 0.85, 0]
        fade.keyTimes = [0, 0.35, 1]
        let pulse = CAAnimationGroup()
        pulse.animations = [fade]
        pulse.duration = 0.42
        pulse.repeatCount = click.count > 1 ? 2 : 1
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)

        if UIAccessibility.isReduceMotionEnabled {
            pulse.duration = 0.25
            pulse.repeatCount = 1
        } else {
            let expand = CABasicAnimation(keyPath: "transform.scale")
            expand.fromValue = 0.55
            expand.toValue = 1.65
            pulse.animations?.append(expand)
        }
        pulse.animations?.forEach { $0.duration = pulse.duration }
        // Replacing one local animation cannot delay input or accumulate layers.
        clickFeedbackLayer.add(pulse, forKey: "click")
    }

    private var directTouch: NSNumber { NSNumber(value: UITouch.TouchType.direct.rawValue) }
    private var indirectPointerTouch: NSNumber { NSNumber(value: UITouch.TouchType.indirectPointer.rawValue) }
    private var pencilTouch: NSNumber { NSNumber(value: UITouch.TouchType.pencil.rawValue) }

    private func installGestures() {
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.numberOfTouchesRequired = 1

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 1
        singleTap.require(toFail: doubleTap)

        let rightClick = UITapGestureRecognizer(target: self, action: #selector(handleRightClick))
        rightClick.numberOfTapsRequired = 1
        rightClick.numberOfTouchesRequired = 2

        let move = UIPanGestureRecognizer(target: self, action: #selector(handleMove))
        move.minimumNumberOfTouches = 1
        move.maximumNumberOfTouches = 1
        move.allowedScrollTypesMask = []

        let drag = UILongPressGestureRecognizer(target: self, action: #selector(handleDrag))
        drag.minimumPressDuration = 0.45
        drag.allowableMovement = 6
        dragRecognizer = drag

        // A swipe must be free to start as soon as UIKit detects movement.
        // Waiting for the hold used to buffer a large delta and turn slow swipes
        // into mouse-down events. Only a stationary hold should start a drag.
        for tap in [singleTap, doubleTap] {
            tap.require(toFail: move)
            tap.require(toFail: drag)
        }

        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        scroll.allowedScrollTypesMask = []

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        pinch.delegate = self
        scroll.delegate = self

        let fingerGestures = [singleTap, doubleTap, rightClick, move, drag, scroll, pinch]
        fingerGestures.forEach {
            $0.allowedTouchTypes = [directTouch]
            addGestureRecognizer($0)
        }
        installPointerGestures()
    }

    private func installPointerGestures() {
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handlePointerHover))
        hover.allowedTouchTypes = [indirectPointerTouch]
        hover.delegate = self

        let pointerDrag = UIPanGestureRecognizer(target: self, action: #selector(handlePointerDrag))
        pointerDrag.allowedTouchTypes = [indirectPointerTouch]
        pointerDrag.maximumNumberOfTouches = 1
        pointerDrag.allowedScrollTypesMask = []
        pointerDrag.delegate = self
        pointerDragRecognizer = pointerDrag

        let pointerClick = UITapGestureRecognizer(target: self, action: #selector(handlePointerClick))
        pointerClick.allowedTouchTypes = [indirectPointerTouch]
        pointerClick.buttonMaskRequired = .primary
        pointerClick.numberOfTapsRequired = 1

        let pointerDoubleClick = UITapGestureRecognizer(target: self, action: #selector(handlePointerDoubleClick))
        pointerDoubleClick.allowedTouchTypes = [indirectPointerTouch]
        pointerDoubleClick.buttonMaskRequired = .primary
        pointerDoubleClick.numberOfTapsRequired = 2
        pointerClick.require(toFail: pointerDoubleClick)
        pointerClick.require(toFail: pointerDrag)
        pointerDoubleClick.require(toFail: pointerDrag)

        let pointerRightClick = UITapGestureRecognizer(target: self, action: #selector(handlePointerRightClick))
        pointerRightClick.allowedTouchTypes = [indirectPointerTouch]
        pointerRightClick.buttonMaskRequired = .secondary

        // Fingers stay on the touch recognizers. Trackpad and mouse scrolling is a
        // different touch type, so it cannot fall through to the capped finger path.
        // A pressed button is a drag, never a wheel. The scroll pan rejects any
        // event that has a button down, and it will not begin during a primary drag.
        let pointerScroll = UIPanGestureRecognizer(target: self, action: #selector(handlePointerScroll))
        pointerScroll.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.indirect.rawValue),
            indirectPointerTouch,
        ]
        pointerScroll.allowedScrollTypesMask = [.continuous, .discrete]
        pointerScroll.delegate = self
        pointerScrollRecognizer = pointerScroll

        let pencilClick = UITapGestureRecognizer(target: self, action: #selector(handlePencilClick))
        pencilClick.allowedTouchTypes = [pencilTouch]
        pencilClick.numberOfTapsRequired = 1

        let pencilDoubleClick = UITapGestureRecognizer(target: self, action: #selector(handlePencilDoubleClick))
        pencilDoubleClick.allowedTouchTypes = [pencilTouch]
        pencilDoubleClick.numberOfTapsRequired = 2
        pencilClick.require(toFail: pencilDoubleClick)

        [hover, pointerDrag, pointerClick, pointerDoubleClick, pointerRightClick, pointerScroll, pencilClick, pencilDoubleClick]
            .forEach(addGestureRecognizer)
    }

    @objc private func handleSingleTap() {
        session?.click(.left, count: 1)
    }

    @objc private func handleDoubleTap() {
        session?.click(.left, count: 2)
        selectionDragArmedUntil = CACurrentMediaTime() + 0.55
    }

    @objc private func handleRightClick() {
        session?.click(.right, count: 1)
    }

    @objc private func handleMove(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            let translation = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)
            if gesture.state == .began, CACurrentMediaTime() < selectionDragArmedUntil {
                selectionDragArmedUntil = 0
                selectionDragActive = true
                session?.mouseDown(.left)
            }
            if selectionDragActive {
                moveRemotePointer(by: translation)
            } else if scrollMode {
                scrollByDrag(translation)
            } else {
                moveRemotePointer(by: translation)
            }
        case .ended, .cancelled, .failed:
            scrollRemainder = .zero
            session?.endScrollGesture()
            if selectionDragActive {
                session?.mouseUp(.left)
                selectionDragActive = false
            }
        default:
            break
        }
    }

    @objc private func handleDrag(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            previousDragLocation = gesture.location(in: self)
            session?.mouseDown(.left)
        case .changed:
            let location = gesture.location(in: self)
            if let previousDragLocation {
                moveRemotePointer(
                    by: CGPoint(
                        x: location.x - previousDragLocation.x,
                        y: location.y - previousDragLocation.y
                    )
                )
            }
            previousDragLocation = location
        case .ended, .cancelled, .failed:
            if previousDragLocation != nil {
                session?.mouseUp(.left)
            }
            previousDragLocation = nil
        default:
            break
        }
    }

    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            let translation = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)

            if isPinching {
                return
            }

            if zoomScale > RemoteGeometry.minimumZoomScale {
                let baseImageRect = fittedImageRect()
                panOffset = RemoteGeometry.clampedPanOffset(
                    CGPoint(x: panOffset.x + translation.x, y: panOffset.y + translation.y),
                    baseRect: baseImageRect,
                    viewportRect: interactionViewport,
                    zoomScale: zoomScale
                )
                layoutRemoteContent()
                return
            }

            emitScroll(translation)
        case .ended, .cancelled, .failed:
            scrollRemainder = .zero
            session?.endScrollGesture()
        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            isPinching = true
        case .changed:
            let oldScale = zoomScale
            let newScale = RemoteGeometry.clampedZoomScale(oldScale * gesture.scale)
            let baseImageRect = fittedImageRect()

            panOffset = RemoteGeometry.panOffsetKeepingFocalPointStable(
                currentOffset: panOffset,
                focalPoint: gesture.location(in: self),
                baseCenter: CGPoint(x: baseImageRect.midX, y: baseImageRect.midY),
                oldScale: oldScale,
                newScale: newScale
            )
            zoomScale = newScale
            panOffset = RemoteGeometry.clampedPanOffset(
                panOffset,
                baseRect: baseImageRect,
                viewportRect: interactionViewport,
                zoomScale: zoomScale
            )
            gesture.scale = 1
            layoutRemoteContent()
        case .ended, .cancelled, .failed:
            isPinching = false
            if zoomScale < 1.05 {
                zoomScale = RemoteGeometry.minimumZoomScale
                panOffset = .zero
                layoutRemoteContent()
            }
        default:
            break
        }
    }

    private func configureFramebufferLayer() {
        let screenScale = RemoteGeometry.sanitizedDisplayScale(contentScaleFactor)
        imageLayer.contentsScale = screenScale
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        imageLayer.masksToBounds = true
    }

    private func fittedImageRect() -> CGRect {
        RemoteGeometry.aspectFitRect(
            imageSize: framebufferSize,
            in: contentBounds,
            placement: pinsContentToBottom ? .bottom : .center
        )
    }

    private func scrollByDrag(_ translation: CGPoint) {
        emitScroll(translation, pointsPerDetent: RemoteScroll.scrollModePointsPerDetent)
    }

    private func emitScroll(
        _ translation: CGPoint,
        pointsPerDetent: CGFloat = RemoteScroll.pointsPerDetent
    ) {
        guard let tick = RemoteScroll.consume(
            translation,
            remainder: &scrollRemainder,
            pointsPerDetent: pointsPerDetent
        ) else { return }
        session?.scroll(Self.wheel(for: tick.direction), steps: UInt32(tick.steps))
    }

    private static func wheel(for direction: RemoteWheelDirection) -> VNCMouseWheel {
        switch direction {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        }
    }

    @objc private func handlePointerHover(_ gesture: UIHoverGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else { return }
        moveAbsolute(to: gesture.location(in: self))
    }

    @objc private func handlePointerClick(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        clickAbsolute(at: gesture.location(in: self), button: .left, count: 1)
    }

    @objc private func handlePointerDoubleClick(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        clickAbsolute(at: gesture.location(in: self), button: .left, count: 2)
    }

    @objc private func handlePointerRightClick(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        clickAbsolute(at: gesture.location(in: self), button: .right, count: 1)
    }

    @objc private func handlePointerDrag(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)
        switch gesture.state {
        case .began:
            guard gesture.buttonMask == .primary else { return }
            moveAbsolute(to: location)
            session?.mouseDown(.left)
            pointerDragIsDown = true
        case .changed:
            guard pointerDragIsDown else { return }
            moveAbsolute(to: location)
        case .ended, .cancelled, .failed:
            guard pointerDragIsDown else { return }
            moveAbsolute(to: location)
            session?.mouseUp(.left)
            pointerDragIsDown = false
        default:
            break
        }
    }

    @objc private func handlePointerScroll(_ gesture: UIPanGestureRecognizer) {
        if pointerDragIsDown || !gesture.buttonMask.isEmpty {
            pointerScrollRemainder = .zero
            return
        }
        switch gesture.state {
        case .began, .changed:
            let translation = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)
            for event in RemoteScroll.pointerSteps(delta: translation, remainder: &pointerScrollRemainder) {
                session?.scroll(Self.wheel(for: event.direction), steps: event.steps)
            }
        case .ended, .cancelled, .failed:
            pointerScrollRemainder = .zero
        default:
            break
        }
    }

    @objc private func handlePencilClick(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        clickAbsolute(at: gesture.location(in: self), button: .left, count: 1)
    }

    @objc private func handlePencilDoubleClick(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        clickAbsolute(at: gesture.location(in: self), button: .left, count: 2)
    }

    private func clickAbsolute(at viewPoint: CGPoint, button: VNCMouseButton, count: Int) {
        guard moveAbsolute(to: viewPoint) else { return }
        session?.click(button, count: count)
    }

    @discardableResult
    private func moveAbsolute(to viewPoint: CGPoint) -> Bool {
        guard let session, framebufferSize.width > 0, framebufferSize.height > 0 else { return false }
        let imageRect = RemoteGeometry.zoomedRect(
            baseRect: fittedImageRect(),
            zoomScale: zoomScale,
            panOffset: panOffset
        )
        guard imageRect.width > 0, imageRect.height > 0 else { return false }
        session.movePointer(
            toFramebufferPoint: RemoteGeometry.framebufferPoint(
                fromViewPoint: viewPoint,
                imageRect: imageRect,
                framebufferSize: framebufferSize,
                displayScale: contentScaleFactor
            )
        )
        cursorPoint = session.cursorPoint
        layoutRemoteContent()
        return true
    }

    private func moveRemotePointer(by delta: CGPoint) {
        guard let session else { return }
        let baseImageRect = fittedImageRect()
        session.movePointer(
            viewDelta: delta,
            viewSize: baseImageRect.size,
            zoomScale: zoomScale,
            displayScale: contentScaleFactor
        )
        cursorPoint = session.cursorPoint

        guard zoomScale > RemoteGeometry.minimumZoomScale,
              framebufferSize.width > 0,
              framebufferSize.height > 0 else {
            layoutRemoteContent()
            return
        }

        panOffset = RemoteGeometry.panOffsetFollowingCursor(
            normalizedCursorPoint: CGPoint(
                x: cursorPoint.x / framebufferSize.width,
                y: cursorPoint.y / framebufferSize.height
            ),
            currentOffset: panOffset,
            baseRect: baseImageRect,
            viewportRect: interactionViewport,
            zoomScale: zoomScale
        )
        layoutRemoteContent()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if isPointerDragAndScroll(gestureRecognizer, otherGestureRecognizer) {
            return false
        }
        if gestureRecognizer is UIHoverGestureRecognizer || otherGestureRecognizer is UIHoverGestureRecognizer {
            return true
        }
        let pair = [gestureRecognizer, otherGestureRecognizer]
        return pair.contains { $0 is UIPinchGestureRecognizer }
            && pair.contains { $0 is UIPanGestureRecognizer }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive event: UIEvent) -> Bool {
        if gestureRecognizer === pointerDragRecognizer {
            return event.buttonMask == .primary
        }
        if gestureRecognizer === pointerScrollRecognizer {
            if pointerDragIsDown { return false }
            if let drag = pointerDragRecognizer, drag.state == .began || drag.state == .changed {
                return false
            }
            return event.buttonMask.isEmpty
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Only hold a wheel while a primary drag is already tracking. An idle drag
        // recognizer must not delay buttonless trackpad and mouse-wheel scrolling.
        guard gestureRecognizer === pointerScrollRecognizer,
              otherGestureRecognizer === pointerDragRecognizer else {
            return false
        }
        switch otherGestureRecognizer.state {
        case .began, .changed:
            return true
        default:
            return false
        }
    }

    private func isPointerDragAndScroll(
        _ gestureRecognizer: UIGestureRecognizer,
        _ otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        let pair = [gestureRecognizer, otherGestureRecognizer]
        return pair.contains { $0 === pointerDragRecognizer }
            && pair.contains { $0 === pointerScrollRecognizer }
    }
}
