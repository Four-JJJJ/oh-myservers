import XCTest
@testable import OhMyServersCore

final class MetricsParserTests: XCTestCase {
    func testParseFixtureSnapshot() throws {
        let raw = try loadRaw()
        let snap = MetricsParser.parse(serverID: UUID(), raw: raw)

        XCTAssertTrue(snap.isReachable)
        XCTAssertEqual(snap.cpuPercent ?? -1, 65.625, accuracy: 0.05)
        XCTAssertEqual(snap.load1, 0.52)
        XCTAssertEqual(snap.load5, 0.41)
        XCTAssertEqual(snap.load15, 0.38)
        XCTAssertEqual(snap.uptimeSeconds, 123456)
        XCTAssertEqual(snap.diskUsedPercent, 47)
        XCTAssertEqual(snap.netRxBytesPerSec ?? -1, 5000, accuracy: 0.1)
        XCTAssertEqual(snap.netTxBytesPerSec ?? -1, 10000, accuracy: 0.1)

        XCTAssertEqual(snap.memoryTotalBytes, 8165496 * 1024)
        XCTAssertEqual(snap.memoryUsedBytes, (8165496 - 4096000) * 1024)
    }

    func testPartialFailureStillReturnsReachableSnapshot() {
        let raw = RemoteMetricRaw(
            procStat1: "bad",
            procStat2: "bad",
            procMeminfo: "bad",
            procLoadavg: "0.1 0.2 0.3",
            procUptime: "10.0 20.0",
            procNetDev1: "bad",
            procNetDev2: "bad",
            df: "bad",
            sampleIntervalSeconds: 1
        )
        let snap = MetricsParser.parse(serverID: UUID(), raw: raw)
        XCTAssertTrue(snap.isReachable)
        XCTAssertNil(snap.cpuPercent)
        XCTAssertEqual(snap.load1, 0.1)
        XCTAssertEqual(snap.uptimeSeconds, 10)
    }

    private func loadRaw() throws -> RemoteMetricRaw {
        RemoteMetricRaw(
            procStat1: try fixture("proc_stat_1.txt"),
            procStat2: try fixture("proc_stat_2.txt"),
            procMeminfo: try fixture("proc_meminfo.txt"),
            procLoadavg: try fixture("proc_loadavg.txt"),
            procUptime: try fixture("proc_uptime.txt"),
            procNetDev1: try fixture("proc_net_dev_1.txt"),
            procNetDev2: try fixture("proc_net_dev_2.txt"),
            df: try fixture("df.txt"),
            sampleIntervalSeconds: 1
        )
    }

    private func fixture(_ name: String) throws -> String {
        let ns = name as NSString
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: ns.deletingPathExtension,
                withExtension: ns.pathExtension,
                subdirectory: "Fixtures"
            )
        )
        return try String(contentsOf: url, encoding: .utf8)
    }
}
