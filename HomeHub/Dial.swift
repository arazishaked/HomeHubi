import Foundation

// MARK: - DIAL: גילוי והפעלה של אפליקציות צפייה
//
// רוב הטלוויזיות החכמות (Samsung, LG, Sony, Android/Google TV, Roku, Chromecast) מריצות שרת DIAL —
// הפרוטוקול שבו Netflix ו-YouTube "משדרים" לטלוויזיה. שאילתה GET על שם אפליקציה מחזירה 200 אם היא מותקנת,
// ו-POST מפעיל אותה. כך האפליקציה לומדת לבד מה מותקן, גם בטלוויזיות שלא מחזירות רשימה מלאה.

enum Dial {
    /// כתובות DIAL ידועות לפי יצרן (ללא SSDP, כי שליחת multicast ב-iOS דורשת הרשאה מיוחדת מאפל)
    static func candidateBases(_ d: Device) -> [String] {
        let ip = d.ip
        let all = [
            "http://\(ip):8080/ws/apps/",   // Samsung Tizen
            "http://\(ip):36866/apps/",     // LG webOS
            "http://\(ip):8008/apps/",      // Android TV / Google TV / Chromecast
            "http://\(ip):8060/dial/",      // Roku
            "http://\(ip)/DIAL/apps/",      // Sony Bravia
            "http://\(ip):56789/apps/",     // דגמים נוספים
        ]
        switch d.brand {
        case .samsung: return [all[0]] + all.filter { $0 != all[0] }
        case .lg: return [all[1]] + all.filter { $0 != all[1] }
        case .cast: return [all[2]] + all.filter { $0 != all[2] }
        case .roku: return [all[3]]
        case .sony: return [all[4], all[2]] + all.filter { $0 != all[4] && $0 != all[2] }
        default: return all
        }
    }

    /// קטלוג אפליקציות צפייה: שם תצוגה + שמות DIAL אפשריים (הראשון שעונה 200 מנצח)
    static let catalog: [(name: String, dial: [String])] = [
        ("Netflix", ["Netflix"]),
        ("YouTube", ["YouTube"]),
        ("Prime Video", ["AmazonInstantVideo", "PrimeVideo", "com.amazon.amazonvideo.livingroom"]),
        ("Disney+", ["com.disney.disneyplus-prod", "DisneyPlus", "Disney+"]),
        ("Apple TV", ["com.apple.appletv", "AppleTV"]),
        ("Max", ["Max", "HBOMax", "com.hbo.hbonow"]),
        ("Spotify", ["spotify", "Spotify", "com.spotify.Spotify.TVv2"]),
        ("YouTube TV", ["YouTubeTV"]),
        ("YouTube Kids", ["YouTubeKids"]),
        ("YouTube Music", ["YouTubeMusic"]),
        ("Plex", ["Plex"]),
        ("Twitch", ["Twitch"]),
        ("Hulu", ["Hulu"]),
        ("Paramount+", ["CBSAllAccess", "ParamountPlus"]),
        ("Rakuten TV", ["RakutenTV"]),
        ("Pluto TV", ["PlutoTV"]),
    ]

    static func isInstalled(_ url: String) async -> Bool {
        guard let r = try? await httpRequest(url, timeout: 2.5) else { return false }
        guard r.1 == 200 else { return false }
        let s = String(decoding: r.0, as: UTF8.self)
        // תשובה תקינה היא XML עם <service> או <state>; כמה שרתים מחזירים גוף ריק
        return s.isEmpty || s.contains("<service") || s.contains("<state")
    }

    /// מוצא את כתובת שרת ה-DIAL של המכשיר (בודק YouTube, שכמעט תמיד קיים)
    static func findBase(_ d: Device) async -> String? {
        if let saved = d.config["dialURL"], !saved.isEmpty { return saved }
        for base in candidateBases(d) {
            for probe in ["YouTube", "Netflix"] {
                if await isInstalled(base + probe) { return base }
            }
        }
        return nil
    }

    /// אפליקציות הצפייה שמותקנות במכשיר, לפי DIAL
    static func installedApps(base: String) async -> [AppInfo] {
        await withTaskGroup(of: (Int, AppInfo?).self) { g in
            for (i, entry) in catalog.enumerated() {
                g.addTask {
                    for name in entry.dial {
                        if await isInstalled(base + name) { return (i, AppInfo(id: "dial:" + name, name: entry.name)) }
                    }
                    return (i, nil)
                }
            }
            var found: [(Int, AppInfo)] = []
            for await (i, a) in g { if let a = a { found.append((i, a)) } }
            return found.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    static func launch(base: String, appID: String) async throws {
        let name = appID.hasPrefix("dial:") ? String(appID.dropFirst(5)) : appID
        let r = try await httpRequest(base + name, method: "POST",
                                      headers: ["Content-Type": "text/plain; charset=utf-8"], body: Data(), timeout: 6)
        guard (200..<300).contains(r.1) else { throw HHError.msg("הטלוויזיה לא פתחה את האפליקציה (קוד \(r.1))") }
    }
}

// MARK: - זיהוי מכשיר: שם, דגם ומערכת הפעלה, ישירות מהמכשיר

struct DeviceIdentity {
    var name: String? = nil
    var model: String? = nil
    var manufacturer: String? = nil
    var os: String? = nil
    var mac: String? = nil
    var isTV: Bool? = nil
}
