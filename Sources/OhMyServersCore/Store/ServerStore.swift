import Foundation

public final class ServerStore: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "app.ohmyservers.serverstore")
    private var servers: [ServerConfig]

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            self.servers = try JSONDecoder().decode([ServerConfig].self, from: data)
        } else {
            self.servers = []
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try persistLocked()
        }
    }

    public static func defaultStore() throws -> ServerStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("OhMyServers", isDirectory: true)
        return try ServerStore(fileURL: dir.appendingPathComponent("servers.json"))
    }

    public func list() -> [ServerConfig] {
        queue.sync { servers }
    }

    public func upsert(_ server: ServerConfig) throws {
        try queue.sync {
            if let idx = servers.firstIndex(where: { $0.id == server.id }) {
                servers[idx] = server
            } else {
                servers.append(server)
            }
            try persistLocked()
        }
    }

    public func delete(id: UUID) throws {
        try queue.sync {
            servers.removeAll { $0.id == id }
            try persistLocked()
        }
    }

    private func persistLocked() throws {
        let data = try JSONEncoder().encode(servers)
        let tmp = fileURL.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.moveItem(at: tmp, to: fileURL)
    }
}
