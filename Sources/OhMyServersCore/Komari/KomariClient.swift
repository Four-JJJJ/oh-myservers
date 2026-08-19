import Foundation

/// Static node metadata from Komari `GET /api/nodes`.
public struct KomariNodeInfo: Identifiable, Sendable, Equatable {
    public var id: String { uuid }
    public let uuid: String
    public let name: String
    public let region: String
    public let os: String
    public let cpuCores: Int
    public let memTotal: UInt64
    public let diskTotal: UInt64

    public init(uuid: String, name: String, region: String, os: String, cpuCores: Int, memTotal: UInt64, diskTotal: UInt64) {
        self.uuid = uuid
        self.name = name
        self.region = region
        self.os = os
        self.cpuCores = cpuCores
        self.memTotal = memTotal
        self.diskTotal = diskTotal
    }
}

/// Latest realtime report from Komari WebSocket `/api/clients` (`get`).
public struct KomariRealtimeReport: Sendable, Equatable {
    public let cpuUsagePercent: Double
    public let ramUsed: UInt64
    public let ramTotal: UInt64
    public let diskUsed: UInt64
    public let diskTotal: UInt64
    public let netUpBytesPerSec: Double
    public let netDownBytesPerSec: Double
    public let load1: Double
    public let load5: Double
    public let load15: Double
    public let uptimeSeconds: UInt64
    public let processCount: Int

    public init(
        cpuUsagePercent: Double,
        ramUsed: UInt64,
        ramTotal: UInt64,
        diskUsed: UInt64,
        diskTotal: UInt64,
        netUpBytesPerSec: Double,
        netDownBytesPerSec: Double,
        load1: Double,
        load5: Double,
        load15: Double,
        uptimeSeconds: UInt64,
        processCount: Int
    ) {
        self.cpuUsagePercent = cpuUsagePercent
        self.ramUsed = ramUsed
        self.ramTotal = ramTotal
        self.diskUsed = diskUsed
        self.diskTotal = diskTotal
        self.netUpBytesPerSec = netUpBytesPerSec
        self.netDownBytesPerSec = netDownBytesPerSec
        self.load1 = load1
        self.load5 = load5
        self.load15 = load15
        self.uptimeSeconds = uptimeSeconds
        self.processCount = processCount
    }
}

/// Node metadata merged with its realtime report.
public struct KomariNodeStatus: Identifiable, Sendable, Equatable {
    public var id: String { info.uuid }
    public let info: KomariNodeInfo
    public let isOnline: Bool
    public let report: KomariRealtimeReport?

    public init(info: KomariNodeInfo, isOnline: Bool, report: KomariRealtimeReport?) {
        self.info = info
        self.isOnline = isOnline
        self.report = report
    }

    public var memUsedPercent: Double? {
        guard let report, report.ramTotal > 0 else { return nil }
        return Double(report.ramUsed) / Double(report.ramTotal) * 100
    }

    public var diskUsedPercent: Double? {
        guard let report, report.diskTotal > 0 else { return nil }
        return Double(report.diskUsed) / Double(report.diskTotal) * 100
    }
}

public enum KomariError: Error, Equatable {
    case invalidBaseURL(String)
    case httpStatus(Int)
    case apiError(String)
    case timeout
    case invalidResponse
}

/// Pure JSON decoding for Komari payloads (kept separate from networking for tests).
public enum KomariParser {
    private struct NodesResponse: Decodable {
        let status: String
        let data: [Node]

        struct Node: Decodable {
            let uuid: String
            let name: String
            let region: String
            let os: String
            let cpuCores: Int
            let memTotal: UInt64
            let diskTotal: UInt64
        }
    }

