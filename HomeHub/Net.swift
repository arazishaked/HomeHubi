import Foundation
import Network
import Darwin

enum HHError: LocalizedError {
    case msg(String)
    var errorDescription: String? {
        if case .msg(let s) = self { return s }
        return nil
    }
}

// MARK: - HTTP

final class InsecureDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

let insecureDelegate = InsecureDelegate()

func makeSession(timeout: TimeInterval = 3) -> URLSession {
    let c = URLSessionConfiguration.ephemeral
    c.timeoutIntervalForRequest = timeout
    c.timeoutIntervalForResource = timeout * 3
    return URLSession(configuration: c, delegate: insecureDelegate, delegateQueue: nil)
}

let sharedHTTP = makeSession(timeout: 3)

func httpRequest(_ url: String, method: String = "GET", headers: [String: String] = [:],
                 body: Data? = nil, timeout: TimeInterval = 3) async throws -> (Data, Int) {
    guard let u = URL(string: url) else { throw HHError.msg("כתובת לא תקינה") }
    var r = URLRequest(url: u, timeoutInterval: timeout)
    r.httpMethod = method
    r.httpBody = body
    for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
    let (d, resp) = try await sharedHTTP.data(for: r)
    return (d, (resp as? HTTPURLResponse)?.statusCode ?? 0)
}

func jsonObj(_ d: Data) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
}

func jsonString(_ o: Any) -> String {
    guard let d = try? JSONSerialization.data(withJSONObject: o) else { return "{}" }
    return String(decoding: d, as: UTF8.self)
}

func tag(_ name: String, _ s: String) -> String? {
    guard let r = s.range(of: "<\(name)>(.*?)</\(name)>", options: .regularExpression) else { return nil }
    let inner = String(s[r])
        .replacingOccurrences(of: "<\(name)>", with: "")
        .replacingOccurrences(of: "</\(name)>", with: "")
    return inner.isEmpty ? nil : inner
}

// MARK: - TCP

final class TCP {
    let conn: NWConnection

    init(host: String, port: UInt16) {
        conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    }

    func connect(timeout: TimeInterval = 2) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let lock = NSLock()
            var done = false
            func finish(_ r: Result<Void, Error>) {
                lock.lock(); defer { lock.unlock() }
                if done { return }
                done = true
                cont.resume(with: r)
            }
            conn.stateUpdateHandler = { s in
                switch s {
                case .ready: finish(.success(()))
                case .failed(let e): finish(.failure(e))
                case .waiting(let e): finish(.failure(e))
                case .cancelled: finish(.failure(HHError.msg("בוטל")))
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(.failure(HHError.msg("פג הזמן")))
            }
        }
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { e in
                if let e = e { c.resume(throwing: e) } else { c.resume() }
            })
        }
    }

    func receive(max: Int = 4096, timeout: TimeInterval = 1) async -> Data {
        await withCheckedContinuation { (c: CheckedContinuation<Data, Never>) in
            let lock = NSLock()
            var done = false
            func finish(_ d: Data) {
                lock.lock(); defer { lock.unlock() }
                if done { return }
                done = true
                c.resume(returning: d)
            }
            conn.receive(minimumIncompleteLength: 1, maximumLength: max) { d, _, _, _ in finish(d ?? Data()) }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(Data()) }
        }
    }

    func close() { conn.cancel() }
}

func isOpen(_ ip: String, _ port: UInt16, _ timeout: Double) async -> Bool {
    let t = TCP(host: ip, port: port)
    do {
        try await t.connect(timeout: timeout)
        t.close()
        return true
    } catch {
        t.close()
        return false
    }
}

// MARK: - WebSocket

final class WS {
    let task: URLSessionWebSocketTask
    let session: URLSession

    init(url: URL) {
        session = makeSession(timeout: 30)
        task = session.webSocketTask(with: url)
        task.resume()
    }

    func send(_ s: String) async throws {
        try await task.send(.string(s))
    }

    func recv(timeout: Double) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let lock = NSLock()
            var done = false
            func finish(_ r: Result<String, Error>) {
                lock.lock(); defer { lock.unlock() }
                if done { return }
                done = true
                cont.resume(with: r)
            }
            task.receive { result in
                switch result {
                case .success(let m):
                    switch m {
                    case .string(let s): finish(.success(s))
                    case .data(let d): finish(.success(String(decoding: d, as: UTF8.self)))
                    @unknown default: finish(.failure(HHError.msg("הודעה לא מוכרת")))
                    }
                case .failure(let e): finish(.failure(e))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(.failure(HHError.msg("אין תגובה מהמכשיר")))
            }
        }
    }

    func close() {
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
}

// MARK: - Local network

