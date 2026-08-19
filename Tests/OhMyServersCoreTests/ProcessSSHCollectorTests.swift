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

    func testSSHFailureDoesNotClearSampleCache() {
        let collector = ProcessSSHCollector()
        let serverID = UUID()
        collector.storeSample(makeSample(sampledAt: Date()), for: serverID)
        XCTAssertNotNil(collector.cachedSample(for: serverID))
        // SSH failures must keep the /proc cache so the next success stays a single sample.
        XCTAssertNotNil(collector.cachedSample(for: serverID))
    }

    func testKeepaliveSeconds() {
        XCTAssertEqual(ProcessSSHCollector.serverAliveInterval, 30)
        XCTAssertEqual(ProcessSSHCollector.serverAliveCountMax, 3)
        XCTAssertEqual(ProcessSSHCollector.controlPath, "/tmp/ohmyservers-%C")
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
