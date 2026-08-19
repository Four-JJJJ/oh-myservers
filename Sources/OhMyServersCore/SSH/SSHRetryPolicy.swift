import Foundation

public enum SSHRetryPolicy {
    public static let fastFailSeconds: TimeInterval = 6

    public static func shouldRetry(elapsed: TimeInterval, message: String) -> Bool {
        guard elapsed < fastFailSeconds else { return false }
        let lower = message.lowercased()
        if isNonRetryable(lower) { return false }
        return isRetryable(lower)
    }

    private static func isNonRetryable(_ lower: String) -> Bool {
        if lower.contains("permission denied") { return true }
        if lower.contains("认证失败") { return true }
        if lower.contains("identity") { return true }
        if lower.contains("找不到私钥") { return true }
        if lower.contains("缺少登录凭据") { return true }
        if lower.contains("无法解析远端指标") { return true }
        if lower.contains("failed to parse remote metrics") { return true }
        return false
    }

    private static func isRetryable(_ lower: String) -> Bool {
        if lower.contains("timed out") || lower.contains("timeout") || lower.contains("连接超时") {
            return true
        }
        if lower.contains("connection reset") { return true }
        if lower.contains("connection refused") { return true }
        if lower.contains("broken pipe") { return true }
        if lower.contains("mux") { return true }
        if lower.contains("control socket") { return true }
        if lower.contains("network is unreachable") || lower.contains("网络不可达") { return true }
        if lower.contains("connection closed") { return true }
        if lower.contains("no route to host") { return true }
        return false
    }
}
