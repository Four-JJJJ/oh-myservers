import XCTest
@testable import OhMyServersCore

final class ProcessSSHCollectorTests: XCTestCase {
    func testRemoteCommandUsesInitialScriptWhenCacheEmpty() {
        XCTAssertEqual(
            ProcessSSHCollector.remoteCommand(hasCache: false),
            RemoteMetricScripts.collectCommandInitial
        )
    }

    func testRemoteCommandUsesSteadyScriptWhenCachePresent() {
        XCTAssertEqual(
            ProcessSSHCollector.remoteCommand(hasCache: true),
            RemoteMetricScripts.collectCommand
        )
    }

    func testClearSampleDropsCachedEntry() {
        let collector = ProcessSSHCollector()
        let serverID = UUID()
        let sample = MetricSample(
            procStat: "cpu  1 0 1 1 0 0 0 0 0 0",
            procMeminfo: "",
            procLoadavg: "",
            procUptime: "",
            procNetDev: "",
            df: "",
            nprocText: "1",
            sampledAt: Date()
        )
        collector.storeSample(sample, for: serverID)
        XCTAssertNotNil(collector.cachedSample(for: serverID))
        collector.clearSample(for: serverID)
        XCTAssertNil(collector.cachedSample(for: serverID))
    }
}
