import SwiftUI

// MARK: - Settings root (נפתח מ-☰)

struct SettingsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        List {
            Section {
                row(.scan, "סריקת רשת", "dot.radiowaves.left.and.right",
                    store.discovered.isEmpty ? nil : "\(store.discovered.count) נמצאו")
                row(.myDevices, "המכשירים שלי", "square.stack.3d.up", "\(store.devices.count)")
            } header: {
                Text("מכשירים")
            } footer: {
                Text("סורקים את הרשת ובוחרים אילו מכשירים להוריד לאפליקציה.")
            }
            Section {
                row(.connections, "קישורים", "cable.connector.horizontal", "\(store.connections.count)")
                row(.rooms, "חדרים", "door.left.hand.open", "\(store.rooms.count)")
            } header: {
                Text("מבנה הבית")
            } footer: {
                Text("קישורים מגדירים איזה כבל מחובר מאיזו יציאה לאיזו כניסה. חדרים מסדרים את מסך הבית.")
            }
            Section {
                row(.tuya, "חשבון Tuya / Smart Life", "person.crop.circle.badge.checkmark",
                    store.tuyaCloud.isEmpty ? "לא מחובר" : "\(store.tuyaCloud.count) מכשירים")
            } header: {
                Text("חשבונות")
            } footer: {
                Text("מחברים פעם אחת כדי שהמפסקים, השקעים והנורות של Tuya יופיעו עם השמות שנתת להם באפליקציית Smart Life.")
            }
            Section("מערכת") {
                row(.log, "יומן פעולות", "list.bullet.rectangle", nil)
            }
        }
        .navigationTitle("הגדרות")
    }

    func row(_ r: Route, _ title: String, _ icon: String, _ badge: String?) -> some View {
        NavigationLink(value: r) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                if let b = badge { Text(b).foregroundStyle(.secondary) }
            }
        }
    }
}

// MARK: - Scan

struct ScanView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        List {
            Section {
                if store.scanning {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("סורק את הרשת… \(Int(store.progress * 100))%").font(.subheadline)
                        ProgressView(value: store.progress)
                    }
                    .padding(.vertical, 4)
                } else {
                    Button { Task { await store.scan() } } label: {
                        Label(store.discovered.isEmpty ? "התחל סריקה" : "סרוק שוב", systemImage: "dot.radiowaves.left.and.right")
                    }
                }
            } footer: {
                Text("בפעם הראשונה iOS יבקש אישור לגישה לרשת המקומית. אם לא נמצא כלום, סרוק שוב.")
            }

            if !store.discovered.isEmpty {
                Section("נמצאו ברשת (\(store.discovered.count))") {
                    ForEach(store.discovered) { d in ScanRow(d: d) }
                }
            }
        }
        .navigationTitle("סריקת רשת")
        .toolbar {
            if store.discovered.contains(where: { !store.isAdded($0.ip) }) {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("הוסף הכל") { store.addAllDiscovered() }
                }
            }
        }
    }
}

struct ScanRow: View {
    @EnvironmentObject var store: Store
    let d: Device

