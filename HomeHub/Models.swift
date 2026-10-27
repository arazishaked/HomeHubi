import Foundation

enum Brand: String, Codable, CaseIterable {
    case samsung, lg, roku, sony, denon, yamaha, onkyo, tuya, shelly, sonoff, hue, sonos, apple, philips, cast, camera, unknown
    var title: String {
        switch self {
        case .samsung: return "Samsung"
        case .lg: return "LG webOS"
        case .roku: return "Roku"
        case .sony: return "Sony Bravia"
        case .denon: return "Denon/Marantz"
        case .yamaha: return "Yamaha"
        case .onkyo: return "Onkyo / Pioneer"
        case .tuya: return "Tuya"
        case .shelly: return "Shelly"
        case .sonoff: return "Sonoff"
        case .hue: return "Philips Hue"
        case .sonos: return "Sonos"
        case .apple: return "Apple"
        case .philips: return "Philips TV"
        case .cast: return "Android TV / Cast"
        case .camera: return "מצלמה"
        case .unknown: return "לא מזוהה"
        }
    }
}

enum Kind: String, Codable, CaseIterable {
    case tv, receiver, streamer, speaker, light, curtain, blind, plug, camera, hub, computer, phone, printer, other
    var title: String {
        switch self {
        case .tv: return "טלוויזיה"
        case .receiver: return "רסיבר"
        case .streamer: return "סטרימר"
        case .light: return "מנורה"
        case .curtain: return "וילון"
        case .blind: return "תריס"
        case .plug: return "שקע / מפסק"
        case .camera: return "מצלמה"
        case .speaker: return "רמקול"
        case .hub: return "רכזת / גשר"
        case .computer: return "מחשב"
        case .phone: return "טלפון / טאבלט"
        case .printer: return "מדפסת"
        case .other: return "אחר"
        }
    }
    var icon: String {
        switch self {
        case .tv: return "tv"
        case .receiver: return "hifispeaker"
        case .streamer: return "play.rectangle"
        case .light: return "lightbulb"
        case .curtain, .blind: return "rectangle.split.3x1"
        case .plug: return "powerplug"
        case .camera: return "video"
        case .speaker: return "hifispeaker.2"
        case .hub: return "point.3.connected.trianglepath.dotted"
        case .computer: return "desktopcomputer"
        case .phone: return "iphone"
        case .printer: return "printer"
        case .other: return "wifi"
        }
    }
}

struct Device: Identifiable, Codable, Hashable {
    var ip: String
    var name: String
    var brand: Brand
    var kind: Kind
    var model: String = ""
    var mac: String = ""
    var ports: [Int] = []
    var config: [String: String] = [:]
    var roomID: UUID? = nil
    var id: String { ip }
}

/// אפליקציה שמותקנת בטלוויזיה / בסטרימר
struct AppInfo: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var iconURL: String? = nil    // כתובת אייקון ב-HTTP (LG, Roku, Sony)
    var iconPath: String? = nil   // נתיב אייקון פנימי בטלוויזיה (Samsung)

    /// אפליקציות צפייה מוכרות מופיעות ראשונות
    var priority: Int {
        let n = name.lowercased()
        let order = ["netflix", "disney", "prime", "youtube", "apple tv", "max", "hbo", "yes", "hot", "partner",
                     "cellcom", "sting", "next", "kan", "spotify", "plex", "twitch"]
        return order.firstIndex { n.contains($0) } ?? order.count
    }
}

struct Status: Equatable {
    var power: Bool? = nil
    var input: String? = nil
    var volume: String? = nil
    var reachable: Bool = false
    var level: Int? = nil        // בהירות / מיקום וילון (0-100)
    var kindHint: Kind? = nil    // סוג שזוהה אוטומטית (Tuya)
}

/// חיבור פיזי: כבל מיציאה של מכשיר אחד לכניסה של מכשיר אחר.
struct Connection: Codable, Identifiable, Hashable {
    var id = UUID()
    var fromIP: String
    var fromPort: String          // יציאה במכשיר המקור, למשל "HDMI OUT"
    var toIP: String
    var toPort: String            // כניסה במכשיר היעד בשפת המכשיר, למשל "HDMI2" או "GAME"
    var isDefault: Bool = true    // המקור שנבחר כברירת מחדל בכניסות של היעד
    var linkedPower: Bool = true  // הדלקה וכיבוי משותפים לאורך החיבור
}

/// חדר, כמו ב-Control4: מכשירים שמשויכים אליו ונקודות קצה לווידאו ולשמע.
struct Room: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var icon: String = "sofa"
    var videoIP: String? = nil        // מי מציג תמונה (בדרך כלל הטלוויזיה)
    var audioIP: String? = nil        // מי מנהל את הסאונד (רסיבר או הטלוויזיה)
    var tvAudioInput: String? = nil   // לאיזה קלט הרסיבר עובר כשצופים באפליקציות של הטלוויזיה

    static let icons = ["sofa", "bed.double", "fork.knife", "tv", "books.vertical",
                        "briefcase", "shower", "leaf", "car", "house"]
}
