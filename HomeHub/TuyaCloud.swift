import Foundation
import CommonCrypto

// MARK: - חשבון Tuya: שמות המפסקים, סוג כל מכשיר ומפתחות השליטה המקומית
//
// מכשירי Tuya לא מעבירים את השם שלהם ברשת – השם ("תאורת סלון", "דוד") שמור בחשבון Smart Life / Tuya.
// מתחברים פעם אחת עם Access ID ו-Access Secret של פרויקט ב-iot.tuya.com (שמקושר לחשבון Smart Life),
// ומקבלים לכל מכשיר: שם, סוג, Device ID ו-Local Key. אחרי זה השליטה כולה מקומית, בלי ענן.

struct TuyaCloudDevice: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var localKey: String
    var category: String
    var productName: String
    var online: Bool

    /// סוג המכשיר באפליקציה לפי הקטגוריה של Tuya
    var kind: Kind {
        switch category {
        case "dj", "dd", "fwd", "dc", "xdd", "fsd", "tgq", "tgkg", "tyndj", "gyd": return .light
        case "cl", "clkg", "mc", "ckmkzq": return .curtain
        case "kg", "cz", "pc", "tdq", "dlq", "qjdcz", "wkcz": return .plug
        case "sp", "dghsxj": return .camera
        case "wg2", "wfcon", "zigbee": return .hub
        default: return .plug
        }
    }

    /// מספר ה-DP שמדליק ומכבה (נורות משתמשות ב-20, מפסקים ושקעים ב-1)
    var powerDP: String { kind == .light && ["dj", "dd", "fwd", "xdd", "fsd", "gyd"].contains(category) ? "20" : "1" }
}

enum TuyaCloud {
    static let regions: [(id: String, title: String, host: String)] = [
        ("eu", "אירופה וישראל", "https://openapi.tuyaeu.com"),
        ("us", "ארה\"ב", "https://openapi.tuyaus.com"),
        ("cn", "סין", "https://openapi.tuyacn.com"),
        ("in", "הודו", "https://openapi.tuyain.com"),
    ]

