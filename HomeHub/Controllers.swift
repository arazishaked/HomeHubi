import Foundation
import CommonCrypto

enum RemoteKey { case volUp, volDown, mute, home }
enum CoverCommand { case open, close, stop }

class Controller {
    var dev: Device
    let save: (String, String) -> Void

    init(_ d: Device, save: @escaping (String, String) -> Void) {
        dev = d
        self.save = save
    }

    /// מכשיר בלי ממשק שליטה: רק בודקים שהוא זמין ברשת
    func status() async -> Status {
        for p in dev.ports.prefix(2) {
            if await isOpen(dev.ip, UInt16(p), 1.0) { return Status(power: nil, reachable: true) }
        }
        return Status(power: nil, reachable: false)
    }
    func power(_ on: Bool) async throws { throw HHError.msg("לא נתמך במכשיר הזה") }
    func apps() async throws -> [AppInfo] { throw HHError.msg("לא נתמך במכשיר הזה") }
    func launch(_ app: AppInfo) async throws { throw HHError.msg("לא נתמך במכשיר הזה") }
    /// אייקונים של אפליקציות, לפי מזהה אפליקציה (PNG/JPEG)
    func icons(_ apps: [AppInfo]) async -> [String: Data] { await fetchIconURLs(apps, headers: [:]) }
    /// זיהוי המכשיר: שם, דגם, יצרן ומערכת הפעלה כפי שהמכשיר מדווח
    func identify() async -> DeviceIdentity { DeviceIdentity() }

    /// אפליקציות צפייה שהמכשיר מדווח עליהן ב-DIAL
    func dialApps() async -> [AppInfo] {
        guard let base = await Dial.findBase(dev) else { return [] }
        if dev.config["dialURL"] != base { save("dialURL", base) }
        return await Dial.installedApps(base: base)
    }

    /// פתיחת אפליקציה: דרך DIAL אם זו אפליקציה שנמצאה כך, אחרת בממשק של היצרן
    func openApp(_ app: AppInfo) async throws {
        if app.id.hasPrefix("dial:") {
            guard let base = await Dial.findBase(dev) else { throw HHError.msg("הטלוויזיה לא עונה ל-DIAL") }
            try await Dial.launch(base: base, appID: app.id)
        } else {
            try await launch(app)
        }
    }
    func setInput(_ name: String) async throws { throw HHError.msg("לא נתמך במכשיר הזה") }
    func inputList() async -> [String] { [] }
    func press(_ k: RemoteKey) async throws { throw HHError.msg("לא נתמך במכשיר הזה") }
    func cover(_ c: CoverCommand) async throws { throw HHError.msg("לא נתמך במכשיר הזה") }
    func setLevel(_ pct: Int) async throws { throw HHError.msg("לא נתמך במכשיר הזה") }
}

/// הורדת אייקונים מכתובות HTTP, עד 6 במקביל
func fetchIconURLs(_ apps: [AppInfo], headers: [String: String]) async -> [String: Data] {
    let list = apps.filter { $0.iconURL != nil }
    var out: [String: Data] = [:]
    var i = 0
    while i < list.count {
        let part = Array(list[i..<min(i + 6, list.count)])
        i += 6
        await withTaskGroup(of: (String, Data?).self) { g in
            for a in part {
                let url = a.iconURL!
                g.addTask {
                    guard let r = try? await httpRequest(url, headers: headers, timeout: 5), r.1 == 200, !r.0.isEmpty else {
                        return (a.id, nil)
                    }
                    return (a.id, r.0)
                }
            }
            for await (id, d) in g { if let d = d { out[id] = d } }
        }
    }
    return out
}

func makeController(_ d: Device, save: @escaping (String, String) -> Void) -> Controller {
    switch d.brand {
    case .samsung: return SamsungController(d, save: save)
    case .lg: return LGController(d, save: save)
    case .roku: return RokuController(d, save: save)
    case .sony: return SonyController(d, save: save)
    case .denon: return DenonController(d, save: save)
    case .yamaha: return YamahaController(d, save: save)
    case .tuya: return TuyaController(d, save: save)
    case .cast: return CastController(d, save: save)
    case .shelly: return ShellyController(d, save: save)
    case .sonoff: return SonoffController(d, save: save)
    case .camera:
        return CameraController(d, save: save)
    default: return Controller(d, save: save)
    }
}

let tvInputs = ["HDMI1", "HDMI2", "HDMI3", "HDMI4"]

// MARK: - Samsung (Tizen)

final class SamsungController: Controller {
    private func connect() async throws -> WS {
        let name = Data("HomeHub".utf8).base64EncodedString()
        var s = "wss://\(dev.ip):8002/api/v2/channels/samsung.remote.control?name=\(name)"
        if let t = dev.config["token"], !t.isEmpty { s += "&token=\(t)" }
        guard let url = URL(string: s) else { throw HHError.msg("כתובת לא תקינה") }
        let ws = WS(url: url)
        do {
            for _ in 0..<6 {
                let t = try await ws.recv(timeout: 30)
                guard let o = jsonObj(Data(t.utf8)) else { continue }
                let ev = o["event"] as? String
                if ev == "ms.channel.connect" {
                    if let d = o["data"] as? [String: Any], let tok = d["token"] as? String { save("token", tok) }
                    return ws
                }
                if ev == "ms.channel.unauthorized" { throw HHError.msg("הטלוויזיה דחתה את החיבור") }
            }
            throw HHError.msg("אשר את החיבור על מסך הטלוויזיה ונסה שוב")
        } catch {
            ws.close()
            throw error
        }
    }

