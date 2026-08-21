import Foundation

/// A Komari Monitor instance the user added by address.
public struct KomariSite: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    /// Display name; empty falls back to the URL host.
    public var name: String
    public var urlString: String
    public var isEnabled: Bool

    public init(id: UUID = UUID(), name: String = "", urlString: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.isEnabled = isEnabled
    }

    public var url: URL? {
        guard let url = URL(string: urlString), url.host != nil else { return nil }
        return url
    }

    /// Name for section headers: configured name, or the host as a fallback.
    public var displayName: String {
        if !name.isEmpty { return name }
        return url?.host ?? urlString
    }
}