    private static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    private static func sha256(_ d: Data) -> String {
        var out = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        d.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(d.count), &out) }
        return hex(Data(out))
    }

    private static func hmac(_ key: String, _ msg: String) -> String {
        let k = Data(key.utf8), m = Data(msg.utf8)
        var out = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        k.withUnsafeBytes { kp in
            m.withUnsafeBytes { mp in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), kp.baseAddress, k.count, mp.baseAddress, m.count, &out)
            }
        }
        return hex(Data(out)).uppercased()
    }

    /// בקשה חתומה ל-Tuya OpenAPI
    static func call(host: String, id: String, secret: String, token: String?, path: String,
                     method: String = "GET", body: Data? = nil) async throws -> [String: Any] {
        let t = String(Int(Date().timeIntervalSince1970 * 1000))
        let nonce = UUID().uuidString
        let stringToSign = method + "\n" + sha256(body ?? Data()) + "\n\n" + path
        let sign = hmac(secret, id + (token ?? "") + t + nonce + stringToSign)
        var headers = ["client_id": id, "t": t, "nonce": nonce, "sign": sign, "sign_method": "HMAC-SHA256"]
        if let token = token { headers["access_token"] = token }
        if body != nil { headers["Content-Type"] = "application/json" }
        let r = try await httpRequest(host + path, method: method, headers: headers, body: body, timeout: 10)
        guard let o = jsonObj(r.0) else { throw HHError.msg("תשובה לא תקינה מ-Tuya") }
        if (o["success"] as? Bool) != true {
            let msg = (o["msg"] as? String) ?? "שגיאה"
            throw HHError.msg("Tuya: \(msg)")
        }
        return o
    }

    /// כל המכשירים בחשבון, עם שמות ומפתחות
    static func fetchDevices(region: String, accessID: String, secret: String, anyDeviceID: String?) async throws -> [TuyaCloudDevice] {
        guard let host = regions.first(where: { $0.id == region })?.host else { throw HHError.msg("אזור לא מוכר") }
        let tok = try await call(host: host, id: accessID, secret: secret, token: nil, path: "/v1.0/token?grant_type=1")
        guard let token = (tok["result"] as? [String: Any])?["access_token"] as? String else {
            throw HHError.msg("Tuya לא החזירה הרשאה. בדוק את ה-Access ID וה-Secret")
        }

        func parse(_ list: [[String: Any]]) -> [TuyaCloudDevice] {
            list.compactMap { o in
                guard let id = o["id"] as? String else { return nil }
                return TuyaCloudDevice(id: id, name: (o["name"] as? String) ?? id, localKey: (o["local_key"] as? String) ?? "",
                                       category: (o["category"] as? String) ?? "", productName: (o["product_name"] as? String) ?? "",
                                       online: (o["online"] as? Bool) ?? false)
            }
        }

        // 1. מכשירים של חשבונות Smart Life שמקושרים לפרויקט
        var all: [TuyaCloudDevice] = []
        var lastKey = ""
        for _ in 0..<10 {
            let path = "/v1.0/iot-01/associated-users/devices?last_row_key=\(lastKey)&size=100"
            guard let o = try? await call(host: host, id: accessID, secret: secret, token: token, path: path),
                  let res = o["result"] as? [String: Any] else { break }
            all += parse((res["devices"] as? [[String: Any]]) ?? [])
            guard (res["has_more"] as? Bool) == true, let k = res["last_row_key"] as? String, !k.isEmpty else { break }
            lastKey = k
        }
        if !all.isEmpty { return all }

        // 2. דרך חלופית: לפי Device ID של מכשיר אחד מוצאים את המשתמש ואת כל המכשירים שלו
        guard let dev = anyDeviceID, !dev.isEmpty else {
            throw HHError.msg("לא נמצאו מכשירים. ודא שחשבון Smart Life מקושר לפרויקט (Devices ← Link App Account), או הזן Device ID של מכשיר אחד")
        }
        let one = try await call(host: host, id: accessID, secret: secret, token: token, path: "/v1.0/devices/\(dev)")
        guard let uid = (one["result"] as? [String: Any])?["uid"] as? String else { throw HHError.msg("המכשיר לא נמצא בחשבון") }
        let list = try await call(host: host, id: accessID, secret: secret, token: token, path: "/v1.0/users/\(uid)/devices")
        return parse((list["result"] as? [[String: Any]]) ?? [])
    }
}


// MARK: - שליטה דרך חשבון Tuya (לכל מכשיר: Zigbee, מפסקים מרובי ערוצים, פרוטוקולים חדשים)

/// ערוץ אחד במכשיר Tuya: מפסק 3 ערוצים = 3 ערוצים, כל אחד עם השם שלו ("סלון", "מטבח", "מרפסת")
struct TuyaChannel: Hashable {
    var code: String
    var name: String
}

