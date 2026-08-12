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
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(model.menuBarTitle)
                    .font(.system(size: 12).monospacedDigit())
            }
        }
        .menuBarExtraStyle(.window)

        Window("Oh My Servers", id: "settings") {
            SettingsView()
                .environmentObject(model)
                .frame(minWidth: 520, minHeight: 420)
        }
    }

    private var statusColor: Color {
        let enabled = model.servers.filter(\.isEnabled)
        guard !enabled.isEmpty else { return Color.gray }
        let healths = enabled.map { model.snapshots[$0.id]?.health ?? .offline }
        if healths.contains(.offline) { return Color(red: 1, green: 0.35, blue: 0.35) }
        if healths.contains(.high) { return Color(red: 1, green: 0.84, blue: 0.04) }
        if healths.allSatisfy({ $0 == .online }) { return Color(red: 0.19, green: 0.82, blue: 0.35) }
        return Color.gray
    }
}
