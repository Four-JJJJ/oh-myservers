import SwiftUI

enum Graphite {
    static let bg = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let bgElevated = Color(red: 0.14, green: 0.14, blue: 0.15)
    static let card = Color(red: 0.17, green: 0.17, blue: 0.18)
    static let field = Color(red: 0.20, green: 0.20, blue: 0.21)
    static let text = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let muted = Color(red: 0.63, green: 0.63, blue: 0.65)
    static let divider = Color(red: 0.23, green: 0.23, blue: 0.24)
    static let accent = Color(red: 0.35, green: 0.78, blue: 0.92)
    static let online = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let high = Color(red: 1, green: 0.84, blue: 0.04)
    static let offline = Color(red: 1, green: 0.35, blue: 0.35)
}

enum L10n {
    static let appName = "Oh My Servers"
    static let settings = "设置"
    static let refresh = "立即刷新"
    static let quit = "退出"
    static let noServers = "还没有服务器"
    static let noServersHint = "打开设置添加香港 / 美国等主机"
    static let waitingSample = "正在采集第一份数据…"
    static let online = "在线"
    static let high = "偏高"
    static let offline = "离线"
    static let cpu = "CPU"
    static let mem = "内存"
    static let load = "负载"
    static let disk = "磁盘"
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