actor TuyaSession {
    static let shared = TuyaSession()

    private var token: String?
    private var tokenExpiry = Date.distantPast
    private var statusCache: [String: [String: Any]] = [:]
    private var statusTime: [String: Date] = [:]
    private var known: Set<String> = []
    private var fetching: Task<Void, Never>?

    private struct Creds { let host: String; let id: String; let secret: String }

    private func creds() throws -> Creds {
        let ud = UserDefaults.standard
        let region = ud.string(forKey: "tuyaRegion") ?? "eu"
        let id = (ud.string(forKey: "tuyaAccessID") ?? "").trimmingCharacters(in: .whitespaces)
        let secret = (ud.string(forKey: "tuyaSecret") ?? "").trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !secret.isEmpty, let host = TuyaCloud.regions.first(where: { $0.id == region })?.host else {
            throw HHError.msg("חשבון Tuya לא מחובר (הגדרות ← חשבון Tuya)")
        }
        return Creds(host: host, id: id, secret: secret)
    }

    private func validToken(_ c: Creds) async throws -> String {
        if let t = token, Date() < tokenExpiry { return t }
        let o = try await TuyaCloud.call(host: c.host, id: c.id, secret: c.secret, token: nil, path: "/v1.0/token?grant_type=1")
        guard let res = o["result"] as? [String: Any], let t = res["access_token"] as? String else {
            throw HHError.msg("Tuya לא החזירה הרשאה")
        }
        token = t
        tokenExpiry = Date().addingTimeInterval(Double((res["expire_time"] as? Int) ?? 3600) - 120)
        return t
    }

    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        let c = try creds()
        let tok = try await validToken(c)
        let data = body.map { Data(jsonString($0).utf8) }
        do {
            return try await TuyaCloud.call(host: c.host, id: c.id, secret: c.secret, token: tok, path: path, method: method, body: data)
        } catch {
            token = nil   // הרשאה פגה: מנסים פעם אחת עם הרשאה חדשה
            let tok2 = try await validToken(c)
            return try await TuyaCloud.call(host: c.host, id: c.id, secret: c.secret, token: tok2, path: path, method: method, body: data)
        }
    }

    /// טוען בבת אחת את המצב של כל המכשירים ברשימה
    func prefetch(_ ids: [String]) async {
        known.formUnion(ids)
        await fetchBatch(Array(known))
    }

    /// מצב המכשיר (code → value). כל המכשירים נמשכים יחד בבקשה אחת, פעם בדקה לכל היותר
    func status(_ id: String, maxAge: TimeInterval = 60) async -> [String: Any]? {
        known.insert(id)
        if let t = statusTime[id], Date().timeIntervalSince(t) < maxAge { return statusCache[id] }
        if let f = fetching { await f.value; return statusCache[id] }
        let ids = Array(known)
        let task = Task { await self.fetchBatch(ids) }
        fetching = task
        await task.value
        fetching = nil
        return statusCache[id]
    }

    private func fetchBatch(_ ids: [String]) async {
        var i = 0
        while i < ids.count {
            let part = ids[i..<min(i + 20, ids.count)].joined(separator: ",")
            i += 20
            guard let o = try? await request("/v1.0/iot-03/devices/status?device_ids=\(part)"),
                  let list = o["result"] as? [[String: Any]] else { continue }
            for d in list {
                guard let id = d["id"] as? String else { continue }
                var map: [String: Any] = [:]
                for s in (d["status"] as? [[String: Any]]) ?? [] {
                    if let code = s["code"] as? String { map[code] = s["value"] }
                }
                statusCache[id] = map
                statusTime[id] = Date()
            }
        }
    }

    func send(_ id: String, _ code: String, _ value: Any) async throws {
        _ = try await request("/v1.0/devices/\(id)/commands", method: "POST",
                              body: ["commands": [["code": code, "value": value]]])
        statusTime[id] = nil
        if var m = statusCache[id] { m[code] = value; statusCache[id] = m }
    }

    /// שמות הערוצים של מפסק מרובה ערוצים, כפי שנקבעו ב-Smart Life
    func channelNames(_ id: String) async -> [String: String] {
        guard let o = try? await request("/v1.0/devices/\(id)/multiple-names"),
              let res = o["result"] as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in res { if let n = v as? String, !n.isEmpty { out[k] = n } }
        return out
    }
}

extension TuyaCloudDevice {
    /// הערוצים שאפשר להדליק ולכבות, לפי קודי המצב של המכשיר
    func channels(status: [String: Any], names: [String: String]) -> [TuyaChannel] {
        let codes = status.keys.filter { $0 == "switch" || $0 == "switch_led" || $0.hasPrefix("switch_") && Int($0.dropFirst(7)) != nil }
            .sorted { a, b in (Int(a.split(separator: "_").last ?? "") ?? 0) < (Int(b.split(separator: "_").last ?? "") ?? 0) }
        if codes.count <= 1 { return [TuyaChannel(code: codes.first ?? (kind == .curtain ? "control" : "switch_1"), name: name)] }
        return codes.enumerated().map { i, c in TuyaChannel(code: c, name: names[c] ?? "\(name) \(i + 1)") }
    }
}
