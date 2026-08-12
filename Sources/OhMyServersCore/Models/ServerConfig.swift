import Foundation

public enum AuthMethod: String, Codable, Sendable, CaseIterable {
    case password
    case privateKey
}

public struct ServerConfig: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: UInt16
    public var username: String
    public var label: String
    public var authMethod: AuthMethod
    public var privateKeyPath: String?
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: UInt16 = 22,
        username: String,
        label: String,
        authMethod: AuthMethod,
        privateKeyPath: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.label = label
        self.authMethod = authMethod
        self.privateKeyPath = privateKeyPath
        self.isEnabled = isEnabled
    }
}
