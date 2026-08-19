import XCTest
@testable import OhMyServersCore

final class ReachabilityGateTests: XCTestCase {
    func testFirstSuccessPassesThrough() {
        var gate = ReachabilityGate()
        let id = UUID()
        let snap = MetricsSnapshot(serverID: id, isReachable: true, cpuPercent: 21)
        let out = gate.accept(snap)
        XCTAssertEqual(out.cpuPercent, 21)
        XCTAssertTrue(out.isReachable)
    }

    func testOneMissHoldsLastGoodIncludingCollectedAt() {
        var gate = ReachabilityGate()
        let id = UUID()
        let collectedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let good = MetricsSnapshot(
            serverID: id,
            collectedAt: collectedAt,
            isReachable: true,
            cpuPercent: 33
        )
        _ = gate.accept(good)
        let miss = MetricsSnapshot.unreachable(serverID: id, message: "连接超时")
        let out = gate.accept(miss)
        XCTAssertTrue(out.isReachable)
        XCTAssertEqual(out.cpuPercent, 33)
        XCTAssertEqual(out.collectedAt, collectedAt)
    }

    func testSecondMissGoesOffline() {
        var gate = ReachabilityGate()
        let id = UUID()
        _ = gate.accept(MetricsSnapshot(serverID: id, isReachable: true, cpuPercent: 10))
        _ = gate.accept(.unreachable(serverID: id, message: "t1"))
        let out = gate.accept(.unreachable(serverID: id, message: "t2"))
        XCTAssertFalse(out.isReachable)
        XCTAssertEqual(out.errorMessage, "t2")
    }

    func testSuccessResetsMissCount() {
        var gate = ReachabilityGate()
        let id = UUID()
        _ = gate.accept(MetricsSnapshot(serverID: id, isReachable: true, cpuPercent: 10))
        _ = gate.accept(.unreachable(serverID: id, message: "t1"))
        _ = gate.accept(MetricsSnapshot(serverID: id, isReachable: true, cpuPercent: 44))
        let out = gate.accept(.unreachable(serverID: id, message: "t2"))
        XCTAssertTrue(out.isReachable)
        XCTAssertEqual(out.cpuPercent, 44)
    }

    func testFirstMissWithoutHistoryIsOffline() {
        var gate = ReachabilityGate()
        let id = UUID()
        let out = gate.accept(.unreachable(serverID: id, message: "连接超时"))
        XCTAssertFalse(out.isReachable)
    }

    func testPruneDropsState() {
        var gate = ReachabilityGate()
        let id = UUID()
        _ = gate.accept(MetricsSnapshot(serverID: id, isReachable: true, cpuPercent: 10))
        gate.prune(keeping: [])
        let out = gate.accept(.unreachable(serverID: id, message: "t"))
        XCTAssertFalse(out.isReachable)
    }

    func testServersAreIndependent() {
        var gate = ReachabilityGate()
        let a = UUID()
        let b = UUID()
        _ = gate.accept(MetricsSnapshot(serverID: a, isReachable: true, cpuPercent: 1))
        _ = gate.accept(MetricsSnapshot(serverID: b, isReachable: true, cpuPercent: 2))
        _ = gate.accept(.unreachable(serverID: a, message: "a1"))
        _ = gate.accept(.unreachable(serverID: a, message: "a2"))
        let stillB = gate.accept(.unreachable(serverID: b, message: "b1"))
        XCTAssertTrue(stillB.isReachable)
        XCTAssertEqual(stillB.cpuPercent, 2)
    }
}
