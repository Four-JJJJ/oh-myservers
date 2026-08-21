import Foundation

/// Metrics the user can show in the menu bar, in stable display order.
public enum MenuBarMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory
    case load
    case disk
    case networkUp
    case networkDown
    case uptime
    case process

    public var id: String { rawValue }
}

/// Which metrics and which nodes appear in the menu bar title.
/// `selectedNodeUUIDs == nil` means "show every node".
public struct MenuBarDisplaySettings: Codable, Equatable, Sendable {
    public var metrics: [MenuBarMetric]
    public var selectedNodeUUIDs: Set<String>?

    public init(metrics: [MenuBarMetric] = [.cpu], selectedNodeUUIDs: Set<String>? = nil) {
        self.metrics = metrics
        self.selectedNodeUUIDs = selectedNodeUUIDs
    }

    public static let `default` = MenuBarDisplaySettings()
}

/// Persists menu bar display preferences in UserDefaults as JSON.
public final class MenuBarDisplaySettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let storageKey = "menuBarDisplaySettings"
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> MenuBarDisplaySettings {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(MenuBarDisplaySettings.self, from: data) else {
            return .default
        }
        return settings
    }

    public func save(_ settings: MenuBarDisplaySettings) {
        lock.lock(); defer { lock.unlock() }
        let data = try? JSONEncoder().encode(settings)
        defaults.set(data, forKey: storageKey)
    }
}
