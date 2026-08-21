import OhMyServersCore
import SwiftUI

enum Graphite {
    /// Matches the approved Graphite demo (#1c1c1e / #2c2c2e).
    static let bg = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    static let bgElevated = Color(red: 36 / 255, green: 36 / 255, blue: 38 / 255)
    static let card = Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255)
    static let field = Color(red: 58 / 255, green: 58 / 255, blue: 60 / 255)
    static let text = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    static let muted = Color(red: 161 / 255, green: 161 / 255, blue: 166 / 255)
    static let divider = Color(red: 58 / 255, green: 58 / 255, blue: 60 / 255)
    static let accent = Color(red: 100 / 255, green: 210 / 255, blue: 255 / 255)
    static let online = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
    static let high = Color(red: 255 / 255, green: 214 / 255, blue: 10 / 255)
    static let offline = Color(red: 255 / 255, green: 69 / 255, blue: 58 / 255)
}

enum L10n {
    static let appName = "Oh My Servers"
    static let settings = "设置"
    static let refresh = "刷新"
    static let quit = "退出"
    static let online = "在线"
    static let offline = "离线"
    static let komariSites = "Komari 站点"
    static let noSites = "还没有站点"
    static let noSitesHint = "打开设置，添加 Komari 站点地址"
    static let siteURL = "站点地址"
    static let siteURLHint = "https://komari.example.com"
    static let nameOptional = "名称（可选）"
    static let invalidURL = "地址格式不正确"
    static let add = "添加"
    static let delete = "删除"
    static let save = "保存"
    static let monitoring = "监控"
    static let pollInterval = "刷新间隔"
    static let launchAtLogin = "开机自启"
    static let launchAtLoginFailed = "无法设置开机自启，请在系统设置中允许"
    static let cancel = "取消"
    static let menuBarDisplay = "菜单栏显示"
    static let allServers = "全部服务器"
    static let menuBarNoNodes = "暂无服务器数据"
    static let preview = "预览"

    static func menuBarMetricName(_ metric: MenuBarMetric) -> String {
        switch metric {
        case .cpu: "CPU"
        case .memory: "内存"
        case .load: "负载"
        case .disk: "磁盘"
        case .networkUp: "上行"
        case .networkDown: "下行"
        case .uptime: "运行时间"
        case .process: "进程数"
        }
    }

    static func pollIntervalOption(_ seconds: Int) -> String {
        "\(seconds) 秒"
    }
}
