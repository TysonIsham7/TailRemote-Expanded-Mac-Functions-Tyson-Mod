import RoyalVNCKit
import SwiftUI
import UIKit

enum RemoteTrackpadDirection: Equatable {
    case up, down, left, right
}

enum RemoteTrackpadAction: Equatable {
    case move(CGPoint)
    case click
    case rightClick
    case buttonDown
    case buttonUp
    case holdCommand(Bool)
    case scroll(RemoteWheelDirection, Int)
    case missionControl
    case appExpose
    case previousSpace
    case nextSpace
}

enum RemoteTrackpadGesture: Equatable {
    case move(CGPoint)
    case tap
    case twoFingerTap
    case twoFingerMove(CGPoint)
    case dragBegan
    case dragMoved(CGPoint)
    case dragEnded
    case threeFingerSwipe(RemoteTrackpadDirection)
}

enum RemoteTrackpad {
    /// A second touch this soon after a tap is a click-drag, matching a Mac trackpad.
    static let dragArmWindow: TimeInterval = 0.45
    static let threeFingerMinimumTravel: CGFloat = 24

    static func beginsDrag(secondsSinceTap: TimeInterval?) -> Bool {
        guard let secondsSinceTap else { return false }
        return secondsSinceTap >= 0 && secondsSinceTap <= dragArmWindow
    }

    /// Finger travel on the pad. Up is negative Y, the same direction UIKit reports.
    static func threeFingerSwipe(translation: CGPoint) -> RemoteTrackpadDirection? {
        let horizontal = abs(translation.x) > abs(translation.y)
        let travel = horizontal ? translation.x : translation.y
        guard abs(travel) >= threeFingerMinimumTravel else { return nil }
        if horizontal {
            return travel < 0 ? .left : .right
        }
        return travel < 0 ? .up : .down
    }

    static func actions(
        for gesture: RemoteTrackpadGesture,
        commandHeld: Bool,
        remainder: inout CGPoint
    ) -> [RemoteTrackpadAction] {
        switch gesture {
        case .move(let delta):
            guard delta != .zero else { return [] }
            return [.move(delta)]
        case .tap:
            return commandHeld ? [.holdCommand(true), .click, .holdCommand(false)] : [.click]
        case .twoFingerTap:
            return [.rightClick]
        case .twoFingerMove(let delta):
            guard let tick = RemoteScroll.consume(delta, remainder: &remainder) else { return [] }
            return [.scroll(tick.direction, tick.steps)]
        case .dragBegan:
            return commandHeld ? [.holdCommand(true), .buttonDown] : [.buttonDown]
        case .dragMoved(let delta):
            guard delta != .zero else { return [] }
            return [.move(delta)]
        case .dragEnded:
            return commandHeld ? [.buttonUp, .holdCommand(false)] : [.buttonUp]
        case .threeFingerSwipe(let direction):
            switch direction {
            case .up: return [.missionControl]
            case .down: return [.appExpose]
            case .left: return [.previousSpace]
            case .right: return [.nextSpace]
            }
        }
    }
}

struct RemoteTrackpadPanel: View {
    @ObservedObject var session: VNCSession
    var commandHeld: Bool
    var onCommandToggle: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            Text("Trackpad")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.muted)
                .allowsHitTesting(false)
            RemoteTrackpadSurface(session: session, commandHeld: commandHeld)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button(action: onCommandToggle) {
                Text("⌘")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(commandHeld ? AppTheme.tailBlue : AppTheme.text)
                    .frame(width: 36, height: 32)
                    .background(commandHeld ? AppTheme.tailBlue.opacity(0.16) : Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel("Command")
            .accessibilityIdentifier("trackpad-command")
            .accessibilityAddTraits(commandHeld ? .isSelected : [])
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .accessibilityIdentifier("remote-trackpad-panel")
    }
}

struct RemoteTrackpadSurface: UIViewRepresentable {
    @ObservedObject var session: VNCSession
    var commandHeld: Bool

    func makeUIView(context: Context) -> RemoteTrackpadUIView {
        let view = RemoteTrackpadUIView()
        view.session = session
        view.commandHeld = commandHeld
        return view
    }

