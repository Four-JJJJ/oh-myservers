import os
import XCTest
@testable import OhMyServersCore

private struct MockCollector: SSHCollecting {
    var results: [UUID: MetricsSnapshot]

    func collect(from server: ServerConfig, credential: SSHCredential) async -> MetricsSnapshot {
        results[server.id] ?? .unreachable(serverID: server.id, message: "missing")
    }
}

/// Class mock: struct mutation is lost across concurrent actor hops.
private final class DelayCollector: SSHCollecting, @unchecked Sendable {
    private let countLock = OSAllocatedUnfairLock(initialState: 0)
    let delayNanoseconds: UInt64

    var count: Int {
        countLock.withLock { $0 }
    }

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func collect(from server: ServerConfig, credential: SSHCredential) async -> MetricsSnapshot {
        countLock.withLock { $0 += 1 }
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        return MetricsSnapshot(serverID: server.id, isReachable: true, cpuPercent: 1)
    }
}

private final class SequenceCollector: SSHCollecting, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)
    let snapshots: [MetricsSnapshot]

    init(snapshots: [MetricsSnapshot]) {
        self.snapshots = snapshots
    }

    func collect(from server: ServerConfig, credential: SSHCredential) async -> MetricsSnapshot {
        let i = lock.withLock { idx -> Int in
            let current = idx
            idx += 1
            return current
        }
        if i < snapshots.count { return snapshots[i] }
        return snapshots.last ?? .unreachable(serverID: server.id, message: "empty")
    }
}

