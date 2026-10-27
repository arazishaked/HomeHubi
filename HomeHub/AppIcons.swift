import Foundation

// MARK: - אייקונים של אפליקציות מהאינטרנט
//
// כשהטלוויזיה לא מעבירה אייקון (אפליקציות שנמצאו ב-DIAL, או Samsung שלא מחזירה רשימה),
// האפליקציה מורידה את האייקון הרשמי של אותה אפליקציה מ-App Store (iTunes Lookup API, ציבורי וללא מפתח).
// קודם לפי מזהה האפליקציה הידוע (מדויק), ואם אין — חיפוש לפי שם, רק כשהשם תואם.

enum OnlineIcons {
    /// מזהי App Store של אפליקציות הצפייה הנפוצות
    static let bundleIDs: [(match: String, bundle: String)] = [
        ("netflix", "com.netflix.Netflix"),
        ("disney", "com.disney.disneyplus"),
        ("prime video", "com.amazon.aiv.AIVApp"),
        ("amazon", "com.amazon.aiv.AIVApp"),
        ("youtube tv", "com.google.ios.youtubeunplugged"),
        ("youtube kids", "com.google.ios.youtubekids"),
        ("youtube music", "com.google.ios.youtubemusic"),
        ("youtube", "com.google.ios.youtube"),
        ("apple tv", "com.apple.tv"),
        ("hbo", "com.wbd.stream"),
        ("max", "com.wbd.stream"),
        ("spotify", "com.spotify.client"),
        ("plex", "com.plexapp.plex"),
        ("twitch", "tv.twitch"),
        ("hulu", "com.hulu.plus"),
        ("paramount", "com.cbsvideo.app"),
        ("pluto", "tv.pluto.ios"),
    ]

    /// אפליקציות מערכת שאין להן מקבילה ב-App Store — לא מחפשים להן אייקון כדי לא להציג אייקון שגוי
    static let systemNames = ["internet", "browser", "settings", "gallery", "media", "source", "guide", "store",
                              "apps", "live tv", "tv plus", "smartthings", "web browser", "usb", "photos", "music"]

    static func normalized(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "+", with: " plus").trimmingCharacters(in: .whitespaces)
    }

    static func bundleID(for name: String) -> String? {
        let n = normalized(name)
        return bundleIDs.first { n.contains($0.match) }?.bundle
    }

    private static func artwork(_ query: String) async -> (url: String, title: String)? {
        guard let r = try? await httpRequest(query, timeout: 6), r.1 == 200,
              let o = jsonObj(r.0), let first = (o["results"] as? [[String: Any]])?.first,
              let art = (first["artworkUrl512"] as? String) ?? (first["artworkUrl100"] as? String) else { return nil }
        return (art, (first["trackName"] as? String) ?? "")
    }

    /// האייקון הרשמי של אפליקציה לפי שמה, או nil אם לא נמצא בוודאות
    static func icon(for name: String) async -> Data? {
        let n = normalized(name)
        if n.count < 2 || systemNames.contains(where: { n == $0 || n.hasPrefix($0 + " ") }) { return nil }

        var found: (url: String, title: String)? = nil
        if let b = bundleID(for: name) {
            found = await artwork("https://itunes.apple.com/lookup?bundleId=\(b)&country=il")
            if found == nil { found = await artwork("https://itunes.apple.com/lookup?bundleId=\(b)") }
        }
        if found == nil, let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            // חיפוש לפי שם: מקבלים רק אם שם האפליקציה בחנות תואם לשם בטלוויזיה
            if let r = await artwork("https://itunes.apple.com/search?term=\(q)&entity=software&country=il&limit=1") {
                let t = normalized(r.title)
                let key = n.split(separator: " ").first.map(String.init) ?? n
                if t.contains(key) || n.contains(t.split(separator: " ").first.map(String.init) ?? t) { found = r }
            }
        }
        guard let f = found, let r = try? await httpRequest(f.url, timeout: 8), r.1 == 200, !r.0.isEmpty else { return nil }
        return r.0
    }
}
