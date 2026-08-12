import Foundation

public enum SSHErrorLocalizer {
    public static func message(from raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("permission denied") {
            return "认证失败，请检查密码或密钥"
        }
        if lower.contains("timed out") || lower.contains("timeout") || lower.contains("连接超时") {
            return "连接超时"
        }
        if lower.contains("connection refused") {
            return "连接被拒绝"
        }
        if lower.contains("could not resolve") || lower.contains("nodename nor servname") {
            return "无法解析主机名"
        }
        if lower.contains("network is unreachable") {
            return "网络不可达"
        }
        if lower.contains("no such file") || lower.contains("identity") {
            return "找不到私钥文件"
        }
        if lower.contains("missing credentials") || lower.contains("缺少登录凭据") {
            return "缺少登录凭据"
        }
        if lower.contains("failed to parse remote metrics") || lower.contains("无法解析远端指标") {
            return "无法解析远端指标"
        }
        let clipped = raw.count <= 160 ? raw : String(raw.prefix(160))
        return "SSH 失败：\(clipped)"
    }
}
