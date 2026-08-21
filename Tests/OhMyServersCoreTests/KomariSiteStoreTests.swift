import XCTest
@testable import OhMyServersCore

final class KomariSiteStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "KomariSiteStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testSeedsDefaultSiteOnFirstRun() {
        let store = KomariSiteStore(defaults: defaults)
        let sites = store.list()
        XCTAssertEqual(sites.count, 1)
        XCTAssertEqual(sites.first?.urlString, KomariSiteStore.defaultSiteURL)
        XCTAssertTrue(sites.first?.isEnabled ?? false)
    }

    func testMigratesLegacyBaseURL() {
        defaults.set("https://legacy.example.com", forKey: "komariBaseURL")
        let store = KomariSiteStore(defaults: defaults)
        let sites = store.list()
        XCTAssertEqual(sites.map(\.urlString), ["https://legacy.example.com"])
        XCTAssertNil(defaults.string(forKey: "komariBaseURL"))
        // Second access reads the migrated list, not the seed path.
        XCTAssertEqual(store.list().map(\.urlString), ["https://legacy.example.com"])
    }

    func testUpsertAppendsAndUpdates() {
        let store = KomariSiteStore(defaults: defaults)
        _ = store.list() // seed
        let site = KomariSite(name: "A", urlString: "https://a.example.com")
        store.upsert(site)
        XCTAssertEqual(store.list().count, 2)

        var updated = site
        updated.name = "B"
        updated.isEnabled = false
        store.upsert(updated)
        let list = store.list()
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list.first(where: { $0.id == site.id })?.name, "B")
        XCTAssertEqual(list.first(where: { $0.id == site.id })?.isEnabled, false)
    }

    func testDelete() {
        let store = KomariSiteStore(defaults: defaults)
        let seeded = store.list().first!
        store.delete(id: seeded.id)
        XCTAssertTrue(store.list().isEmpty)
    }
}
