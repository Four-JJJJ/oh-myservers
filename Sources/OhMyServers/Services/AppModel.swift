import AppKit
import Foundation
import OhMyServersCore

@MainActor
final class AppModel: ObservableObject {
    @Published var sites: [KomariSite] = []
    /// Realtime status of every node across all enabled sites, for the menu bar summary.
    @Published var nodeStatuses: [KomariNodeStatus] = []
    @Published var menuBarTitle: String = "…"
    @Published var isRefreshing = false
    static let allowedPollIntervals: [Double] = [5, 15, 30, 60]

    @Published var pollIntervalSeconds: Double = 15
    @Published var menuBarSettings: MenuBarDisplaySettings

    private let store: KomariSiteStore
    private let menuBarSettingsStore: MenuBarDisplaySettingsStore
    private let aggregator = StatusAggregator()
    private var pollTasks: [UUID: Task<Void, Never>] = [:]
    private var wakeObserver: NSObjectProtocol?

    init(
        store: KomariSiteStore = KomariSiteStore(),
        menuBarSettingsStore: MenuBarDisplaySettingsStore = MenuBarDisplaySettingsStore()
    ) {
        self.store = store
        self.menuBarSettingsStore = menuBarSettingsStore
        sites = store.list()
        pollIntervalSeconds = Self.resolvedPollIntervalSeconds()
        menuBarSettings = menuBarSettingsStore.load()
        restartPolling()
        observeWake()
    }

    var enabledSites: [KomariSite] {
        sites.filter(\.isEnabled)
    }

    // MARK: - Site CRUD

    @discardableResult
    func addSite(name: String, urlString: String) throws -> KomariSite {
        guard let normalized = Self.normalizedURLString(urlString) else {
            throw KomariError.invalidBaseURL(urlString)
        }
        let site = KomariSite(name: name.trimmingCharacters(in: .whitespaces), urlString: normalized)
        store.upsert(site)
        reloadSites()
        return site
    }

    func updateSite(_ site: KomariSite) throws {
        guard site.url != nil else { throw KomariError.invalidBaseURL(site.urlString) }
        store.upsert(site)
        reloadSites()
    }

    func deleteSite(id: UUID) {
        store.delete(id: id)
        reloadSites()
        KomariWebStore.shared.remove(siteID: id)
    }

    private func reloadSites() {
        sites = store.list()
        restartPolling()
        KomariWebStore.shared.preload(sites: enabledSites)
        refreshTitle()
    }

    // MARK: - Polling

    private func restartPolling() {
        for (_, task) in pollTasks { task.cancel() }
        pollTasks.removeAll()
        perSiteStatuses.removeAll()
        nodeStatuses = []

        for site in enabledSites {
            guard let url = site.url else { continue }
            let client = KomariClient(baseURL: url)
            pollTasks[site.id] = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.pollSite(siteID: site.id, client: client)
                    let interval = self?.pollIntervalSeconds ?? 15
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                }
            }
        }
        refreshTitle()
    }

    private var perSiteStatuses: [UUID: [KomariNodeStatus]] = [:]

    private func pollSite(siteID: UUID, client: KomariClient) async {
        isRefreshing = true
        defer { isRefreshing = false }
        guard let status = try? await client.fetchStatus() else { return }
        perSiteStatuses[siteID] = status
        nodeStatuses = perSiteStatuses.values.flatMap { $0 }
        refreshTitle()
    }

    private func refreshTitle() {
        if !nodeStatuses.isEmpty {
            menuBarTitle = aggregator.menuBarTitle(komariNodes: nodeStatuses, settings: menuBarSettings)
        } else {
            menuBarTitle = enabledSites.isEmpty ? "无站点" : "…"
        }
    }

    // MARK: - Menu bar display settings

    func updateMenuBarSettings(_ settings: MenuBarDisplaySettings) {
        menuBarSettings = settings
        menuBarSettingsStore.save(settings)
        refreshTitle()
    }

    func refreshNow() {
        for site in enabledSites {
            guard let url = site.url else { continue }
            let client = KomariClient(baseURL: url)
            Task { await pollSite(siteID: site.id, client: client) }
        }
    }

    // MARK: - Poll interval

    func updatePollInterval(_ seconds: Double) {
        let value = Self.normalizedPollInterval(seconds)
        pollIntervalSeconds = value
        UserDefaults.standard.set(value, forKey: "pollIntervalSeconds")
    }

    static func resolvedPollIntervalSeconds() -> Double {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "pollIntervalSeconds") != nil else { return 15 }
        return normalizedPollInterval(defaults.double(forKey: "pollIntervalSeconds"))
    }

    static func normalizedPollInterval(_ seconds: Double) -> Double {
        allowedPollIntervals.contains(seconds) ? seconds : 15
    }

    // MARK: - Helpers

    static func normalizedURLString(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Tolerate addresses typed without a scheme.
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), url.host != nil else { return nil }
        return candidate
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
}
