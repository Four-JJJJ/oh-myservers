import Foundation

/// Collects metrics by shelling out to `/usr/bin/ssh` (same stack as the user's
/// working CLI config). Citadel/NIOSSH fails KEX against modern OpenSSH servers.
public struct ProcessSSHCollector: SSHCollecting {
    public var connectTimeoutSeconds: Int

    public init(connectTimeoutSeconds: Int = 10) {
        self.connectTimeoutSeconds = connectTimeoutSeconds
    }

    public func collect(from server: ServerConfig, credential: SSHCredential) async -> MetricsSnapshot {
        do {
            let output = try await runSSH(server: server, credential: credential)
            guard let raw = RemoteMetricScripts.parseSections(output) else {
                return .unreachable(serverID: server.id, message: "Failed to parse remote metrics")
            }
            return MetricsParser.parse(serverID: server.id, raw: raw)
        } catch {
            return .unreachable(serverID: server.id, message: error.localizedDescription)
        }
    }

    private func runSSH(server: ServerConfig, credential: SSHCredential) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try Self.execute(server: server, credential: credential, timeout: self.connectTimeoutSeconds)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func execute(server: ServerConfig, credential: SSHCredential, timeout: Int) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

        var args: [String] = [
            "-o", "ConnectTimeout=\(timeout)",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "LogLevel=ERROR",
            "-p", String(server.port)
        ]

        var environment = ProcessInfo.processInfo.environment
        var askpassURL: URL?

        switch credential {
        case .password(let password):
            args += [
                "-o", "PreferredAuthentications=password",
                "-o", "PubkeyAuthentication=no",
                "-o", "NumberOfPasswordPrompts=1"
            ]
            askpassURL = try writeAskpass(password: password)
            environment["SSH_ASKPASS"] = askpassURL!.path
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment["DISPLAY"] = environment["DISPLAY"] ?? ":0"
        case .privateKey(let path, _):
            args += [
                "-i", path,
                "-o", "IdentitiesOnly=yes",
                "-o", "BatchMode=yes",
                "-o", "PreferredAuthentications=publickey"
            ]
        }

        args += ["\(server.username)@\(server.host)", "bash", "-s"]
        process.arguments = args
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin

        defer {
            if let askpassURL {
                try? FileManager.default.removeItem(at: askpassURL)
            }
        }

        try process.run()
        if let data = RemoteMetricScripts.collectCommand.data(using: .utf8) {
            stdin.fileHandleForWriting.write(data)
        }
        try? stdin.fileHandleForWriting.close()

        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let message = err.isEmpty ? "ssh exited \(process.terminationStatus)" : err
            throw ProcessSSHError.failed(message)
        }
        return out
    }

    private static func writeAskpass(password: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohmyservers-askpass-\(UUID().uuidString).sh")
        // Avoid interpolating password into a form that breaks on quotes: write binary echo via printf %s
        let script = """
        #!/bin/sh
        printf '%s\\n' \(shellSingleQuoted(password))
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum ProcessSSHError: Error, LocalizedError {
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}
