import XCTest
@testable import OhMyServersCore

final class ModelSmokeTests: XCTestCase {
    func testServerConfigCodableRoundTrip() throws {
        let s = ServerConfig(
            id: UUID(),
            name: "Hong Kong",
            host: "hk.example.com",
            port: 22,
            username: "ubuntu",
            label: "HK",
            authMethod: .password,
            privateKeyPath: nil,
            isEnabled: true
        )
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: data)
        XCTAssertEqual(decoded.host, "hk.example.com")
        XCTAssertEqual(decoded.label, "HK")
        XCTAssertEqual(decoded.authMethod, .password)
    }

    func testHealthOfflineWhenUnreachable() {
        let snap = MetricsSnapshot.unreachable(serverID: UUID(), message: "timeout")
        XCTAssertEqual(snap.health, .offline)
    }

    func testHealthHighWhenCPUElevated() {
        let snap = MetricsSnapshot(
            serverID: UUID(),
            isReachable: true,
            cpuPercent: 90
        )
        XCTAssertEqual(snap.health, .high)
    }
}
