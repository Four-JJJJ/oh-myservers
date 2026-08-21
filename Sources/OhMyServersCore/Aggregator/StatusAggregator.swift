import Foundation

public struct StatusAggregator {
    public init() {}

    /// Builds the menu bar title from Komari nodes, honoring the user's
    /// metric/node selection — e.g. `HK 23% M45% · US 41% M60%`.
    public func menuBarTitle(
        komariNodes: [KomariNodeStatus],
        settings: MenuBarDisplaySettings = .default
    ) -> String {
        let nodes: [KomariNodeStatus]
        if let selected = settings.selectedNodeUUIDs {
            nodes = komariNodes.filter { selected.contains($0.info.uuid) }
        } else {
            nodes = komariNodes
        }
        guard !nodes.isEmpty else { return "无服务器" }

        // Output follows allCases order so the title never reshuffles.
        let metrics = MenuBarMetric.allCases.filter { settings.metrics.contains($0) }

        return nodes.map { node in
            let label = String(node.info.name.prefix(2)).uppercased()
            guard !metrics.isEmpty else { return label }
            guard node.isOnline, let report = node.report else {
                return "\(label) —"
            }
            let parts = metrics.map { format($0, node: node, report: report) }
            return ([label] + parts).joined(separator: " ")
        }
        .joined(separator: " · ")
    }

    private func format(_ metric: MenuBarMetric, node: KomariNodeStatus, report: KomariRealtimeReport) -> String {
        switch metric {
        case .cpu:
            return "\(Int(report.cpuUsagePercent.rounded()))%"
        case .memory:
            guard let percent = node.memUsedPercent else { return "M—" }
            return "M\(Int(percent.rounded()))%"
        case .load:
            return "L\(String(format: "%.2f", report.load1))"
        case .disk:
            guard let percent = node.diskUsedPercent else { return "D—" }
            return "D\(Int(percent.rounded()))%"
        case .networkUp:
            return "↑\(formatRate(report.netUpBytesPerSec))"
        case .networkDown:
            return "↓\(formatRate(report.netDownBytesPerSec))"
        case .uptime:
            return "U\(formatUptime(report.uptimeSeconds))"
        case .process:
            return "P\(report.processCount)"
        }
    }

    /// Bytes/sec → compact rate like `1.2K/s`, `250K/s`, `3.4M/s`.
    private func formatRate(_ bytesPerSecond: Double) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var value = max(bytesPerSecond, 0)
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        let number: String
        if unitIndex > 0, value < 100 {
            number = String(format: "%.1f", value)
        } else {
            number = "\(Int(value.rounded()))"
        }
        return "\(number)\(units[unitIndex])/s"
    }

    /// Seconds → largest unit: `12d`, `5h`, `42m`.
    private func formatUptime(_ seconds: UInt64) -> String {
        let days = seconds / 86_400
        if days > 0 { return "\(days)d" }
        let hours = seconds / 3_600
        if hours > 0 { return "\(hours)h" }
        return "\(seconds / 60)m"
    }
}
