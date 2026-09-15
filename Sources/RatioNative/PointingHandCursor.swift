import AppKit
import SwiftUI

extension View {
    /// Apply after the control's padding so the cursor covers its clickable area.
    func pointingHandCursor(_ enabled: Bool = true) -> some View {
        modifier(PointingHandCursorModifier(enabled: enabled))
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    let enabled: Bool

    func body(content: Content) -> some View {
        content.overlay {
            PointingHandCursorRegion(isEnabled: enabled && isEnabled)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct PointingHandCursorRegion: NSViewRepresentable {
    let isEnabled: Bool

    func makeNSView(context: Context) -> PointingHandCursorView {
        let view = PointingHandCursorView(frame: .zero)
        view.isCursorEnabled = isEnabled
        return view
    }

    func updateNSView(_ nsView: PointingHandCursorView, context: Context) {
        nsView.isCursorEnabled = isEnabled
    }

    static func dismantleNSView(_ nsView: PointingHandCursorView, coordinator: ()) {
        nsView.isCursorEnabled = false
    }
}

/// A transparent cursor region that also supports direct AppKit embedding.
/// AppKit owns the cursor lifecycle and resets rectangles after frame, bounds,
/// hierarchy and scrolling changes; there is no process-wide cursor stack to balance.
final class PointingHandCursorView: NSView {
    var isCursorEnabled = true {
        didSet {
            guard isCursorEnabled != oldValue else { return }
            refreshNonKeyWindowCursor()
            window?.invalidateCursorRects(for: self)
        }
    }

    /// Status-item windows do not become key, so their cursor needs mouse tracking.
    /// Keep this off for ordinary SwiftUI controls, whose windows own cursor rectangles.
    var usesNonKeyWindowTracking = false {
        didSet {
            guard usesNonKeyWindowTracking != oldValue else { return }
            configureWindowNotifications()
            updateTrackingAreas()
        }
    }

    private var nonKeyTrackingArea: NSTrackingArea?
    private var ownsNonKeyWindowCursor = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isCursorEnabled, !isHiddenOrHasHiddenAncestor, !visibleRect.isEmpty else { return }
        addCursorRect(visibleRect, cursor: .pointingHand)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow {
            releaseNonKeyWindowCursor()
            NotificationCenter.default.removeObserver(self)
            discardCursorRects()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindowNotifications()
        updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if usesNonKeyWindowTracking {
            if nonKeyTrackingArea == nil {
                // activeAlways does not deliver cursorUpdate events. Mouse events
                // also work while another app is active, without intercepting clicks.
                let area = NSTrackingArea(rect: .zero,
                                          options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
                                          owner: self, userInfo: nil)
                addTrackingArea(area)
                nonKeyTrackingArea = area
            }
        } else if let area = nonKeyTrackingArea {
            removeTrackingArea(area)
            nonKeyTrackingArea = nil
        }
        refreshNonKeyWindowCursor()
    }

    override func mouseEntered(with event: NSEvent) { refreshNonKeyWindowCursor() }
    override func mouseMoved(with event: NSEvent) { refreshNonKeyWindowCursor() }
    override func mouseExited(with event: NSEvent) { releaseNonKeyWindowCursor() }

    override func viewDidHide() {
        super.viewDidHide()
        releaseNonKeyWindowCursor()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        refreshNonKeyWindowCursor()
    }

    private func configureWindowNotifications() {
        NotificationCenter.default.removeObserver(self)
        guard usesNonKeyWindowTracking, let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didChangeOcclusionStateNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(refreshNonKeyWindowCursor(_:)),
                                                   name: name, object: window)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(releaseNonKeyWindowCursor(_:)),
                                               name: NSWindow.willCloseNotification, object: window)
    }

    @objc private func refreshNonKeyWindowCursor(_ notification: Notification? = nil) {
        guard usesNonKeyWindowTracking, isCursorEnabled, !isHiddenOrHasHiddenAncestor,
              let window, window.isVisible,
              visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)),
              NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == window.windowNumber else {
            releaseNonKeyWindowCursor()
            return
        }
        guard !window.isKeyWindow else {
            releaseNonKeyWindowCursor()
            return
        }
        ownsNonKeyWindowCursor = true
        NSCursor.pointingHand.set()
    }

    @objc private func releaseNonKeyWindowCursor(_ notification: Notification? = nil) {
        guard ownsNonKeyWindowCursor else { return }
        ownsNonKeyWindowCursor = false
        if NSCursor.current == .pointingHand {
            NSCursor.arrow.set()
        }
    }
}