func localIPv4() -> (ip: UInt32, mask: UInt32)? {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
    defer { freeifaddrs(ifaddr) }
    var ptr: UnsafeMutablePointer<ifaddrs>? = first
    while let p = ptr {
        let ifa = p.pointee
        if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
           String(cString: ifa.ifa_name) == "en0" {
            let ip = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            var mask: UInt32 = 0xFFFFFF00
            if let nm = ifa.ifa_netmask {
                mask = nm.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                }
            }
            return (ip, mask)
        }
        ptr = ifa.ifa_next
    }
    return nil
}

func ipString(_ a: UInt32) -> String {
    "\((a >> 24) & 255).\((a >> 16) & 255).\((a >> 8) & 255).\(a & 255)"
}

func subnetHosts() -> [String] {
    guard let info = localIPv4() else { return [] }
    let mask = max(info.mask, 0xFFFFFF00)       // עד 254 כתובות
    let net = info.ip & mask
    let count = ~mask
    var out: [String] = []
    if count < 2 { return out }
    for h in 1..<count {
        let a = net | h
        if a == info.ip { continue }
        out.append(ipString(a))
    }
    return out
}

// MARK: - Wake on LAN

func sendWOL(mac: String) {
    let hex = mac.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
    guard hex.count == 12 else { return }
    var bytes: [UInt8] = []
    var i = hex.startIndex
    while i < hex.endIndex {
        let j = hex.index(i, offsetBy: 2)
        if let b = UInt8(hex[i..<j], radix: 16) { bytes.append(b) }
        i = j
    }
    guard bytes.count == 6 else { return }
    var pkt = [UInt8](repeating: 0xFF, count: 6)
    for _ in 0..<16 { pkt += bytes }
    var targets = ["255.255.255.255"]
    if let info = localIPv4() { targets.append(ipString(info.ip | ~info.mask)) }
    let fd = socket(AF_INET, SOCK_DGRAM, 0)
    guard fd >= 0 else { return }
    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
    for t in targets {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(9).bigEndian
        addr.sin_addr.s_addr = inet_addr(t)
        withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = sendto(fd, pkt, pkt.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }
    Darwin.close(fd)
}

// MARK: - Host probing

enum ProbeResult { case open, refused, none }

/// בדיקת פורט: פתוח / נדחה (המכשיר קיים אבל הפורט סגור) / אין תגובה
func probe(_ ip: String, _ port: UInt16, _ timeout: Double) async -> ProbeResult {
    guard let p = NWEndpoint.Port(rawValue: port) else { return .none }
    let conn = NWConnection(host: NWEndpoint.Host(ip), port: p, using: .tcp)
    return await withCheckedContinuation { (cont: CheckedContinuation<ProbeResult, Never>) in
        let lock = NSLock()
        var done = false
        func finish(_ r: ProbeResult) {
            lock.lock()
            if done { lock.unlock(); return }
            done = true
            lock.unlock()
            conn.cancel()
            cont.resume(returning: r)
        }
        conn.stateUpdateHandler = { s in
            switch s {
            case .ready:
                finish(.open)
            case .waiting(let e), .failed(let e):
                if case .posix(let code) = e, code == .ECONNREFUSED || code == .ECONNRESET {
                    finish(.refused)
                } else {
                    finish(.none)
                }
            default:
                break
            }
        }
        conn.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(.none) }
    }
}

/// שם המכשיר כפי שהראוטר מכיר אותו (DNS הפוך), למשל "Galaxy-S23" או "Living-Room-TV"
func reverseName(_ ip: String, timeout: Double = 1.5) async -> String? {
    await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
        let lock = NSLock()
        var done = false
        func finish(_ v: String?) {
            lock.lock()
            if done { lock.unlock(); return }
            done = true
            lock.unlock()
            cont.resume(returning: v)
        }
        DispatchQueue.global().async {
            var sin = sockaddr_in()
            let len = socklen_t(MemoryLayout<sockaddr_in>.size)
            sin.sin_len = UInt8(len)
            sin.sin_family = sa_family_t(AF_INET)
            guard inet_pton(AF_INET, ip, &sin.sin_addr) == 1 else { finish(nil); return }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let r = withUnsafePointer(to: &sin) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getnameinfo($0, len, &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
                }
            }
            guard r == 0 else { finish(nil); return }
            var name = String(cString: host)
            for suffix in [".local", ".lan", ".home", ".localdomain", ".domain"] where name.lowercased().hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
            }
            finish(name == ip || name.isEmpty ? nil : name)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(nil) }
    }
}

func ipv4String(_ data: Data) -> String? {
    data.withUnsafeBytes { raw -> String? in
        guard let base = raw.baseAddress, raw.count >= MemoryLayout<sockaddr_in>.size else { return nil }
        let sa = base.assumingMemoryBound(to: sockaddr.self).pointee
        guard sa.sa_family == sa_family_t(AF_INET) else { return nil }
        var addr = base.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
        return String(cString: buf)
    }
}