    var body: some View {
        HStack(spacing: 12) {
            DeviceIcon(kind: d.kind, size: 30).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.name).font(.body.weight(.semibold))
                Text("\(d.kind.title) · \(d.brand.title) \(d.model)").font(.caption).foregroundStyle(.secondary)
                Text(d.ip).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if store.isAdded(d.ip) {
                VStack(alignment: .trailing, spacing: 2) {
                    Label("נוסף", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(.green)
                    if store.loadingApps.contains(d.ip) {
                        Text("לומד אפליקציות…").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text(store.roomName(store.device(d.ip)?.roomID)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else {
                Menu {
                    Section("הוסף לחדר") {
                        ForEach(store.rooms) { r in
                            Button { store.add(d, room: r.id) } label: { Label(r.name, systemImage: r.icon) }
                        }
                        Button { store.add(d, room: nil) } label: { Label("ללא חדר", systemImage: "tray") }
                    }
                } label: {
                    Text("הוסף")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - My devices

struct MyDevicesView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        List {
            ForEach(store.rooms) { r in
                section(r.name, r.id)
            }
            section(store.rooms.isEmpty ? "מכשירים" : "ללא חדר", nil)
        }
        .overlay {
            if store.devices.isEmpty {
                VStack(spacing: 12) {
                    Text("עדיין לא הוספת מכשירים").foregroundStyle(.secondary)
                    NavigationLink(value: Route.scan) { Text("לסריקת רשת") }
                }
            }
        }
        .navigationTitle("המכשירים שלי")
    }

    @ViewBuilder
    func section(_ title: String, _ id: UUID?) -> some View {
        let list = store.roomDevices(id)
        if !list.isEmpty {
            Section(title) {
                ForEach(list) { d in
                    NavigationLink(value: Route.deviceSettings(d.ip)) { DeviceRow(d: d) }
                }
                .onDelete { idx in
                    for i in idx { store.remove(list[i].ip) }
                }
            }
        }
    }
}

// MARK: - Connections (קישורים פיזיים, כמו Connections ב-Control4)

struct ConnectionsSettingsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        List {
            ForEach(store.rooms) { r in section(r.name, r.id) }
            section(store.rooms.isEmpty ? "מכשירים" : "ללא חדר", nil)

            if !store.connections.isEmpty {
                Section {
                    ForEach(store.connections) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(store.name(c.fromIP)) · \(store.portName(c.fromIP, c.fromPort))")
                                .font(.subheadline.weight(.semibold))
                            Text("← \(store.name(c.toIP)) · \(store.portName(c.toIP, c.toPort))")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { idx in
                        for id in idx.map({ store.connections[$0].id }) { store.unbind(id) }
                    }
                } header: {
                    Text("כל החיבורים (\(store.connections.count))")
                }
            }
        }
        .overlay {
            if !store.devices.contains(where: { !ports(for: $0).isEmpty }) {
                VStack(spacing: 8) {
                    Image(systemName: "cable.connector.horizontal").font(.largeTitle).foregroundStyle(.secondary)
                    Text("אין מכשירי מולטימדיה").font(.headline)
                    Text("הוסף טלוויזיה, רסיבר או סטרימר מהסריקה, ואז חבר כאן את המחברים שלהם.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(32)
            }
        }
        .navigationTitle("קישורים")
    }

    @ViewBuilder
    func section(_ title: String, _ id: UUID?) -> some View {
        let list = store.roomDevices(id).filter { !ports(for: $0).isEmpty }
        if !list.isEmpty {
            Section(title) {
                ForEach(list) { d in
                    let total = ports(for: d).count
                    let used = store.connectedCount(d)
                    NavigationLink(value: Route.deviceConnections(d.ip)) {
                        HStack(spacing: 12) {
                            DeviceIcon(kind: d.kind, size: 28).foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.name).font(.body.weight(.semibold))
                                Text("\(d.kind.title) · \(total) מחברים").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(used)/\(total)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(used > 0 ? Color.green : Color.secondary)
                        }
                    }
                }
            }
        }
    }
}

/// מסך המחברים של מכשיר אחד: יציאות וכניסות ולמה כל אחד מחובר
struct DeviceConnectionsView: View {
    @EnvironmentObject var store: Store
    let ip: String
    @State private var editing: Port? = nil

    var body: some View {
        if let d = store.device(ip) {
            let all = ports(for: d)
            List {
                portSection("יציאות", all.filter { $0.dir == .output }, d)
                portSection("כניסות", all.filter { $0.dir == .input }, d)
            }
            .navigationTitle(d.name)
            .sheet(item: $editing) { p in
                PortBindingSheet(ip: ip, port: p).environmentObject(store)
            }
        } else {
            Text("המכשיר הוסר").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func portSection(_ title: String, _ list: [Port], _ d: Device) -> some View {
        if !list.isEmpty {
            Section(title) {
                ForEach(list) { p in
                    let c = store.connection(ip, p)
                    Button { editing = p } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(p.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                    TypePill(type: p.type)
                                    if let c = c, p.dir == .input, c.isDefault, store.incoming(ip).count > 1 {
                                        Text("ברירת מחדל").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                                    }
                                }
                                Text(peerText(p, c))
                                    .font(.subheadline)
                                    .foregroundStyle(c == nil ? Color.secondary : Color.primary)
                            }
                            Spacer()
                            Image(systemName: "chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions {
                        if let c = c {
                            Button("נתק", role: .destructive) { store.unbind(c.id) }
                        }
                    }
                }
            }
        }
    }

    func peerText(_ p: Port, _ c: Connection?) -> String {
        guard let c = c else { return "לא מחובר" }
        if p.dir == .output { return "← \(store.name(c.toIP)) · \(store.portName(c.toIP, c.toPort))" }
        return "→ \(store.name(c.fromIP)) · \(store.portName(c.fromIP, c.fromPort))"
    }
}

struct TypePill: View {
    let type: PortType
    var body: some View {
        Text(type.title)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(type == .hdmi ? Color.accentColor.opacity(0.14) : Color.orange.opacity(0.16)))
            .foregroundStyle(type == .hdmi ? Color.accentColor : Color.orange)
    }
}

/// בחירת הצד השני של מחבר: רק מחברים תואמים (יציאה ↔ כניסה, אותו סוג)
struct PortBindingSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let ip: String
    let port: Port

    struct Candidate: Identifiable {
        let device: Device
        let port: Port
        var id: String { device.ip + "|" + port.id }
    }

    var candidates: [Candidate] {
        let want: PortDir = port.dir == .output ? .input : .output
        return store.devices.filter { $0.ip != ip }.flatMap { d in
            ports(for: d).filter { $0.dir == want && $0.type == port.type }.map { Candidate(device: d, port: $0) }
        }
    }

    var body: some View {
        let current = store.connection(ip, port)
        NavigationStack {
            List {
                if let c = current {
                    Section {
                        if port.dir == .input {
                            Toggle("מקור ברירת מחדל", isOn: Binding(get: { store.connection(ip, port)?.isDefault ?? false },
                                                                   set: { store.setDefault(c.id, $0) }))
                        }
                        Toggle("הפעלה משותפת", isOn: Binding(get: { store.connection(ip, port)?.linkedPower ?? false },
                                                             set: { store.setLinkedPower(c.id, $0) }))
                    } footer: {
                        Text("ברירת מחדל: הקלט שהמכשיר עובר אליו כשהוא נדלק עם הטלוויזיה. הפעלה משותפת: כשהמכשיר בצד הכניסה נדלק או נכבה, המכשיר בצד היציאה נדלק או נכבה איתו.")
                    }
                }
                Section {
                    ForEach(candidates) { cand in
                        let taken = store.connection(cand.device.ip, cand.port)
                        let isCurrent = taken?.id == current?.id && taken != nil
                        Button {
                            if port.dir == .output {
                                store.bind(outIP: ip, outPort: port, inIP: cand.device.ip, inPort: cand.port)
                            } else {
                                store.bind(outIP: cand.device.ip, outPort: cand.port, inIP: ip, inPort: port)
                            }
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                DeviceIcon(kind: cand.device.kind, size: 24).foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(cand.device.name) · \(cand.port.name)").foregroundStyle(.primary)
                                    Text(status(cand, taken, isCurrent)).font(.caption)
                                        .foregroundStyle(taken != nil && !isCurrent ? Color.orange : Color.secondary)
                                }
                                Spacer()
                                if isCurrent { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                            }
                        }
                    }
                } header: {
                    Text(port.dir == .output ? "חבר לכניסה" : "חבר ליציאה")
                } footer: {
                    if candidates.isEmpty {
                        Text("אין מחברים תואמים במכשירים אחרים. הוסף מכשירים מהסריקה.")
                    } else {
                        Text("בחירת מחבר תפוס מעבירה אליו את החיבור.")
                    }
                }
            }
            .navigationTitle("\(port.name) · \(port.type.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("סגור") { dismiss() } }
                if let c = current {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("נתק", role: .destructive) { store.unbind(c.id); dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    func status(_ cand: Candidate, _ taken: Connection?, _ isCurrent: Bool) -> String {
        if isCurrent { return "מחובר עכשיו" }
        if let t = taken {
            let otherIP = cand.port.dir == .input ? t.fromIP : t.toIP
            let otherPort = cand.port.dir == .input ? t.fromPort : t.toPort
            return "תפוס: \(store.name(otherIP)) · \(store.portName(otherIP, otherPort))"
        }
        return "פנוי · \(store.roomName(cand.device.roomID))"
    }
}

// MARK: - Rooms

struct RoomsView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var newName = ""

    var body: some View {
        List {
            ForEach(store.rooms) { r in
                NavigationLink(value: Route.room(r.id)) {
                    HStack(spacing: 12) {
                        Image(systemName: r.icon).frame(width: 28).foregroundStyle(Color.accentColor)
                        Text(r.name)
                        Spacer()
                        Text("\(store.roomDevices(r.id).count) מכשירים").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { store.deleteRooms(at: $0) }
            .onMove { store.moveRooms(from: $0, to: $1) }
        }
        .overlay {
            if store.rooms.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "door.left.hand.open").font(.largeTitle).foregroundStyle(.secondary)
                    Text("עדיין אין חדרים").font(.headline)
                    Text("צור חדרים ושייך אליהם מכשירים. מסך הבית יוצג לפי החדרים.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(32)
            }
        }
        .navigationTitle("חדרים")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { newName = ""; adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("חדר חדש")
            }
            if !store.rooms.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) { EditButton() }
            }
        }
        .alert("חדר חדש", isPresented: $adding) {
            TextField("שם החדר", text: $newName)
            Button("ביטול", role: .cancel) {}
            Button("צור") {
                let n = newName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { store.addRoom(n) }
            }
        }
    }
}

struct RoomEditView: View {
    @EnvironmentObject var store: Store
    let id: UUID
    @State private var rxInputs: [String] = []

    var body: some View {
        if let r = store.room(id) {
            form(r)
        } else {
            Text("החדר נמחק").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func form(_ r: Room) -> some View {
        let devs = store.roomDevices(id)
        let tvs = devs.filter { $0.kind == .tv }
        let audio = devs.filter { $0.kind == .receiver || $0.kind == .tv }
        let resolvedAudio = store.audioEndpoint(id)
        Form {
            Section("חדר") {
                TextField("שם", text: Binding(get: { store.room(id)?.name ?? "" }, set: { v in store.updateRoom(id) { $0.name = v } }))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                    ForEach(Room.icons, id: \.self) { icon in
                        Button { store.updateRoom(id) { $0.icon = icon } } label: {
                            Image(systemName: icon)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(RoundedRectangle(cornerRadius: 10)
                                    .fill(r.icon == icon ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill)))
                                .foregroundStyle(r.icon == icon ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(icon)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker("תמונה (וידאו)", selection: Binding<String?>(get: { store.room(id)?.videoIP },
                                                                    set: { v in store.updateRoom(id) { $0.videoIP = v } })) {
                    Text("אוטומטי").tag(String?.none)
                    ForEach(tvs) { Text($0.name).tag(Optional($0.ip)) }
                }
                Picker("סאונד", selection: Binding<String?>(get: { store.room(id)?.audioIP },
                                                           set: { v in store.updateRoom(id) { $0.audioIP = v; $0.tvAudioInput = nil } })) {
                    Text("אוטומטי").tag(String?.none)
                    ForEach(audio) { Text($0.name).tag(Optional($0.ip)) }
                }
                if let rx = resolvedAudio, rx.kind == .receiver {
                    Picker("קלט ברסיבר לאפליקציות הטלוויזיה",
                           selection: Binding<String?>(get: { store.room(id)?.tvAudioInput },
                                                       set: { v in store.updateRoom(id) { $0.tvAudioInput = v } })) {
                        Text("לפי הקישורים").tag(String?.none)
                        ForEach(rxInputs, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    .task(id: rx.ip) { rxInputs = await store.controller(for: rx).inputList() }
                }
            } header: {
                Text("נקודות קצה")
            } footer: {
                Text("כמו ב-Control4: מי מציג את התמונה ומי מנהל את הסאונד בחדר. כשבוחרים מקור, האפליקציה הולכת לפי הקישורים ומחליפה את הקלטים בדרך.")
            }

            Section {
                ForEach(store.devices) { d in
                    Button {
                        store.setRoom(d.ip, d.roomID == id ? nil : id)
                    } label: {
                        HStack {
                            DeviceRow(d: d, subtitle: d.roomID == id ? d.kind.title : "\(d.kind.title) · \(store.roomName(d.roomID))")
                            Image(systemName: d.roomID == id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(d.roomID == id ? Color.accentColor : Color.secondary)
                                .font(.title3)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("מכשירים בחדר (\(devs.count))")
            } footer: {
                Text("סמן את המכשירים ששייכים לחדר הזה. מכשיר יכול להיות בחדר אחד בלבד.")
            }
        }
        .navigationTitle(r.name)
    }
}

// MARK: - Tuya account

struct TuyaAccountView: View {
    @EnvironmentObject var store: Store
    @State private var msg = ""
    @State private var ok = false

    var body: some View {
        Form {
            Section {
                Picker("אזור", selection: Binding(get: { store.tuyaRegion }, set: { store.tuyaRegion = $0 })) {
                    ForEach(TuyaCloud.regions.map { $0.id }, id: \.self) { rid in
                        Text(TuyaCloud.regions.first { $0.id == rid }?.title ?? rid).tag(rid)
                    }
                }
                TextField("Access ID", text: Binding(get: { store.tuyaAccessID }, set: { store.tuyaAccessID = $0 }))
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                SecureField("Access Secret", text: Binding(get: { store.tuyaSecret }, set: { store.tuyaSecret = $0 }))
                TextField("Device ID של מכשיר אחד (לא חובה)", text: Binding(get: { store.tuyaDeviceHint }, set: { store.tuyaDeviceHint = $0 }))
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
            } header: {
                Text("פרטי הפרויקט")
            } footer: {
                Text("ב-iot.tuya.com: Cloud ← Development ← Create Cloud Project (אזור Central Europe). בלשונית Devices ← Link Tuya App Account סורקים את הקוד מאפליקציית Smart Life. את Access ID ו-Access Secret מעתיקים מ-Overview.")
            }
            Section {
                Button {
                    msg = ""; ok = false
                    Task {
                        do { try await store.syncTuya(); ok = true; msg = "התקבלו \(store.tuyaCloud.count) מכשירים" }
                        catch { msg = error.localizedDescription }
                    }
                } label: {
                    HStack {
                        Label(store.tuyaCloud.isEmpty ? "התחבר וקבל את השמות" : "רענן מהחשבון", systemImage: "arrow.triangle.2.circlepath")
                        if store.tuyaSyncing { Spacer(); ProgressView() }
                    }
                }
                .disabled(store.tuyaAccessID.isEmpty || store.tuyaSecret.isEmpty || store.tuyaSyncing)
                if !msg.isEmpty { Text(msg).font(.footnote).foregroundStyle(ok ? Color.green : Color.red) }
            }
            if !store.tuyaCloud.isEmpty {
                Section {
                    ForEach(store.tuyaCloud) { c in
                        let local = (store.devices + store.discovered).first { $0.config["id"] == c.id }
                        HStack(spacing: 12) {
                            DeviceIcon(kind: c.kind, size: 26).foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).font(.body.weight(.semibold))
                                Text(c.productName.isEmpty ? c.kind.title : c.productName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let l = local {
                                Text(l.ip).font(.caption.monospacedDigit()).foregroundStyle(.green)
                            } else {
                                Text("לא נמצא ברשת").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("מכשירים בחשבון (\(store.tuyaCloud.count))")
                } footer: {
                    Text("מכשיר ש\"לא נמצא ברשת\": סרוק שוב, או בחר אותו ידנית בהגדרות המכשיר. מכשירי Tuya חדשים מאוד (פרוטוקול 3.4/3.5) עדיין לא נתמכים בשליטה מקומית.")
                }
            }
        }
        .navigationTitle("חשבון Tuya")
    }
}

// MARK: - Log

struct LogView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        List(store.log, id: \.self) { Text($0).font(.footnote) }
            .overlay { if store.log.isEmpty { Text("אין פעולות עדיין").foregroundStyle(.secondary) } }
            .navigationTitle("יומן פעולות")
    }
}
