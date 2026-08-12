import XCTest
@testable import OhMyServersCore

private struct MockCollector: SSHCollecting {
    var results: [UUID: MetricsSnapshot]

    func collect(from server: ServerConfig, credential: SSHCredential) async -> MetricsSnapshot {
        results[server.id] ?? .unreachable(serverID: server.id, message: "missing")
    }
}

final class PollSchedulerTests: XCTestCase {
    func testPollIsolatesServersAndEmitsUpdate() async {
        let a = ServerConfig(name: "A", host: "a", username: "u", label: "A", authMethod: .password)
        let b = ServerConfig(name: "B", host: "b", username: "u", label: "B", authMethod: .password)
        let collector = MockCollector(results: [
            a.id: MetricsSnapshot(serverID: a.id, isReachable: true, cpuPercent: 12),
            b.id: .unreachable(serverID: b.id, message: "down")
        ])
        let scheduler = PollScheduler(collector: collector, intervalSeconds: 60) { _ in
            .password("x")
        }

        let expectation = expectation(description: "update")
        var received: [UUID: MetricsSnapshot] = [:]
        await scheduler.start(serversProvider: { [a, b] }) { snaps, _ in
            received = snaps
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2)
        await scheduler.stop()
        XCTAssertEqual(received[a.id]?.cpuPercent, 12)
        XCTAssertEqual(received[b.id]?.isReachable, false)
    }
}
