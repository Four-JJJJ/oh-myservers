import Foundation

public struct AlertEvent: Sendable, Equatable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public struct AlertEvaluator {
    public init() {}

    /// Edge-triggered: notify when a server flips reachable→unreachable,
    /// or overall health flips normal→abnormal.
    public func evaluate(
        servers: [ServerConfig],
        previous: [UUID: MetricsSnapshot],
        current: [UUID: MetricsSnapshot]
    ) -> [AlertEvent] {
        var events: [AlertEvent] = []

        for server in servers where server.isEnabled {
            let wasReachable = previous[server.id]?.isReachable ?? true
            let isReachable = current[server.id]?.isReachable ?? false
            if wasReachable && !isReachable {
                let detail = current[server.id]?.errorMessage ?? "Connection failed"
                events.append(AlertEvent(
                    title: "\(server.name) offline",
                    body: detail
                ))
            }
        }

        let prevSnaps = servers.compactMap { previous[$0.id] }
        let currSnaps = servers.compactMap { current[$0.id] }
        let aggregator = StatusAggregator()
        let wasAbnormal = aggregator.overallIsAbnormal(snapshots: prevSnaps)
        let isAbnormal = aggregator.overallIsAbnormal(snapshots: currSnaps)
        if !wasAbnormal && isAbnormal {
            // Avoid duplicate if we already emitted per-server offline for the only change.
            if events.isEmpty {
                events.append(AlertEvent(
                    title: "Server status abnormal",
                    body: "One or more servers need attention"
                ))
            }
        }

        return events
    }
}
