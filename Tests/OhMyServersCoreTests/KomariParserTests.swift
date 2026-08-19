import XCTest
@testable import OhMyServersCore

final class KomariParserTests: XCTestCase {
    // Captured 2026-08-17 from GET https://komari.fourj.ccwu.cc/api/nodes
    private let nodesJSON = """
    {"data":[
      {"uuid":"865feca1-6acb-4722-82ff-ee90a9d7921e","name":"HK","cpu_name":"Intel(R) Xeon(R) CPU E5-2697A v4 @ 2.60GHz","virtualization":"kvm","arch":"amd64","cpu_cores":4,"cpu_physical_cores":4,"os":"CentOS Stream 9","kernel_version":"5.14.0-725.el9.x86_64","gpu_name":"None","region":"🇭🇰","mem_total":3832459264,"swap_total":2147479552,"disk_total":52654874624,"weight":0,"price":0,"billing_cycle":0,"auto_renewal":false,"currency":"$","expired_at":null,"group":"","tags":"NewAPI;Sub2API","hidden":false,"traffic_limit":0,"traffic_limit_type":"max","created_at":"2026-08-17T09:49:58.953295323Z","updated_at":"2026-08-17T10:09:59.320889687Z"},
      {"uuid":"ca2d1dc8-20bc-4a2e-a251-5a5cfa697a0a","name":"US","cpu_name":"Intel(R) Xeon(R) CPU E5-2699 v4 @ 2.20GHz","virtualization":"kvm","arch":"amd64","cpu_cores":3,"cpu_physical_cores":3,"os":"Debian GNU/Linux 13 (trixie)","kernel_version":"6.12.43+deb13-amd64","gpu_name":"None","region":"🇺🇸","mem_total":4112056320,"swap_total":2147479552,"disk_total":61198983168,"weight":0,"price":0,"billing_cycle":0,"auto_renewal":false,"currency":"$","expired_at":null,"group":"","tags":"Backup","hidden":false,"traffic_limit":0,"traffic_limit_type":"max","created_at":"2026-08-17T09:50:32.1449371Z","updated_at":"2026-08-17T10:13:26.083643823Z"}
    ],"message":"","status":"success"}
    """

    // Captured 2026-08-17 from wss://komari.fourj.ccwu.cc/api/clients ("get")
    private let realtimeJSON = """
    {"data":{
      "online":["ca2d1dc8-20bc-4a2e-a251-5a5cfa697a0a","865feca1-6acb-4722-82ff-ee90a9d7921e"],
      "data":{
        "865feca1-6acb-4722-82ff-ee90a9d7921e":{
          "cpu":{"usage":7.5125208673478046},
          "ram":{"total":3832459264,"used":1618427904},
          "swap":{"total":2147479552,"used":141869056},
          "load":{"load1":0.41,"load5":0.44,"load15":0.39},
          "disk":{"total":52654874624,"used":11068125184},
          "network":{"up":219366,"down":270258,"totalUp":103665610183,"totalDown":104252507527},
          "connections":{"tcp":304,"udp":2},
          "uptime":964431,"process":155,"message":"",
          "updated_at":"2026-08-17T10:17:59.529418504Z"
        },
        "ca2d1dc8-20bc-4a2e-a251-5a5cfa697a0a":{
          "cpu":{"usage":0.8938547493242034},
          "ram":{"total":4112056320,"used":1594953728},
          "swap":{"total":2147479552,"used":435253248},
          "load":{"load1":0.29,"load5":0.35,"load15":0.26},
          "disk":{"total":61198983168,"used":22593802240},
          "network":{"up":290,"down":205,"totalUp":129632212070,"totalDown":189118236346},
          "connections":{"tcp":49,"udp":1},
          "uptime":3393533,"process":194,"message":"",
          "updated_at":"2026-08-17T10:17:59.040584067Z"
        }
      }
    },"status":"success"}
    """

    func testParseNodes() throws {
        let nodes = try KomariParser.parseNodes(Data(nodesJSON.utf8))
        XCTAssertEqual(nodes.count, 2)

        let hk = try XCTUnwrap(nodes.first)
        XCTAssertEqual(hk.uuid, "865feca1-6acb-4722-82ff-ee90a9d7921e")
        XCTAssertEqual(hk.name, "HK")
        XCTAssertEqual(hk.region, "🇭🇰")
        XCTAssertEqual(hk.os, "CentOS Stream 9")
        XCTAssertEqual(hk.cpuCores, 4)
        XCTAssertEqual(hk.memTotal, 3_832_459_264)
        XCTAssertEqual(hk.diskTotal, 52_654_874_624)
    }

    func testParseRealtime() throws {
        let (online, reports) = try KomariParser.parseRealtime(Data(realtimeJSON.utf8))
        XCTAssertEqual(online.count, 2)
        XCTAssertTrue(online.contains("865feca1-6acb-4722-82ff-ee90a9d7921e"))

        let hk = try XCTUnwrap(reports["865feca1-6acb-4722-82ff-ee90a9d7921e"])
        XCTAssertEqual(hk.cpuUsagePercent, 7.5125208673478046, accuracy: 0.0001)
        XCTAssertEqual(hk.ramUsed, 1_618_427_904)
        XCTAssertEqual(hk.ramTotal, 3_832_459_264)
        XCTAssertEqual(hk.diskUsed, 11_068_125_184)
        XCTAssertEqual(hk.netUpBytesPerSec, 219_366)
        XCTAssertEqual(hk.netDownBytesPerSec, 270_258)
        XCTAssertEqual(hk.load1, 0.41, accuracy: 0.0001)
        XCTAssertEqual(hk.uptimeSeconds, 964_431)
        XCTAssertEqual(hk.processCount, 155)
    }

    func testNodeStatusPercents() throws {
        let nodes = try KomariParser.parseNodes(Data(nodesJSON.utf8))
        let (online, reports) = try KomariParser.parseRealtime(Data(realtimeJSON.utf8))
        let statuses = nodes.map {
            KomariNodeStatus(info: $0, isOnline: online.contains($0.uuid), report: reports[$0.uuid])
        }
        let hk = try XCTUnwrap(statuses.first)
        XCTAssertTrue(hk.isOnline)
        XCTAssertEqual(hk.memUsedPercent ?? 0, 42.23, accuracy: 0.01)
        XCTAssertEqual(hk.diskUsedPercent ?? 0, 21.02, accuracy: 0.01)
    }

    func testParseNodesFailureStatus() {
        let bad = Data(#"{"status":"error","message":"nope"}"#.utf8)
        XCTAssertThrowsError(try KomariParser.parseNodes(bad))
    }
}
