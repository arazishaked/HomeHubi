import Foundation

// MARK: - Bonjour (mDNS): מכשירים שמכריזים על עצמם ברשת
//
// רוב המכשירים החכמים מכריזים על עצמם: Chromecast, Apple TV, HomePod, Sonos, רסיברים, מדפסות, Shelly, Hue,
// HomeKit ועוד. ההכרזה כוללת שם ודגם. כל סוג שירות חייב להופיע גם ב-NSBonjourServices ב-Info.plist.

final class BonjourScanner: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    struct Info {
        var name: String
        var types: Set<String> = []
        var txt: [String: String] = [:]
    }

    static let types = [
        "_googlecast._tcp.", "_airplay._tcp.", "_raop._tcp.", "_companion-link._tcp.", "_hap._tcp.",
        "_homekit._tcp.", "_spotify-connect._tcp.", "_sonos._tcp.", "_heos-audio._tcp.", "_androidtvremote2._tcp.",
        "_amzn-wplay._tcp.", "_http._tcp.", "_ipp._tcp.", "_printer._tcp.", "_pdl-datastream._tcp.",
        "_hue._tcp.", "_shelly._tcp.", "_ewelink._tcp.", "_esphomelib._tcp.", "_matter._tcp.",
        "_smb._tcp.", "_workstation._tcp.", "_ssh._tcp.", "_rfb._tcp.", "_device-info._tcp.",
        "_daap._tcp.", "_touch-able._tcp.", "_mediaremotetv._tcp.", "_viziocast._tcp.", "_rtsp._tcp.",
        "_ewelink._tcp.", "_miio._udp.", "_elg._tcp.", "_wled._tcp.", "_lgsmarttv._tcp."
    ]

    private var browsers: [NetServiceBrowser] = []
    private var services: [NetService] = []
    private(set) var found: [String: Info] = [:]

    /// סורק את כל סוגי השירותים במשך מספר שניות ומחזיר מידע לפי כתובת IP
    @MainActor
    func run(seconds: Double) async -> [String: Info] {
        for t in Set(Self.types) {
            let b = NetServiceBrowser()
            b.delegate = self
            b.searchForServices(ofType: t, inDomain: "local.")
            browsers.append(b)
        }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        browsers.forEach { $0.stop() }
        services.forEach { $0.stop() }
        return found
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 4)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addrs = sender.addresses else { return }
        var txt: [String: String] = [:]
        if let d = sender.txtRecordData() {
            for (k, v) in NetService.dictionary(fromTXTRecord: d) {
                txt[k] = String(decoding: v, as: UTF8.self)
            }
        }
        var name = sender.name
        if let at = name.firstIndex(of: "@") { name = String(name[name.index(after: at)...]) }   // "MAC@שם" ב-AirPlay
        if let fn = txt["fn"], !fn.isEmpty { name = fn }                                          // שם ידידותי ב-Cast
        for a in addrs {
            guard let ip = ipv4String(a) else { continue }
            var info = found[ip] ?? Info(name: name)
            info.types.insert(sender.type)
            info.txt.merge(txt) { old, _ in old }
            if sender.type.hasPrefix("_googlecast") || info.name.isEmpty { info.name = name }
            found[ip] = info
        }
    }
}
