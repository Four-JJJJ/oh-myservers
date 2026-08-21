import SwiftUI
import OhMyServersCore

@main
struct OhMyServersApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Warm the Komari web views in the background so the first popover
        // open renders immediately instead of loading each SPA on click.
        DispatchQueue.main.async {
            let sites = KomariSiteStore().list().filter(\.isEnabled)
            KomariWebStore.shared.preload(sites: sites)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView()
                .environmentObject(model)
        } label: {
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
        let nodes = model.nodeStatuses
        guard !nodes.isEmpty else { return Graphite.muted }
        return nodes.allSatisfy(\.isOnline) ? Graphite.online : Graphite.offline
    }
}
