import Foundation

public enum ServerHealth: String, Sendable, Equatable {
    case online
    case high
    case offline
}

public struct MetricsSnapshot: Identifiable, Sendable, Equatable {
    public var id: UUID { serverID }
    public var serverID: UUID
    public var collectedAt: Date
    public var isReachable: Bool
    public var cpuPercent: Double?
    public var load1: Double?
    public var load5: Double?
    public var load15: Double?
    public var memoryUsedBytes: UInt64?
    public var memoryTotalBytes: UInt64?
    public var diskUsedPercent: Double?
    public var netRxBytesPerSec: Double?
    public var netTxBytesPerSec: Double?
    public var uptimeSeconds: UInt64?
    public var errorMessage: String?

    public init(
        serverID: UUID,
        collectedAt: Date = Date(),
        isReachable: Bool,
        cpuPercent: Double? = nil,
        load1: Double? = nil,
        load5: Double? = nil,
        load15: Double? = nil,
        memoryUsedBytes: UInt64? = nil,
        memoryTotalBytes: UInt64? = nil,
        diskUsedPercent: Double? = nil,
        netRxBytesPerSec: Double? = nil,
        netTxBytesPerSec: Double? = nil,
        uptimeSeconds: UInt64? = nil,
        errorMessage: String? = nil
    ) {
        self.serverID = serverID
        self.collectedAt = collectedAt
        self.isReachable = isReachable
        self.cpuPercent = cpuPercent
        self.load1 = load1
        self.load5 = load5
        self.load15 = load15
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.diskUsedPercent = diskUsedPercent
        self.netRxBytesPerSec = netRxBytesPerSec
        self.netTxBytesPerSec = netTxBytesPerSec
        self.uptimeSeconds = uptimeSeconds
        self.errorMessage = errorMessage
    }

    public var memoryUsedPercent: Double? {
        guard let used = memoryUsedBytes, let total = memoryTotalBytes, total > 0 else { return nil }
        return Double(used) / Double(total) * 100.0
    }

    public var health: ServerHealth {
        guard isReachable else { return .offline }
        let cpuHigh = (cpuPercent ?? 0) >= 85
        let memHigh = (memoryUsedPercent ?? 0) >= 90
        let diskHigh = (diskUsedPercent ?? 0) >= 90
        if cpuHigh || memHigh || diskHigh { return .high }
        return .online
    }

    public static func unreachable(serverID: UUID, message: String) -> MetricsSnapshot {
        MetricsSnapshot(
            serverID: serverID,
            isReachable: false,
            errorMessage: message
        )
    }
}
