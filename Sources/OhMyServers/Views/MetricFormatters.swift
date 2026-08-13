import Foundation
import SwiftUI
import OhMyServersCore

enum MetricFormatters {
    private static let bytesPerGB: Double = 1_073_741_824
    private static let bytesPerMB: Double = 1_048_576

    static func usageText(used: UInt64?, total: UInt64?, percent: Double?) -> String {
        if let used, let total, total > 0 {
            if Double(total) >= bytesPerGB {
                return String(
                    format: "%.1f / %.1f GB",
                    Double(used) / bytesPerGB,
                    Double(total) / bytesPerGB
                )
            }
            return String(
                format: "%.1f / %.1f MB",
                Double(used) / bytesPerMB,
                Double(total) / bytesPerMB
            )
        }
        if let percent {
            return "\(Int(percent.rounded()))%"
        }
        return "—"
    }

    static func loadText(_ snapshot: MetricsSnapshot) -> String {
        guard let load1 = snapshot.load1, let load5 = snapshot.load5, let load15 = snapshot.load15 else {
            if let load1 = snapshot.load1 {
                return String(format: "%.2f", load1)
            }
            return "—"
        }
        return String(format: "%.2f / %.2f / %.2f", load1, load5, load15)
    }

    static func loadColor(load1: Double?, cpuCount: Int?) -> Color {
        guard let load1, let cpuCount, cpuCount > 0 else { return Graphite.text }
        let ratio = load1 / Double(cpuCount)
        if ratio >= 1.5 { return Graphite.offline }
        if ratio >= 1 { return Graphite.high }
        return Graphite.text
    }

    static func barFraction(percent: Double?) -> Double? {
        guard let percent, percent.isFinite else { return nil }
        return min(max(percent / 100, 0), 1)
    }

    static func barFill(percent: Double?, highThreshold: Double) -> Color {
        guard let percent else { return Graphite.accent }
        if percent >= highThreshold { return Graphite.high }
        return Graphite.accent
    }

    static func diskPercent(_ snapshot: MetricsSnapshot) -> Double? {
        if let used = snapshot.diskUsedBytes, let total = snapshot.diskTotalBytes, total > 0 {
            return Double(used) / Double(total) * 100
        }
        return snapshot.diskUsedPercent
    }
}
