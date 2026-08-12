import XCTest
@testable import OhMyServersCore

final class RemoteMetricScriptsTests: XCTestCase {
    func testSteadyCollectCommandHasSingleSectionsAndNproc() {
        let cmd = RemoteMetricScripts.collectCommand
        XCTAssertTrue(cmd.contains("___PROC_STAT___"))
        XCTAssertTrue(cmd.contains("___PROC_NET_DEV___"))
        XCTAssertTrue(cmd.contains("___NPROC___"))
        XCTAssertTrue(cmd.contains("nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1"))
        XCTAssertFalse(cmd.contains("___PROC_STAT_1___"))
        XCTAssertFalse(cmd.contains("sleep"))
    }

    func testParseSectionsSteadyOutput() {
        let output = """
        ___PROC_STAT___
        cpu  1 0 1 1 0 0 0 0 0 0
        ___PROC_NET_DEV___
        eth0: 10 0 0 0 0 0 0 0 20 0 0 0 0 0 0 0
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
        ___NPROC___
        4
        ___END___
        """
        let sample = RemoteMetricScripts.parseSections(output)
        XCTAssertNotNil(sample)
        XCTAssertTrue(sample?.procStat.contains("cpu  1") == true)
        XCTAssertEqual(sample?.nprocText, "4")
        XCTAssertEqual(sample?.procLoadavg.split(whereSeparator: \.isWhitespace).first.map(String.init), "0.1")

        let snap = MetricsParser.parse(serverID: UUID(), current: sample!, previous: nil)
        XCTAssertEqual(snap.load1, 0.1)
        XCTAssertEqual(snap.diskUsedPercent, 40)
        XCTAssertEqual(snap.uptimeSeconds, 99)
        XCTAssertEqual(snap.cpuCount, 4)
        XCTAssertNil(snap.cpuPercent)
    }

    func testParseInitialSectionsReturnsPairedSamples() {
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
        ___NPROC___
        2
        ___END___
        """
        let pair = RemoteMetricScripts.parseInitialSections(output)
        XCTAssertNotNil(pair)
        guard let (first, second) = pair else { return }
        XCTAssertTrue(first.procStat.contains("cpu  1"))
        XCTAssertTrue(second.procStat.contains("cpu  2"))
        XCTAssertTrue(first.procNetDev.contains("10"))
        XCTAssertTrue(second.procNetDev.contains("20"))
        XCTAssertEqual(first.nprocText, "2")
        XCTAssertEqual(second.nprocText, "2")

        let snap = MetricsParser.parse(
            serverID: UUID(),
            current: second,
            previous: first,
            intervalSeconds: 1
        )
        XCTAssertEqual(snap.load1, 0.1)
        XCTAssertNotNil(snap.cpuPercent)
        XCTAssertEqual(snap.cpuCount, 2)
    }

    func testInitialCollectCommandSleepsBetweenPairedSamples() {
        let cmd = RemoteMetricScripts.collectCommandInitial
        XCTAssertTrue(cmd.contains("___PROC_STAT_1___"))
        XCTAssertTrue(cmd.contains("___PROC_NET_DEV_1___"))
        XCTAssertTrue(cmd.contains("sleep 1"))
        XCTAssertTrue(cmd.contains("___PROC_STAT_2___"))
        XCTAssertTrue(cmd.contains("___PROC_NET_DEV_2___"))
        XCTAssertTrue(cmd.contains("___NPROC___"))
    }
}
