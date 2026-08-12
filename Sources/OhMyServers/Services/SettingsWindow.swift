import AppKit
import SwiftUI

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    private static var closer: WindowCloser?

    static func present(model: AppModel) {
        // LSUIElement menu-bar apps stay .accessory; windows won't surface until .regular.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let root = SettingsView()
            .environmentObject(model)
            .frame(minWidth: 560, minHeight: 440)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Oh My Servers"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 440))
        window.center()
        window.isReleasedWhenClosed = false
        let closer = WindowCloser {
            Self.window = nil
            Self.closer = nil
            NSApp.setActivationPolicy(.accessory)
        }
        window.delegate = closer
        self.closer = closer
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
}

private final class WindowCloser: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
