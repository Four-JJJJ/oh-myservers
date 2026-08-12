import XCTest
@testable import OhMyServersCore

final class SSHErrorLocalizerTests: XCTestCase {
    func testPermissionDenied() {
        XCTAssertEqual(
            SSHErrorLocalizer.message(from: "Permission denied (publickey,password)"),
            "认证失败，请检查密码或密钥"
        )
    }

    func testTimeoutVariants() {
        XCTAssertEqual(SSHErrorLocalizer.message(from: "Connection timed out"), "连接超时")
        XCTAssertEqual(SSHErrorLocalizer.message(from: "TIMEOUT waiting for banner"), "连接超时")
        XCTAssertEqual(SSHErrorLocalizer.message(from: "连接超时"), "连接超时")
    }

    func testConnectionRefused() {
        XCTAssertEqual(SSHErrorLocalizer.message(from: "Connection refused"), "连接被拒绝")
    }

    func testHostResolution() {
        XCTAssertEqual(SSHErrorLocalizer.message(from: "Could not resolve hostname example.invalid"), "无法解析主机名")
        XCTAssertEqual(
            SSHErrorLocalizer.message(from: "ssh: Could not resolve hostname foo: nodename nor servname provided, or not known"),
            "无法解析主机名"
        )
    }

    func testNetworkUnreachable() {
        XCTAssertEqual(SSHErrorLocalizer.message(from: "Network is unreachable"), "网络不可达")
    }

    func testMissingIdentityFile() {
        XCTAssertEqual(
            SSHErrorLocalizer.message(from: "Warning: Identity file /tmp/missing.pem not accessible: No such file or directory"),
            "找不到私钥文件"
        )
        XCTAssertEqual(
            SSHErrorLocalizer.message(from: "Could not open identity file /tmp/id_rsa"),
            "找不到私钥文件"
        )
    }

    func testMissingCredentials() {
        XCTAssertEqual(SSHErrorLocalizer.message(from: "Missing credentials"), "缺少登录凭据")
        XCTAssertEqual(SSHErrorLocalizer.message(from: "缺少登录凭据"), "缺少登录凭据")
    }

    func testFallbackTruncatesTo160Characters() {
        let original = String(repeating: "x", count: 200)
        let message = SSHErrorLocalizer.message(from: original)
        XCTAssertTrue(message.hasPrefix("SSH 失败："))
        let body = String(message.dropFirst("SSH 失败：".count))
        XCTAssertEqual(body.count, 160)
        XCTAssertEqual(body, String(repeating: "x", count: 160))
    }
}
