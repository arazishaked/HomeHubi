import Foundation
import SwiftUI

@MainActor
final class Store: ObservableObject {
    /// המכשירים שהמשתמש "הוריד" לאפליקציה
    @Published var devices: [Device] = []
    /// תוצאות הסריקה האחרונה (לא נשמרות)
    @Published var discovered: [Device] = []
    @Published var rooms: [Room] = []
    @Published var connections: [Connection] = []
    @Published var statuses: [String: Status] = [:]
    /// אפליקציות מותקנות לכל טלוויזיה/סטרימר (לפי IP), נשמר בין הפעלות
    @Published var tvApps: [String: [AppInfo]] = [:]
    /// אפליקציות מועדפות לכל טלוויזיה (מזהי אפליקציה, לפי הסדר)
    @Published var favoriteApps: [String: [String]] = [:]
    /// אייקונים שנטענו, לפי "ip|appId"
    @Published var appIcons: [String: Data] = [:]
    @Published var loadingApps: Set<String> = []
    /// מכשירי Tuya מהחשבון (שם, סוג, מזהה ומפתח מקומי)
    @Published var tuyaCloud: [TuyaCloudDevice] = []
    @Published var tuyaSyncing = false
    /// מתי נלמדה רשימת האפליקציות של כל מכשיר
    @Published var appsUpdated: [String: Date] = [:]
    private var lastLearnAttempt: [String: Date] = [:]
    /// אפליקציות שלא נמצא להן אייקון בשום מקור בהפעלה הנוכחית (לא מנסים שוב עד הפעלה הבאה)
    private var iconMisses: Set<String> = []
    @Published var selectedRoomID: UUID? {
        didSet { UserDefaults.standard.set(selectedRoomID?.uuidString, forKey: "selectedRoom") }
    }
    @Published var scanning = false
    @Published var progress = 0.0
    @Published var log: [String] = []
    private var pollTask: Task<Void, Never>?

    init() { load() }

    // MARK: - Persistence

    func load() {
        let ud = UserDefaults.standard
        let dec = JSONDecoder()
        if let d = ud.data(forKey: "devices"), let v = try? dec.decode([Device].self, from: d) { devices = v }
        if let d = ud.data(forKey: "rooms"), let v = try? dec.decode([Room].self, from: d) { rooms = v }
        if let d = ud.data(forKey: "connections"), let v = try? dec.decode([Connection].self, from: d) { connections = v }
        if let d = ud.data(forKey: "tvApps"), let v = try? dec.decode([String: [AppInfo]].self, from: d) { tvApps = v }
        if let d = ud.data(forKey: "favoriteApps"), let v = try? dec.decode([String: [String]].self, from: d) { favoriteApps = v }
        if let d = ud.data(forKey: "appsUpdated"), let v = try? dec.decode([String: Date].self, from: d) { appsUpdated = v }
        if let d = ud.data(forKey: "tuyaCloud"), let v = try? dec.decode([TuyaCloudDevice].self, from: d) { tuyaCloud = v }
        if let s = ud.string(forKey: "selectedRoom"), let id = UUID(uuidString: s), rooms.contains(where: { $0.id == id }) {
            selectedRoomID = id
        } else {
            selectedRoomID = rooms.first?.id
        }
    }

    func saveAll() {
        let ud = UserDefaults.standard
        let enc = JSONEncoder()
        if let d = try? enc.encode(devices) { ud.set(d, forKey: "devices") }
        if let d = try? enc.encode(rooms) { ud.set(d, forKey: "rooms") }
        if let d = try? enc.encode(connections) { ud.set(d, forKey: "connections") }
        if let d = try? enc.encode(tvApps) { ud.set(d, forKey: "tvApps") }
        if let d = try? enc.encode(favoriteApps) { ud.set(d, forKey: "favoriteApps") }
        if let d = try? enc.encode(appsUpdated) { ud.set(d, forKey: "appsUpdated") }
        if let d = try? enc.encode(tuyaCloud) { ud.set(d, forKey: "tuyaCloud") }
    }

