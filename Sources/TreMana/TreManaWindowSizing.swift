import SwiftUI
import AppKit

/// A disconnected client needs a compact connection window. The torrent window
/// restores the user's last connected size after a successful connection.
struct TreManaWindowSizing: NSViewRepresentable {
    let isConnected: Bool

    func makeNSView(context: Context) -> WindowSizeObserver {
        WindowSizeObserver()
    }

    func updateNSView(_ view: WindowSizeObserver, context: Context) {
        view.setConnectionState(isConnected)
    }
}

final class WindowSizeObserver: NSView {
    private static let widthKey = "com.sl.tremana.connected-window-width.v1"
    private static let heightKey = "com.sl.tremana.connected-window-height.v1"
    private var desiredConnected = false
    private var appliedConnected: Bool?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyIfNeeded()
    }

    func setConnectionState(_ connected: Bool) {
        desiredConnected = connected
        applyIfNeeded()
    }

    private func applyIfNeeded() {
        guard let window, appliedConnected != desiredConnected else { return }
        appliedConnected = desiredConnected

        if desiredConnected {
            window.minSize = NSSize(width: 840, height: 560)
            let defaults = UserDefaults.standard
            let width = defaults.double(forKey: Self.widthKey)
            let height = defaults.double(forKey: Self.heightKey)
            let connectedSize = NSSize(
                width: width >= 840 && width <= 6000 ? width : 1140,
                height: height >= 560 && height <= 4000 ? height : 740
            )
            window.setContentSize(connectedSize)
        } else {
            let oldSize = window.contentRect(forFrameRect: window.frame).size
            if oldSize.width >= 840 && oldSize.height >= 560 {
                UserDefaults.standard.set(oldSize.width, forKey: Self.widthKey)
                UserDefaults.standard.set(oldSize.height, forKey: Self.heightKey)
            }
            window.minSize = NSSize(width: 750, height: 510)
            window.setContentSize(NSSize(width: 820, height: 620))
        }
    }
}
