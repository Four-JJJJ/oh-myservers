import Foundation

public enum RemoteMetricScripts {
    /// Single remote script: sample /proc twice (~1s apart) plus mem/load/uptime/df.
    public static let collectCommand: String = #"""
    set -e
    echo '___PROC_STAT_1___'
    cat /proc/stat
    echo '___PROC_NET_DEV_1___'
    cat /proc/net/dev
    sleep 1
    echo '___PROC_STAT_2___'
    cat /proc/stat
    echo '___PROC_NET_DEV_2___'
    cat /proc/net/dev
    echo '___PROC_MEMINFO___'
    cat /proc/meminfo
    echo '___PROC_LOADAVG___'
    cat /proc/loadavg
    echo '___PROC_UPTIME___'
    cat /proc/uptime
    echo '___DF___'
    df -Pk /
    echo '___END___'
    """#

    public static func parseSections(_ output: String) -> RemoteMetricRaw? {
        func section(_ name: String) -> String? {
            let start = "___" + name + "___"
            guard let startRange = output.range(of: start) else { return nil }
            let after = output[startRange.upperBound...]
            if let next = after.range(of: "___", options: []) {
                return String(after[..<next.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return String(after).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard
            let stat1 = section("PROC_STAT_1"),
            let stat2 = section("PROC_STAT_2"),
            let mem = section("PROC_MEMINFO"),
            let load = section("PROC_LOADAVG"),
            let uptime = section("PROC_UPTIME"),
            let net1 = section("PROC_NET_DEV_1"),
            let net2 = section("PROC_NET_DEV_2"),
            let df = section("DF")
        else {
            return nil
        }

        return RemoteMetricRaw(
            procStat1: stat1,
            procStat2: stat2,
            procMeminfo: mem,
            procLoadavg: load,
            procUptime: uptime,
            procNetDev1: net1,
            procNetDev2: net2,
            df: df,
            sampleIntervalSeconds: 1.0
        )
    }
}
