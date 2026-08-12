import Citadel
import Crypto
import Foundation
import NIO

public struct CitadelSSHCollector: SSHCollecting {
    public var connectTimeoutSeconds: Int64

    public init(connectTimeoutSeconds: Int64 = 10) {
        self.connectTimeoutSeconds = connectTimeoutSeconds
    }

    public func collect(from server: ServerConfig, credential: SSHCredential) async -> MetricsSnapshot {
        do {
            return try await withTimeout(seconds: connectTimeoutSeconds + 15) {
                try await self.collectThrowing(from: server, credential: credential)
            }
        } catch {
            return .unreachable(serverID: server.id, message: error.localizedDescription)
        }
    }

    private func collectThrowing(from server: ServerConfig, credential: SSHCredential) async throws -> MetricsSnapshot {
        let auth = try Self.authenticationMethod(username: server.username, credential: credential)
        let client = try await SSHClient.connect(
            host: server.host,
            port: Int(server.port),
            authenticationMethod: auth,
            hostKeyValidator: .acceptAnything(),
            reconnect: .never,
            algorithms: .all,
            connectTimeout: .seconds(connectTimeoutSeconds)
        )
        defer { Task { try? await client.close() } }

        let buffer = try await client.executeCommand(
            RemoteMetricScripts.collectCommand,
            maxResponseSize: 512 * 1024,
            mergeStreams: true
        )
        let output = String(buffer: buffer)
        guard let raw = RemoteMetricScripts.parseSections(output) else {
            return .unreachable(serverID: server.id, message: "Failed to parse remote metrics")
        }
        return MetricsParser.parse(serverID: server.id, raw: raw)
    }

    static func authenticationMethod(username: String, credential: SSHCredential) throws -> SSHAuthenticationMethod {
        switch credential {
        case .password(let password):
            return .passwordBased(username: username, password: password)
        case .privateKey(let path, let passphrase):
            let keyString = try String(contentsOfFile: path, encoding: .utf8)
            let decryption = passphrase.flatMap { $0.data(using: .utf8) }
            let keyType = try SSHKeyDetection.detectPrivateKeyType(from: keyString)
            switch keyType {
            case .ed25519:
                let key = try Curve25519.Signing.PrivateKey(sshEd25519: keyString, decryptionKey: decryption)
                return .ed25519(username: username, privateKey: key)
            case .rsa:
                let key = try Insecure.RSA.PrivateKey(sshRsa: keyString, decryptionKey: decryption)
                return .rsa(username: username, privateKey: key)
            default:
                throw CollectorError.unsupportedKeyType(
                    "\(keyType.description) (supported: Ed25519, RSA)"
                )
            }
        }
    }
}

public enum CollectorError: Error, LocalizedError {
    case unsupportedKeyType(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .unsupportedKeyType(let t): return "Unsupported SSH key type: \(t)"
        case .timeout: return "SSH collection timed out"
        }
    }
}

private func withTimeout<T: Sendable>(
    seconds: Int64,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            throw CollectorError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
