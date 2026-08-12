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
    @Published var menuBarTitle: String = "No servers"
    @Published var showSettings = false
    @Published var isRefreshing = false
    @Published var pollIntervalSeconds: Double = 15

    private let store: ServerStore
    private let credentials: CredentialStore
    private let aggregator = StatusAggregator()
    private let notifications = NotificationService()
    private let serverList = ServerListBox()
    private var scheduler: PollScheduler?
    private var wakeObserver: NSObjectProtocol?

    init() {
        do {
            store = try ServerStore.defaultStore()
        } catch {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ohmyservers-servers.json")
            store = try! ServerStore(fileURL: url)
        }
        credentials = CredentialStore()
        servers = store.list()
        serverList.set(servers)
        pollIntervalSeconds = Self.resolvedPollIntervalSeconds()
        refreshTitle()
        startMonitoring()
        observeWake()
        Task { await notifications.requestAuthorization() }
    }

    func refreshTitle() {
        menuBarTitle = aggregator.menuBarTitle(servers: servers, snapshots: snapshots)
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

    private static func resolvedPollIntervalSeconds() -> Double {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "pollIntervalSeconds") != nil else { return 15 }
        let value = defaults.double(forKey: "pollIntervalSeconds")
        guard value.isFinite, value > 0 else { return 15 }
        return value
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
