import AppKit
import Combine
import SwiftUI

@main
struct RatioNativeApp: App {
    @NSApplicationDelegateAdaptor(RatioAppDelegate.self) private var appDelegate
    var body: some Scene {
        Settings { PreferencesView().environmentObject(appDelegate.model) }
            .commands { RatioCommands(model: appDelegate.model, delegate: appDelegate) }
    }
}

private struct RatioCommands: Commands {
    @ObservedObject var model: AppModel
    let delegate: RatioAppDelegate
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…", action: delegate.showPreferences).keyboardShortcut(",")
        }
        CommandGroup(replacing: .newItem) {
            Button("Show Ratio", action: delegate.showPanel).keyboardShortcut("1")
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo Reset", action: model.undoResetToday)
                .keyboardShortcut("z").disabled(!model.canUndoReset)
        }
        CommandMenu("Tracking") {
            Button(model.session.isPaused ? "Resume Tracking" : "Pause Tracking", action: model.togglePause)
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Show History") { model.page = .history; delegate.showPanel() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Divider()
            Button(model.session.isDemo ? "Exit Demo" : "Try Demo") {
                if model.session.isDemo { model.exitDemo() } else { model.startDemo() }
                delegate.showPanel()
            }.keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Reset Today") {
                if model.session.isDemo { model.resetDemo() } else { model.resetToday() }
            }.keyboardShortcut("r", modifiers: [.command, .shift])
            Button("How It Works…", action: model.showTour).keyboardShortcut("?", modifiers: [.command])
        }
    }
}

