import Foundation

public enum SSHCredential: Sendable, Equatable {
    case password(String)
    case privateKey(path: String, passphrase: String?)
}

public protocol SSHCollecting: Sendable {
    func collect(from server: ServerConfig, credential: SSHCredential) async -> MetricsSnapshot
}