    func updateUIView(_ view: RemoteTrackpadUIView, context: Context) {
        view.session = session
        view.commandHeld = commandHeld
    }
}

@MainActor
final class RemoteTrackpadUIView: UIView {
    var session: VNCSession?
    var commandHeld = false

    private var scrollRemainder = CGPoint.zero
    private var lastTapAt: TimeInterval?
    private var dragging = false
    private var dragHoldsCommand = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityIdentifier = "remote-trackpad"
        accessibilityLabel = "Trackpad"
        installGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func installGestures() {
        let move = UIPanGestureRecognizer(target: self, action: #selector(handleMove))
        move.minimumNumberOfTouches = 1
        move.maximumNumberOfTouches = 1

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.require(toFail: move)

        let rightTap = UITapGestureRecognizer(target: self, action: #selector(handleRightTap))
        rightTap.numberOfTouchesRequired = 2

        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        rightTap.require(toFail: scroll)

        let swipe = UIPanGestureRecognizer(target: self, action: #selector(handleThreeFinger))
        swipe.minimumNumberOfTouches = 3
        swipe.maximumNumberOfTouches = 3

        [move, tap, rightTap, scroll, swipe].forEach(addGestureRecognizer)
    }

    @objc private func handleTap() {
        lastTapAt = CACurrentMediaTime()
        emit(.tap)
    }

    @objc private func handleRightTap() {
        emit(.twoFingerTap)
    }

    @objc private func handleMove(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        switch gesture.state {
        case .began:
            let sinceTap = lastTapAt.map { CACurrentMediaTime() - $0 }
            if RemoteTrackpad.beginsDrag(secondsSinceTap: sinceTap) {
                dragging = true
                dragHoldsCommand = commandHeld
                lastTapAt = nil
                emit(.dragBegan, command: dragHoldsCommand)
            }
        case .changed:
            if dragging {
                emit(.dragMoved(translation), command: dragHoldsCommand)
            } else {
                emit(.move(translation))
            }
        case .ended, .cancelled, .failed:
            if dragging {
                emit(.dragEnded, command: dragHoldsCommand)
                dragging = false
            }
        default:
            break
        }
    }

    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        switch gesture.state {
        case .began, .changed:
            emit(.twoFingerMove(translation))
        case .ended, .cancelled, .failed:
            scrollRemainder = .zero
            session?.endScrollGesture()
        default:
            break
        }
    }

    @objc private func handleThreeFinger(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let translation = gesture.translation(in: self)
        guard let direction = RemoteTrackpad.threeFingerSwipe(translation: translation) else { return }
        emit(.threeFingerSwipe(direction))
    }

    private func emit(_ gesture: RemoteTrackpadGesture, command: Bool? = nil) {
        let actions = RemoteTrackpad.actions(
            for: gesture,
            commandHeld: command ?? commandHeld,
            remainder: &scrollRemainder
        )
        perform(actions)
    }

    private func perform(_ actions: [RemoteTrackpadAction]) {
        guard let session else { return }
        for action in actions {
            switch action {
            case .move(let delta):
                session.movePointer(viewDelta: delta, viewSize: bounds.size, zoomScale: 1)
            case .click:
                session.click(.left)
            case .rightClick:
                session.click(.right)
            case .buttonDown:
                session.mouseDown(.left)
            case .buttonUp:
                session.mouseUp(.left)
            case .holdCommand(let down):
                if down {
                    session.keyDown(.command)
                } else {
                    session.keyUp(.command)
                }
            case .scroll(let direction, let steps):
                session.scroll(Self.wheel(for: direction), steps: UInt32(steps))
            case .missionControl:
                session.pressKey(.upArrow, modifiers: [.control])
            case .appExpose:
                session.pressKey(.downArrow, modifiers: [.control])
            case .previousSpace:
                session.pressKey(.leftArrow, modifiers: [.control])
            case .nextSpace:
                session.pressKey(.rightArrow, modifiers: [.control])
            }
        }
    }

    private static func wheel(for direction: RemoteWheelDirection) -> VNCMouseWheel {
        switch direction {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        }
    }
}
