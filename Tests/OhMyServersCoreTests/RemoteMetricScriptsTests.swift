import XCTest
@testable import OhMyServersCore

final class RemoteMetricScriptsTests: XCTestCase {
    func testParseSections() {
        let output = """
        ___PROC_STAT_1___
        cpu  1 0 1 1 0 0 0 0 0 0
        ___PROC_NET_DEV_1___
        eth0: 10 0 0 0 0 0 0 0 20 0 0 0 0 0 0 0
        ___PROC_STAT_2___
        cpu  2 0 2 2 0 0 0 0 0 0
        ___PROC_NET_DEV_2___
        eth0: 20 0 0 0 0 0 0 0 40 0 0 0 0 0 0 0
        ___PROC_MEMINFO___
        MemTotal: 1000 kB
        MemAvailable: 400 kB
        ___PROC_LOADAVG___
        0.1 0.2 0.3 1/1 1
        ___PROC_UPTIME___
        99.0 1.0
        ___DF___
        Filesystem 1024-blocks Used Available Capacity Mounted on
        /dev/sda1 100 40 60 40% /
        ___END___
        """
        let raw = RemoteMetricScripts.parseSections(output)
        XCTAssertNotNil(raw)
        let snap = MetricsParser.parse(serverID: UUID(), raw: raw!)
        XCTAssertEqual(snap.load1, 0.1)
        XCTAssertEqual(snap.diskUsedPercent, 40)
        XCTAssertEqual(snap.uptimeSeconds, 99)
    }
}
