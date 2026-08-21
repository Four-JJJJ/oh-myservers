import Foundation

/// Persists the user's Komari sites in UserDefaults as a JSON array.
/// Migrates the legacy single `komariBaseURL` key on first access.
public final class KomariSiteStore: @unchecked Sendable {
    public static let defaultSiteURL = "https://komari.fourj.ccwu.cc"

    private let defaults: UserDefaults
    private let storageKey = "komariSites"
    private let legacyKey = "komariBaseURL"
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func list() -> [KomariSite] {
        lock.lock(); defer { lock.unlock() }
        if let data = defaults.data(forKey: storageKey),
           let sites = try? JSONDecoder().decode([KomariSite].self, from: data) {
            return sites
        }
        // First run (or pre-migration): seed from the legacy single-URL key.
        let seed = defaults.string(forKey: legacyKey) ?? Self.defaultSiteURL
        let sites = [KomariSite(urlString: seed)]
        saveLocked(sites)
        defaults.removeObject(forKey: legacyKey)
        return sites
    }

    public func upsert(_ site: KomariSite) {
        lock.lock(); defer { lock.unlock() }
        var sites = listLocked()
        if let index = sites.firstIndex(where: { $0.id == site.id }) {
            sites[index] = site
        } else {
            sites.append(site)
        }
        saveLocked(sites)
    }

    public func delete(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        saveLocked(listLocked().filter { $0.id != id })
    }

    // MARK: - Private (call with lock held)

    private func listLocked() -> [KomariSite] {
        guard let data = defaults.data(forKey: storageKey),
              let sites = try? JSONDecoder().decode([KomariSite].self, from: data) else {
            return []
        }
        return sites
    }

    private func saveLocked(_ sites: [KomariSite]) {
        let data = try? JSONEncoder().encode(sites)
        defaults.set(data, forKey: storageKey)
    }
}
