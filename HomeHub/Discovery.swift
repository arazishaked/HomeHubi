import Foundation

// MARK: - סריקת רשת: כל מכשיר שמחובר לרשת הביתית
//
// שלושה מקורות, ביחד:
// 1. Bonjour – מכשירים שמכריזים על עצמם (שם, סוג ודגם).
// 2. סריקת כתובות – כל כתובת ברשת נבדקת מול רשימת פורטים. גם פורט "סגור" שהמכשיר דוחה מעיד שהמכשיר קיים.
// 3. זיהוי לפי יצרן – לכל מכשיר חי בודקים את הממשקים המוכרים (Samsung, LG, Sony, Denon, Yamaha, Shelly...).
// מכשיר שלא זוהה מופיע בכל זאת, עם השם שהראוטר נתן לו.

enum Discovery {
    static let ports: [UInt16] = [23, 80, 443, 554, 1255, 1400, 1925, 1926, 3000, 3001, 5000, 6466, 6668,
                                  7000, 8001, 8002, 8008, 8009, 8060, 8080, 8081, 8443, 9197, 49152, 60006,
                                  60128, 62078]

    /// סורק את הרשת. כל מכשיר שזוהה נשלח מיד ל-onFound, כך שהרשימה מתמלאת תוך כדי סריקה
    static func scan(progress: @escaping (Double) -> Void, onFound: @escaping (Device) -> Void) async -> [Device] {
        // Bonjour רץ במקביל, ובסוף משלים שמות וסוגים
        let bonjourTask = Task { @MainActor in await BonjourScanner().run(seconds: 8) }
        let me = localIPv4().map { ipString($0.ip) }
        let hosts = subnetHosts().filter { $0 != me }
        var found: [String: Device] = [:]

        var idx = 0
        let chunk = 12
        while idx < hosts.count {
            let part = Array(hosts[idx..<min(idx + chunk, hosts.count)])
            idx += chunk
            await withTaskGroup(of: Device?.self) { g in
                for h in part {
                    g.addTask {
                        guard await Discovery.quickAlive(h) else { return nil }
                        let (_, open, _) = await Discovery.sweep(h)
                        return await Discovery.identify(h, open: open, bonjour: nil)
                    }
                }
                for await d in g {
                    if let d = d { found[d.ip] = d; onFound(d) }
                }
            }
            progress(Double(min(idx, hosts.count)) / Double(max(hosts.count, 1)) * 0.9)
        }

        // השלמה מ-Bonjour: שמות לכל מה שלא זוהה, ומכשירים שלא ענו בסריקה
        let bonjour = await bonjourTask.value
        for (ip, info) in bonjour where ip != me {
            let old = found[ip]
            let generic = old == nil || old!.brand == .unknown || old!.name.hasPrefix("מכשיר ") || old!.name.hasSuffix(" \(ip)")
            guard generic else { continue }
            var open = old?.ports ?? []
            if old == nil { open = await Discovery.sweep(ip).1 }
            let d = await Discovery.identify(ip, open: open, bonjour: info)
            found[ip] = d
            onFound(d)
        }
        progress(1)
        return Array(found.values)
    }

    static let quickPorts: [UInt16] = [80, 443, 62078, 6668, 8008, 554, 3000]

    static func quickAlive(_ ip: String) async -> Bool {
        await withTaskGroup(of: ProbeResult.self) { g in
            for p in quickPorts { g.addTask { await probe(ip, p, 0.7) } }
            var ok = false
            for await r in g where r != .none { ok = true }
            return ok
        }
    }

    /// כל הפורטים של כתובת אחת במקביל. מחזיר את הפתוחים, והאם יש שם מכשיר בכלל
    static func sweep(_ ip: String) async -> (String, [Int], Bool) {
        await withTaskGroup(of: (UInt16, ProbeResult).self) { g in
            for p in ports { g.addTask { (p, await probe(ip, p, 0.9)) } }
            var open: [Int] = []
            var isAlive = false
            for await (p, r) in g {
                if r == .open { open.append(Int(p)); isAlive = true }
                if r == .refused { isAlive = true }
            }
            return (ip, open.sorted(), isAlive)
        }
    }

