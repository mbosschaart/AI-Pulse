import AppKit

/// A content-sized dashboard remembers its top edge, not the bottom of its temporary launch frame.
@MainActor final class DashboardWindow: NSWindow {
    private static let positionKey = "dashboard-position-v1"
    private var position: DashboardPosition?
    private var restoring = true
    private var tracksPosition = false
    private let savesPosition: Bool

    init(savesPosition: Bool = true) {
        self.savesPosition = savesPosition
        super.init(contentRect: NSRect(x: 0, y: 0, width: 640, height: 580),
                   styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        if savesPosition, let data = UserDefaults.standard.data(forKey: Self.positionKey),
           let saved = try? JSONDecoder().decode(DashboardPosition.self, from: data),
           saved.x.isFinite, saved.top.isFinite {
            position = saved
        }
        tracksPosition = true
        identifier = NSUserInterfaceItemIdentifier("main")
    }

    func restorePosition() {
        contentView?.layoutSubtreeIfNeeded()
        // Use the fitted size before constraining to a display, rather than the 640x580 launch placeholder.
        let fitting = contentView?.fittingSize ?? frame.size
        let size = fitting.width > 0 && fitting.height > 0 ? fitting : frame.size
        let screens = NSScreen.screens.map(\.visibleFrame)
        let anchor = position ?? DashboardPosition(frame: frame)
        let restored = anchor.restoredFrame(size: size, screens: screens)
        super.setFrame(restored, display: false)
        position = DashboardPosition(frame: frame)
        restoring = false
        savePosition()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var target = frameRect
        if tracksPosition, let position, restoring || frameRect.size != frame.size {
            target = position.frame(size: frameRect.size)
        }
        super.setFrame(target, display: flag)
        guard tracksPosition, !restoring else { return }
        position = DashboardPosition(frame: frame)
        savePosition()
    }

    // setFrameOrigin is the custom drag path; save explicitly rather than relying on AppKit autosave.
    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        guard tracksPosition, !restoring else { return }
        position = DashboardPosition(frame: frame)
        savePosition()
    }

    func savePosition() {
        guard savesPosition, !restoring, let position,
              let data = try? JSONEncoder().encode(position) else { return }
        UserDefaults.standard.set(data, forKey: Self.positionKey)
    }
}
