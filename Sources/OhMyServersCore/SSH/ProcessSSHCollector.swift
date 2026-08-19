import Darwin
import Foundation

/// Collects metrics by shelling out to `/usr/bin/ssh` (same stack as the user's
/// working CLI config). Citadel/NIOSSH fails KEX against modern OpenSSH servers.
public final class ProcessSSHCollector: SSHCollecting, @unchecked Sendable {
    public var connectTimeoutSeconds: Int
    public var overallTimeoutSeconds: TimeInterval

    private let lock = NSLock()
    private var previousSamples: [UUID: MetricSample] = [:]

    public init(connectTimeoutSeconds: Int = 10, overallTimeoutSeconds: TimeInterval = 15) {
        self.connectTimeoutSeconds = connectTimeoutSeconds
        self.overallTimeoutSeconds = overallTimeoutSeconds
    }

    static let controlPath = "/tmp/ohmyservers-%C"
    static let serverAliveInterval = 30
    static let serverAliveCountMax = 3
    static let muxExitTimeoutSeconds: TimeInterval = 2
    static let maxSampleAgeSeconds: TimeInterval = 120

    static func isUsableCache(
        _ sample: MetricSample?,
        now: Date = Date(),
        maxAge: TimeInterval = maxSampleAgeSeconds
    ) -> Bool {
        guard let sample else { return false }
        return now.timeIntervalSince(sample.sampledAt) <= maxAge
    }

    static func remoteCommand(hasCache: Bool) -> String {
        hasCache ? RemoteMetricScripts.collectCommand : RemoteMetricScripts.collectCommandInitial
    }

    public func collect(from server: ServerConfig, credential: SSHCredential) async -> MetricsSnapshot {
        do {
            let cached = cachedSample(for: server.id)
            let hasUsableCache = Self.isUsableCache(cached)
            let output = try await runSSH(
                server: server,
                credential: credential,
                command: Self.remoteCommand(hasCache: hasUsableCache)
            )
            if hasUsableCache, let cached {
                guard let current = RemoteMetricScripts.parseSections(output) else {
                    return parseFailure(serverID: server.id)
                }
                storeSample(current, for: server.id)
                return MetricsParser.parse(serverID: server.id, current: current, previous: cached)
            } else {
                guard let (sample1, sample2) = RemoteMetricScripts.parseInitialSections(output) else {
                    return parseFailure(serverID: server.id)
                }
                storeSample(sample2, for: server.id)
                return MetricsParser.parse(
                    serverID: server.id,
                    current: sample2,
                    previous: sample1,
                    intervalSeconds: 1
                )
            }
        } catch {
            return .unreachable(
                serverID: server.id,
                message: SSHErrorLocalizer.message(from: error.localizedDescription)
            )
        }
    }

    private func parseFailure(serverID: UUID) -> MetricsSnapshot {
        clearSample(for: serverID)
        return .unreachable(
            serverID: serverID,
            message: SSHErrorLocalizer.message(from: "无法解析远端指标")
        )
    }

    func cachedSample(for serverID: UUID) -> MetricSample? {
        lock.lock()
        defer { lock.unlock() }
        return previousSamples[serverID]
    }

    func storeSample(_ sample: MetricSample, for serverID: UUID) {
        lock.lock()
        previousSamples[serverID] = sample
        lock.unlock()
    }

    func clearSample(for serverID: UUID) {
        lock.lock()
        previousSamples[serverID] = nil
        lock.unlock()
    }

    private func runSSH(server: ServerConfig, credential: SSHCredential, command: String) async throws -> String {
        var lastError: Error?
        for attempt in 0..<2 {
            let started = Date()
            do {
                return try await runSSHOnce(server: server, credential: credential, command: command)
            } catch {
                lastError = error
                Self.exitMux(server: server)
                let elapsed = Date().timeIntervalSince(started)
                if attempt == 0, SSHRetryPolicy.shouldRetry(
                    elapsed: elapsed,
                    message: error.localizedDescription
                ) {
                    continue
                }
                throw error
            }
        }
        throw lastError ?? ProcessSSHError.failed("连接超时")
    }

    private func runSSHOnce(
        server: ServerConfig,
        credential: SSHCredential,
        command: String
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try Self.execute(
                        server: server,
                        credential: credential,
                        command: command,
                        connectTimeout: self.connectTimeoutSeconds,
                        overallTimeout: self.overallTimeoutSeconds
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func execute(
        server: ServerConfig,
        credential: SSHCredential,
        command: String,
        connectTimeout: Int,
        overallTimeout: TimeInterval
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

        var args: [String] = [
            "-o", "ConnectTimeout=\(connectTimeout)",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "LogLevel=ERROR",
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(controlPath)",
            "-o", "ControlPersist=120",
            "-o", "ServerAliveInterval=\(serverAliveInterval)",
            "-o", "ServerAliveCountMax=\(serverAliveCountMax)",
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

        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in
            group.leave()
        }

        do {
            try process.run()
        } catch {
            group.leave()
            throw error
        }
        if let data = command.data(using: .utf8) {
            stdin.fileHandleForWriting.write(data)
        }
        try? stdin.fileHandleForWriting.close()

        let waitResult = group.wait(timeout: .now() + overallTimeout)
        if waitResult == .timedOut {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            throw ProcessSSHError.failed("连接超时")
        }

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

    static func exitMux(server: ServerConfig) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-O", "exit",
            "-o", "ControlPath=\(controlPath)",
            "-o", "ConnectTimeout=2",
            "-p", String(server.port),
            "\(server.username)@\(server.host)"
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in
            group.leave()
        }
        do {
            try process.run()
        } catch {
            group.leave()
            return
        }
        if group.wait(timeout: .now() + muxExitTimeoutSeconds) == .timedOut {
            process.terminate()
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
        }
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
