import CoreGraphics

struct ViewportMapper: Sendable {
    let sourceSize: CGSize
    let viewportSize: CGSize

    init(sourceSize: CGSize, viewportSize: CGSize) {
        self.sourceSize = sourceSize
        self.viewportSize = viewportSize
    }

    init(resolution: FrameContract.Resolution, viewportSize: CGSize) {
        self.sourceSize = CGSize(width: resolution.width, height: resolution.height)
        self.viewportSize = viewportSize
    }

    var displayedRect: CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0 else {
            return .zero
        }
        let scale = min(viewportSize.width / sourceSize.width, viewportSize.height / sourceSize.height)
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: (viewportSize.width - size.width) / 2,
            y: (viewportSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    func sourcePoint(for viewportPoint: CGPoint) -> CGPoint? {
        let rect = displayedRect
        guard rect.width > 0, rect.height > 0, rect.contains(viewportPoint) else { return nil }
        return CGPoint(
            x: (viewportPoint.x - rect.minX) / rect.width * sourceSize.width,
            y: (viewportPoint.y - rect.minY) / rect.height * sourceSize.height
        )
    }
}
