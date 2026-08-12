import AppKit
import SwiftUI
import OhMyServersCore

struct MenuBarRootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Graphite.accent)
                Text(L10n.appName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Graphite.text)
                Spacer(minLength: 8)
                Button(L10n.settings) {
                    SettingsWindow.present(model: model)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Graphite.muted)
                .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle()
                .fill(Graphite.divider)
                .frame(height: 1)

            if model.servers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.noServers)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Graphite.text)
                    Text(L10n.noServersHint)
                        .font(.system(size: 11))
                        .foregroundStyle(Graphite.muted)
                }
                .padding(16)
            } else {
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

            Rectangle()
                .fill(Graphite.divider)
                .frame(height: 1)

            HStack {
                Button(L10n.refresh) {
                    model.refreshNow()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Graphite.muted)
                Spacer()
                Button(L10n.quit) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Graphite.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 380)
        .background(Graphite.bg)
        .onAppear {
            model.refreshNow()
        }
    }
}

struct ServerRowView: View {
    let server: ServerConfig
    let snapshot: MetricsSnapshot?

    private let labelWidth: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                statusDot
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Graphite.text)
                    Text("\(server.label)  ·  \(server.host)")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(Graphite.muted)
                }
                Spacer(minLength: 8)
                Text(statusText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.14))
                    .clipShape(Capsule())
            }

            if let snapshot, snapshot.isReachable {
                VStack(spacing: 7) {
                    metricRow((L10n.cpu, cpuText(snapshot)), (L10n.mem, memText(snapshot)))
                    metricRow((L10n.load, loadText(snapshot)), (L10n.disk, diskText(snapshot)))
                    metricRow((L10n.netIn, netRxText(snapshot)), (L10n.netOut, netTxText(snapshot)))
                    metricRow((L10n.uptime, uptimeText(snapshot)), nil)
                }
            } else {
                Text(snapshot?.errorMessage ?? L10n.waitingSample)
                    .font(.system(size: 11))
                    .foregroundStyle(Graphite.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Graphite.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private func metricRow(_ left: (String, String), _ right: (String, String)?) -> some View {
        HStack(spacing: 16) {
            metric(left.0, left.1)
            if let right {
                metric(right.0, right.1)
            } else {
                Color.clear.frame(maxWidth: .infinity)
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

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .foregroundStyle(Graphite.muted)
                .frame(width: labelWidth, alignment: .leading)
            Text(value)
                .foregroundStyle(Graphite.text)
                .fontWeight(.semibold)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 11).monospacedDigit())
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
        return String(format: "%.2f / %.2f / %.2f", a, b, c)
    }

    private func diskText(_ s: MetricsSnapshot) -> String {
        guard let v = s.diskUsedPercent else { return "—" }
        return "\(Int(v.rounded()))%"
    }

    private func netRxText(_ s: MetricsSnapshot) -> String {
        guard let rx = s.netRxBytesPerSec else { return "—" }
        return formatRate(rx)
    }

    private func netTxText(_ s: MetricsSnapshot) -> String {
        guard let tx = s.netTxBytesPerSec else { return "—" }
        return formatRate(tx)
    }

    private func uptimeText(_ s: MetricsSnapshot) -> String {
        guard let sec = s.uptimeSeconds else { return "—" }
        let days = sec / 86_400
        let hours = (sec % 86_400) / 3600
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        let mins = (sec % 3600) / 60
        return "\(hours) 小时 \(mins) 分"
    }

    private func formatRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec > 1_000_000 { return String(format: "%.1f MB/s", bytesPerSec / 1_000_000) }
        if bytesPerSec > 1_000 { return String(format: "%.1f KB/s", bytesPerSec / 1_000) }
        return String(format: "%.0f B/s", bytesPerSec)
    }
}
