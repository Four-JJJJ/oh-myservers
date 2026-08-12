import Foundation

public actor PollScheduler {
    public var intervalNanoseconds: UInt64
    private let collector: any SSHCollecting
    private let credentialProvider: @Sendable (ServerConfig) -> SSHCredential?
    private var task: Task<Void, Never>?
    private var latest: [UUID: MetricsSnapshot] = [:]
    private var previous: [UUID: MetricsSnapshot] = [:]
    private var onUpdate: (@Sendable ([UUID: MetricsSnapshot], [AlertEvent]) -> Void)?

    public init(
        collector: any SSHCollecting,
        intervalSeconds: Double = 15,
        credentialProvider: @escaping @Sendable (ServerConfig) -> SSHCredential?
    ) {
        self.collector = collector
        self.intervalNanoseconds = UInt64(intervalSeconds * 1_000_000_000)
        self.credentialProvider = credentialProvider
    }

    public func start(
        serversProvider: @escaping @Sendable () -> [ServerConfig],
        onUpdate: @escaping @Sendable ([UUID: MetricsSnapshot], [AlertEvent]) -> Void
    ) {
        stop()
        self.onUpdate = onUpdate
        task = Task {
            while !Task.isCancelled {
                let servers = serversProvider()
                await self.pollOnce(servers: servers)
                try? await Task.sleep(nanoseconds: self.intervalNanoseconds)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    public func currentSnapshots() -> [UUID: MetricsSnapshot] {
        latest
    }

    func pollOnce(servers: [ServerConfig]) async {
        let enabled = servers.filter(\.isEnabled)
        var next: [UUID: MetricsSnapshot] = [:]

        await withTaskGroup(of: MetricsSnapshot.self) { group in
            for server in enabled {
                group.addTask {
                    guard let credential = self.credentialProvider(server) else {
                        return .unreachable(serverID: server.id, message: "Missing credentials")
                    }
                    return await self.collector.collect(from: server, credential: credential)
                }
            }
            for await snap in group {
                next[snap.serverID] = snap
            }
        }

        let prev = previous.isEmpty ? latest : previous
        previous = latest
        latest = next

        let events = AlertEvaluator().evaluate(servers: enabled, previous: prev, current: next)
        onUpdate?(next, events)
    }
}