/// AppKit owns the menu-bar anchor and transient panel; SwiftUI renders its exact grid.
@MainActor
final class RatioAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem?
    private var panel: RatioPanel?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var subscriptions = Set<AnyCancellable>()
    private var preferencesWindow: NSWindow?
    private var tourWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        if let button = item.button {
            let cursorView = PointingHandCursorView(frame: button.bounds)
            cursorView.usesNonKeyWindowTracking = true
            cursorView.autoresizingMask = [.width, .height]
            cursorView.setAccessibilityElement(false)
            button.addSubview(cursorView)
        }
        let panel = RatioPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Ratio"
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.onCancel = { [weak self] in self?.closePanel() }
        self.panel = panel
        model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }.store(in: &subscriptions)
        model.$appearance.sink { [weak self] appearance in
            guard let self else { return }
            self.panel?.appearance = Self.nativeAppearance(appearance)
            self.preferencesWindow?.appearance = Self.nativeAppearance(appearance)
            self.tourWindow?.appearance = Self.nativeAppearance(appearance)
        }.store(in: &subscriptions)
        model.$tourPresented.removeDuplicates().sink { [weak self] presented in
            if presented { self?.showTourWindow() }
            else { self?.tourWindow?.close() }
        }.store(in: &subscriptions)
        updateStatusItem()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.showPanel() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let tourWindow, tourWindow.isVisible {
            tourWindow.makeKeyAndOrderFront(nil)
        } else if let preferencesWindow, preferencesWindow.isVisible {
            preferencesWindow.makeKeyAndOrderFront(nil)
        } else if panel?.isVisible != true && !flag {
            showPanel()
        }
        return false
    }
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApplication.shared.currentEvent?.type == .rightMouseUp {
            closePanel()
            let menu = contextMenu()
            statusItem?.menu = menu
            sender.performClick(nil)
            statusItem?.menu = nil
        } else if panel?.isVisible == true { closePanel() }
        else { showPanel() }
    }
    func showPanel() {
        if let panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        guard let button = statusItem?.button, let anchorWindow = button.window, let panel else { return }
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = anchorWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchor
        let left = min(max(anchor.midX - 180, screen.minX + 4), screen.maxX - 364)
        let pointer = anchor.midX - left
        panel.contentViewController = NSHostingController(rootView:
            AnchoredPanelView(pointer: pointer, showPreferences: { [weak self] in self?.showPreferences() })
                .environmentObject(model))
        panel.appearance = Self.nativeAppearance(model.appearance)
        panel.setFrame(NSRect(x: left, y: anchor.minY - 360, width: 360, height: 360), display: true)
        panel.makeKeyAndOrderFront(nil)
        installDismissalMonitors()
        captureReferenceIfRequested()
    }
    /// Native rendering makes the reference fixture reproducible without screen-recording permission.
    private func captureReferenceIfRequested() {
        guard model.isReferenceDemo,
              let path = ProcessInfo.processInfo.environment["RATIO_NATIVE_CAPTURE_PATH"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let view = self?.panel?.contentView else { return }
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
            do { try png.write(to: URL(fileURLWithPath: path), options: .atomic) }
            catch { NSLog("Reference image could not be saved: %@", error.localizedDescription) }
        }
    }
    private func closePanel() {
        panel?.orderOut(nil)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        outsideClickMonitor = nil
        localClickMonitor = nil
    }
    private func installDismissalMonitors() {
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePanel()
            }
        }
        if localClickMonitor == nil {
            localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self else { return event }
                if event.window !== self.panel && event.window !== self.statusItem?.button?.window { self.closePanel() }
                return event
            }
        }
    }
    func showPreferences() {
        closePanel()
        if preferencesWindow == nil {
            preferencesWindow = auxiliaryWindow(title: "Ratio Settings", size: NSSize(width: 450, height: 600),
                                                 content: PreferencesView().environmentObject(model))
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }
    private func showTourWindow() {
        closePanel()
        if tourWindow == nil {
            tourWindow = auxiliaryWindow(title: "How Ratio Works", size: NSSize(width: 760, height: 600),
                                         content: TourView(showPreferences: { [weak self] in self?.showPreferences() }).environmentObject(model))
            tourWindow?.delegate = self
        } else {
            tourWindow?.contentViewController = NSHostingController(rootView: TourView(showPreferences: { [weak self] in self?.showPreferences() }).environmentObject(model))
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        tourWindow?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === tourWindow {
            model.closeGuidedTour()
        }
    }
    private func auxiliaryWindow<Content: View>(title: String, size: NSSize, content: Content) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: content)
        window.appearance = Self.nativeAppearance(model.appearance)
        window.center()
        return window
    }
    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let category = model.activeCategory
        let paused = model.indicatorPaused
        let font = RatioTypography.nativeFont()
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = RatioTypography.lineHeight()
        paragraph.maximumLineHeight = RatioTypography.lineHeight()
        paragraph.alignment = .center
        let color = MenuIndicator.color(category: category, paused: paused)
        button.image = paused ? MenuIndicator.image(category: category, paused: true) : nil
        button.imagePosition = paused ? .imageLeading : .noImage
        button.font = font
        button.attributedTitle = NSAttributedString(
            string: (paused ? "" : MenuIndicator.glyph(category: category)) + " " + model.menuRatio + (model.session.isDemo ? " D" : ""),
            attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
        button.toolTip = "Ratio · \(model.statusText)"
        button.setAccessibilityLabel("Ratio \(model.menuRatio), \(model.statusText)")
    }
    private static func nativeAppearance(_ appearance: AppModel.Appearance) -> NSAppearance? {
        switch appearance {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        add("Show Ratio", to: menu, action: #selector(openPanel))
        add("Settings…", to: menu, action: #selector(openPreferences), key: ",")
        add("How It Works…", to: menu, action: #selector(openTour))
        menu.addItem(.separator())
        add(model.session.isPaused ? "Resume Tracking" : "Pause Tracking", to: menu, action: #selector(togglePause))
        add(model.session.isDemo ? "Exit Demo" : "Try Demo", to: menu, action: #selector(toggleDemo))
        let undo = add("Undo Reset", to: menu, action: #selector(undoReset))
        undo.isEnabled = model.canUndoReset
        menu.autoenablesItems = false
        menu.addItem(.separator())
        add("Quit Ratio Native", to: menu, action: #selector(quit), key: "q")
        return menu
    }
    @discardableResult
    private func add(_ title: String, to menu: NSMenu, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }
    @objc private func openPanel() { showPanel() }
    @objc private func openPreferences() { showPreferences() }
    @objc private func openTour() { model.showTour() }
    @objc private func togglePause() { model.togglePause() }
    @objc private func toggleDemo() {
        if model.session.isDemo { model.exitDemo() } else { model.startDemo() }
        showPanel()
    }
    @objc private func undoReset() { model.undoResetToday() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}


/// Borderless native panel with normal keyboard focus and an Escape dismissal action.
private final class RatioPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

private struct AnchoredPanelView: View {
    @EnvironmentObject private var model: AppModel
    let pointer: CGFloat
    let showPreferences: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 8)
            MenuBarView(showPreferences: showPreferences)
        }
        .frame(width: 360, height: 360)
        .background(RatioTheme.background, in: PanelOutline(pointer: pointer))
        .clipShape(PanelOutline(pointer: pointer))
        .preferredColorScheme(model.appearance.colorScheme)
    }
}

private struct PanelOutline: Shape {
    let pointer: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: CGRect(x: 0, y: 8, width: rect.width, height: rect.height - 8),
                        cornerRadius: 8)
        let center = min(max(pointer, 16), rect.width - 16)
        path.move(to: CGPoint(x: center - 10, y: 8))
        path.addLine(to: CGPoint(x: center - 3, y: 1))
        path.addQuadCurve(to: CGPoint(x: center + 3, y: 1), control: CGPoint(x: center, y: -2))
        path.addLine(to: CGPoint(x: center + 10, y: 8))
        path.closeSubpath()
        return path
    }
}
