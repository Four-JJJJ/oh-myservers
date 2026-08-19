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

    private func komariNode(name: String, online: Bool, cpu: Double?) -> KomariNodeStatus {
        KomariNodeStatus(
            info: KomariNodeInfo(uuid: name, name: name, region: "", os: "", cpuCores: 1, memTotal: 1, diskTotal: 1),
            isOnline: online,
            report: cpu.map {
                KomariRealtimeReport(
                    cpuUsagePercent: $0, ramUsed: 0, ramTotal: 1, diskUsed: 0, diskTotal: 1,
                    netUpBytesPerSec: 0, netDownBytesPerSec: 0,
                    load1: 0, load5: 0, load15: 0, uptimeSeconds: 0, processCount: 0
                )
            }
        )
    }

    func testKomariMenuBarTitle() {
        let nodes = [komariNode(name: "HK", online: true, cpu: 7.5), komariNode(name: "US", online: true, cpu: 0.9)]
        XCTAssertEqual(StatusAggregator().menuBarTitle(komariNodes: nodes), "HK 8% · US 1%")
    }

    func testKomariMenuBarTitleOffline() {
        let nodes = [komariNode(name: "HK", online: true, cpu: 7.5), komariNode(name: "US", online: false, cpu: nil)]
        XCTAssertEqual(StatusAggregator().menuBarTitle(komariNodes: nodes), "HK 8% · US —")
    }

    func testKomariMenuBarTitleEmpty() {
        XCTAssertEqual(StatusAggregator().menuBarTitle(komariNodes: []), "无服务器")
    }
}
