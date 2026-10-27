import Foundation

enum Discovery {
    static let ports: [UInt16] = [23, 80, 554, 3000, 3001, 6466, 6668, 8001, 8008, 8009, 8060]

    static func scan(progress: @escaping (Double) -> Void) async -> [Device] {
        let hosts = subnetHosts()
        var found: [Device] = []
        var done = 0
        var idx = 0
        let chunk = 12
        while idx < hosts.count {
            let part = Array(hosts[idx..<min(idx + chunk, hosts.count)])
            idx += chunk
            await withTaskGroup(of: Device?.self) { g in
                for h in part { g.addTask { await Discovery.fingerprint(h) } }
                for await r in g { if let d = r { found.append(d) } }
            }
            done += part.count
            progress(Double(done) / Double(max(hosts.count, 1)))
        }
        return found
    }

    static func openPorts(_ ip: String) async -> [Int] {
        await withTaskGroup(of: Int?.self) { g in
            for p in ports {
                g.addTask { (await isOpen(ip, p, 0.7)) ? Int(p) : nil }
            }
            var r: [Int] = []
            for await x in g { if let x = x { r.append(x) } }
            return r.sorted()
        }
    }

    static func fingerprint(_ ip: String) async -> Device? {
        let open = await openPorts(ip)
        if open.isEmpty { return nil }
        var d = Device(ip: ip, name: ip, brand: .unknown, kind: .other)
        d.ports = open

        // Samsung Tizen
        if open.contains(8001), let r = try? await httpRequest("http://\(ip):8001/api/v2/"), r.1 == 200,
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
        if open.contains(80) {
            // Yamaha
            if let r = try? await httpRequest("http://\(ip)/YamahaExtendedControl/v1/system/getDeviceInfo"), r.1 == 200,
               let o = jsonObj(r.0), let model = o["model_name"] as? String {
                d.brand = .yamaha; d.kind = .receiver
                d.model = model; d.name = "Yamaha \(model)"
                return d
            }
            // Denon / Marantz
            if let r = try? await httpRequest("http://\(ip)/goform/Deviceinfo.xml"), r.1 == 200 {
                let s = String(decoding: r.0, as: UTF8.self)
                if s.contains("ModelName") || s.contains("DeviceInfo") {
                    d.brand = .denon; d.kind = .receiver
                    d.model = tag("ModelName", s) ?? ""
                    d.name = d.model.isEmpty ? "Denon/Marantz" : d.model
                    d.mac = tag("MacAddress", s) ?? ""
                    return d
                }
            }
            // Sony Bravia
            let body = Data(#"{"method":"getInterfaceInformation","id":33,"params":[],"version":"1.0"}"#.utf8)
            if let r = try? await httpRequest("http://\(ip)/sony/system", method: "POST", body: body), r.1 == 200,
               let o = jsonObj(r.0), let res = (o["result"] as? [[String: Any]])?.first {
                d.brand = .sony; d.kind = .tv
                d.model = (res["modelName"] as? String) ?? ""
                d.name = "Sony \(d.model)"
                return d
            }
        }
        // LG webOS
        if open.contains(3000) || open.contains(3001) {
            d.brand = .lg; d.kind = .tv; d.name = "LG webOS TV"
            return d
        }
        // Google Cast / Android TV / Google TV (טלוויזיות Philips, TCL, Hisense, Xiaomi ועוד)
        if open.contains(8008) || open.contains(8009) || open.contains(6466) {
            d.brand = .cast; d.kind = open.contains(6466) ? .tv : .streamer; d.name = "Google Cast"
            if let r = try? await httpRequest("http://\(ip):8008/setup/eureka_info?params=name,device_info"), r.1 == 200,
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
        if open.contains(6668) {
            d.brand = .tuya; d.kind = .plug; d.name = "Tuya \(ip)"
            return d
        }
        if open.contains(554) {
            d.brand = .camera; d.kind = .camera; d.name = "מצלמה \(ip)"
            return d
        }
        return nil
    }
}
