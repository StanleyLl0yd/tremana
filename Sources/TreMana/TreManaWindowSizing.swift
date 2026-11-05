import SwiftUI
import AppKit
import TreManaCore

/// The connection window cannot be resized manually, but automatically grows
/// with localized form content and visible validation messages.
struct TreManaWindowSizing: NSViewRepresentable {
    let isConnected: Bool
    let disconnectedContentHeight: CGFloat

    func makeNSView(context: Context) -> WindowSizeObserver {
        WindowSizeObserver()
    }

    func updateNSView(_ view: WindowSizeObserver, context: Context) {
        view.configure(connected: isConnected, contentHeight: disconnectedContentHeight)
    }
}

/// Settings uses intrinsic content measurement, rather than a hard-coded 505 pt
/// window that cuts off its own bottom controls.
struct TreManaSettingsWindowSizing: NSViewRepresentable {
    let contentHeight: CGFloat

    func makeNSView(context: Context) -> SettingsSizeObserver {
        SettingsSizeObserver()
    }

    func updateNSView(_ view: SettingsSizeObserver, context: Context) {
        view.contentHeight = contentHeight
        view.resizeToFit()
    }
}

private enum WindowSizing {
    static func visibleFrame(for window: NSWindow) -> NSRect {
        window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    static func contentHeight(_ height: CGFloat, window: NSWindow) -> CGFloat {
        let chrome = window.frame.height
            - window.contentRect(forFrameRect: window.frame).height
        return CGFloat(AdaptiveWindowHeight.fitted(
            contentHeight: Double(height),
            visibleHeight: Double(visibleFrame(for: window).height),
            minimum: 340,
            chromeHeight: Double(max(30, chrome)),
            screenMargin: 26
        ))
    }

    /// Keep the window's top edge steady as status/error text expands the form.
    static func setContentSize(_ size: NSSize, for window: NSWindow) {
        let current = window.contentRect(forFrameRect: window.frame).size
        guard abs(current.width - size.width) > 1 || abs(current.height - size.height) > 1 else {
            return
        }

        let desiredFrameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: size)
        ).size
        let visible = visibleFrame(for: window)
        var frame = window.frame
        let oldTop = frame.maxY
        frame.size = desiredFrameSize
        frame.origin.y = oldTop - frame.height
        frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
        frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
        window.setFrame(frame, display: true, animate: false)
    }
}

final class WindowSizeObserver: NSView {
    private static let widthKey = "com.sl.tremana.connected-window-width.v1"
    private static let heightKey = "com.sl.tremana.connected-window-height.v1"
    private var desiredConnected = false
    private var contentHeight: CGFloat = 470
    private var appliedConnected: Bool?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyIfNeeded()
    }

    func configure(connected: Bool, contentHeight: CGFloat) {
        desiredConnected = connected
        self.contentHeight = contentHeight
        applyIfNeeded()
    }

    private func applyIfNeeded() {
        guard let window else { return }

        if appliedConnected != desiredConnected {
            if desiredConnected {
                window.styleMask.insert(.resizable)
                window.standardWindowButton(.zoomButton)?.isEnabled = true
                window.minSize = NSSize(width: 840, height: 560)

                let defaults = UserDefaults.standard
                let width = defaults.double(forKey: Self.widthKey)
                let height = defaults.double(forKey: Self.heightKey)
                let available = WindowSizing.visibleFrame(for: window)
                let target = NSSize(
                    width: min(width >= 840 && width <= 6000 ? width : 1140,
                               max(840, available.width - 26)),
                    height: min(height >= 560 && height <= 4000 ? height : 740,
                                max(560, available.height - 45))
                )
                WindowSizing.setContentSize(target, for: window)
            } else {
                // Never overwrite the connected geometry with compact form size.
                if appliedConnected == true {
                    let old = window.contentRect(forFrameRect: window.frame).size
                    if old.width >= 840 && old.height >= 560 {
                        UserDefaults.standard.set(old.width, forKey: Self.widthKey)
                        UserDefaults.standard.set(old.height, forKey: Self.heightKey)
                    }
                }
                window.minSize = NSSize(width: 1, height: 1)
                window.styleMask.remove(.resizable)
                window.standardWindowButton(.zoomButton)?.isEnabled = false
            }
            appliedConnected = desiredConnected
        }

        if !desiredConnected {
            let screen = WindowSizing.visibleFrame(for: window)
            let target = NSSize(
                width: max(340, min(760, screen.width - 26)),
                height: WindowSizing.contentHeight(contentHeight, window: window)
            )
            WindowSizing.setContentSize(target, for: window)
        }
    }
}

final class SettingsSizeObserver: NSView {
    var contentHeight: CGFloat = 520

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resizeToFit()
    }

    func resizeToFit() {
        guard let window else { return }
        window.minSize = NSSize(width: 1, height: 1)
        window.styleMask.remove(.resizable)
        window.standardWindowButton(.zoomButton)?.isEnabled = false

        let visible = WindowSizing.visibleFrame(for: window)
        WindowSizing.setContentSize(
            NSSize(
                width: max(340, min(570, visible.width - 26)),
                height: WindowSizing.contentHeight(contentHeight, window: window)
            ),
            for: window
        )
    }
}
