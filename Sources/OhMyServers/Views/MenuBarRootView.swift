import AppKit
import SwiftUI
import OhMyServersCore

struct MenuBarRootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact header — demo-like, minimal chrome
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Graphite.muted)
                Text(L10n.appName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Graphite.muted)
                Spacer(minLength: 8)
                headerButton(L10n.settings) {
                    SettingsWindow.present(model: model)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            if model.servers.isEmpty {
                Text(L10n.noServersHint)
                    .font(.system(size: 12))
                    .foregroundStyle(Graphite.muted)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            } else {
                // Single inner card with dividers — matches Graphite demo
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.servers.enumerated()), id: \.element.id) { index, server in
                        if index > 0 {
                            Rectangle()
                                .fill(Graphite.divider)
                                .frame(height: 1)
                                .padding(.vertical, 10)
                        }
                        ServerBlockView(
                            server: server,
                            snapshot: model.snapshots[server.id]
                        )
                    }
                }
                .padding(12)
                .background(Graphite.card)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }

            HStack(spacing: 16) {
                headerButton(L10n.refresh) { model.refreshNow() }
                Spacer()
                headerButton(L10n.quit) { NSApplication.shared.terminate(nil) }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 320)
        .background(Graphite.bg)
        .onAppear { model.refreshNow() }
    }

    private func headerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Graphite.muted)
        }
        .buttonStyle(.borderless)
    }
}

/// One server block inside the shared demo card.
struct ServerBlockView: View {
    let server: ServerConfig
    let snapshot: MetricsSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(server.name)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Graphite.text)
                Spacer(minLength: 8)
                Text(statusText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(statusColor)
            }

            if let snapshot, snapshot.isReachable {
                VStack(spacing: 6) {
                    HStack(spacing: 0) {
                        demoMetric(L10n.cpu, cpuText(snapshot))
                        demoMetric(L10n.mem, memText(snapshot))
                    }
                    HStack(spacing: 0) {
                        demoMetric(L10n.load, loadText(snapshot))
                        demoMetric(L10n.disk, diskText(snapshot))
                    }
                    HStack(spacing: 0) {
                        demoMetric(L10n.netIn, netRxText(snapshot))
                        demoMetric(L10n.netOut, netTxText(snapshot))
                    }
                    HStack(spacing: 0) {
                        demoMetric(L10n.uptime, uptimeText(snapshot))
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            } else {
                Text(snapshot?.errorMessage ?? L10n.waitingSample)
                    .font(.system(size: 11))
                    .foregroundStyle(Graphite.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusText: String {
        switch snapshot?.health {
        case .online: return L10n.online
        case .high: return L10n.high
        case .offline: return L10n.offline
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

    private func demoMetric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(Graphite.muted)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(Graphite.text)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12).monospacedDigit())
        .frame(maxWidth: .infinity, alignment: .leading)
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
        guard let a = s.load1, let b = s.load5, let c = s.load15 else {
            if let a = s.load1 { return String(format: "%.2f", a) }
            return "—"
        }
        return String(format: "%.2f/%.2f/%.2f", a, b, c)
    }

    private func diskText(_ s: MetricsSnapshot) -> String {
        guard let v = s.diskUsedPercent else { return "—" }
        return "\(Int(v.rounded()))%"
    }

    private func netRxText(_ s: MetricsSnapshot) -> String {
        guard let rx = s.netRxBytesPerSec else { return "—" }
        return "↓\(formatRate(rx))"
    }

    private func netTxText(_ s: MetricsSnapshot) -> String {
        guard let tx = s.netTxBytesPerSec else { return "—" }
        return "↑\(formatRate(tx))"
    }

    private func uptimeText(_ s: MetricsSnapshot) -> String {
        guard let sec = s.uptimeSeconds else { return "—" }
        let days = sec / 86_400
        let hours = (sec % 86_400) / 3600
        if days > 0 { return "\(days)天\(hours)时" }
        let mins = (sec % 3600) / 60
        return "\(hours)时\(mins)分"
    }

    private func formatRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_000_000 { return String(format: "%.1fM", bytesPerSec / 1_000_000) }
        if bytesPerSec >= 1_000 { return String(format: "%.1fK", bytesPerSec / 1_000) }
        return String(format: "%.0fB", bytesPerSec)
    }
}
