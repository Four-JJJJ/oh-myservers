import Foundation

public struct MetricSample: Sendable, Equatable {
    public var procStat: String
    public var procMeminfo: String
    public var procLoadavg: String
    public var procUptime: String
    public var procNetDev: String
    public var df: String
    public var nprocText: String
    public var sampledAt: Date

    public init(
        procStat: String,
        procMeminfo: String,
        procLoadavg: String,
        procUptime: String,
        procNetDev: String,
        df: String,
        nprocText: String,
        sampledAt: Date
    ) {
        self.procStat = procStat
        self.procMeminfo = procMeminfo
        self.procLoadavg = procLoadavg
        self.procUptime = procUptime
        self.procNetDev = procNetDev
        self.df = df
        self.nprocText = nprocText
        self.sampledAt = sampledAt
    }
}

public enum MetricsParser {
    public static func parse(
        serverID: UUID,
        current: MetricSample,
        previous: MetricSample?,
        intervalSeconds: Double? = nil
    ) -> MetricsSnapshot {
        let mem = memory(from: current.procMeminfo)
        let load = loadAverage(from: current.procLoadavg)
        let uptime = uptimeSeconds(from: current.procUptime)
        let disk = diskUsage(from: current.df)
        let cpuCount = cpuCount(from: current.nprocText)

        var cpu: Double?
        var net: (rx: Double, tx: Double)?
        if let previous {
            let interval = intervalSeconds ?? current.sampledAt.timeIntervalSince(previous.sampledAt)
            if interval > 0 {
                cpu = cpuPercent(stat1: previous.procStat, stat2: current.procStat)
                net = networkRate(net1: previous.procNetDev, net2: current.procNetDev, interval: interval)
            }
        }

        return MetricsSnapshot(
            serverID: serverID,
            collectedAt: current.sampledAt,
            isReachable: true,
            cpuPercent: cpu,
            load1: load?.0,
            load5: load?.1,
            load15: load?.2,
            cpuCount: cpuCount,
            memoryUsedBytes: mem?.used,
            memoryTotalBytes: mem?.total,
            diskUsedPercent: disk.percent,
            diskUsedBytes: disk.usedBytes,
            diskTotalBytes: disk.totalBytes,
            netRxBytesPerSec: net?.rx,
            netTxBytesPerSec: net?.tx,
            uptimeSeconds: uptime
        )
    }

    // MARK: - CPU

    static func cpuPercent(stat1: String, stat2: String) -> Double? {
        guard let a = cpuTimes(from: stat1), let b = cpuTimes(from: stat2) else { return nil }
        let totalDelta = b.total - a.total
        let idleDelta = b.idle - a.idle
        guard totalDelta > 0 else { return nil }
        let busy = totalDelta - idleDelta
        return max(0, min(100, Double(busy) / Double(totalDelta) * 100.0))
    }

    private struct CPUTimes {
        var total: UInt64
        var idle: UInt64
    }

    private static func cpuTimes(from stat: String) -> CPUTimes? {
        guard let line = stat.split(separator: "\n").first(where: { $0.hasPrefix("cpu ") }) else {
            return nil
        }
        let parts = line.split(whereSeparator: \.isWhitespace)
        // cpu user nice system idle iowait irq softirq steal guest guest_nice
        guard parts.count >= 5 else { return nil }
        let values = parts.dropFirst().compactMap { UInt64($0) }
        guard values.count >= 4 else { return nil }
        let idle = values[3] + (values.count > 4 ? values[4] : 0) // idle + iowait
        let total = values.reduce(UInt64(0), +)
        return CPUTimes(total: total, idle: idle)
    }

    static func cpuCount(from text: String) -> Int? {
        text.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }.first
    }

    // MARK: - Memory

    static func memory(from meminfo: String) -> (used: UInt64, total: UInt64)? {
        var totalKB: UInt64?
        var availableKB: UInt64?
        for line in meminfo.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2, let value = UInt64(parts[1]) else { continue }
            if parts[0].hasPrefix("MemTotal") { totalKB = value }
            if parts[0].hasPrefix("MemAvailable") { availableKB = value }
        }
        guard let totalKB, let availableKB, totalKB > 0 else { return nil }
        let total = totalKB * 1024
        let used = (totalKB &- min(totalKB, availableKB)) * 1024
        return (used, total)
    }

    // MARK: - Load

    static func loadAverage(from loadavg: String) -> (Double, Double, Double)? {
        let parts = loadavg.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 3,
              let a = Double(parts[0]),
              let b = Double(parts[1]),
              let c = Double(parts[2]) else { return nil }
        return (a, b, c)
    }

    // MARK: - Uptime

    static func uptimeSeconds(from uptime: String) -> UInt64? {
        let parts = uptime.split(whereSeparator: \.isWhitespace)
        guard let first = parts.first, let value = Double(first) else { return nil }
        return UInt64(value)
    }

    // MARK: - Disk

    static func diskUsage(from df: String) -> (percent: Double?, usedBytes: UInt64?, totalBytes: UInt64?) {
        for line in df.split(separator: "\n").dropFirst() {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 6 else { continue }
            let mount = parts[parts.count - 1]
            guard mount == "/" else { continue }
            let capacity = parts[parts.count - 2].trimmingCharacters(in: CharacterSet(charactersIn: "%"))
            let percent = Double(capacity)
            let totalBytes = UInt64(parts[parts.count - 5]).map { $0 * 1024 }
            let usedBytes = UInt64(parts[parts.count - 4]).map { $0 * 1024 }
            return (percent, usedBytes, totalBytes)
        }
        return (nil, nil, nil)
    }

    // MARK: - Network

    static func networkRate(net1: String, net2: String, interval: Double) -> (rx: Double, tx: Double)? {
        guard interval > 0,
              let a = primaryInterfaceCounters(from: net1),
              let b = primaryInterfaceCounters(from: net2) else { return nil }
        let rx = Double(b.rx &- a.rx) / interval
        let tx = Double(b.tx &- a.tx) / interval
        return (max(0, rx), max(0, tx))
    }

    /// Prefer physical NICs (eth*/en*/ens*/enp*) over docker bridges when ranking.
    private static func primaryInterfaceCounters(from netDev: String) -> (rx: UInt64, tx: UInt64)? {
        var preferred: (name: String, rx: UInt64, tx: UInt64)?
        var best: (name: String, rx: UInt64, tx: UInt64)?
        for line in netDev.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let name = trimmed[..<colon].trimmingCharacters(in: .whitespaces)
            if name == "lo" || name.hasPrefix("Inter") || name.hasPrefix("face") { continue }
            let rest = trimmed[trimmed.index(after: colon)...]
            let nums = rest.split(whereSeparator: \.isWhitespace).compactMap { UInt64($0) }
            guard nums.count >= 9 else { continue }
            let rx = nums[0]
            let tx = nums[8]
            let candidate = (String(name), rx, tx)
            if name.hasPrefix("eth") || name.hasPrefix("en") || name.hasPrefix("ens") || name.hasPrefix("enp") {
                if preferred == nil || rx + tx > preferred!.rx + preferred!.tx {
                    preferred = candidate
                }
            }
            if best == nil || rx + tx > best!.rx + best!.tx {
                best = candidate
            }
        }
        let chosen = preferred ?? best
        guard let chosen else { return nil }
        return (chosen.rx, chosen.tx)
    }
}
