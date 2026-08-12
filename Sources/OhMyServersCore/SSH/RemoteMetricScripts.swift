import Foundation

public enum RemoteMetricScripts {
    /// Steady-state remote script: one /proc sample, no sleep.
    public static let collectCommand: String = #"""
    set -e
    echo '___PROC_STAT___'
    cat /proc/stat
    echo '___PROC_NET_DEV___'
    cat /proc/net/dev
    echo '___PROC_MEMINFO___'
    cat /proc/meminfo
    echo '___PROC_LOADAVG___'
    cat /proc/loadavg
    echo '___PROC_UPTIME___'
    cat /proc/uptime
    echo '___DF___'
    df -Pk /
    echo '___NPROC___'
    nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1
    echo '___END___'
    """#

    /// First poll for a server: pair STAT/NET one second apart so CPU/net rates exist immediately.
    public static let collectCommandInitial: String = #"""
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
    echo '___NPROC___'
    nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1
    echo '___END___'
    """#

    public static func parseSections(_ output: String) -> MetricSample? {
        guard
            let procStat = section("PROC_STAT", in: output),
            let procNetDev = section("PROC_NET_DEV", in: output),
            let mem = section("PROC_MEMINFO", in: output),
            let load = section("PROC_LOADAVG", in: output),
            let uptime = section("PROC_UPTIME", in: output),
            let df = section("DF", in: output),
            let nproc = section("NPROC", in: output)
        else {
            return nil
        }

        return MetricSample(
            procStat: procStat,
            procMeminfo: mem,
            procLoadavg: load,
            procUptime: uptime,
            procNetDev: procNetDev,
            df: df,
            nprocText: nproc,
            sampledAt: Date()
        )
    }

    public static func parseInitialSections(_ output: String) -> (MetricSample, MetricSample)? {
        guard
            let stat1 = section("PROC_STAT_1", in: output),
            let stat2 = section("PROC_STAT_2", in: output),
            let net1 = section("PROC_NET_DEV_1", in: output),
            let net2 = section("PROC_NET_DEV_2", in: output),
            let mem = section("PROC_MEMINFO", in: output),
            let load = section("PROC_LOADAVG", in: output),
            let uptime = section("PROC_UPTIME", in: output),
            let df = section("DF", in: output),
            let nproc = section("NPROC", in: output)
        else {
            return nil
        }

        let sampledAt = Date()
        let first = MetricSample(
            procStat: stat1,
            procMeminfo: mem,
            procLoadavg: load,
            procUptime: uptime,
            procNetDev: net1,
            df: df,
            nprocText: nproc,
            sampledAt: sampledAt
        )
        let second = MetricSample(
            procStat: stat2,
            procMeminfo: mem,
            procLoadavg: load,
            procUptime: uptime,
            procNetDev: net2,
            df: df,
            nprocText: nproc,
            sampledAt: sampledAt
        )
        return (first, second)
    }

    private static func section(_ name: String, in output: String) -> String? {
        let start = "___" + name + "___"
        guard let startRange = output.range(of: start) else { return nil }
        let after = output[startRange.upperBound...]
        if let next = after.range(of: "___", options: []) {
            return String(after[..<next.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(after).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
