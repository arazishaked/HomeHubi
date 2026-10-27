import SwiftUI

// MARK: - Icons

struct CurtainShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + w * x, y: r.minY + h * y) }
        p.move(to: pt(0, 0.1)); p.addLine(to: pt(1, 0.1))
        p.move(to: pt(0.08, 0.1)); p.addLine(to: pt(0.08, 0.95))
        p.addQuadCurve(to: pt(0.46, 0.95), control: pt(0.27, 0.78))
        p.addLine(to: pt(0.46, 0.1))
        p.move(to: pt(0.92, 0.1)); p.addLine(to: pt(0.92, 0.95))
        p.addQuadCurve(to: pt(0.54, 0.95), control: pt(0.73, 0.78))
        p.addLine(to: pt(0.54, 0.1))
        return p
    }
}

struct BlindShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + w * x, y: r.minY + h * y) }
        p.addRect(CGRect(x: r.minX, y: r.minY + h * 0.05, width: w, height: h * 0.1))
        for y in [0.3, 0.45, 0.6, 0.75] as [CGFloat] { p.move(to: pt(0.06, y)); p.addLine(to: pt(0.94, y)) }
        p.move(to: pt(0.5, 0.75)); p.addLine(to: pt(0.5, 0.95))
        return p
    }
}

struct DeviceIcon: View {
    let kind: Kind
    var on: Bool = false
    var size: CGFloat = 28

    var body: some View {
        Group {
            switch kind {
            case .curtain:
                CurtainShape().stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)).padding(size * 0.08)
            case .blind:
                BlindShape().stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)).padding(size * 0.08)
            case .light:
                Image(systemName: on ? "lightbulb.fill" : "lightbulb")
                    .font(.system(size: size * 0.8))
                    .foregroundStyle(on ? Color.yellow : Color.primary)
            default:
                Image(systemName: kind.icon).font(.system(size: size * 0.75))
            }
        }
        .frame(width: size, height: size)
    }
}


// MARK: - Navigation

enum Route: Hashable {
    case settings, scan, myDevices, connections, rooms, log, tuya
    case watch, listen, lights, shades, roomDevices
    case deviceConnections(String) // המחברים של מכשיר
    case device(String)          // שליטה במכשיר
    case deviceSettings(String)  // הגדרות מכשיר
    case room(UUID)              // עריכת חדר
}

// MARK: - Shared rows

func statusColor(_ s: Status?) -> Color {
    guard let s = s else { return .gray }
    if !s.reachable { return .red }
    if s.power == true { return .green }
    if s.power == false { return .orange }
    return .blue
}

struct DeviceRow: View {
    @EnvironmentObject var store: Store
    let d: Device
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            DeviceIcon(kind: d.kind, on: store.statuses[d.ip]?.power == true, size: 30)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.name).font(.body.weight(.semibold))
                Text(subtitle ?? "\(d.brand.title) \(d.model) · \(store.address(d))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.isAdded(d.ip) {
                Circle().fill(statusColor(store.statuses[d.ip])).frame(width: 10, height: 10)
            }
        }
    }
}

/// כפתורי וילון/תריס: חצים לפתיחה, עצירה וסגירה
struct CoverButtons: View {
    let kind: Kind
    let action: (CoverCommand) -> Void

    var body: some View {
        HStack(spacing: 8) {
            button(.open)
            button(.stop)
            button(.close)
        }
        .buttonStyle(.bordered)
    }

    func button(_ c: CoverCommand) -> some View {
        Button { action(c) } label: {
            VStack(spacing: 2) {
                if c == .stop {
                    Image(systemName: "stop.fill")
                } else if kind == .blind {
                    Image(systemName: c == .open ? "arrow.up" : "arrow.down")
                } else {
                    Image(systemName: c == .open ? "arrow.left.and.line.vertical.and.arrow.right"
                                                 : "arrow.right.and.line.vertical.and.arrow.left")
                }
                Text(c == .open ? "פתח" : (c == .close ? "סגור" : "עצור")).font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .accessibilityLabel(c == .open ? "פתח" : (c == .close ? "סגור" : "עצור"))
    }
}

/// הרצת פקודה על מכשיר עם הודעת שגיאה
@MainActor
func runOn(_ store: Store, _ ip: String, _ title: String,
           _ block: @escaping @MainActor (Controller) async throws -> Void) {
    guard let d = store.device(ip) else { return }
    Task { @MainActor in
        do {
            try await block(store.controller(for: d))
            store.addLog("\(d.name): \(title)")
        } catch {
            store.addLog("שגיאה ב-\(d.name): \(error.localizedDescription)")
        }
    }
}
