import Foundation

public actor PollScheduler {
    public var intervalNanoseconds: UInt64
    private let collector: any SSHCollecting
    private let credentialProvider: @Sendable (ServerConfig) -> SSHCredential?
    private var task: Task<Void, Never>?
    private var latest: [UUID: MetricsSnapshot] = [:]
    private var previous: [UUID: MetricsSnapshot] = [:]
    private var onUpdate: (@Sendable ([UUID: MetricsSnapshot], [AlertEvent]) -> Void)?
    private var onRefreshing: (@Sendable (Bool) -> Void)?
    private var isPolling = false

    public init(
        collector: any SSHCollecting,
        intervalSeconds: Double = 15,
        credentialProvider: @escaping @Sendable (ServerConfig) -> SSHCredential?
    ) {
        self.collector = collector
        self.intervalNanoseconds = Self.nanoseconds(forIntervalSeconds: intervalSeconds)
        self.credentialProvider = credentialProvider
    }

    public func setIntervalSeconds(_ seconds: Double) {
        intervalNanoseconds = Self.nanoseconds(forIntervalSeconds: seconds)
    }

    public func start(
        serversProvider: @escaping @Sendable () -> [ServerConfig],
        onUpdate: @escaping @Sendable ([UUID: MetricsSnapshot], [AlertEvent]) -> Void,
        onRefreshing: (@Sendable (Bool) -> Void)? = nil
    ) {
        stop()
        self.onUpdate = onUpdate
        self.onRefreshing = onRefreshing
        task = Task {
            while !Task.isCancelled {
                let started = ContinuousClock.now
                let servers = serversProvider()
                await self.pollOnce(servers: servers)
                let elapsed = ContinuousClock.now - started
                let interval = Duration.nanoseconds(Int64(clamping: self.intervalNanoseconds))
                let remaining = interval - elapsed
                if remaining > .zero {
                    try? await Task.sleep(for: remaining)
                }
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    public func refresh(servers: [ServerConfig]) async {
        await pollOnce(servers: servers)
    }

    public func currentSnapshots() -> [UUID: MetricsSnapshot] {
        latest
    }

    func pollOnce(servers: [ServerConfig]) async {
        if isPolling { return }
        isPolling = true
        onRefreshing?(true)
        defer {
            isPolling = false
            onRefreshing?(false)
        }

        let enabled = servers.filter(\.isEnabled)
        var next: [UUID: MetricsSnapshot] = [:]

        await withTaskGroup(of: MetricsSnapshot.self) { group in
            for server in enabled {
                group.addTask {
                    guard let credential = self.credentialProvider(server) else {
                        return .unreachable(serverID: server.id, message: "缺少登录凭据")
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

    private static func nanoseconds(forIntervalSeconds seconds: Double) -> UInt64 {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        let nanos = seconds * 1_000_000_000
        guard nanos < Double(UInt64.max) else { return UInt64.max }
        return UInt64(nanos)
    }
}
