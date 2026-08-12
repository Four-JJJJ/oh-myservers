import AppKit
import SwiftUI
import OhMyServersCore

private enum Graphite {
    static let bg = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let card = Color(red: 0.17, green: 0.17, blue: 0.18)
    static let text = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let muted = Color(red: 0.63, green: 0.63, blue: 0.65)
    static let divider = Color(red: 0.23, green: 0.23, blue: 0.24)
    static let online = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let high = Color(red: 1, green: 0.84, blue: 0.04)
    static let offline = Color(red: 1, green: 0.35, blue: 0.35)
}

struct MenuBarRootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Oh My Servers")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Graphite.text)
                Spacer()
                Button("Settings") {
                    SettingsWindow.present(model: model)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Graphite.muted)
                .font(.system(size: 12))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().background(Graphite.divider)

            if model.servers.isEmpty {
                Text("No servers yet. Open Settings to add one.")
                    .font(.system(size: 12))
                    .foregroundStyle(Graphite.muted)
                    .padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.servers) { server in
                            ServerRowView(
                                server: server,
                                snapshot: model.snapshots[server.id]
                            )
                        }
                    }
                    .padding(12)
                }
            }

            Divider().background(Graphite.divider)

            HStack {
                Button("Refresh now") {
                    // Next poll cycle is ≤15s; restart monitoring for immediacy.
                    model.startMonitoring()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Graphite.muted)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Graphite.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 340)
        .background(Graphite.bg)
    }
}

struct ServerRowView: View {
    let server: ServerConfig
    let snapshot: MetricsSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(server.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Graphite.text)
                Spacer()
                Text(statusText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor)
            }

            if let snapshot, snapshot.isReachable {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    metric("CPU", cpuText(snapshot))
                    metric("MEM", memText(snapshot))
                    metric("Load", loadText(snapshot))
                    metric("Disk", diskText(snapshot))
                    metric("Net", netText(snapshot))
                    metric("Up", uptimeText(snapshot))
                }
            } else {
                Text(snapshot?.errorMessage ?? "Waiting for first sample…")
                    .font(.system(size: 11))
                    .foregroundStyle(Graphite.muted)
            }
        }
        .padding(12)
        .background(Graphite.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statusText: String {
        switch snapshot?.health {
        case .online: return "Online"
        case .high: return "High"
        case .offline: return "Offline"
        case nil: return "…"
        }
    }

    private var statusColor: Color {
        switch snapshot?.health {
        case .online: return Graphite.online
        case .high: return Graphite.high
        case .offline: return Graphite.offline
        case nil: return Graphite.muted
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(Graphite.muted)
            Text(value)
                .foregroundStyle(Graphite.text)
                .fontWeight(.semibold)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11).monospacedDigit())
    }

    private func cpuText(_ s: MetricsSnapshot) -> String {
        guard let v = s.cpuPercent else { return "—" }
        return "\(Int(v.rounded()))%"
    }

    private func memText(_ s: MetricsSnapshot) -> String {
        guard let v = s.memoryUsedPercent else { return "—" }
        return "\(Int(v.rounded()))%"
    }

    private func loadText(_ s: MetricsSnapshot) -> String {
        guard let a = s.load1 else { return "—" }
        return String(format: "%.2f", a)
    }

    private func diskText(_ s: MetricsSnapshot) -> String {
        guard let v = s.diskUsedPercent else { return "—" }
        return "\(Int(v.rounded()))%"
    }

    private func netText(_ s: MetricsSnapshot) -> String {
        guard let rx = s.netRxBytesPerSec else { return "—" }
        return "↓\(formatRate(rx))"
    }

    private func uptimeText(_ s: MetricsSnapshot) -> String {
        guard let sec = s.uptimeSeconds else { return "—" }
        let days = sec / 86_400
        let hours = (sec % 86_400) / 3600
        if days > 0 { return "\(days)d \(hours)h" }
        let mins = (sec % 3600) / 60
        return "\(hours)h \(mins)m"
    }

    private func formatRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec > 1_000_000 { return String(format: "%.1fM", bytesPerSec / 1_000_000) }
        if bytesPerSec > 1_000 { return String(format: "%.1fK", bytesPerSec / 1_000) }
        return String(format: "%.0fB", bytesPerSec)
    }
}
