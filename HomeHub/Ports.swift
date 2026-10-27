import Foundation

// MARK: - מחברים פיזיים, כמו ב-Connections של Control4
//
// לכל מכשיר יש רשימת מחברים: יציאות וכניסות, כל אחד מסוג HDMI או שמע.
// קישור = יציאה של מכשיר אחד ← כניסה של מכשיר אחר, מאותו סוג, אחד לאחד.
// המזהה של כניסה הוא גם הפקודה שהמכשיר מקבל כדי לעבור אליה (למשל "GAME" ברסיבר Denon או "HDMI2" בטלוויזיה).

enum PortDir: String, Codable { case input, output }

enum PortType: String, Codable {
    case hdmi, audio
    var title: String { self == .hdmi ? "HDMI" : "שמע" }
}

struct Port: Identifiable, Hashable {
    let id: String
    let name: String
    let dir: PortDir
    let type: PortType
}

private func inp(_ id: String, _ name: String? = nil, _ t: PortType = .hdmi) -> Port {
    Port(id: id, name: name ?? id, dir: .input, type: t)
}

private func out(_ id: String, _ name: String? = nil, _ t: PortType = .hdmi) -> Port {
    Port(id: id, name: name ?? id, dir: .output, type: t)
}

func ports(for d: Device) -> [Port] {
    switch d.kind {
    case .tv:
        return [inp("HDMI1", "HDMI 1"), inp("HDMI2", "HDMI 2"), inp("HDMI3", "HDMI 3"), inp("HDMI4", "HDMI 4"),
                out("ARC", "ARC / Optical", .audio)]
    case .receiver:
        switch d.brand {
        case .yamaha:
            return [out("HDMI OUT"),
                    inp("hdmi1", "HDMI 1"), inp("hdmi2", "HDMI 2"), inp("hdmi3", "HDMI 3"), inp("hdmi4", "HDMI 4"),
                    inp("tv", "TV (ARC)", .audio), inp("av1", "AV 1", .audio), inp("audio1", "AUDIO 1", .audio)]
        case .denon:
            return [out("HDMI OUT 1"), out("HDMI OUT 2"),
                    inp("TV", "TV (ARC)", .audio), inp("GAME"), inp("MPLAY", "MEDIA PLAYER"), inp("BD", "Blu-ray"),
                    inp("SAT/CBL", "CBL/SAT"), inp("DVD"), inp("AUX1", "AUX 1"), inp("CD", "CD", .audio)]
        default:
            return [out("HDMI OUT"),
                    inp("HDMI1", "HDMI 1"), inp("HDMI2", "HDMI 2"), inp("HDMI3", "HDMI 3"), inp("HDMI4", "HDMI 4"),
                    inp("TV", "TV (ARC)", .audio)]
        }
    case .streamer, .other:
        return [out("HDMI OUT")]
    default:
        return []
    }
}

func findPort(_ d: Device, _ id: String) -> Port? {
    ports(for: d).first { $0.id == id }
}