    func addLog(_ s: String) {
        log.insert("\(Date().formatted(date: .omitted, time: .standard))  \(s)", at: 0)
        if log.count > 100 { log.removeLast() }
    }

    // MARK: - Devices

    func device(_ ip: String) -> Device? { devices.first { $0.ip == ip } }
    func name(_ ip: String) -> String { device(ip)?.name ?? ip }
    func isAdded(_ ip: String) -> Bool { devices.contains { $0.ip == ip } }

    private func mutate(_ ip: String, _ change: (inout Device) -> Void) {
        guard let i = devices.firstIndex(where: { $0.ip == ip }) else { return }
        change(&devices[i])
        saveAll()
    }

    func setConfig(_ ip: String, _ key: String, _ value: String) { mutate(ip) { $0.config[key] = value } }
    func rename(_ ip: String, _ name: String) { mutate(ip) { $0.name = name } }
    func setMac(_ ip: String, _ mac: String) { mutate(ip) { $0.mac = mac } }
    func setKind(_ ip: String, _ kind: Kind) { mutate(ip) { $0.kind = kind } }
    func setRoom(_ ip: String, _ roomID: UUID?) { mutate(ip) { $0.roomID = roomID } }

    func controller(for d: Device) -> Controller {
        makeController(d) { [weak self] k, v in
            Task { @MainActor in self?.setConfig(d.ip, k, v) }
        }
    }

    /// מוריד מכשיר מהסריקה לאפליקציה
    func add(_ d: Device, room: UUID?) {
        guard !isAdded(d.ip) else { setRoom(d.ip, room); return }
        var n = d
        n.roomID = room
        devices.append(n)
        saveAll()
        addLog("נוסף: \(d.name)")
        // מיד אחרי ההוספה: מזהים את המכשיר ולומדים את האפליקציות שלו לבד
        Task { await learn(n) }
    }

    func addAllDiscovered() {
        for d in discovered where !isAdded(d.ip) { add(d, room: selectedRoomID) }
    }

    func remove(_ ip: String) {
        devices.removeAll { $0.ip == ip }
        connections.removeAll { $0.fromIP == ip || $0.toIP == ip }
        for i in rooms.indices {
            if rooms[i].videoIP == ip { rooms[i].videoIP = nil }
            if rooms[i].audioIP == ip { rooms[i].audioIP = nil; rooms[i].tvAudioInput = nil }
        }
        statuses[ip] = nil
        saveAll()
    }

    func scan() async {
        if scanning { return }
        scanning = true
        progress = 0
        addLog("סריקת רשת התחילה")
        let found = await Discovery.scan { p in
            Task { @MainActor in self.progress = p }
        }
        discovered = found.sorted { ($0.kind.rawValue, $0.ip) < ($1.kind.rawValue, $1.ip) }
        // רענון פרטים טכניים של מכשירים שכבר באפליקציה, בלי לגעת בשם, בסוג ובחדר
        for f in found {
            mutate(f.ip) { d in
                d.ports = f.ports
                if !f.model.isEmpty { d.model = f.model }
                if d.mac.isEmpty { d.mac = f.mac }
            }
        }
        scanning = false
        addLog("נמצאו \(found.count) מכשירים")
        if !tuyaCloud.isEmpty { await matchTuya() }
    }

    // MARK: - Tuya account (שמות המפסקים והמפתחות)

