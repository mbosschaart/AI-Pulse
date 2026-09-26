import Foundation

struct DashboardPosition: Codable, Equatable {
    let x: Double
    let top: Double

    init(frame: CGRect) {
        x = frame.minX
        top = frame.maxY
    }

    func frame(size: CGSize) -> CGRect {
        CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }

    /// Restore on the saved display when possible; keep the dashboard reachable after display changes.
    func restoredFrame(size: CGSize, screens: [CGRect]) -> CGRect {
        let proposed = frame(size: size)
        guard let screen = screens.first(where: { $0.contains(CGPoint(x: x, y: top - 1)) })
            ?? screens.max(by: { Self.area($0.intersection(proposed)) < Self.area($1.intersection(proposed)) }) else {
            return proposed
        }
        let left = min(max(proposed.minX, screen.minX), max(screen.minX, screen.maxX - size.width))
        let upper = max(min(top, screen.maxY), min(screen.maxY, screen.minY + size.height))
        return CGRect(x: left, y: upper - size.height, width: size.width, height: size.height)
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
}
