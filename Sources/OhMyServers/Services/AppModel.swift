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

    private let store: ServerStore
    private let credentials: CredentialStore
    private let aggregator = StatusAggregator()
    private let notifications = NotificationService()
    private let serverList = ServerListBox()
    private var scheduler: PollScheduler?

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
        refreshTitle()
        startMonitoring()
        Task { await notifications.requestAuthorization() }
    }

    func refreshTitle() {
        menuBarTitle = aggregator.menuBarTitle(servers: servers, snapshots: snapshots)
    }

    func startMonitoring() {
        let credentials = self.credentials
        let serverList = self.serverList
        let scheduler = PollScheduler(
            collector: CitadelSSHCollector(),
            intervalSeconds: 15
        ) { server in
            Self.credential(for: server, credentials: credentials)
        }
        self.scheduler = scheduler
        Task {
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
                }
            )
        }
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
