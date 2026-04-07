// actor-swift/main.swift
// Polyglot Infinity — Swift 6.1 Actor Portfolio Manager (:8008)
// 핵심 강점: actor 키워드 — 컴파일러가 data race를 원천 차단합니다.
// actor 외부에서 내부 프로퍼티 접근 시 await 강제 → 컴파일 타임 직렬화 보증.
// Java synchronized, Go Mutex와 달리 런타임이 아닌 컴파일 타임에 검증합니다.
//
// GET /health
// GET /api/swift/status
// GET /api/swift/concurrent?n=100   — N개 Task 동시 접근, data race 검증
// GET /api/swift/trade?sym=AAPL&qty=10&price=182.5

import Foundation
import Dispatch

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

// ── Actor 정의 ─────────────────────────────────────────────────────
// actor: Swift 6 컴파일러가 이 타입의 모든 저장 프로퍼티를 보호합니다.
// 외부에서 positions, tradeCount 등에 접근하려면 반드시 await이 필요합니다.
// 컴파일 타임에 "actor-isolated" 검사를 통과하지 않으면 빌드 에러가 발생합니다.
actor PortfolioLedger {
    private var positions: [String: Double] = [:]
    private var tradeCount  = 0
    private var totalNotional = 0.0

    // actor-isolated: 이 메서드는 actor 내부에서만 실행됩니다.
    // 외부 Task가 await 없이 직접 호출하면 컴파일 에러입니다.
    func trade(sym: String, qty: Double, price: Double) {
        positions[sym, default: 0.0] += qty
        tradeCount    += 1
        totalNotional += abs(qty * price)
    }

    func state() -> (pos: [String: Double], trades: Int, notional: Double) {
        return (positions, tradeCount, totalNotional)
    }

    func reset() {
        positions     = [:]
        tradeCount    = 0
        totalNotional = 0.0
    }
}

// ── 동시성 스트레스 테스트 ─────────────────────────────────────────
// N개 Task를 동시에 실행하여 모두 같은 actor를 호출합니다.
// actor가 모든 접근을 직렬화하므로 tradeCount는 정확히 n이어야 합니다.
// data race라면 count가 어긋납니다 (Java에서 synchronized 없이 ++ 하는 것과 비교).
func runConcurrentTrades(ledger: PortfolioLedger, n: Int) async -> String {
    let symbols = ["AAPL", "NVDA", "MSFT", "TSLA", "GOOG"]
    await ledger.reset()

    await withTaskGroup(of: Void.self) { group in
        for i in 0..<n {
            group.addTask {
                let sym   = symbols[i % symbols.count]
                let qty   = Double((i % 10) + 1) * 5.0
                let price = 100.0 + Double(i % 200)
                // await: actor 격리를 통과해야만 trade()를 호출할 수 있습니다.
                // Swift 컴파일러가 이 await 없이는 빌드를 거부합니다.
                await ledger.trade(sym: sym, qty: qty, price: price)
            }
        }
    }

    let s = await ledger.state()
    let dataRace = s.trades != n

    var posArr: [String] = []
    for (sym, qty) in s.pos.sorted(by: { $0.key < $1.key }) {
        posArr.append("{\"sym\":\"\(sym)\",\"qty\":\(String(format: "%.0f", qty))}")
    }

    return "{\"lang\":\"swift\",\"version\":\"6.1\","
         + "\"actor\":\"PortfolioLedger\","
         + "\"concurrent_tasks\":\(n),"
         + "\"expected_trades\":\(n),"
         + "\"actual_trades\":\(s.trades),"
         + "\"data_race_detected\":\(dataRace),"
         + "\"total_notional\":\(String(format: "%.2f", s.notional)),"
         + "\"positions\":[\(posArr.joined(separator: ","))],"
         + "\"guarantee\":\"Swift actor serialized all \(n) concurrent mutations — compile-time data race prevention\"}"
}

// ── HTTP 유틸리티 ─────────────────────────────────────────────────
func sendResponse(fd: Int32, body: String, status: Int = 200) {
    let statusLine = status == 200 ? "200 OK" : "404 Not Found"
    let resp = "HTTP/1.1 \(statusLine)\r\n"
             + "Content-Type: application/json\r\n"
             + "Content-Length: \(body.utf8.count)\r\n"
             + "Access-Control-Allow-Origin: *\r\n"
             + "Connection: close\r\n\r\n"
             + body
    resp.withCString { ptr in
        _ = send(fd, ptr, Int(strlen(ptr)), 0)
    }
    close(fd)
}