    public static func parseNodes(_ data: Data) throws -> [KomariNodeInfo] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(NodesResponse.self, from: data)
        guard response.status == "success" else { throw KomariError.apiError(response.status) }
        return response.data.map {
            KomariNodeInfo(
                uuid: $0.uuid,
                name: $0.name,
                region: $0.region,
                os: $0.os,
                cpuCores: $0.cpuCores,
                memTotal: $0.memTotal,
                diskTotal: $0.diskTotal
            )
        }
    }

    private struct RealtimeResponse: Decodable {
        let status: String
        let data: Payload

        struct Payload: Decodable {
            let online: [String]
            let data: [String: Report]
        }

        struct Report: Decodable {
            struct CPU: Decodable { let usage: Double }
            struct Amount: Decodable {
                let total: UInt64
                let used: UInt64
            }
            struct Network: Decodable {
                let up: Double
                let down: Double
            }
            struct Load: Decodable {
                let load1: Double
                let load5: Double
                let load15: Double
            }

            let cpu: CPU
            let ram: Amount
            let disk: Amount
            let network: Network
            let load: Load
            let uptime: UInt64
            let process: Int
        }
    }

    public static func parseRealtime(_ data: Data) throws -> (online: Set<String>, reports: [String: KomariRealtimeReport]) {
        let response = try JSONDecoder().decode(RealtimeResponse.self, from: data)
        guard response.status == "success" else { throw KomariError.apiError(response.status) }
        let reports = response.data.data.mapValues { report in
            KomariRealtimeReport(
                cpuUsagePercent: report.cpu.usage,
                ramUsed: report.ram.used,
                ramTotal: report.ram.total,
                diskUsed: report.disk.used,
                diskTotal: report.disk.total,
                netUpBytesPerSec: report.network.up,
                netDownBytesPerSec: report.network.down,
                load1: report.load.load1,
                load5: report.load.load5,
                load15: report.load.load15,
                uptimeSeconds: report.uptime,
                processCount: report.process
            )
        }
        return (Set(response.data.online), reports)
    }
}

/// Minimal client for a public Komari Monitor instance (no auth).
public final class KomariClient: @unchecked Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public convenience init?(baseURLString: String) {
        guard let url = URL(string: baseURLString), url.host != nil else { return nil }
        self.init(baseURL: url)
    }

    public func fetchNodes() async throws -> [KomariNodeInfo] {
        let url = baseURL.appendingPathComponent("api/nodes")
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw KomariError.invalidResponse }
        guard http.statusCode == 200 else { throw KomariError.httpStatus(http.statusCode) }
        return try KomariParser.parseNodes(data)
    }

    /// Connects to `/api/clients`, sends `get`, decodes one realtime frame, disconnects.
    public func fetchRealtime() async throws -> (online: Set<String>, reports: [String: KomariRealtimeReport]) {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/clients"), resolvingAgainstBaseURL: false)
        if components?.scheme == "https" { components?.scheme = "wss" }
        if components?.scheme == "http" { components?.scheme = "ws" }
        guard let wsURL = components?.url else { throw KomariError.invalidBaseURL(baseURL.absoluteString) }

        var request = URLRequest(url: wsURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // Komari instances behind origin checks (and Cloudflare) reject WS upgrades without a matching Origin.
        if let scheme = baseURL.scheme, let host = baseURL.host {
            var origin = "\(scheme)://\(host)"
            if let port = baseURL.port { origin += ":\(port)" }
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }

        let task = session.webSocketTask(with: request)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        try await task.send(.string("get"))
        let message = try await withTimeout(seconds: 10) {
            try await task.receive()
        }
        guard case .string(let text) = message, let data = text.data(using: .utf8) else {
            throw KomariError.invalidResponse
        }
        return try KomariParser.parseRealtime(data)
    }

    /// Nodes + realtime merged into display-ready status, ordered like `/api/nodes`.
    public func fetchStatus() async throws -> [KomariNodeStatus] {
        async let nodesTask = fetchNodes()
        async let realtimeTask = fetchRealtime()
        let (nodes, realtime) = try await (nodesTask, realtimeTask)
        return nodes.map { node in
            KomariNodeStatus(
                info: node,
                isOnline: realtime.online.contains(node.uuid),
                report: realtime.reports[node.uuid]
            )
        }
    }
}

func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw KomariError.timeout
        }
        guard let result = try await group.next() else { throw KomariError.timeout }
        group.cancelAll()
        return result
    }
}
