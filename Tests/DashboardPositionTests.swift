import XCTest
@testable import AIPulseCore

final class DashboardPositionTests: XCTestCase {
    func testCompactRestorePreservesTopLeftAcrossLaunchSizeChanges() throws {
        let original = CGRect(x: 420, y: 600, width: 380, height: 240)
        let saved = DashboardPosition(frame: original)
        let decoded = try JSONDecoder().decode(DashboardPosition.self, from: JSONEncoder().encode(saved))
        let launch = decoded.frame(size: CGSize(width: 640, height: 580))
        XCTAssertEqual(launch.maxY, original.maxY)
        XCTAssertEqual(DashboardPosition(frame: launch).frame(size: original.size), original)
        XCTAssertEqual(decoded.frame(size: CGSize(width: 1148, height: 166)).maxY, original.maxY)
    }
    func testRestorationOnSecondaryDisplayAndAfterDisconnection() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let second = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let original = CGRect(x: -800, y: 500, width: 380, height: 240)
        let saved = DashboardPosition(frame: original)
        XCTAssertEqual(saved.restoredFrame(size: original.size, screens: [main, second]), original)
        let recovered = saved.restoredFrame(size: original.size, screens: [main])
        XCTAssertTrue(main.contains(recovered))
        XCTAssertEqual(recovered.maxY, original.maxY)
    }
    func testLargeDashboardKeepsTopEdgeReachable() {
        let screen = CGRect(x: 0, y: 40, width: 1000, height: 700)
        let saved = DashboardPosition(frame: CGRect(x: 900, y: -200, width: 380, height: 240))
        let restored = saved.restoredFrame(size: CGSize(width: 1200, height: 900), screens: [screen])
        XCTAssertEqual(restored.minX, screen.minX)
        XCTAssertEqual(restored.maxY, screen.maxY)
    }
}
