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
    static let noServers = "还没有服务器"
    static let noServersHint = "打开设置添加香港 / 美国等主机"
    static let waitingSample = "正在采集…"
    static let online = "在线"
    static let high = "偏高"
    static let offline = "离线"
    static let cpu = "CPU"
    static let mem = "MEM"
    static let load = "Load"
    static let disk = "Disk"
    static let net = "Net"
    static let netIn = "下行"
    static let netOut = "上行"
    static let uptime = "运行"
    static let servers = "服务器"
    static let add = "添加"
    static let delete = "删除"
    static let save = "保存"
    static let basic = "基本信息"
    static let auth = "登录方式"
    static let name = "名称"
    static let label = "摘要标签"
    static let host = "主机"
    static let port = "端口"
    static let username = "用户名"
    static let enabled = "启用监控"
    static let password = "密码"
    static let privateKey = "私钥"
    static let keyPath = "私钥路径"
    static let browse = "选择…"
    static let passphrase = "私钥口令"
    static let keepPassword = "编辑已有服务器时留空，可保留原密码"
    static let passphraseOptional = "可选；未加密私钥可留空"
    static let selectServer = "选择左侧服务器，或点击添加"
    static let requiredFields = "请填写名称、标签、主机和用户名"
    static let passwordRequired = "新服务器需要填写密码"
    static let keyRequired = "请填写私钥路径"
    static let authPassword = "密码登录"
    static let authKey = "密钥登录"
}