    static func identify(_ ip: String, open: [Int], bonjour: BonjourScanner.Info?) async -> Device {
        var d = await fingerprint(ip, open: open) ?? Device(ip: ip, name: "", brand: .unknown, kind: .other)
        d.ports = open
        let types = bonjour?.types ?? []
        let txt = bonjour?.txt ?? [:]
        func has(_ t: String) -> Bool { types.contains { $0.hasPrefix(t) } }

        // שם מ-Bonjour גובר על שמות כלליים
        if let n = bonjour?.name, !n.isEmpty, d.name.isEmpty || d.name == ip || d.brand == .unknown || d.name == "Google Cast" {
            d.name = n
        }

        // סיווג מכשירים שלא זוהו לפי היצרן
        if d.brand == .unknown {
            let model = txt["model"] ?? txt["md"] ?? txt["ty"] ?? ""
            if has("_airplay") || has("_raop") || has("_companion-link") || has("_mediaremotetv") {
                d.brand = .apple
                d.model = model
                if model.hasPrefix("AppleTV") { d.kind = .streamer }
                else if model.hasPrefix("AudioAccessory") { d.kind = .speaker }
                else if model.contains("Mac") { d.kind = .computer }
                else if open.contains(62078) { d.kind = .phone }
                else if has("_raop") { d.kind = .speaker }
            } else if open.contains(62078) {
                d.brand = .apple; d.kind = .phone
            } else if has("_sonos") || open.contains(1400) {
                d.brand = .sonos; d.kind = .speaker
            } else if has("_hue") {
                d.brand = .hue; d.kind = .hub
            } else if has("_ipp") || has("_printer") || has("_pdl-datastream") {
                d.kind = .printer; d.model = model
            } else if has("_hap") || has("_homekit") || has("_matter") || has("_esphomelib") || has("_wled") {
                d.kind = .plug; d.model = model
            } else if has("_spotify-connect") || has("_heos-audio") {
                d.kind = .speaker
            } else if has("_smb") || has("_workstation") || has("_ssh") || has("_rfb") {
                d.kind = .computer
            } else if open.contains(1925) || open.contains(1926) {
                d.brand = .philips; d.kind = .tv; if d.name.isEmpty { d.name = "Philips TV" }
            } else if open.contains(60128) {
                d.brand = .onkyo; d.kind = .receiver; if d.name.isEmpty { d.name = "Onkyo / Pioneer" }
            } else if open.contains(554) {
                d.brand = .camera; d.kind = .camera
            }
        }

        // שם מהראוטר, ואם אין – כותרת דף הניהול של המכשיר
        if d.name.isEmpty || d.name == ip {
            if let n = await reverseName(ip) { d.name = n }
        }
        if (d.name.isEmpty || d.name == ip), open.contains(80),
           let r = try? await httpRequest("http://\(ip)/", timeout: 1.5), let t = tag("title", String(decoding: r.0, as: UTF8.self)) {
            d.name = t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if d.name.isEmpty || d.name == ip {
            d.name = d.kind == .other ? "מכשיר \(ip)" : "\(d.kind.title) \(ip)"
        }
        return d
    }

    /// זיהוי לפי הממשקים של יצרנים מוכרים
    static func fingerprint(_ ip: String, open: [Int]) async -> Device? {
        var d = Device(ip: ip, name: ip, brand: .unknown, kind: .other)

        // Samsung Tizen
        if open.contains(8001) || open.contains(8002), let r = try? await httpRequest("http://\(ip):8001/api/v2/"), r.1 == 200,
           let o = jsonObj(r.0), let dev = o["device"] as? [String: Any] {
            d.brand = .samsung; d.kind = .tv
            d.name = (dev["name"] as? String) ?? "Samsung TV"
            d.model = (dev["modelName"] as? String) ?? ""
            d.mac = (dev["wifiMac"] as? String) ?? ""
            return d
        }
        // Roku
        if open.contains(8060), let r = try? await httpRequest("http://\(ip):8060/query/device-info"), r.1 == 200 {
            let s = String(decoding: r.0, as: UTF8.self)
            d.brand = .roku
            d.kind = (tag("is-tv", s) == "true") ? .tv : .streamer
            d.name = tag("user-device-name", s) ?? tag("friendly-device-name", s) ?? "Roku"
            d.model = tag("model-name", s) ?? ""
            d.mac = tag("wifi-mac", s) ?? ""
            return d
        }
        // Denon / Marantz (דגמים ישנים בפורט 80, חדשים בפורט 8080)
        for port in [80, 8080] where open.contains(port) {
            if let r = try? await httpRequest("http://\(ip):\(port)/goform/Deviceinfo.xml", timeout: 2), r.1 == 200 {
                let s = String(decoding: r.0, as: UTF8.self)
                if s.contains("ModelName") || s.contains("DeviceInfo") {
                    d.brand = .denon; d.kind = .receiver
                    d.model = tag("ModelName", s) ?? ""
                    d.name = d.model.isEmpty ? "Denon/Marantz" : d.model
                    d.mac = tag("MacAddress", s) ?? ""
                    return d
                }
            }
        }
        // Denon / Marantz עם HEOS
        if open.contains(60006), let r = try? await httpRequest("http://\(ip):60006/upnp/desc/aios_device/aios_device.xml", timeout: 2),
           r.1 == 200 {
            let s = String(decoding: r.0, as: UTF8.self)
            d.brand = .denon; d.kind = .receiver
            d.model = tag("modelName", s) ?? ""
            d.name = tag("friendlyName", s) ?? (d.model.isEmpty ? "Denon/Marantz" : d.model)
            return d
        }
        if open.contains(80) {
            // Yamaha MusicCast
            if let r = try? await httpRequest("http://\(ip)/YamahaExtendedControl/v1/system/getDeviceInfo", timeout: 2), r.1 == 200,
               let o = jsonObj(r.0), let model = o["model_name"] as? String {
                d.brand = .yamaha; d.kind = .receiver
                d.model = model; d.name = "Yamaha \(model)"
                return d
            }
            // Shelly
            if let r = try? await httpRequest("http://\(ip)/shelly", timeout: 2), r.1 == 200, let o = jsonObj(r.0),
               o["type"] != nil || o["gen"] != nil || o["model"] != nil {
                d.brand = .shelly
                let gen = (o["gen"] as? Int) ?? 1
                d.config["gen"] = String(gen)
                let type = (o["type"] as? String) ?? (o["model"] as? String) ?? (o["app"] as? String) ?? ""
                d.model = type
                let t = type.lowercased()
                d.kind = (t.contains("dimmer") || t.contains("bulb") || t.contains("rgbw") || t.contains("duo") || t.contains("vintage")) ? .light : .plug
                d.mac = (o["mac"] as? String) ?? ""
                if let n = o["name"] as? String, !n.isEmpty { d.name = n }
                else if gen == 1, let s = try? await httpRequest("http://\(ip)/settings", timeout: 2), let so = jsonObj(s.0) {
                    if let n = so["name"] as? String, !n.isEmpty { d.name = n }
                    if (so["mode"] as? String) == "roller" { d.kind = .curtain }
                } else { d.name = "Shelly \(type)" }
                return d
            }
            // Philips Hue bridge
            if let r = try? await httpRequest("http://\(ip)/api/config", timeout: 2), r.1 == 200, let o = jsonObj(r.0),
               o["bridgeid"] != nil {
                d.brand = .hue; d.kind = .hub
                d.name = (o["name"] as? String) ?? "Hue Bridge"
                d.model = (o["modelid"] as? String) ?? ""
                d.mac = (o["mac"] as? String) ?? ""
                return d
            }
            // Sony Bravia
            let body = Data(#"{"method":"getInterfaceInformation","id":33,"params":[],"version":"1.0"}"#.utf8)
            if let r = try? await httpRequest("http://\(ip)/sony/system", method: "POST", body: body, timeout: 2), r.1 == 200,
               let o = jsonObj(r.0), let res = (o["result"] as? [[String: Any]])?.first {
                d.brand = .sony; d.kind = .tv
                d.model = (res["modelName"] as? String) ?? ""
                d.name = "Sony \(d.model)"
                return d
            }
        }
        // Sonoff במצב LAN / DIY
        if open.contains(8081) {
            let body = Data(#"{"deviceid":"","data":{}}"#.utf8)
            if let r = try? await httpRequest("http://\(ip):8081/zeroconf/info", method: "POST",
                                              headers: ["Content-Type": "application/json"], body: body, timeout: 2),
               r.1 == 200, jsonObj(r.0) != nil {
                d.brand = .sonoff; d.kind = .plug; d.name = "Sonoff \(ip)"
                return d
            }
        }
        // Sonos
        if open.contains(1400), let r = try? await httpRequest("http://\(ip):1400/xml/device_description.xml", timeout: 2), r.1 == 200 {
            let s = String(decoding: r.0, as: UTF8.self)
            d.brand = .sonos; d.kind = .speaker
            d.model = tag("modelName", s) ?? ""
            d.name = tag("roomName", s) ?? tag("friendlyName", s) ?? "Sonos"
            return d
        }
        // LG webOS
        if open.contains(3000) || open.contains(3001) {
            d.brand = .lg; d.kind = .tv; d.name = "LG webOS TV"
            return d
        }
        // Google Cast / Android TV / Google TV
        if open.contains(8008) || open.contains(8009) || open.contains(6466) {
            d.brand = .cast; d.kind = open.contains(6466) ? .tv : .streamer; d.name = "Google Cast"
            if let r = try? await httpRequest("http://\(ip):8008/setup/eureka_info?params=name,device_info", timeout: 2), r.1 == 200,
               let o = jsonObj(r.0) {
                if let n = o["name"] as? String { d.name = n }
                let info = o["device_info"] as? [String: Any] ?? [:]
                let maker = info["manufacturer"] as? String ?? ""
                let model = info["model_name"] as? String ?? ""
                d.model = [maker, model].filter { !$0.isEmpty }.joined(separator: " ")
                if !maker.isEmpty && !maker.lowercased().contains("google") { d.kind = .tv }
            }
            return d
        }
        // Tuya: מפסקים, שקעים, נורות, וילונות (השם האמיתי מגיע מחשבון Tuya)
        if open.contains(6668) {
            d.brand = .tuya; d.kind = .plug; d.name = ""
            return d
        }
        return nil
    }
}
