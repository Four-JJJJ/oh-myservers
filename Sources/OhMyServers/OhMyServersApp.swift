import SwiftUI
import OhMyServersCore

@main
struct OhMyServersApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView()
                .environmentObject(model)
        } label: {
            Label {
                Text(model.menuBarTitle)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
            } icon: {
                Image(systemName: "server.rack")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(statusColor, statusColor.opacity(0.85))
            }
            .labelStyle(.titleAndIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var statusColor: Color {
        let enabled = model.servers.filter(\.isEnabled)
        guard !enabled.isEmpty else { return Graphite.muted }
        let healths = enabled.map { model.snapshots[$0.id]?.health ?? .offline }
        if healths.contains(.offline) { return Graphite.offline }
        if healths.contains(.high) { return Graphite.high }
        if healths.allSatisfy({ $0 == .online }) { return Graphite.online }
        return Graphite.muted
    }
}