private final class Box<T>: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<[T]>(initialState: [])

    func append(_ value: T) {
        lock.withLock { $0.append(value) }
    }

    var snapshot: [T] {
        lock.withLock { $0 }
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
        let received = Box<[UUID: MetricsSnapshot]>()
        await scheduler.start(serversProvider: { [a, b] }) { snaps, _ in
            received.append(snaps)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2)
        await scheduler.stop()
        let last = received.snapshot.last
        XCTAssertEqual(last?[a.id]?.cpuPercent, 12)
        XCTAssertEqual(last?[b.id]?.isReachable, false)
    }

    func testWallClockIntervalSubtractsCollectDuration() async {
        let server = ServerConfig(name: "A", host: "a", username: "u", label: "A", authMethod: .password)
        let collector = DelayCollector(delayNanoseconds: 250_000_000)
        let scheduler = PollScheduler(collector: collector, intervalSeconds: 0.4) { _ in
            .password("x")
        }

        let expectation = expectation(description: "two updates")
        expectation.expectedFulfillmentCount = 2
        let times = Box<Date>()
        await scheduler.start(serversProvider: { [server] }) { _, _ in
            times.append(Date())
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 3)
        await scheduler.stop()

        let recorded = times.snapshot
        XCTAssertEqual(recorded.count, 2)
        let gap = recorded[1].timeIntervalSince(recorded[0])
        XCTAssertGreaterThanOrEqual(gap, 0.35)
        XCTAssertLessThan(gap, 0.55)
    }

    func testRefreshDuringPollDoesNotOverlap() async {
        let server = ServerConfig(name: "A", host: "a", username: "u", label: "A", authMethod: .password)
        let collector = DelayCollector(delayNanoseconds: 400_000_000)
        let scheduler = PollScheduler(collector: collector, intervalSeconds: 60) { _ in
            .password("x")
        }

        let flags = Box<Bool>()
        let expectation = expectation(description: "first update")
        expectation.assertForOverFulfill = false
        await scheduler.start(
            serversProvider: { [server] },
            onUpdate: { _, _ in expectation.fulfill() },
            onRefreshing: { flags.append($0) }
        )
        await scheduler.refresh(servers: [server])
        await scheduler.refresh(servers: [server])

        await fulfillment(of: [expectation], timeout: 2)
        try? await Task.sleep(nanoseconds: 200_000_000)
        await scheduler.stop()

        XCTAssertEqual(collector.count, 1, "one enabled server, one in-flight poll")
        XCTAssertEqual(flags.snapshot, [true, false])
    }

    func testStartEmitsRefreshingTrueThenFalse() async {
        let server = ServerConfig(name: "A", host: "a", username: "u", label: "A", authMethod: .password)
        let collector = DelayCollector(delayNanoseconds: 50_000_000)
        let scheduler = PollScheduler(collector: collector, intervalSeconds: 60) { _ in
            .password("x")
        }

        let flags = Box<Bool>()
        let expectation = expectation(description: "refresh finished")
        await scheduler.start(
            serversProvider: { [server] },
            onUpdate: { _, _ in },
            onRefreshing: { refreshing in
                flags.append(refreshing)
                if !refreshing { expectation.fulfill() }
            }
        )

        await fulfillment(of: [expectation], timeout: 2)
        await scheduler.stop()
        XCTAssertEqual(flags.snapshot, [true, false])
    }

    func testOneFailureAfterSuccessStaysReachableAndSilent() async {
        let server = ServerConfig(name: "HK", host: "hk", username: "u", label: "HK", authMethod: .password)
        let good = MetricsSnapshot(serverID: server.id, isReachable: true, cpuPercent: 19)
        let collector = SequenceCollector(snapshots: [
            good,
            .unreachable(serverID: server.id, message: "连接超时")
        ])
        let scheduler = PollScheduler(collector: collector, intervalSeconds: 60) { _ in
            .password("x")
        }
        let updates = Box<([UUID: MetricsSnapshot], [AlertEvent])>()
        let first = expectation(description: "first update")
        let second = expectation(description: "second update")
        await scheduler.start(serversProvider: { [server] }) { snaps, events in
            updates.append((snaps, events))
            switch updates.snapshot.count {
            case 1: first.fulfill()
            case 2: second.fulfill()
            default: break
            }
        }
        await fulfillment(of: [first], timeout: 2)
        await scheduler.refresh(servers: [server])
        await fulfillment(of: [second], timeout: 2)
        await scheduler.stop()

        XCTAssertEqual(updates.snapshot.count, 2)
        XCTAssertEqual(updates.snapshot[1].0[server.id]?.cpuPercent, 19)
        XCTAssertTrue(updates.snapshot[1].0[server.id]?.isReachable ?? false)
        XCTAssertTrue(updates.snapshot[1].1.isEmpty)
    }

    func testTwoFailuresAfterSuccessGoOfflineAndNotify() async {
        let server = ServerConfig(name: "HK", host: "hk", username: "u", label: "HK", authMethod: .password)
        let good = MetricsSnapshot(serverID: server.id, isReachable: true, cpuPercent: 19)
        let collector = SequenceCollector(snapshots: [
            good,
            .unreachable(serverID: server.id, message: "t1"),
            .unreachable(serverID: server.id, message: "t2")
        ])
        let scheduler = PollScheduler(collector: collector, intervalSeconds: 60) { _ in
            .password("x")
        }
        let updates = Box<([UUID: MetricsSnapshot], [AlertEvent])>()
        let first = expectation(description: "first update")
        let second = expectation(description: "second update")
        let third = expectation(description: "third update")
        await scheduler.start(serversProvider: { [server] }) { snaps, events in
            updates.append((snaps, events))
            switch updates.snapshot.count {
            case 1: first.fulfill()
            case 2: second.fulfill()
            case 3: third.fulfill()
            default: break
            }
        }
        await fulfillment(of: [first], timeout: 2)
        await scheduler.refresh(servers: [server])
        await fulfillment(of: [second], timeout: 2)
        await scheduler.refresh(servers: [server])
        await fulfillment(of: [third], timeout: 2)
        await scheduler.stop()

        XCTAssertEqual(updates.snapshot.count, 3)
        XCTAssertFalse(updates.snapshot[2].0[server.id]?.isReachable ?? true)
        XCTAssertTrue(updates.snapshot[2].1.contains(where: { $0.title.contains("离线") }))
    }
}
