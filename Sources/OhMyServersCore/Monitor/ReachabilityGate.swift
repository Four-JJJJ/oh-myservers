import Foundation

public struct ReachabilityGate: Sendable {
    public var confirmAfter: Int
    private var missCount: [UUID: Int] = [:]
    private var lastGood: [UUID: MetricsSnapshot] = [:]

    public init(confirmAfter: Int = 2) {
        self.confirmAfter = max(1, confirmAfter)
    }

    public mutating func accept(_ raw: MetricsSnapshot) -> MetricsSnapshot {
        let id = raw.serverID
        if raw.isReachable {
            missCount[id] = 0
            lastGood[id] = raw
            return raw
        }
        missCount[id, default: 0] += 1
        if missCount[id, default: 0] < confirmAfter, let held = lastGood[id] {
            return held
        }
        return raw
    }

    public mutating func prune(keeping ids: Set<UUID>) {
        missCount = missCount.filter { ids.contains($0.key) }
        lastGood = lastGood.filter { ids.contains($0.key) }
    }
}
