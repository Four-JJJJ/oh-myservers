import AppKit
import Foundation
import OhMyServersCore
import Combine

/// Thread-safe snapshot of server list for the poller.
final class ServerListBox: @unchecked Sendable {
    private let lock = NSLock()
    private var servers: [ServerConfig] = []

    func get() -> [ServerConfig] {
        lock.lock(); defer { lock.unlock() }
        return servers
    }

    func set(_ value: [ServerConfig]) {
        lock.lock(); defer { lock.unlock() }
        servers = value
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var servers: [ServerConfig] = []
    @Published var snapshots: [UUID: MetricsSnapshot] = [:]
    @Published var komariNodes: [KomariNodeStatus] = []
    @Published var menuBarTitle: String = "No servers"
    @Published var showSettings = false
    @Published var isRefreshing = false
    static let allowedPollIntervals: [Double] = [5, 15, 30, 60]

    @Published var pollIntervalSeconds: Double = 15

    private let store: ServerStore
    private let credentials: CredentialStore
    private let aggregator = StatusAggregator()
    private let notifications = NotificationService()
    private let serverList = ServerListBox()
    private var scheduler: PollScheduler?
    private var wakeObserver: NSObjectProtocol?
    private let komariClient: KomariClient?
    private var komariTask: Task<Void, Never>?

    init() {
        do {
            store = try ServerStore.defaultStore()
        } catch {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ohmyservers-servers.json")
            store = try! ServerStore(fileURL: url)
        }
        credentials = CredentialStore()
        komariClient = KomariClient(baseURLString: Self.komariBaseURLString())
        servers = store.list()
        serverList.set(servers)
        pollIntervalSeconds = Self.resolvedPollIntervalSeconds()
        refreshTitle()
        startMonitoring()
        startKomariPolling()
        observeWake()
        Task { await notifications.requestAuthorization() }
    }

    static func komariBaseURLString() -> String {
        UserDefaults.standard.string(forKey: "komariBaseURL") ?? "https://komari.fourj.ccwu.cc"
    }

    func refreshTitle() {
        if servers.contains(where: \.isEnabled) {
            menuBarTitle = aggregator.menuBarTitle(servers: servers, snapshots: snapshots)
        } else if !komariNodes.isEmpty {
            menuBarTitle = aggregator.menuBarTitle(komariNodes: komariNodes)
        } else {
            menuBarTitle = komariClient != nil ? "…" : "无服务器"
        }
    }

    private func startKomariPolling() {
        guard let client = komariClient else { return }
        komariTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollKomari(client: client)
                let interval = self?.pollIntervalSeconds ?? 15
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func pollKomari(client: KomariClient) async {
        guard let status = try? await client.fetchStatus() else { return }
        komariNodes = status
        refreshTitle()
    }

    func startMonitoring() {
        let credentials = self.credentials
        let serverList = self.serverList
        let existing = scheduler
        let scheduler = PollScheduler(
            collector: ProcessSSHCollector(),
            intervalSeconds: pollIntervalSeconds
        ) { server in
            Self.credential(for: server, credentials: credentials)
        }
        self.scheduler = scheduler
        Task {
            await existing?.stop()
            await scheduler.start(
                serversProvider: { serverList.get() },
                onUpdate: { [weak self] snaps, events in
                    Task { @MainActor in
                        guard let self else { return }
                        self.snapshots = snaps
                        self.refreshTitle()
                        for event in events {
                            self.notifications.post(title: event.title, body: event.body)
                        }
                    }
                },
                onRefreshing: { [weak self] refreshing in
                    Task { @MainActor in
                        self?.isRefreshing = refreshing
                    }
                }
            )
        }
    }

    func refreshNow() {
        let servers = serverList.get()
        Task {
            await scheduler?.refresh(servers: servers)
        }
        if let komariClient {
            Task { await pollKomari(client: komariClient) }
        }
    }

    func openInTerminal(server: ServerConfig) {
        let command = Self.sshInvocation(for: server)
        let source = """
        tell application "Terminal"
            activate
            do script \(Self.appleScriptQuoted(command))
        end tell
        """
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return }
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            NSLog("OhMyServers: openInTerminal failed: \(errorInfo)")
        }
    }

    static func sshInvocation(for server: ServerConfig) -> String {
        var parts: [String] = ["ssh"]
        if server.port != 22 {
            parts.append("-p")
            parts.append(String(server.port))
        }
        if server.authMethod == .privateKey,
           let path = server.privateKeyPath,
           !path.isEmpty {
            parts.append("-i")
            parts.append(posixSingleQuoted(path))
        }
        parts.append(posixSingleQuoted("\(server.username)@\(server.host)"))
        return parts.joined(separator: " ")
    }

    private static func posixSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
        }
    }

    func updatePollInterval(_ seconds: Double) {
        let value = Self.normalizedPollInterval(seconds)
        pollIntervalSeconds = value
        UserDefaults.standard.set(value, forKey: "pollIntervalSeconds")
        Task { await scheduler?.setIntervalSeconds(value) }
    }

    static func resolvedPollIntervalSeconds() -> Double {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "pollIntervalSeconds") != nil else { return 15 }
        return normalizedPollInterval(defaults.double(forKey: "pollIntervalSeconds"))
    }

    static func normalizedPollInterval(_ seconds: Double) -> Double {
        allowedPollIntervals.contains(seconds) ? seconds : 15
    }

    func reloadServersFromDisk() {
        servers = store.list()
        serverList.set(servers)
        refreshTitle()
    }

    func save(server: ServerConfig, password: String?, keyPassphrase: String?) throws {
        try store.upsert(server)
        if server.authMethod == .password, let password, !password.isEmpty {
            try credentials.save(serverID: server.id, kind: .password, secret: password)
        }
        if server.authMethod == .privateKey, let keyPassphrase, !keyPassphrase.isEmpty {
            try credentials.save(serverID: server.id, kind: .keyPassphrase, secret: keyPassphrase)
        }
        reloadServersFromDisk()
    }

    func delete(serverID: UUID) throws {
        try store.delete(id: serverID)
        try credentials.deleteAll(for: serverID)
        snapshots.removeValue(forKey: serverID)
        reloadServersFromDisk()
    }

    nonisolated private static func credential(for server: ServerConfig, credentials: CredentialStore) -> SSHCredential? {
        switch server.authMethod {
        case .password:
            guard let password = try? credentials.load(serverID: server.id, kind: .password),
                  !password.isEmpty else { return nil }
            return .password(password)
        case .privateKey:
            guard let path = server.privateKeyPath, !path.isEmpty else { return nil }
            let phrase = try? credentials.load(serverID: server.id, kind: .keyPassphrase)
            return .privateKey(path: path, passphrase: phrase)
        }
    }
}
