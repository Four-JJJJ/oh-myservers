import Foundation

public struct StatusAggregator {
    public init() {}

    /// Builds menu bar title like `HK 23% · US 41%` or `HK —` when offline.
    public func menuBarTitle(servers: [ServerConfig], snapshots: [UUID: MetricsSnapshot]) -> String {
        let enabled = servers.filter(\.isEnabled)
        guard !enabled.isEmpty else { return "No servers" }

        return enabled.map { server in
            let label = server.label.isEmpty ? String(server.name.prefix(2)).uppercased() : server.label
            guard let snap = snapshots[server.id], snap.isReachable, let cpu = snap.cpuPercent else {
                return "\(label) —"
            }
            return "\(label) \(Int(cpu.rounded()))%"
        }
        .joined(separator: " · ")
    }

    public func overallIsAbnormal(snapshots: [MetricsSnapshot]) -> Bool {
        guard !snapshots.isEmpty else { return false }
        return snapshots.contains { $0.health != .online }
    }
}