    private func sendKey(_ key: String) async throws {
        let ws = try await connect()
        defer { ws.close() }
        let msg = #"{"method":"ms.remote.control","params":{"Cmd":"Click","DataOfCmd":"\#(key)","Option":"false","TypeOfRemote":"SendRemoteKey"}}"#
        try await ws.send(msg)
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    override func status() async -> Status {
        guard let r = try? await httpRequest("http://\(dev.ip):8001/api/v2/", timeout: 2), r.1 == 200,
              let o = jsonObj(r.0) else { return Status(power: false, reachable: false) }
        let state = ((o["device"] as? [String: Any])?["PowerState"] as? String) ?? "on"
        return Status(power: state == "on", reachable: true)
    }

    override func power(_ on: Bool) async throws {
        let st = await status()
        if on {
            if st.reachable { try await sendKey("KEY_POWER") }
            else if !dev.mac.isEmpty || !(dev.config["mac"] ?? "").isEmpty {
                sendWOL(mac: dev.config["mac"] ?? dev.mac)
            } else { throw HHError.msg("הטלוויזיה כבויה לגמרי. הוסף כתובת MAC בהגדרות להדלקה מרחוק") }
        } else {
            try await sendKey("KEY_POWER")
        }
    }

    override func apps() async throws -> [AppInfo] {
        let ws = try await connect()
        defer { ws.close() }
        try await ws.send(#"{"method":"ms.channel.emit","params":{"event":"ed.installedApp.get","to":"host"}}"#)
        for _ in 0..<10 {
            guard let t = try? await ws.recv(timeout: 6), let o = jsonObj(Data(t.utf8)) else { break }
            if (o["event"] as? String) == "ed.installedApp.get" {
                let list = ((o["data"] as? [String: Any])?["data"] as? [[String: Any]]) ?? []
                let apps: [AppInfo] = list.compactMap { a in
                    guard let id = a["appId"] as? String, let n = a["name"] as? String else { return nil }
                    return AppInfo(id: id, name: n, iconPath: a["icon"] as? String)
                }
                if !apps.isEmpty { return apps }
            }
        }
        // דגמים חדשים לא מחזירים רשימה: בודקים מול הטלוויזיה אילו אפליקציות מוכרות באמת מותקנות
        return await probeCatalog()
    }

    /// מזהי אפליקציות ידועים ב-Tizen; הטלוויזיה עונה 200 רק על מה שמותקן
    static let catalog: [(id: String, name: String)] = [
        ("3201907018807", "Netflix"), ("11101200001", "Netflix"),
        ("3201901017640", "Disney+"),
        ("3201910019365", "Prime Video"), ("3201512006785", "Prime Video"),
        ("111299001912", "YouTube"),
        ("3201807016597", "Apple TV"),
        ("3201601007230", "Max"),
        ("3201606009684", "Spotify"),
        ("3201512006963", "Plex"),
        ("3201707014489", "YouTube TV"),
        ("3201706012478", "Samsung TV Plus"),
        ("org.tizen.browser", "Internet"),
    ]

    private func probeCatalog() async -> [AppInfo] {
        let ip = dev.ip
        let found: [(Int, AppInfo)] = await withTaskGroup(of: (Int, AppInfo?).self) { g in
            for (i, e) in Self.catalog.enumerated() {
                g.addTask {
                    guard let r = try? await httpRequest("http://\(ip):8001/api/v2/applications/\(e.id)", timeout: 3),
                          r.1 == 200 else { return (i, nil) }
                    let name = (jsonObj(r.0)?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? e.name
                    return (i, AppInfo(id: e.id, name: name))
                }
            }
            var out: [(Int, AppInfo)] = []
            for await (i, a) in g { if let a = a { out.append((i, a)) } }
            return out
        }
        var seen = Set<String>()
        return found.sorted { $0.0 < $1.0 }.map { $0.1 }.filter { seen.insert($0.name.lowercased()).inserted }
    }

    override func identify() async -> DeviceIdentity {
        guard let r = try? await httpRequest("http://\(dev.ip):8001/api/v2/", timeout: 3), r.1 == 200,
              let o = jsonObj(r.0), let d = o["device"] as? [String: Any] else { return DeviceIdentity() }
        var id = DeviceIdentity(name: d["name"] as? String, model: d["modelName"] as? String, manufacturer: "Samsung",
                                os: d["OS"] as? String, mac: d["wifiMac"] as? String, isTV: true)
        if let t = d["type"] as? String, !t.lowercased().contains("tv") { id.isTV = nil }
        return id
    }

    override func icons(_ apps: [AppInfo]) async -> [String: Data] {
        let withPath = apps.filter { ($0.iconPath ?? "").isEmpty == false }
        guard !withPath.isEmpty, let ws = try? await connect() else { return [:] }
        defer { ws.close() }
        var out: [String: Data] = [:]
        for a in withPath {
            let msg = jsonString(["method": "ms.channel.emit",
                                  "params": ["event": "ed.apps.icon", "to": "host", "data": ["iconPath": a.iconPath!]]])
            guard (try? await ws.send(msg)) != nil else { break }
            for _ in 0..<4 {
                guard let t = try? await ws.recv(timeout: 4), let o = jsonObj(Data(t.utf8)) else { break }
                guard (o["event"] as? String) == "ed.apps.icon" else { continue }
                if let d = o["data"] as? [String: Any], let b64 = d["imageBase64"] as? String,
                   let img = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) {
                    out[a.id] = img
                }
                break
            }
        }
        return out
    }

    override func launch(_ app: AppInfo) async throws {
        if let r = try? await httpRequest("http://\(dev.ip):8001/api/v2/applications/\(app.id)", method: "POST"),
           (200..<300).contains(r.1) { return }
        let ws = try await connect()
        defer { ws.close() }
        let msg = jsonString(["method": "ms.channel.emit",
                              "params": ["event": "ed.apps.launch", "to": "host",
                                         "data": ["action_type": "DEEP_LINK", "appId": app.id]]])
        try await ws.send(msg)
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    override func setInput(_ name: String) async throws {
        let digits = name.filter { $0.isNumber }
        try await sendKey(digits.isEmpty ? "KEY_SOURCE" : "KEY_HDMI\(digits)")
    }

    override func inputList() async -> [String] { tvInputs }

    override func press(_ k: RemoteKey) async throws {
        switch k {
        case .volUp: try await sendKey("KEY_VOLUP")
        case .volDown: try await sendKey("KEY_VOLDOWN")
        case .mute: try await sendKey("KEY_MUTE")
        case .home: try await sendKey("KEY_HOME")
        }
    }
}

// MARK: - LG webOS

final class LGController: Controller {
    private let perms = ["LAUNCH", "LAUNCH_WEBAPP", "APP_TO_APP", "CONTROL_AUDIO", "CONTROL_POWER",
                         "CONTROL_INPUT_TV", "READ_APP_STATUS", "READ_RUNNING_APPS", "READ_INSTALLED_APPS",
                         "READ_INPUT_DEVICE_LIST", "READ_POWER_STATE", "READ_CURRENT_CHANNEL"]

    private func connect() async throws -> WS {
        let secure = dev.ports.contains(3001)
        guard let url = URL(string: secure ? "wss://\(dev.ip):3001" : "ws://\(dev.ip):3000") else {
            throw HHError.msg("כתובת לא תקינה")
        }
        let ws = WS(url: url)
        do {
            var payload: [String: Any] = ["forcePairing": false, "pairingType": "PROMPT",
                                          "manifest": ["manifestVersion": 1, "permissions": perms]]
            if let k = dev.config["clientKey"], !k.isEmpty { payload["client-key"] = k }
            try await ws.send(jsonString(["type": "register", "id": "reg0", "payload": payload]))
            for _ in 0..<6 {
                let t = try await ws.recv(timeout: 30)
                guard let o = jsonObj(Data(t.utf8)) else { continue }
                let type = o["type"] as? String
                if type == "registered" {
                    if let p = o["payload"] as? [String: Any], let k = p["client-key"] as? String { save("clientKey", k) }
                    return ws
                }
                if type == "error" { throw HHError.msg("הטלוויזיה דחתה את החיבור") }
            }
            throw HHError.msg("אשר את החיבור על מסך הטלוויזיה ונסה שוב")
        } catch {
            ws.close()
            throw error
        }
    }

    @discardableResult
    private func request(_ uri: String, _ payload: [String: Any] = [:]) async throws -> [String: Any] {
        let ws = try await connect()
        defer { ws.close() }
        try await ws.send(jsonString(["type": "request", "id": "r1", "uri": uri, "payload": payload]))
        for _ in 0..<6 {
            let t = try await ws.recv(timeout: 8)
            if let o = jsonObj(Data(t.utf8)), (o["id"] as? String) == "r1" {
                return (o["payload"] as? [String: Any]) ?? [:]
            }
        }
        throw HHError.msg("אין תגובה מהטלוויזיה")
    }

    override func status() async -> Status {
        let p: UInt16 = dev.ports.contains(3001) ? 3001 : 3000
        let up = await isOpen(dev.ip, p, 1.5)
        return Status(power: up, reachable: up)
    }

    override func power(_ on: Bool) async throws {
        if on {
            let mac = dev.config["mac"] ?? dev.mac
            if mac.isEmpty { throw HHError.msg("הוסף כתובת MAC של הטלוויזיה בהגדרות כדי להדליק מרחוק") }
            sendWOL(mac: mac)
        } else {
            try await request("ssap://system/turnOff")
        }
    }

    override func apps() async throws -> [AppInfo] {
        let p = try await request("ssap://com.webos.applicationManager/listLaunchPoints")
        let list = (p["launchPoints"] as? [[String: Any]]) ?? []
        return list.compactMap { a in
            guard let id = a["id"] as? String, let t = a["title"] as? String else { return nil }
            var icon = (a["largeIcon"] as? String) ?? (a["icon"] as? String)
            if let i = icon, i.hasPrefix("/") { icon = "http://\(dev.ip):3000\(i)" }
            return AppInfo(id: id, name: t, iconURL: icon)
        }
    }

    override func launch(_ app: AppInfo) async throws {
        try await request("ssap://system.launcher/launch", ["id": app.id])
    }

    override func identify() async -> DeviceIdentity {
        guard !(dev.config["clientKey"] ?? "").isEmpty,
              let p = try? await request("ssap://system/getSystemInfo") else {
            return DeviceIdentity(manufacturer: "LG", os: "webOS", isTV: true)
        }
        var id = DeviceIdentity(model: p["modelName"] as? String, manufacturer: "LG", os: "webOS", isTV: true)
        if let sw = try? await request("ssap://com.webos.service.update/getCurrentSWInformation"),
           let v = sw["product_name"] as? String { id.os = v }
        return id
    }

    override func setInput(_ name: String) async throws {
        let digits = name.filter { $0.isNumber }
        try await request("ssap://tv/switchInput", ["inputId": "HDMI_\(digits.isEmpty ? "1" : digits)"])
    }

    override func inputList() async -> [String] { tvInputs }

    override func press(_ k: RemoteKey) async throws {
        switch k {
        case .volUp: try await request("ssap://audio/volumeUp")
        case .volDown: try await request("ssap://audio/volumeDown")
        case .mute: try await request("ssap://audio/setMute", ["mute": true])
        case .home: try await request("ssap://system.launcher/launch", ["id": "com.webos.app.home"])
        }
    }
}

// MARK: - Roku

final class RokuController: Controller {
    private var base: String { "http://\(dev.ip):8060" }

    override func status() async -> Status {
        guard let r = try? await httpRequest("\(base)/query/device-info", timeout: 2), r.1 == 200 else {
            return Status(power: false, reachable: false)
        }
        let s = String(decoding: r.0, as: UTF8.self)
        let mode = tag("power-mode", s) ?? "PowerOn"
        return Status(power: mode == "PowerOn", reachable: true)
    }

    private func key(_ k: String) async throws {
        _ = try await httpRequest("\(base)/keypress/\(k)", method: "POST")
    }

    override func power(_ on: Bool) async throws { try await key(on ? "PowerOn" : "PowerOff") }

    override func apps() async throws -> [AppInfo] {
        let r = try await httpRequest("\(base)/query/apps")
        let s = String(decoding: r.0, as: UTF8.self)
        let re = try NSRegularExpression(pattern: #"<app id="([^"]+)"[^>]*>([^<]*)</app>"#)
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map {
            let id = ns.substring(with: $0.range(at: 1))
            return AppInfo(id: id,
                           name: ns.substring(with: $0.range(at: 2)).replacingOccurrences(of: "&amp;", with: "&"),
                           iconURL: "\(base)/query/icon/\(id)")
        }
    }

    override func launch(_ app: AppInfo) async throws {
        _ = try await httpRequest("\(base)/launch/\(app.id)", method: "POST")
    }

    override func identify() async -> DeviceIdentity {
        guard let r = try? await httpRequest("\(base)/query/device-info", timeout: 3), r.1 == 200 else { return DeviceIdentity() }
        let s = String(decoding: r.0, as: UTF8.self)
        return DeviceIdentity(name: tag("user-device-name", s) ?? tag("friendly-device-name", s),
                              model: tag("model-name", s), manufacturer: tag("vendor-name", s) ?? "Roku",
                              os: tag("software-version", s).map { "Roku OS \($0)" },
                              mac: tag("wifi-mac", s) ?? tag("ethernet-mac", s), isTV: tag("is-tv", s) == "true")
    }

    override func setInput(_ name: String) async throws { try await key("Input\(name.replacingOccurrences(of: " ", with: ""))") }
    override func inputList() async -> [String] { tvInputs }

    override func press(_ k: RemoteKey) async throws {
        switch k {
        case .volUp: try await key("VolumeUp")
        case .volDown: try await key("VolumeDown")
        case .mute: try await key("VolumeMute")
        case .home: try await key("Home")
        }
    }
}

// MARK: - Sony Bravia

final class SonyController: Controller {
    private func call(_ path: String, _ method: String, _ params: [Any]) async throws -> [String: Any] {
        guard let psk = dev.config["psk"], !psk.isEmpty else {
            throw HHError.msg("הגדר Pre-Shared Key בהגדרות הטלוויזיה (Network ← Home Network ← IP Control)")
        }
        let body = Data(jsonString(["method": method, "id": 1, "params": params, "version": "1.0"]).utf8)
        let r = try await httpRequest("http://\(dev.ip)/sony/\(path)", method: "POST",
                                      headers: ["X-Auth-PSK": psk], body: body)
        return jsonObj(r.0) ?? [:]
    }

    override func status() async -> Status {
        guard let o = try? await call("system", "getPowerStatus", []),
              let s = (o["result"] as? [[String: Any]])?.first?["status"] as? String else {
            return Status(power: nil, reachable: false)
        }
        return Status(power: s == "active", reachable: true)
    }

    override func power(_ on: Bool) async throws { _ = try await call("system", "setPowerStatus", [["status": on]]) }

    override func apps() async throws -> [AppInfo] {
        let o = try await call("appControl", "getApplicationList", [])
        let list = ((o["result"] as? [Any])?.first as? [[String: Any]]) ?? []
        return list.compactMap { a in
            guard let u = a["uri"] as? String, let t = a["title"] as? String else { return nil }
            let icon = (a["icon"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return AppInfo(id: u, name: t, iconURL: icon)
        }
    }

    override func launch(_ app: AppInfo) async throws { _ = try await call("appControl", "setActiveApp", [["uri": app.id]]) }

    override func icons(_ apps: [AppInfo]) async -> [String: Data] {
        await fetchIconURLs(apps, headers: dev.config["psk"].map { ["X-Auth-PSK": $0] } ?? [:])
    }

    override func identify() async -> DeviceIdentity {
        var id = DeviceIdentity(manufacturer: "Sony", isTV: true)
        let body = Data(#"{"method":"getInterfaceInformation","id":33,"params":[],"version":"1.0"}"#.utf8)
        if let r = try? await httpRequest("http://\(dev.ip)/sony/system", method: "POST", body: body, timeout: 3),
           let res = (jsonObj(r.0)?["result"] as? [[String: Any]])?.first {
            id.model = res["modelName"] as? String
            if let p = res["productName"] as? String { id.os = p }
        }
        if let o = try? await call("system", "getSystemInformation", []),
           let res = (o["result"] as? [[String: Any]])?.first {
            id.name = res["name"] as? String
            id.mac = res["macAddr"] as? String
            if let m = res["model"] as? String { id.model = m }
            if let g = res["generation"] as? String { id.os = "Android TV \(g)" }
        }
        return id
    }

    override func setInput(_ name: String) async throws {
        let digits = name.filter { $0.isNumber }
        _ = try await call("avContent", "setPlayContent", [["uri": "extInput:hdmi?port=\(digits.isEmpty ? "1" : digits)"]])
    }

    override func inputList() async -> [String] { tvInputs }

    override func press(_ k: RemoteKey) async throws {
        switch k {
        case .volUp: _ = try await call("audio", "setAudioVolume", [["target": "speaker", "volume": "+1"]])
        case .volDown: _ = try await call("audio", "setAudioVolume", [["target": "speaker", "volume": "-1"]])
        case .mute: _ = try await call("audio", "setAudioMute", [["status": true]])
        case .home: throw HHError.msg("לא נתמך")
        }
    }
}

// MARK: - Denon / Marantz

final class DenonController: Controller {
    private func talk(_ cmds: [String], read: Bool) async throws -> String {
        let t = TCP(host: dev.ip, port: 23)
        try await t.connect(timeout: 2)
        defer { t.close() }
        var out = ""
        for c in cmds {
            try await t.send(Data((c + "\r").utf8))
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        if read {
            for _ in 0..<4 {
                let d = await t.receive(max: 1024, timeout: 0.4)
                if d.isEmpty { break }
                out += String(decoding: d, as: UTF8.self)
            }
        }
        return out
    }

    override func status() async -> Status {
        guard let txt = try? await talk(["PW?", "SI?", "MV?"], read: true) else {
            return Status(power: false, reachable: false)
        }
        var st = Status(power: nil, reachable: true)
        for l in txt.split(whereSeparator: { $0 == "\r" || $0 == "\n" }) {
            let s = String(l)
            if s == "PWON" { st.power = true }
            else if s == "PWSTANDBY" { st.power = false }
            else if s.hasPrefix("SI") { st.input = String(s.dropFirst(2)) }
            else if s.hasPrefix("MV") && !s.hasPrefix("MVMAX") { st.volume = String(s.dropFirst(2)) }
        }
        return st
    }

    override func power(_ on: Bool) async throws {
        do { _ = try await talk([on ? "PWON" : "PWSTANDBY"], read: false) }
        catch {
            let mac = dev.config["mac"] ?? dev.mac
            if on && !mac.isEmpty { sendWOL(mac: mac) } else { throw error }
        }
    }

    override func setInput(_ name: String) async throws { _ = try await talk(["SI" + name.uppercased()], read: false) }

    override func identify() async -> DeviceIdentity {
        guard let r = try? await httpRequest("http://\(dev.ip)/goform/Deviceinfo.xml", timeout: 3), r.1 == 200 else {
            return DeviceIdentity()
        }
        let s = String(decoding: r.0, as: UTF8.self)
        let model = tag("ModelName", s)
        let brand = (tag("BrandCode", s) == "1") ? "Marantz" : "Denon"
        return DeviceIdentity(name: model.map { "\(brand) \($0)" }, model: model, manufacturer: brand,
                              mac: tag("MacAddress", s), isTV: false)
    }

    override func inputList() async -> [String] {
        ["TV", "GAME", "BD", "DVD", "SAT/CBL", "MPLAY", "CD", "AUX1", "AUX2", "NET", "TUNER", "PHONO", "USB/IPOD", "BT"]
    }

    override func press(_ k: RemoteKey) async throws {
        switch k {
        case .volUp: _ = try await talk(["MVUP"], read: false)
        case .volDown: _ = try await talk(["MVDOWN"], read: false)
        case .mute: _ = try await talk(["MUON"], read: false)
        case .home: throw HHError.msg("לא נתמך")
        }
    }
}

// MARK: - Yamaha

final class YamahaController: Controller {
    private func get(_ path: String) async throws -> [String: Any] {
        let r = try await httpRequest("http://\(dev.ip)/YamahaExtendedControl/v1\(path)")
        return jsonObj(r.0) ?? [:]
    }

    override func status() async -> Status {
        guard let o = try? await get("/main/getStatus") else { return Status(power: false, reachable: false) }
        let vol = (o["volume"] as? Int).map { String($0) }
        return Status(power: (o["power"] as? String) == "on", input: o["input"] as? String, volume: vol, reachable: true)
    }

    override func power(_ on: Bool) async throws { _ = try await get("/main/setPower?power=\(on ? "on" : "standby")") }
    override func setInput(_ name: String) async throws { _ = try await get("/main/setInput?input=\(name)") }

    override func identify() async -> DeviceIdentity {
        guard let o = try? await get("/system/getDeviceInfo") else { return DeviceIdentity() }
        let model = o["model_name"] as? String
        return DeviceIdentity(name: model.map { "Yamaha \($0)" }, model: model, manufacturer: "Yamaha",
                              os: (o["system_version"] as? Double).map { "MusicCast \($0)" }, isTV: false)
    }

    override func inputList() async -> [String] {
        guard let o = try? await get("/system/getFeatures"),
              let zones = o["zone"] as? [[String: Any]],
              let list = zones.first?["input_list"] as? [String] else { return [] }
        return list
    }

    override func press(_ k: RemoteKey) async throws {
        switch k {
        case .volUp: _ = try await get("/main/setVolume?volume=up&step=2")
        case .volDown: _ = try await get("/main/setVolume?volume=down&step=2")
        case .mute: _ = try await get("/main/setMute?enable=true")
        case .home: throw HHError.msg("לא נתמך")
        }
    }
}

// MARK: - Google Cast / Android TV / Google TV

final class CastController: Controller {
    private func eureka() async -> [String: Any]? {
        guard let r = try? await httpRequest("http://\(dev.ip):8008/setup/eureka_info?params=name,device_info,build_info",
                                             timeout: 2.5), r.1 == 200 else { return nil }
        return jsonObj(r.0)
    }

    override func status() async -> Status {
        let up = await eureka() != nil
        return Status(power: nil, reachable: up)
    }

    override func power(_ on: Bool) async throws {
        let mac = dev.config["mac"] ?? dev.mac
        if on, !mac.isEmpty { sendWOL(mac: mac); return }
        throw HHError.msg("הדלקה וכיבוי לא נתמכים במכשיר הזה")
    }

    override func apps() async throws -> [AppInfo] {
        let list = await dialApps()
        if list.isEmpty { throw HHError.msg("המכשיר לא דיווח על אפליקציות") }
        return list
    }

    override func launch(_ app: AppInfo) async throws {
        guard let base = await Dial.findBase(dev) else { throw HHError.msg("המכשיר לא עונה ל-DIAL") }
        try await Dial.launch(base: base, appID: app.id)
    }

    override func identify() async -> DeviceIdentity {
        guard let o = await eureka() else { return DeviceIdentity() }
        let info = o["device_info"] as? [String: Any] ?? [:]
        let maker = info["manufacturer"] as? String
        let model = info["model_name"] as? String
        let build = (o["build_info"] as? [String: Any])?["cast_build_revision"] as? String
        let isTV = maker.map { !$0.lowercased().contains("google") } ?? false
        return DeviceIdentity(name: o["name"] as? String,
                              model: [maker, model].compactMap { $0 }.joined(separator: " "),
                              manufacturer: maker, os: build.map { isTV ? "Google TV / Android TV · Cast \($0)" : "Cast \($0)" },
                              isTV: isTV)
    }
}

// MARK: - Shelly (מפסקים, דימרים ותריסים, Gen1 ו-Gen2+)

final class ShellyController: Controller {
    private var gen2: Bool { (Int(dev.config["gen"] ?? "1") ?? 1) >= 2 }
    private var base: String { "http://\(dev.ip)" }
    private var isLight: Bool { dev.kind == .light }
    private var isCover: Bool { dev.kind == .curtain || dev.kind == .blind }

    private func get(_ path: String) async throws -> [String: Any] {
        let r = try await httpRequest(base + path, timeout: 3)
        guard (200..<300).contains(r.1) else { throw HHError.msg("Shelly החזיר שגיאה \(r.1)") }
        return jsonObj(r.0) ?? [:]
    }

    override func status() async -> Status {
        if gen2 {
            let comp = isCover ? "Cover" : (isLight ? "Light" : "Switch")
            guard let o = try? await get("/rpc/\(comp).GetStatus?id=0") else { return Status(power: nil, reachable: false) }
            var st = Status(power: o["output"] as? Bool, reachable: true)
            if let b = o["brightness"] as? Int { st.level = b }
            if let pos = o["current_pos"] as? Int { st.level = pos }
            return st
        }
        guard let o = try? await get("/status") else { return Status(power: nil, reachable: false) }
        var st = Status(power: nil, reachable: true)
        if let relay = (o["relays"] as? [[String: Any]])?.first { st.power = relay["ison"] as? Bool }
        if let light = (o["lights"] as? [[String: Any]])?.first {
            st.power = light["ison"] as? Bool
            st.level = light["brightness"] as? Int
        }
        if let roller = (o["rollers"] as? [[String: Any]])?.first { st.level = roller["current_pos"] as? Int }
        return st
    }

    override func power(_ on: Bool) async throws {
        if isCover { try await cover(on ? .open : .close); return }
        if gen2 {
            _ = try await get("/rpc/\(isLight ? "Light" : "Switch").Set?id=0&on=\(on)")
        } else {
            _ = try await get("/\(isLight ? "light" : "relay")/0?turn=\(on ? "on" : "off")")
        }
    }

    override func setLevel(_ pct: Int) async throws {
        let p = max(0, min(100, pct))
        if isCover {
            _ = try await get(gen2 ? "/rpc/Cover.GoToPosition?id=0&pos=\(p)" : "/roller/0?go=to_pos&roller_pos=\(p)")
        } else {
            _ = try await get(gen2 ? "/rpc/Light.Set?id=0&on=true&brightness=\(max(1, p))" : "/light/0?turn=on&brightness=\(max(1, p))")
        }
    }

    override func cover(_ c: CoverCommand) async throws {
        let g1 = c == .open ? "open" : (c == .close ? "close" : "stop")
        let g2 = c == .open ? "Open" : (c == .close ? "Close" : "Stop")
        _ = try await get(gen2 ? "/rpc/Cover.\(g2)?id=0" : "/roller/0?go=\(g1)")
    }

    override func identify() async -> DeviceIdentity {
        guard let o = try? await get("/shelly") else { return DeviceIdentity() }
        var id = DeviceIdentity(model: (o["model"] as? String) ?? (o["type"] as? String), manufacturer: "Shelly",
                                os: (o["fw"] as? String) ?? (o["ver"] as? String), mac: o["mac"] as? String, isTV: false)
        if let n = o["name"] as? String, !n.isEmpty { id.name = n }
        else if !gen2, let s = try? await get("/settings"), let n = s["name"] as? String, !n.isEmpty { id.name = n }
        return id
    }
}

// MARK: - Sonoff (מצב LAN / DIY)

final class SonoffController: Controller {
    private func post(_ path: String, _ data: [String: Any]) async throws -> [String: Any] {
        let body = Data(jsonString(["deviceid": dev.config["id"] ?? "", "data": data]).utf8)
        let r = try await httpRequest("http://\(dev.ip):8081/zeroconf/\(path)", method: "POST",
                                      headers: ["Content-Type": "application/json"], body: body, timeout: 3)
        return jsonObj(r.0) ?? [:]
    }

    override func status() async -> Status {
        guard let o = try? await post("info", [:]) else { return Status(power: nil, reachable: false) }
        var data = o["data"] as? [String: Any] ?? [:]
        if let str = o["data"] as? String, let parsed = jsonObj(Data(str.utf8)) { data = parsed }
        return Status(power: (data["switch"] as? String).map { $0 == "on" }, reachable: true)
    }

    override func power(_ on: Bool) async throws { _ = try await post("switch", ["switch": on ? "on" : "off"]) }
}

// MARK: - Camera

final class CameraController: Controller {
    override func status() async -> Status {
        let up = await isOpen(dev.ip, 554, 1.5)
        return Status(power: up, reachable: up)
    }
}

// MARK: - Tuya (פרוטוקול מקומי 3.3)

private let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
    var c = UInt32(i)
    for _ in 0..<8 { c = (c & 1) == 1 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
    return c
}

private func crc32(_ d: Data) -> UInt32 {
    var c: UInt32 = 0xFFFFFFFF
    for b in d { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
    return ~c
}

private func be32(_ v: UInt32) -> Data {
    Data([UInt8(truncatingIfNeeded: v >> 24), UInt8(truncatingIfNeeded: v >> 16),
          UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v)])
}

private func aesECB(_ data: Data, key: Data, encrypt: Bool) -> Data? {
    let cap = data.count + kCCBlockSizeAES128
    var out = Data(count: cap)
    var outLen = 0
    let status: CCCryptorStatus = out.withUnsafeMutableBytes { outPtr in
        data.withUnsafeBytes { inPtr in
            key.withUnsafeBytes { keyPtr in
                CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                        keyPtr.baseAddress, key.count, nil,
                        inPtr.baseAddress, data.count,
                        outPtr.baseAddress, cap, &outLen)
            }
        }
    }
    guard status == kCCSuccess else { return nil }
    return out.prefix(outLen)
}

final class TuyaController: Controller {
    private var devId: String { dev.config["id"] ?? "" }
    private var key: String { dev.config["key"] ?? "" }
    private var isCover: Bool { dev.kind == .curtain || dev.kind == .blind }
    private var dps: String { dev.config["dps"] ?? (dev.kind == .light ? "20" : "1") }

    private func packet(cmd: UInt32, payload: Data) -> Data {
        var d = Data()
        d.append(be32(0x000055AA)); d.append(be32(1)); d.append(be32(cmd)); d.append(be32(UInt32(payload.count + 8)))
        d.append(payload)
        d.append(be32(crc32(d))); d.append(be32(0x0000AA55))
        return d
    }

    private func exchange(cmd: UInt32, json: String, versionHeader: Bool) async throws -> Data {
        guard key.utf8.count == 16, !devId.isEmpty else { throw HHError.msg("חסרים Device ID ו-Local Key בהגדרות") }
        guard let enc = aesECB(Data(json.utf8), key: Data(key.utf8), encrypt: true) else { throw HHError.msg("הצפנה נכשלה") }
        var payload = Data()
        if versionHeader { payload.append(Data("3.3".utf8)); payload.append(Data(count: 12)) }
        payload.append(enc)
        let t = TCP(host: dev.ip, port: 6668)
        try await t.connect(timeout: 2)
        defer { t.close() }
        try await t.send(packet(cmd: cmd, payload: payload))
        return await t.receive(max: 1024, timeout: 2)
    }

    private func readDPS() async throws -> [String: Any] {
        let r = try await exchange(cmd: 0x0a, json: jsonString(["gwId": devId, "devId": devId]), versionHeader: false)
        let b = [UInt8](r)
        guard b.count >= 28 else { throw HHError.msg("תגובה קצרה") }
        var len = 0
        for i in 12..<16 { len = (len << 8) + Int(b[i]) }
        let end = 8 + len
        guard end <= b.count, end > 20 else { throw HHError.msg("תגובה לא תקינה") }
        var body = Data(b[20..<end])
        if body.starts(with: Data("3.3".utf8)) { body = body.dropFirst(15) }
        guard let dec = aesECB(Data(body), key: Data(key.utf8), encrypt: false),
              let o = jsonObj(dec), let d = o["dps"] as? [String: Any] else { throw HHError.msg("פענוח נכשל") }
        return d
    }

    private func setDPS(_ d: [String: Any]) async throws {
        let j = jsonString(["devId": devId, "uid": devId, "t": String(Int(Date().timeIntervalSince1970)), "dps": d])
        _ = try await exchange(cmd: 0x07, json: j, versionHeader: true)
    }

    /// מכשיר שנשלט דרך חשבון Tuya (לא נמצא ברשת, Zigbee, או ערוץ במפסק מרובה ערוצים)
    private var cloud: Bool { dev.config["cloud"] == "1" }
    private var code: String { dev.config["code"] ?? "switch_1" }

    private func cloudStatus() async -> Status {
        guard let m = await TuyaSession.shared.status(devId) else { return Status(power: nil, reachable: false) }
        var st = Status(power: m[code] as? Bool, reachable: true)
        if isCover, let p = (m["percent_control"] ?? m["percent_state"]) as? Int { st.level = p }
        if let b = (m["bright_value_v2"] ?? m["bright_value"]) as? Int { st.level = max(1, min(100, b / 10)) }
        return st
    }

    override func status() async -> Status {
        if cloud { return await cloudStatus() }
        if key.isEmpty { return Status(power: nil, reachable: await isOpen(dev.ip, 6668, 1.5)) }
        guard let d = try? await readDPS() else { return Status(power: nil, reachable: false) }
        var st = Status(power: nil, reachable: true)
        if let v = d["1"] as? String, ["open", "close", "stop"].contains(v) {
            st.kindHint = .curtain
            if let p = d["2"] as? Int { st.level = p }
        } else if d["20"] != nil {
            st.kindHint = .light
            st.power = d["20"] as? Bool
            if let b = d["22"] as? Int { st.level = max(0, min(100, (b - 10) * 100 / 990)) }
        } else {
            st.kindHint = .plug
            st.power = d[dps] as? Bool
        }
        return st
    }

    override func power(_ on: Bool) async throws {
        if isCover { try await cover(on ? .open : .close); return }
        if cloud { try await TuyaSession.shared.send(devId, code, on); return }
        try await setDPS([dps: on])
    }

    override func cover(_ c: CoverCommand) async throws {
        var v = "stop"
        if c == .open { v = "open" } else if c == .close { v = "close" }
        if cloud { try await TuyaSession.shared.send(devId, "control", v); return }
        try await setDPS(["1": v])
    }

    override func setLevel(_ pct: Int) async throws {
        let p = max(0, min(100, pct))
        if cloud {
            if isCover { try await TuyaSession.shared.send(devId, "percent_control", p) }
            else { try await TuyaSession.shared.send(devId, "bright_value_v2", max(10, p * 10)) }
            return
        }
        if isCover { try await setDPS(["2": p]) }              // בחלק מהמנועים 100 = סגור
        else { try await setDPS(["22": 10 + p * 990 / 100]) }  // בהירות 10..1000
    }
}
