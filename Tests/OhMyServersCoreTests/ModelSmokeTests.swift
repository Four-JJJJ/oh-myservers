import XCTest
@testable import OhMyServersCore

final class ModelSmokeTests: XCTestCase {
    func testKomariSiteCodableRoundTrip() throws {
        let site = KomariSite(name: "主站", urlString: "https://komari.example.com", isEnabled: false)
        let data = try JSONEncoder().encode(site)
        let decoded = try JSONDecoder().decode(KomariSite.self, from: data)
        XCTAssertEqual(decoded, site)
    }

    func testKomariSiteDisplayNameFallsBackToHost() {
        let named = KomariSite(name: "主站", urlString: "https://komari.example.com")
        XCTAssertEqual(named.displayName, "主站")
        let unnamed = KomariSite(urlString: "https://komari.example.com")
        XCTAssertEqual(unnamed.displayName, "komari.example.com")
    }

    func testKomariSiteURLValidation() {
        XCTAssertNotNil(KomariSite(urlString: "https://komari.example.com").url)
        XCTAssertNil(KomariSite(urlString: "not a url").url)
    }
}
