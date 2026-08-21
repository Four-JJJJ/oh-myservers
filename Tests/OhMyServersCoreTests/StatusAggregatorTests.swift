import XCTest
@testable import OhMyServersCore

final class StatusAggregatorTests: XCTestCase {
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