func readRequest(fd: Int32) -> String {
    var buf = [UInt8](repeating: 0, count: 4096)
    let n = recv(fd, &buf, 4095, 0)
    guard n > 0 else { return "" }
    return String(bytes: buf[0..<n], encoding: .utf8) ?? ""
}

func parsePath(_ req: String) -> (path: String, params: [String: String]) {
    let firstLine = req.components(separatedBy: "\r\n").first ?? ""
    let parts     = firstLine.components(separatedBy: " ")
    guard parts.count >= 2 else { return ("/", [:]) }
    let full  = parts[1]
    let split = full.components(separatedBy: "?")
    let path  = split[0]
    var params: [String: String] = [:]
    if split.count > 1 {
        for pair in split[1].components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2 { params[kv[0]] = kv[1] }
        }
    }
    return (path, params)
}

// ── 요청 처리 ─────────────────────────────────────────────────────
func handleConnection(fd: Int32, ledger: PortfolioLedger) {
    defer { close(fd) }
    let req = readRequest(fd: fd)
    guard !req.isEmpty else { return }
    let (path, params) = parsePath(req)

    // async actor 호출을 동기 컨텍스트로 브릿지
    let sema = DispatchSemaphore(value: 0)
    var body = ""

    Task.detached {
        defer { sema.signal() }

        if path == "/health" {
            body = "{\"status\":\"ok\",\"lang\":\"swift\",\"port\":8008}"

        } else if path == "/api/swift/status" {
            let s = await ledger.state()
            var posArr: [String] = []
            for (sym, qty) in s.pos.sorted(by: { $0.key < $1.key }) {
                posArr.append("{\"sym\":\"\(sym)\",\"qty\":\(String(format: "%.0f", qty))}")
            }
            body = "{\"lang\":\"swift\",\"version\":\"6.1\","
                 + "\"actor\":\"PortfolioLedger\","
                 + "\"total_trades\":\(s.trades),"
                 + "\"total_notional\":\(String(format: "%.2f", s.notional)),"
                 + "\"positions\":[\(posArr.joined(separator: ","))]}"

        } else if path.hasPrefix("/api/swift/concurrent") {
            let n = max(1, min(Int(params["n"] ?? "100") ?? 100, 500))
            body = await runConcurrentTrades(ledger: ledger, n: n)

        } else if path.hasPrefix("/api/swift/trade") {
            let sym   = params["sym"]   ?? "AAPL"
            let qty   = Double(params["qty"]   ?? "10")  ?? 10.0
            let price = Double(params["price"] ?? "150") ?? 150.0
            await ledger.trade(sym: sym, qty: qty, price: price)
            let s = await ledger.state()
            body = "{\"status\":\"ok\",\"total_trades\":\(s.trades)}"

        } else {
            body = "{\"error\":\"not found\"}"
        }
    }

    sema.wait()
    sendResponse(fd: fd, body: body)
}

// ── 소켓 서버 ─────────────────────────────────────────────────────
func runServer() {
    signal(SIGPIPE, SIG_IGN)

    let sockfd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
    guard sockfd >= 0 else { fatalError("socket() failed") }

    var flag: Int32 = 1
    setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &flag, socklen_t(MemoryLayout<Int32>.size))

    var addr         = sockaddr_in()
    addr.sin_family  = sa_family_t(AF_INET)
    addr.sin_port    = UInt16(8008).bigEndian
    addr.sin_addr    = in_addr(s_addr: INADDR_ANY)

    let bindRet = withUnsafeMutablePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(sockfd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindRet == 0 else { fatalError("bind() failed") }
    listen(sockfd, 128)

    print("[Swift Actor] Server on :8008")

    let ledger = PortfolioLedger()

    while true {
        var clientAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                accept(sockfd, $0, &addrLen)
            }
        }
        guard clientFd >= 0 else { continue }

        let fd = clientFd  // capture for thread
        Thread.detachNewThread {
            handleConnection(fd: fd, ledger: ledger)
        }
    }
}

// ── 진입점 ─────────────────────────────────────────────────────────
let serverThread = Thread { runServer() }
serverThread.start()
dispatchMain()
