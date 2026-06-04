import CoreGraphics

public enum CoordinateSpace {
    /// Convert physical pixels (e.g. from ScreenCaptureKit) to logical points.
    public static func toLogical(_ point: CGPoint, scaleFactor: CGFloat) -> CGPoint {
        CGPoint(x: point.x / scaleFactor, y: point.y / scaleFactor)
    }

    /// Convert logical points to physical pixels.
    public static func toPhysical(_ point: CGPoint, scaleFactor: CGFloat) -> CGPoint {
        CGPoint(x: point.x * scaleFactor, y: point.y * scaleFactor)
    }
}
