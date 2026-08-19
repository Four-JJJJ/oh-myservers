import XCTest
@testable import OhMyServersCore

final class SSHRetryPolicyTests: XCTestCase {
    func testRetriesTimeoutWhenFast() {
        XCTAssertTrue(SSHRetryPolicy.shouldRetry(elapsed: 1, message: "连接超时"))
        XCTAssertTrue(SSHRetryPolicy.shouldRetry(elapsed: 0.4, message: "Connection timed out"))
        XCTAssertTrue(SSHRetryPolicy.shouldRetry(
            elapsed: 2,
            message: "mux_client_request_session: session request failed"
        ))
        XCTAssertTrue(SSHRetryPolicy.shouldRetry(
            elapsed: 0.2,
            message: "Control socket connect failed: Connection refused"
        ))
        XCTAssertTrue(SSHRetryPolicy.shouldRetry(elapsed: 1, message: "broken pipe"))
        XCTAssertTrue(SSHRetryPolicy.shouldRetry(elapsed: 1, message: "Connection reset by peer"))
        XCTAssertTrue(SSHRetryPolicy.shouldRetry(elapsed: 5.9, message: "Network is unreachable"))
    }

    func testDoesNotRetrySlowTimeout() {
        XCTAssertFalse(SSHRetryPolicy.shouldRetry(elapsed: 6, message: "连接超时"))
        XCTAssertFalse(SSHRetryPolicy.shouldRetry(elapsed: 15, message: "Connection timed out"))
    }

    func testDoesNotRetryAuthOrParse() {
        XCTAssertFalse(SSHRetryPolicy.shouldRetry(elapsed: 0.1, message: "Permission denied"))
        XCTAssertFalse(SSHRetryPolicy.shouldRetry(elapsed: 0.1, message: "认证失败，请检查密码或密钥"))
        XCTAssertFalse(SSHRetryPolicy.shouldRetry(elapsed: 0.1, message: "Could not find identity file"))
        XCTAssertFalse(SSHRetryPolicy.shouldRetry(elapsed: 0.1, message: "缺少登录凭据"))
        XCTAssertFalse(SSHRetryPolicy.shouldRetry(elapsed: 0.1, message: "无法解析远端指标"))
    }
}
