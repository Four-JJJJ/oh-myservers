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
        let sample = makeSample(sampledAt: Date())
        collector.storeSample(sample, for: serverID)
        XCTAssertNotNil(collector.cachedSample(for: serverID))
        collector.clearSample(for: serverID)
        XCTAssertNil(collector.cachedSample(for: serverID))
    }

    func testIsUsableCacheRejectsSampleOlderThanMaxAge() {
        let now = Date()
        let sample = makeSample(sampledAt: now.addingTimeInterval(-200))
        XCTAssertFalse(ProcessSSHCollector.isUsableCache(sample, now: now))
        XCTAssertEqual(
            ProcessSSHCollector.remoteCommand(hasCache: false),
            RemoteMetricScripts.collectCommandInitial
        )
    }

    func testIsUsableCacheAcceptsRecentSample() {
        let now = Date()
        let sample = makeSample(sampledAt: now.addingTimeInterval(-10))
        XCTAssertTrue(ProcessSSHCollector.isUsableCache(sample, now: now))
    }

    func testIsUsableCacheRejectsNil() {
        XCTAssertFalse(ProcessSSHCollector.isUsableCache(nil))
    }

    func testIsUsableCacheAcceptsSampleAtExactMaxAge() {
        let now = Date()
        let sample = makeSample(sampledAt: now.addingTimeInterval(-ProcessSSHCollector.maxSampleAgeSeconds))
        XCTAssertTrue(ProcessSSHCollector.isUsableCache(sample, now: now))
    }

    private func makeSample(sampledAt: Date) -> MetricSample {
        MetricSample(
            procStat: "cpu  1 0 1 1 0 0 0 0 0 0",
            procMeminfo: "",
            procLoadavg: "",
            procUptime: "",
            procNetDev: "",
            df: "",
            nprocText: "1",
            sampledAt: sampledAt
        )
    }
}
