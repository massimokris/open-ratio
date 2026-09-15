import AppKit
import SwiftUI

@main
struct RatioNativeApp: App {
    @NSApplicationDelegateAdaptor(RatioAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("Ratio Native", id: "dashboard") {
            DashboardView().environmentObject(model).preferredColorScheme(model.appearance.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Tracking") {
                Button(model.session.isPaused ? "Resume tracking" : "Pause tracking", action: model.togglePause)
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Try demo", action: model.startDemo).keyboardShortcut("d", modifiers: [.command, .shift])
                Button("How it works", action: model.showTour).keyboardShortcut("?", modifiers: [.command])
            }
        }
        MenuBarExtra {
            MenuBarView().environmentObject(model).preferredColorScheme(model.appearance.colorScheme)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: MenuIndicator.image(category: model.activeCategory, paused: model.session.isPaused))
                    .renderingMode(.original)
                Text(model.menuRatio).monospacedDigit()
                if model.session.isDemo { Text("D") }
            }.accessibilityLabel("Ratio \(model.menuRatio), \(model.statusText)")
        }.menuBarExtraStyle(.window)
    }
}

final class RatioAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first { $0.title == "Ratio Native" }?.makeKeyAndOrderFront(nil) }
        return true
    }
}
