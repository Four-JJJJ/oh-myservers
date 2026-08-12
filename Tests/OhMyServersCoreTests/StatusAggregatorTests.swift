import XCTest
@testable import OhMyServersCore

final class StatusAggregatorTests: XCTestCase {
    func testMenuBarTitleWithCPU() {
        let hk = ServerConfig(name: "Hong Kong", host: "hk", username: "u", label: "HK", authMethod: .password)
        let us = ServerConfig(name: "US", host: "us", username: "u", label: "US", authMethod: .password)
        let snaps: [UUID: MetricsSnapshot] = [
            hk.id: MetricsSnapshot(serverID: hk.id, isReachable: true, cpuPercent: 23.4),
            us.id: MetricsSnapshot(serverID: us.id, isReachable: true, cpuPercent: 41.2)
        ]
        let title = StatusAggregator().menuBarTitle(servers: [hk, us], snapshots: snaps)
        XCTAssertEqual(title, "HK 23% · US 41%")
    }

    func testMenuBarTitleOfflineDash() {
        let hk = ServerConfig(name: "Hong Kong", host: "hk", username: "u", label: "HK", authMethod: .password)
        let snaps: [UUID: MetricsSnapshot] = [
            hk.id: .unreachable(serverID: hk.id, message: "timeout")
        ]
        let title = StatusAggregator().menuBarTitle(servers: [hk], snapshots: snaps)
        XCTAssertEqual(title, "HK —")
    }

    func testEmptyServers() {
        XCTAssertEqual(StatusAggregator().menuBarTitle(servers: [], snapshots: [:]), "无服务器")
    }
}
