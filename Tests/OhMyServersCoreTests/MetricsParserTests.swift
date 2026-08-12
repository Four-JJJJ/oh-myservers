import XCTest
@testable import OhMyServersCore

final class MetricsParserTests: XCTestCase {
    func testParseUsesPreviousSampleForCPUAndNetworkRates() throws {
        let previous = try makeSample(
            procStat: fixture("proc_stat_1.txt"),
            procNetDev: fixture("proc_net_dev_1.txt")
        )
        let current = try makeSample(
            procStat: fixture("proc_stat_2.txt"),
            procMeminfo: fixture("proc_meminfo.txt"),
            procLoadavg: fixture("proc_loadavg.txt"),
            procUptime: fixture("proc_uptime.txt"),
            procNetDev: fixture("proc_net_dev_2.txt"),
            df: fixture("df.txt"),
            nprocText: "4\n"
        )

        let snap = MetricsParser.parse(
            serverID: UUID(),
            current: current,
            previous: previous,
            intervalSeconds: 1
        )

        XCTAssertTrue(snap.isReachable)
        XCTAssertEqual(snap.cpuPercent ?? -1, 65.625, accuracy: 0.05)
        XCTAssertEqual(snap.netRxBytesPerSec ?? -1, 5000, accuracy: 0.1)
        XCTAssertEqual(snap.netTxBytesPerSec ?? -1, 10000, accuracy: 0.1)
        XCTAssertEqual(snap.load1, 0.52)
        XCTAssertEqual(snap.load5, 0.41)
        XCTAssertEqual(snap.load15, 0.38)
        XCTAssertEqual(snap.uptimeSeconds, 123456)
        XCTAssertEqual(snap.diskUsedPercent, 47)
        XCTAssertEqual(snap.memoryTotalBytes, 8165496 * 1024)
        XCTAssertEqual(snap.memoryUsedBytes, (8165496 - 4096000) * 1024)
    }

    func testParseWithoutPreviousLeavesCPUAndNetworkNil() throws {
        let current = try makeSample(
            procStat: fixture("proc_stat_2.txt"),
            procMeminfo: fixture("proc_meminfo.txt"),
            procLoadavg: fixture("proc_loadavg.txt"),
            procUptime: fixture("proc_uptime.txt"),
            procNetDev: fixture("proc_net_dev_2.txt"),
            df: fixture("df.txt")
        )

        let snap = MetricsParser.parse(
            serverID: UUID(),
            current: current,
            previous: nil
        )

        XCTAssertTrue(snap.isReachable)
        XCTAssertNil(snap.cpuPercent)
        XCTAssertNil(snap.netRxBytesPerSec)
        XCTAssertNil(snap.netTxBytesPerSec)
        XCTAssertEqual(snap.load1, 0.52)
        XCTAssertEqual(snap.memoryTotalBytes, 8165496 * 1024)
        XCTAssertEqual(snap.uptimeSeconds, 123456)
    }

    func testParseDiskBytesFromDfRootPartition() throws {
        let current = try makeSample(df: fixture("df.txt"))
        let snap = MetricsParser.parse(serverID: UUID(), current: current, previous: nil)

        XCTAssertEqual(snap.diskUsedBytes, 22_528_000 * 1024)
        XCTAssertEqual(snap.diskTotalBytes, 51_200_000 * 1024)
        XCTAssertEqual(snap.diskUsedPercent, 47)
    }

    func testParseCpuCountFromNprocText() {
        let current = makeSample(nprocText: "4\n")
        let snap = MetricsParser.parse(serverID: UUID(), current: current, previous: nil)
        XCTAssertEqual(snap.cpuCount, 4)
    }

    private func makeSample(
        procStat: String = "",
        procMeminfo: String = "",
        procLoadavg: String = "",
        procUptime: String = "",
        procNetDev: String = "",
        df: String = "",
        nprocText: String = "",
        sampledAt: Date = Date()
    ) -> MetricSample {
        MetricSample(
            procStat: procStat,
            procMeminfo: procMeminfo,
            procLoadavg: procLoadavg,
            procUptime: procUptime,
            procNetDev: procNetDev,
            df: df,
            nprocText: nprocText,
            sampledAt: sampledAt
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
