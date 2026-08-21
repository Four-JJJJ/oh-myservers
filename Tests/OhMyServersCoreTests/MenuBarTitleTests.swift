import XCTest
@testable import OhMyServersCore

final class MenuBarTitleTests: XCTestCase {
    private let aggregator = StatusAggregator()

    private func makeReport() -> KomariRealtimeReport {
        KomariRealtimeReport(
            cpuUsagePercent: 23.4,
            ramUsed: 8_000,
            ramTotal: 16_000,
            diskUsed: 600,
            diskTotal: 1_000,
            netUpBytesPerSec: 1_234,
            netDownBytesPerSec: 3_500_000,
            load1: 0.52,
            load5: 0.4,
            load15: 0.3,
            uptimeSeconds: 12 * 86_400 + 3_600,
            processCount: 120
        )
    }

    private func makeNode(
        uuid: String,
        name: String,
        online: Bool = true,
        report: KomariRealtimeReport? = nil
    ) -> KomariNodeStatus {
        KomariNodeStatus(
            info: KomariNodeInfo(
                uuid: uuid, name: name, region: "", os: "linux",
                cpuCores: 4, memTotal: 16_000, diskTotal: 1_000
            ),
            isOnline: online,
            report: report
        )
    }

    func testDefaultSettingsShowCPUOnly() {
        let nodes = [makeNode(uuid: "a", name: "hk", report: makeReport())]
        XCTAssertEqual(aggregator.menuBarTitle(komariNodes: nodes), "HK 23%")
    }

    func testAllMetricsInStableOrder() {
        let nodes = [makeNode(uuid: "a", name: "hk", report: makeReport())]
        let settings = MenuBarDisplaySettings(metrics: MenuBarMetric.allCases)
        XCTAssertEqual(
            aggregator.menuBarTitle(komariNodes: nodes, settings: settings),
            "HK 23% M50% L0.52 D60% ↑1.2K/s ↓3.3M/s U12d P120"
        )
    }

    func testOfflineNodeShowsDash() {
        let nodes = [makeNode(uuid: "a", name: "hk", online: false, report: nil)]
        let settings = MenuBarDisplaySettings(metrics: [.cpu, .memory])
        XCTAssertEqual(aggregator.menuBarTitle(komariNodes: nodes, settings: settings), "HK —")
    }

    func testEmptyMetricsShowLabelOnly() {
        let nodes = [makeNode(uuid: "a", name: "hk", report: makeReport())]
        let settings = MenuBarDisplaySettings(metrics: [])
        XCTAssertEqual(aggregator.menuBarTitle(komariNodes: nodes, settings: settings), "HK")
    }

    func testNodeSelectionFiltersTitle() {
        let nodes = [
            makeNode(uuid: "a", name: "hk", report: makeReport()),
            makeNode(uuid: "b", name: "us", report: makeReport()),
        ]
        let settings = MenuBarDisplaySettings(metrics: [.cpu], selectedNodeUUIDs: ["b"])
        XCTAssertEqual(aggregator.menuBarTitle(komariNodes: nodes, settings: settings), "US 23%")
    }

    func testSelectionMatchingNoNodesFallsBack() {
        let nodes = [makeNode(uuid: "a", name: "hk", report: makeReport())]
        let settings = MenuBarDisplaySettings(metrics: [.cpu], selectedNodeUUIDs: ["gone"])
        XCTAssertEqual(aggregator.menuBarTitle(komariNodes: nodes, settings: settings), "无服务器")
    }

    func testSettingsCodableRoundTrip() throws {
        let settings = MenuBarDisplaySettings(metrics: [.cpu, .disk], selectedNodeUUIDs: ["a", "b"])
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(MenuBarDisplaySettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }

    func testSettingsStoreRoundTripAndDefault() {
        let suite = "MenuBarTitleTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("cannot create suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = MenuBarDisplaySettingsStore(defaults: defaults)
        XCTAssertEqual(store.load(), .default)

        let settings = MenuBarDisplaySettings(metrics: [.load], selectedNodeUUIDs: ["x"])
        store.save(settings)
        XCTAssertEqual(store.load(), settings)
    }
}