    var tuyaRegion: String {
        get { UserDefaults.standard.string(forKey: "tuyaRegion") ?? "eu" }
        set { UserDefaults.standard.set(newValue, forKey: "tuyaRegion"); objectWillChange.send() }
    }
    var tuyaAccessID: String {
        get { UserDefaults.standard.string(forKey: "tuyaAccessID") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "tuyaAccessID"); objectWillChange.send() }
    }
    var tuyaSecret: String {
        get { UserDefaults.standard.string(forKey: "tuyaSecret") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "tuyaSecret"); objectWillChange.send() }
    }
    var tuyaDeviceHint: String {
        get { UserDefaults.standard.string(forKey: "tuyaDeviceHint") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "tuyaDeviceHint"); objectWillChange.send() }
    }

    /// מוריד מהחשבון את כל המכשירים (שמות ומפתחות) ומשייך אותם למכשירים שנמצאו ברשת
    func syncTuya() async throws {
        tuyaSyncing = true
        defer { tuyaSyncing = false }
        let list = try await TuyaCloud.fetchDevices(region: tuyaRegion, accessID: tuyaAccessID.trimmingCharacters(in: .whitespaces),
                                                    secret: tuyaSecret.trimmingCharacters(in: .whitespaces),
                                                    anyDeviceID: tuyaDeviceHint.trimmingCharacters(in: .whitespaces))
        tuyaCloud = list
        saveAll()
        addLog("Tuya: \(list.count) מכשירים בחשבון")
        await matchTuya()
    }

    func tuyaCloudDevice(for d: Device) -> TuyaCloudDevice? {
        guard let id = d.config["id"] else { return nil }
        return tuyaCloud.first { $0.id == id }
    }

    /// מחיל על מכשיר את השם, הסוג והמפתח מהחשבון
    private func applyTuya(_ c: TuyaCloudDevice, to d: inout Device) {
        d.name = c.name
        d.kind = c.kind
        d.model = c.productName
        d.config["id"] = c.id
        d.config["key"] = c.localKey
        d.config["dps"] = c.powerDP
    }

    func assignTuya(ip: String, cloudID: String) {
        guard let c = tuyaCloud.first(where: { $0.id == cloudID }) else { return }
        if let i = devices.firstIndex(where: { $0.ip == ip }) { applyTuya(c, to: &devices[i]) }
        if let i = discovered.firstIndex(where: { $0.ip == ip }) { applyTuya(c, to: &discovered[i]) }
        saveAll()
    }

    /// מוצא איזה מכשיר בחשבון יושב באיזו כתובת: רק המפתח הנכון מצליח לדבר עם המכשיר
    func matchTuya() async {
        let used = Set(devices.compactMap { $0.config["id"] })
        var pending = (devices + discovered.filter { !isAdded($0.ip) }).filter { $0.brand == .tuya }
        // מכשירים שכבר משויכים: רק מעדכנים שם/סוג אם השתנו בחשבון
        for d in pending {
            if let c = tuyaCloudDevice(for: d), d.name != c.name { assignTuya(ip: d.ip, cloudID: c.id) }
        }
        pending.removeAll { $0.config["id"] != nil && !($0.config["key"] ?? "").isEmpty }
        var free = tuyaCloud.filter { !used.contains($0.id) && !$0.localKey.isEmpty }
        for d in pending {
            for c in free {
                var test = d
                test.config["id"] = c.id
                test.config["key"] = c.localKey
                test.config["dps"] = c.powerDP
                let st = await TuyaController(test, save: { _, _ in }).status()
                if st.reachable {
                    assignTuya(ip: d.ip, cloudID: c.id)
                    addLog("Tuya: \(d.ip) ← \(c.name)")
                    free.removeAll { $0.id == c.id }
                    break
                }
            }
        }
    }

    // MARK: - Rooms

    var hasUnassigned: Bool { devices.contains { $0.roomID == nil } }

    func room(_ id: UUID?) -> Room? {
        guard let id = id else { return nil }
        return rooms.first { $0.id == id }
    }

    func roomName(_ id: UUID?) -> String { room(id)?.name ?? "ללא חדר" }

    func roomDevices(_ id: UUID?) -> [Device] { devices.filter { $0.roomID == id } }

    func addRoom(_ name: String, icon: String = "sofa") {
        let r = Room(name: name, icon: icon)
        rooms.append(r)
        if selectedRoomID == nil { selectedRoomID = r.id }
        saveAll()
    }

    func updateRoom(_ id: UUID, _ change: (inout Room) -> Void) {
        guard let i = rooms.firstIndex(where: { $0.id == id }) else { return }
        change(&rooms[i])
        saveAll()
    }

    func deleteRooms(at idx: IndexSet) {
        let ids = idx.map { rooms[$0].id }
        rooms.remove(atOffsets: idx)
        for i in devices.indices where devices[i].roomID.map({ ids.contains($0) }) == true { devices[i].roomID = nil }
        if let s = selectedRoomID, ids.contains(s) { selectedRoomID = rooms.first?.id }
        saveAll()
    }

    func moveRooms(from: IndexSet, to: Int) {
        rooms.move(fromOffsets: from, toOffset: to)
        saveAll()
    }

    /// נקודת קצה וידאו: מה שנבחר בהגדרות החדר, אחרת הטלוויזיה הראשונה בחדר
    func videoEndpoint(_ roomID: UUID?) -> Device? {
        if let ip = room(roomID)?.videoIP, let d = device(ip) { return d }
        return roomDevices(roomID).first { $0.kind == .tv }
    }

    /// נקודת קצה שמע: מה שנבחר, אחרת רסיבר שמחובר לטלוויזיה, אחרת הטלוויזיה עצמה
    func audioEndpoint(_ roomID: UUID?) -> Device? {
        if let ip = room(roomID)?.audioIP, let d = device(ip) { return d }
        if let tv = videoEndpoint(roomID) {
            if let c = connections.first(where: { $0.toIP == tv.ip && device($0.fromIP)?.kind == .receiver }) {
                return device(c.fromIP)
            }
            if let c = connections.first(where: { $0.fromIP == tv.ip && device($0.toIP)?.kind == .receiver }) {
                return device(c.toIP)
            }
        }
        if let rx = roomDevices(roomID).first(where: { $0.kind == .receiver }) { return rx }
        return videoEndpoint(roomID)
    }

    /// מקורות לצפייה: כל מכשיר שהכבלים שלו מגיעים בסוף לטלוויזיה של החדר
    func watchSources(_ roomID: UUID?) -> [Device] {
        guard let tv = videoEndpoint(roomID) else { return [] }
        return devices.filter { d in
            d.ip != tv.ip && d.kind != .receiver && chain(from: d.ip).last?.toIP == tv.ip
        }
    }

    /// הקלט ברסיבר שמקבל את הסאונד של הטלוויזיה: מה שנקבע בחדר, אחרת לפי קישור ה-ARC
    func tvAudioInput(_ roomID: UUID?) -> String? {
        if let v = room(roomID)?.tvAudioInput, !v.isEmpty { return v }
        guard let tv = videoEndpoint(roomID), let rx = audioEndpoint(roomID), rx.ip != tv.ip else { return nil }
        return connections.first { $0.fromIP == tv.ip && $0.toIP == rx.ip }?.toPort
    }

    /// מקורות להאזנה: מה שמחובר לכניסות של הרסיבר בחדר
    func listenSources(_ roomID: UUID?) -> [Connection] {
        guard let rx = audioEndpoint(roomID), rx.kind == .receiver else { return [] }
        return incoming(rx.ip)
    }

    func activeSourceName(_ roomID: UUID?) -> String? {
        guard let tv = videoEndpoint(roomID), statuses[tv.ip]?.power == true else { return nil }
        if let rx = audioEndpoint(roomID), rx.kind == .receiver, let input = statuses[rx.ip]?.input,
           let c = incoming(rx.ip).first(where: { $0.toPort.uppercased() == input.uppercased() }) {
            return c.fromIP == tv.ip ? tv.name : name(c.fromIP)
        }
        return tv.name
    }

    // MARK: - Apps on TVs (אפליקציות מותקנות ואייקונים)

    /// האפליקציות של מכשיר: מועדפות קודם, אחר כך אפליקציות צפייה מוכרות, אחר כך לפי שם
    func apps(for ip: String) -> [AppInfo] {
        let list = tvApps[ip] ?? []
        let fav = favoriteApps[ip] ?? []
        return list.sorted { a, b in
            let fa = fav.firstIndex(of: a.id) ?? Int.max, fb = fav.firstIndex(of: b.id) ?? Int.max
            if fa != fb { return fa < fb }
            if a.priority != b.priority { return a.priority < b.priority }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    func favorites(for ip: String) -> [AppInfo] {
        let fav = favoriteApps[ip] ?? []
        let list = tvApps[ip] ?? []
        return fav.compactMap { id in list.first { $0.id == id } }
    }

    func isFavorite(_ ip: String, _ appID: String) -> Bool { favoriteApps[ip]?.contains(appID) == true }

    func toggleFavorite(_ ip: String, _ appID: String) {
        var fav = favoriteApps[ip] ?? []
        if let i = fav.firstIndex(of: appID) { fav.remove(at: i) } else { fav.append(appID) }
        favoriteApps[ip] = fav
        saveAll()
    }

    /// קורא מהטלוויזיה את רשימת האפליקציות המותקנות ואז טוען את האייקונים
    func refreshApps(_ d: Device) async throws {
        if loadingApps.contains(d.ip) { return }
        loadingApps.insert(d.ip)
        defer { loadingApps.remove(d.ip) }
        lastLearnAttempt[d.ip] = Date()
        let ctl = controller(for: d)
        // 1. הרשימה המלאה מהממשק של היצרן (עם אייקונים)
        var list: [AppInfo] = []
        var failure: Error? = nil
        do { list = try await ctl.apps() } catch { failure = error }
        // 2. השלמה מ-DIAL: אפליקציות צפייה שהטלוויזיה מדווחת שמותקנות
        var dial: [AppInfo] = []
        if d.brand != .cast { dial = await ctl.dialApps() }
        for a in dial where !list.contains(where: { $0.name.lowercased() == a.name.lowercased() }) {
            list.append(a)
        }
        if list.isEmpty {
            throw failure ?? HHError.msg("לא נמצאו אפליקציות במכשיר")
        }
        var seen = Set<String>()
        tvApps[d.ip] = list.filter { seen.insert($0.id).inserted }
        appsUpdated[d.ip] = Date()
        saveAll()
        addLog("\(d.name): נלמדו \(list.count) אפליקציות")
        await loadIcons(d)
    }

    /// זיהוי אוטומטי: שם, דגם, יצרן, מערכת הפעלה ו-MAC כפי שהמכשיר מדווח
    func identify(_ d: Device) async {
        let id = await controller(for: d).identify()
        guard let i = devices.firstIndex(where: { $0.ip == d.ip }) else { return }
        var n = devices[i]
        let generic = n.name == n.ip || n.name.hasPrefix("Tuya ") || n.name.hasPrefix("מצלמה ") || n.name.hasPrefix("מכשיר ")
            || n.name.hasPrefix("Shelly ") || n.name.hasPrefix("Sonoff ") || n.name.hasSuffix(" \(n.ip)")
            || ["Google Cast", "LG webOS TV", "Denon/Marantz", "Roku", "Samsung TV"].contains(n.name)
        if generic, let name = id.name, !name.isEmpty { n.name = name }
        if let m = id.model, !m.isEmpty { n.model = m }
        if n.mac.isEmpty, let mac = id.mac, !mac.isEmpty { n.mac = mac }
        if let os = id.os, !os.isEmpty { n.config["os"] = os }
        if let maker = id.manufacturer, !maker.isEmpty { n.config["maker"] = maker }
        if id.isTV == true, n.kind == .streamer || n.kind == .other { n.kind = .tv }
        n.config["identified"] = ISO8601DateFormatter().string(from: Date())
        if n != devices[i] {
            devices[i] = n
            saveAll()
            addLog("זוהה: \(n.name) · \(n.model)")
        }
    }

    /// לימוד מלא של מכשיר: זיהוי ואז רשימת אפליקציות, בשקט
    func learn(_ d: Device) async {
        await identify(d)
        guard let fresh = device(d.ip), fresh.kind == .tv || fresh.kind == .streamer else { return }
        do { try await refreshApps(fresh) }
        catch { addLog("\(fresh.name): לימוד אפליקציות נכשל – \(error.localizedDescription)") }
    }

    /// האם הגיע הזמן ללמוד שוב את האפליקציות (פעם ב-6 שעות, ולא יותר מניסיון כל 10 דקות)
    private func shouldLearn(_ ip: String) -> Bool {
        if loadingApps.contains(ip) { return false }
        if let t = lastLearnAttempt[ip], Date().timeIntervalSince(t) < 600 { return false }
        guard let u = appsUpdated[ip] else { return true }
        return Date().timeIntervalSince(u) > 6 * 3600
    }

    func icon(_ ip: String, _ appID: String) -> Data? { appIcons["\(ip)|\(appID)"] }

    private var iconDir: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("AppIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func iconFile(_ ip: String, _ appID: String) -> URL? {
        let safe = "\(ip)_\(appID)".map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" ? $0 : "-" }
        return iconDir?.appendingPathComponent(String(safe) + ".img")
    }

    /// אייקונים: קודם מהמטמון בטלפון, ואת החסרים מהטלוויזיה
    func loadIcons(_ d: Device) async {
        let list = tvApps[d.ip] ?? []
        var missing: [AppInfo] = []
        for a in list where icon(d.ip, a.id) == nil && !iconMisses.contains("\(d.ip)|\(a.id)") {
            if let f = iconFile(d.ip, a.id), let data = try? Data(contentsOf: f) {
                appIcons["\(d.ip)|\(a.id)"] = data
            } else {
                missing.append(a)
            }
        }
        guard !missing.isEmpty else { return }

        // 1. אייקונים מהטלוויזיה עצמה
        let got = await controller(for: d).icons(missing)
        for (id, data) in got { storeIcon(d.ip, id, data) }

        // 2. מה שעדיין חסר: האייקון הרשמי מ-App Store (משותף לכל הטלוויזיות, לפי שם)
        let still = missing.filter { got[$0.id] == nil }
        var lookups: [AppInfo] = []
        for a in still {
            if let f = nameIconFile(a.name), let data = try? Data(contentsOf: f) {
                storeIcon(d.ip, a.id, data)
            } else {
                lookups.append(a)
            }
        }
        var i = 0
        while i < lookups.count {
            let part = Array(lookups[i..<min(i + 6, lookups.count)])
            i += 6
            let results: [(AppInfo, Data?)] = await withTaskGroup(of: (AppInfo, Data?).self) { g in
                for a in part { g.addTask { (a, await OnlineIcons.icon(for: a.name)) } }
                var out: [(AppInfo, Data?)] = []
                for await r in g { out.append(r) }
                return out
            }
            for (a, data) in results {
                guard let data = data else { iconMisses.insert("\(d.ip)|\(a.id)"); continue }
                storeIcon(d.ip, a.id, data)
                if let f = nameIconFile(a.name) { try? data.write(to: f) }
            }
        }
    }

    private func storeIcon(_ ip: String, _ appID: String, _ data: Data) {
        appIcons["\(ip)|\(appID)"] = data
        if let f = iconFile(ip, appID) { try? data.write(to: f) }
    }

    private func nameIconFile(_ name: String) -> URL? {
        let key = OnlineIcons.normalized(name).map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return iconDir?.appendingPathComponent("name_" + String(key) + ".img")
    }

    /// מקפיץ אפליקציה בטלוויזיה של החדר (מדליק, מעביר את הרסיבר לסאונד של הטלוויזיה ופותח)
    func launchApp(_ app: AppInfo, on d: Device, roomID: UUID?) async throws {
        if d.ip == videoEndpoint(roomID)?.ip {
            try await watchTVApp(app, roomID: roomID)
        } else {
            await ensureOn(d)
            try await controller(for: d).openApp(app)
            addLog("\(d.name): \(app.name)")
        }
    }

    // MARK: - Connections (חיבורים פיזיים)

    func addConnection(_ c: Connection) {
        connections.append(c)
        saveAll()
    }

    func deleteConnections(at idx: IndexSet) {
        connections.remove(atOffsets: idx)
        saveAll()
    }

    func incoming(_ ip: String) -> [Connection] { connections.filter { $0.toIP == ip } }
    func outgoing(_ ip: String) -> [Connection] { connections.filter { $0.fromIP == ip } }

    /// החיבור שתופס מחבר מסוים (יציאה או כניסה), אם יש
    func connection(_ ip: String, _ p: Port) -> Connection? {
        switch p.dir {
        case .output: return connections.first { $0.fromIP == ip && $0.fromPort == p.id }
        case .input: return connections.first { $0.toIP == ip && $0.toPort == p.id }
        }
    }

    func portName(_ ip: String, _ id: String) -> String {
        guard let d = device(ip) else { return id }
        return findPort(d, id)?.name ?? id
    }

    func connectedCount(_ d: Device) -> Int {
        ports(for: d).filter { connection(d.ip, $0) != nil }.count
    }

    /// מחבר יציאה לכניסה. כמו ב-Control4 כל מחבר מחובר למקום אחד בלבד, אז חיבור קודם בשני הצדדים מתנתק.
    func bind(outIP: String, outPort: Port, inIP: String, inPort: Port) {
        connections.removeAll { ($0.fromIP == outIP && $0.fromPort == outPort.id) || ($0.toIP == inIP && $0.toPort == inPort.id) }
        let outKind = device(outIP)?.kind
        let inKind = device(inIP)?.kind
        let linked = outPort.type == .hdmi && outKind == .receiver && inKind == .tv
        connections.append(Connection(fromIP: outIP, fromPort: outPort.id, toIP: inIP, toPort: inPort.id,
                                      isDefault: incoming(inIP).isEmpty, linkedPower: linked))
        saveAll()
        addLog("קישור: \(name(outIP)) · \(outPort.name) ← \(name(inIP)) · \(inPort.name)")
    }

    func unbind(_ id: UUID) {
        connections.removeAll { $0.id == id }
        saveAll()
    }

    /// האם הקישור מעביר וידאו (HDMI). קישורי שמע (ARC/אופטי) לא נכנסים לנתיב התמונה.
    func isVideo(_ c: Connection) -> Bool {
        guard let d = device(c.fromIP), let p = findPort(d, c.fromPort) else { return true }
        return p.type == .hdmi
    }

    /// שרשרת כבלים ממקור עד טלוויזיה (מקור → רסיבר → טלוויזיה)
    func chain(from ip: String) -> [Connection] {
        var hops: [Connection] = []
        var cur = ip
        var seen: Set<String> = [ip]
        while let c = connections.first(where: { $0.fromIP == cur && !seen.contains($0.toIP) && isVideo($0) }) {
            hops.append(c)
            cur = c.toIP
            seen.insert(cur)
            if device(cur)?.kind == .tv { break }
        }
        return hops
    }

    func defaultSource(of rx: Device) -> Connection? {
        let inc = incoming(rx.ip)
        return inc.first(where: { $0.isDefault }) ?? inc.first
    }

    func setDefault(_ id: UUID, _ on: Bool) {
        guard let c = connections.first(where: { $0.id == id }) else { return }
        for i in connections.indices where connections[i].toIP == c.toIP {
            connections[i].isDefault = on && connections[i].id == id
        }
        saveAll()
    }

    func setLinkedPower(_ id: UUID, _ on: Bool) {
        guard let i = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[i].linkedPower = on
        saveAll()
    }

    // MARK: - Actions (Watch / Listen / Room off)

    private func ensureOn(_ d: Device) async {
        let c = controller(for: d)
        let s = await c.status()
        if s.power != true { try? await c.power(true) }
    }

    /// צפייה במקור: מדליק את כל השרשרת ומעביר כל קלט לפי הכבלים
    func watch(_ src: Device) async {
        let hops = chain(from: src.ip)
        if hops.isEmpty { addLog("אין חיבור מוגדר מ-\(src.name)"); return }
        addLog("צפייה ב-\(src.name)")
        await ensureOn(src)
        for h in hops { if let d = device(h.toIP) { await ensureOn(d) } }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        for h in hops {
            guard let d = device(h.toIP) else { continue }
            do { try await controller(for: d).setInput(h.toPort) }
            catch { addLog("שגיאה ב-\(d.name): \(error.localizedDescription)") }
        }
    }

    /// אפליקציה בטלוויזיה: מדליק טלוויזיה, מעביר את הרסיבר לקלט של הטלוויזיה ופותח את האפליקציה
    func watchTVApp(_ app: AppInfo, roomID: UUID?) async throws {
        guard let tv = videoEndpoint(roomID) else { throw HHError.msg("אין טלוויזיה בחדר") }
        let wasOn = statuses[tv.ip]?.power == true
        await ensureOn(tv)
        if let rx = audioEndpoint(roomID), rx.ip != tv.ip, rx.kind == .receiver {
            await ensureOn(rx)
            if let input = tvAudioInput(roomID) {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                try? await controller(for: rx).setInput(input)
            }
        }
        if !wasOn { try? await Task.sleep(nanoseconds: 5_000_000_000) }   // זמן עלייה של הטלוויזיה
        do {
            try await controller(for: tv).openApp(app)
        } catch {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            try await controller(for: tv).openApp(app)
        }
        addLog("\(tv.name): \(app.name)")
    }

    /// האזנה: מדליק רק את הרסיבר ומעביר לכניסה של המקור
    func listen(_ c: Connection) async {
        guard let rx = device(c.toIP) else { return }
        addLog("האזנה ל-\(name(c.fromIP))")
        if let src = device(c.fromIP) { await ensureOn(src) }
        await ensureOn(rx)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        do { try await controller(for: rx).setInput(c.toPort) }
        catch { addLog("שגיאה ב-\(rx.name): \(error.localizedDescription)") }
    }

    func roomVolume(_ roomID: UUID?, _ k: RemoteKey) async {
        guard let a = audioEndpoint(roomID) else { return }
        try? await controller(for: a).press(k)
    }

    /// "כבה חדר": מכבה את כל המולטימדיה בחדר
    func roomOff(_ roomID: UUID?) async {
        addLog("כיבוי \(roomName(roomID))")
        let ctls = roomDevices(roomID)
            .filter { [.tv, .receiver, .streamer].contains($0.kind) }
            .map { controller(for: $0) }
        await withTaskGroup(of: Void.self) { g in
            for c in ctls { g.addTask { try? await c.power(false) } }
        }
    }

    private func follow(_ c: Connection, on: Bool) async {
        guard let d = device(c.fromIP) else { return }
        let ctl = controller(for: d)
        do {
            try await ctl.power(on)
            addLog("\(d.name) \(on ? "נדלק" : "כבה") (הפעלה משותפת עם \(name(c.toIP)))")
            if on, d.kind == .receiver, let src = defaultSource(of: d) {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                try await ctl.setInput(src.toPort)
            }
        } catch {
            if d.kind == .streamer || d.kind == .other { return }
            addLog("שגיאה ב-\(d.name): \(error.localizedDescription)")
        }
    }

    // MARK: - Polling (מצב מכשירים והפעלה משותפת – כל עוד האפליקציה פתוחה)

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                await pollOnce()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func stopPolling() { pollTask?.cancel() }

    func pollOnce() async {
        let list = devices.filter { $0.kind != .camera && $0.kind != .phone && $0.kind != .computer }
        var jobs: [(String, Controller)] = []
        for d in list { jobs.append((d.ip, controller(for: d))) }
        var results: [(String, Status)] = []
        await withTaskGroup(of: (String, Status).self) { g in
            for (ip, c) in jobs { g.addTask { (ip, await c.status()) } }
            for await r in g { results.append(r) }
        }
        for (ip, new) in results {
            let old = statuses[ip]
            statuses[ip] = new
            if let hint = new.kindHint, hint != .plug, let i = devices.firstIndex(where: { $0.ip == ip }),
               devices[i].kind == .plug || devices[i].kind == .other, devices[i].kind != hint {
                devices[i].kind = hint
                saveAll()
            }
            // לימוד אוטומטי כשטלוויזיה/סטרימר זמינים ברשת
            if new.reachable, let d = device(ip), d.kind == .tv || d.kind == .streamer, shouldLearn(ip) {
                Task { await learn(d) }
            }
            guard let o = old?.power, let n = new.power, o != n else { continue }
            for c in connections where c.linkedPower && c.toIP == ip {
                Task { await follow(c, on: n) }
            }
        }
    }
}
