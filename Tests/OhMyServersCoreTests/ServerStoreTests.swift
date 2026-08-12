import XCTest
@testable import OhMyServersCore

final class ServerStoreTests: XCTestCase {
    func testUpsertAndReload() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("servers.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try ServerStore(fileURL: url)
        let server = ServerConfig(
            name: "HK",
            host: "hk.example.com",
            username: "ubuntu",
            label: "HK",
            authMethod: .privateKey,
            privateKeyPath: "/tmp/id_rsa"
        )
        try store.upsert(server)
        XCTAssertEqual(store.list().count, 1)

        let reloaded = try ServerStore(fileURL: url)
        XCTAssertEqual(reloaded.list().first?.host, "hk.example.com")
        XCTAssertEqual(reloaded.list().first?.authMethod, .privateKey)

        try reloaded.delete(id: server.id)
        XCTAssertTrue(reloaded.list().isEmpty)
    }
}
