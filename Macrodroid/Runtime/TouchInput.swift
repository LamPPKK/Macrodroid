import CoreGraphics

enum TouchPhase: Sendable, Equatable {
    case contact
    case release

    var pressure: Int32 {
        switch self {
        case .contact: 1
        case .release: 0
        }
    }
}

struct TouchInput: Sendable, Equatable {
    static let primaryIdentifier: Int32 = 0

    let x: Int32
    let y: Int32
    let identifier: Int32
    let phase: TouchPhase

    var pressure: Int32 { phase.pressure }

    static func primary(x: Int32, y: Int32, isContact: Bool) -> Self {
        Self(
            x: x,
            y: y,
            identifier: primaryIdentifier,
            phase: isContact ? .contact : .release
        )
    }
}

struct TouchPoint: Sendable, Equatable {
    let x: Int32
    let y: Int32
}

struct PrimaryTouchSequence: Sendable {
    private var lastContactPoint: TouchPoint?

    mutating func contact(at point: TouchPoint?) -> TouchInput? {
        guard let point else { return nil }
        lastContactPoint = point
        return .primary(x: point.x, y: point.y, isContact: true)
    }

    mutating func release(at point: TouchPoint?) -> TouchInput? {
        guard let releasePoint = point ?? lastContactPoint else { return nil }
        lastContactPoint = nil
        return .primary(x: releasePoint.x, y: releasePoint.y, isContact: false)
    }
}

struct GestureTouchMapper: Sendable {
    static func scrollSwipePoints(
        x: Int32,
        y: Int32,
        deltaX: CGFloat,
        deltaY: CGFloat,
        multiplier: CGFloat = 2.0
    ) -> (start: TouchPoint, end: TouchPoint) {
        let endX = x + Int32((deltaX * multiplier).rounded())
        let endY = y + Int32((deltaY * multiplier).rounded())
        return (start: TouchPoint(x: x, y: y), end: TouchPoint(x: endX, y: endY))
    }

    static func pinchSpanPoints(
        centerX: Int32,
        centerY: Int32,
        scale: CGFloat,
        baseSpan: CGFloat = 50.0
    ) -> (finger0: TouchPoint, finger1: TouchPoint) {
        let factor = max(0.1, min(5.0, 1.0 + scale))
        let span = Int32((baseSpan * factor).rounded())
        return (
            finger0: TouchPoint(x: centerX - span, y: centerY - span),
            finger1: TouchPoint(x: centerX + span, y: centerY + span)
        )
    }
}
