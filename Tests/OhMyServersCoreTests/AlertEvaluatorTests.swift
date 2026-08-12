import XCTest
@testable import OhMyServersCore

final class AlertEvaluatorTests: XCTestCase {
    func testNotifyOnReachableToUnreachableEdge() {
        let server = ServerConfig(name: "HK", host: "hk", username: "u", label: "HK", authMethod: .password)
        let prev: [UUID: MetricsSnapshot] = [
            server.id: MetricsSnapshot(serverID: server.id, isReachable: true, cpuPercent: 10)
        ]
        let curr: [UUID: MetricsSnapshot] = [
            server.id: .unreachable(serverID: server.id, message: "timeout")
        ]
        let events = AlertEvaluator().evaluate(servers: [server], previous: prev, current: curr)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].title.contains("offline"))
    }

    func testNoRepeatWhileStillOffline() {
        let server = ServerConfig(name: "HK", host: "hk", username: "u", label: "HK", authMethod: .password)
        let offline = MetricsSnapshot.unreachable(serverID: server.id, message: "timeout")
        let prev = [server.id: offline]
        let curr = [server.id: offline]
        let events = AlertEvaluator().evaluate(servers: [server], previous: prev, current: curr)
        XCTAssertTrue(events.isEmpty)
    }

    func testNotifyOnHighLoadEdgeWithoutOffline() {
        let server = ServerConfig(name: "US", host: "us", username: "u", label: "US", authMethod: .password)
        let prev: [UUID: MetricsSnapshot] = [
            server.id: MetricsSnapshot(serverID: server.id, isReachable: true, cpuPercent: 10)
        ]
        let curr: [UUID: MetricsSnapshot] = [
            server.id: MetricsSnapshot(serverID: server.id, isReachable: true, cpuPercent: 95)
        ]
        let events = AlertEvaluator().evaluate(servers: [server], previous: prev, current: curr)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].title.lowercased().contains("abnormal"))
    }
}
