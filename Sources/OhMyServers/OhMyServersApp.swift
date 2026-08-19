import SwiftUI
import OhMyServersCore

@main
struct OhMyServersApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Warm the Komari web view in the background so the first popover
        // open renders immediately instead of loading the SPA on click.
        DispatchQueue.main.async {
            KomariWebStore.shared.preload()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView()
                .environmentObject(model)
        } label: {
            // Demo style: status dot + summary text
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(model.menuBarTitle)
                    .font(.system(size: 12, weight: .regular).monospacedDigit())
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var statusColor: Color {
        let enabled = model.servers.filter(\.isEnabled)
        if enabled.isEmpty {
            let nodes = model.komariNodes
            guard !nodes.isEmpty else { return Graphite.muted }
            return nodes.allSatisfy(\.isOnline) ? Graphite.online : Graphite.offline
        }
        let healths = enabled.map { model.snapshots[$0.id]?.health ?? .offline }
        if healths.contains(.offline) { return Graphite.offline }
        if healths.contains(.high) { return Graphite.high }
        if healths.allSatisfy({ $0 == .online }) { return Graphite.online }
        return Graphite.muted
    }
}
