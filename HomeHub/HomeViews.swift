import SwiftUI

// MARK: - Root

struct HomeView: View {
    @EnvironmentObject var store: Store
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.devices.isEmpty {
                    EmptyHome(path: $path)
                } else {
                    RoomDashboard()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(value: Route.settings) {
                        Image(systemName: "line.3.horizontal").font(.title3.weight(.semibold))
                    }
                    .accessibilityLabel("הגדרות")
                }
                ToolbarItem(placement: .principal) { RoomPicker() }
            }
            .navigationDestination(for: Route.self) { destination($0) }
        }
    }

    @ViewBuilder
    func destination(_ r: Route) -> some View {
        switch r {
        case .settings: SettingsView()
        case .scan: ScanView()
        case .myDevices: MyDevicesView()
        case .connections: ConnectionsSettingsView()
        case .rooms: RoomsView()
        case .log: LogView()
        case .tuya: TuyaAccountView()
        case .watch: WatchView()
        case .listen: ListenView()
        case .lights: LightsView()
        case .shades: ShadesView()
        case .roomDevices: RoomDevicesView()
        case .deviceConnections(let ip): DeviceConnectionsView(ip: ip)
        case .device(let ip): DeviceControlView(ip: ip)
        case .deviceSettings(let ip): DeviceSettingsView(ip: ip)
        case .room(let id): RoomEditView(id: id)
        }
    }
}

struct EmptyHome: View {
    @Binding var path: NavigationPath

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "house").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("עדיין אין מכשירים בבית").font(.title3.weight(.semibold))
            Text("סרוק את הרשת, בחר את המכשירים שלך וסדר אותם בחדרים.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button {
                path.append(Route.settings)
                path.append(Route.scan)
            } label: {
                Label("סרוק את הרשת", systemImage: "dot.radiowaves.left.and.right").frame(minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}

struct RoomPicker: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let current = store.room(store.selectedRoomID)
        Menu {
            ForEach(store.rooms) { r in
                Button { store.selectedRoomID = r.id } label: { Label(r.name, systemImage: r.icon) }
            }
            if store.hasUnassigned && !store.rooms.isEmpty {
                Button { store.selectedRoomID = nil } label: { Label("ללא חדר", systemImage: "tray") }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: current?.icon ?? "house")
                Text(current?.name ?? (store.rooms.isEmpty ? "הבית שלי" : "ללא חדר")).font(.headline)
                if !store.rooms.isEmpty { Image(systemName: "chevron.down").font(.caption.weight(.bold)) }
            }
            .foregroundStyle(.primary)
        }
        .disabled(store.rooms.isEmpty)
    }
}

// MARK: - Room dashboard (כמו ב-Control4: צפייה, האזנה, תאורה, וילונות)

struct RoomDashboard: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let rid = store.selectedRoomID
        let devs = store.roomDevices(rid)
        let lights = devs.filter { $0.kind == .light || $0.kind == .plug }
        let shades = devs.filter { $0.kind == .curtain || $0.kind == .blind }
        let lightsOn = lights.filter { store.statuses[$0.ip]?.power == true }.count
        let sources = store.watchSources(rid)
        let listen = store.listenSources(rid)
        let tv = store.videoEndpoint(rid)
        let active = store.activeSourceName(rid)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(active.map { "פועל עכשיו: \($0)" } ?? "החדר כבוי")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                if let tv = tv { QuickAppsRow(tv: tv) }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    Tile(title: "צפייה", subtitle: tv == nil ? "אין טלוויזיה" : "\(sources.count) מקורות",
                         route: .watch, enabled: tv != nil) { Image(systemName: "play.tv") }
                    Tile(title: "האזנה", subtitle: listen.isEmpty ? "אין מקורות" : "\(listen.count) מקורות",
                         route: .listen, enabled: !listen.isEmpty) { Image(systemName: "music.note") }
                    Tile(title: "תאורה", subtitle: lights.isEmpty ? "אין תאורה" : "\(lightsOn) מתוך \(lights.count) דולקות",
                         route: .lights, enabled: !lights.isEmpty) {
                        Image(systemName: lightsOn > 0 ? "lightbulb.fill" : "lightbulb")
                    }
                    Tile(title: "וילונות", subtitle: shades.isEmpty ? "אין וילונות" : "\(shades.count) וילונות ותריסים",
                         route: .shades, enabled: !shades.isEmpty) {
                        CurtainShape().stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .frame(width: 26, height: 26)
                    }
                    Tile(title: "מכשירים", subtitle: "\(devs.count) בחדר", route: .roomDevices, enabled: !devs.isEmpty) {
                        Image(systemName: "square.grid.2x2")
                    }
                    RoomOffTile(enabled: devs.contains { [.tv, .receiver, .streamer].contains($0.kind) })
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            if let tv = tv, store.statuses[tv.ip]?.power == true {
                NowPlayingBar(source: active ?? tv.name)
            }
        }
        .refreshable { await store.pollOnce() }
    }
}

struct Tile<Icon: View>: View {
    let title: String
    let subtitle: String
    let route: Route
    let enabled: Bool
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 10) {
                icon().font(.system(size: 26)).foregroundStyle(Color.accentColor).frame(height: 28)
                Spacer(minLength: 0)
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

struct RoomOffTile: View {
    @EnvironmentObject var store: Store
    let enabled: Bool
    @State private var busy = false

    var body: some View {
        Button {
            busy = true
            Task { await store.roomOff(store.selectedRoomID); busy = false }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Group {
                    if busy { ProgressView() } else { Image(systemName: "power") }
                }
                .font(.system(size: 26)).foregroundStyle(.red).frame(height: 28)
                Spacer(minLength: 0)
                Text("כבה חדר").font(.headline).foregroundStyle(.primary)
                Text("טלוויזיה, רסיבר וסטרימר").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
        .opacity(enabled ? 1 : 0.4)
    }
}

struct NowPlayingBar: View {
    @EnvironmentObject var store: Store
    let source: String

    var body: some View {
        let rid = store.selectedRoomID
        HStack(spacing: 14) {
            Image(systemName: "play.tv.fill").foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 0) {
                Text("פועל עכשיו").font(.caption2).foregroundStyle(.secondary)
                Text(source).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            Spacer()
            Button { Task { await store.roomVolume(rid, .volDown) } } label: { Image(systemName: "speaker.minus") }
                .accessibilityLabel("הנמך")
            Button { Task { await store.roomVolume(rid, .mute) } } label: { Image(systemName: "speaker.slash") }
                .accessibilityLabel("השתק")
            Button { Task { await store.roomVolume(rid, .volUp) } } label: { Image(systemName: "speaker.plus") }
                .accessibilityLabel("הגבר")
        }
        .font(.title3)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
}

// MARK: - Apps row on the dashboard (מועדפות, או אפליקציות הצפייה הראשונות)

struct QuickAppsRow: View {
    @EnvironmentObject var store: Store
    let tv: Device
    @State private var busyID: String? = nil
    @State private var msg = ""

    var body: some View {
        let fav = store.favorites(for: tv.ip)
        let list = fav.isEmpty ? Array(store.apps(for: tv.ip).prefix(8)) : fav
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(fav.isEmpty ? "אפליקציות" : "מועדפות").font(.headline)
                Spacer()
                NavigationLink(value: Route.watch) { Text("הכל").font(.subheadline) }
            }
            .padding(.horizontal, 4)
            if list.isEmpty {
                HStack(spacing: 8) {
                    if store.loadingApps.contains(tv.ip) { ProgressView() }
                    Text(store.loadingApps.contains(tv.ip) ? "קורא אפליקציות מהטלוויזיה…" : "אין עדיין רשימת אפליקציות")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(list) { a in
                            Button {
                                busyID = a.id
                                msg = ""
                                Task {
                                    do { try await store.launchApp(a, on: tv, roomID: store.selectedRoomID) }
                                    catch { msg = error.localizedDescription }
                                    busyID = nil
                                }
                            } label: {
                                AppTile(ip: tv.ip, app: a, busy: busyID == a.id, size: 56).frame(width: 72)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            if !msg.isEmpty { Text(msg).font(.footnote).foregroundStyle(.red).padding(.horizontal, 4) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
        .task(id: tv.ip) {
            if store.tvApps[tv.ip] == nil {
                try? await store.refreshApps(tv)
            } else {
                await store.loadIcons(tv)
            }
        }
    }
}

// MARK: - Watch

struct WatchView: View {
    @EnvironmentObject var store: Store
    @State private var busyID: String? = nil
    @State private var msg = ""
    @State private var search = ""

    var body: some View {
        let rid = store.selectedRoomID
        let sources = store.watchSources(rid)
        let tv = store.videoEndpoint(rid)
        GList {
            GSection {
                ForEach(sources) { d in
                    Button {
                        busyID = d.ip
                        Task { await store.watch(d); busyID = nil }
                    } label: {
                        HStack {
                            DeviceRow(d: d, subtitle: route(d))
                            if busyID == d.ip { ProgressView() }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("מקורות")
            } footer: {
                if sources.isEmpty {
                    Text("אין מקורות מחוברים לטלוויזיה. חבר אותם בהגדרות ← קישורים.")
                }
            }

            if let tv = tv {
                let all = store.apps(for: tv.ip)
                let shown = search.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(search) }
                GSection {
                    if all.isEmpty && store.loadingApps.contains(tv.ip) {
                        HStack { ProgressView(); Text("קורא את האפליקציות מהטלוויזיה…").foregroundStyle(.secondary) }
                    }
                    if !shown.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 16) {
                            ForEach(shown) { a in
                                Button { launch(a, tv: tv, rid: rid) } label: {
                                    AppTile(ip: tv.ip, app: a, busy: busyID == a.id, size: 64,
                                            favorite: store.isFavorite(tv.ip, a.id))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { launch(a, tv: tv, rid: rid) } label: { Label("פתח בטלוויזיה", systemImage: "play.fill") }
                                    Button { store.toggleFavorite(tv.ip, a.id) } label: {
                                        if store.isFavorite(tv.ip, a.id) {
                                            Label("הסר ממועדפות", systemImage: "star.slash")
                                        } else {
                                            Label("הוסף למועדפות", systemImage: "star")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    Button {
                        msg = ""
                        Task {
                            do { try await store.refreshApps(tv) } catch { msg = error.localizedDescription }
                        }
                    } label: {
                        Label(all.isEmpty ? "קרא אפליקציות מהטלוויזיה" : "רענן רשימה", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.loadingApps.contains(tv.ip))
                    if !msg.isEmpty { Text(msg).font(.footnote).foregroundStyle(.red) }
                } header: {
                    Text("אפליקציות ב-\(tv.name) (\(all.count))")
                } footer: {
                    Text("לחיצה פותחת את האפליקציה בטלוויזיה. לחיצה ארוכה: הוספה למועדפות שמופיעות במסך הבית.")
                }
            }
        }
        .searchable(text: $search, prompt: "חיפוש אפליקציה")
        .navigationTitle("צפייה")
        .task(id: tv?.ip) {
            guard let tv = tv else { return }
            if store.tvApps[tv.ip] == nil {
                do { try await store.refreshApps(tv) } catch { msg = error.localizedDescription }
            } else {
                await store.loadIcons(tv)
            }
        }
    }

    func launch(_ a: AppInfo, tv: Device, rid: UUID?) {
        busyID = a.id
        msg = ""
        Task {
            do { try await store.launchApp(a, on: tv, roomID: rid) } catch { msg = error.localizedDescription }
            busyID = nil
        }
    }

    func route(_ d: Device) -> String {
        store.chain(from: d.ip).map { "\(store.name($0.toIP)) · \(store.portName($0.toIP, $0.toPort))" }.joined(separator: " ← ")
    }
}

/// אייקון אפליקציה: האייקון האמיתי מהטלוויזיה, ואם אין — אות ראשונה על רקע בצבע קבוע לפי השם
struct AppTile: View {
    @EnvironmentObject var store: Store
    let ip: String
    let app: AppInfo
    let busy: Bool
    var size: CGFloat = 64
    var favorite: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                ZStack {
                    if let data = store.icon(ip, app.id), let img = UIImage(data: data) {
                        RoundedRectangle(cornerRadius: size * 0.22).fill(Color(.systemBackground))
                        Image(uiImage: img).resizable().scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: size * 0.22).fill(fallbackColor.gradient)
                        Text(String(app.name.prefix(1)).uppercased())
                            .font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white)
                    }
                    if busy {
                        RoundedRectangle(cornerRadius: size * 0.22).fill(Color.black.opacity(0.35))
                        ProgressView().tint(.white)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
                .overlay(RoundedRectangle(cornerRadius: size * 0.22).stroke(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                if favorite {
                    Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(.yellow)
                        .padding(3).background(Circle().fill(Color(.systemBackground))).offset(x: -4, y: -4)
                }
            }
            Text(app.name).font(.caption).lineLimit(1).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("פתח את \(app.name)")
    }

    var fallbackColor: Color {
        let palette: [Color] = [.red, .blue, .indigo, .teal, .orange, .purple, .green, .pink]
        let h = app.name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[h % palette.count]
    }
}

// MARK: - Listen

struct ListenView: View {
    @EnvironmentObject var store: Store
    @State private var busyID: UUID? = nil

    var body: some View {
        let rid = store.selectedRoomID
        let sources = store.listenSources(rid)
        GList {
            GSection("מקורות") {
                ForEach(sources) { c in
                    Button {
                        busyID = c.id
                        Task { await store.listen(c); busyID = nil }
                    } label: {
                        HStack {
                            if let d = store.device(c.fromIP) {
                                DeviceRow(d: d, subtitle: "\(store.name(c.toIP)) · \(c.toPort)")
                            }
                            if busyID == c.id { ProgressView() }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if let a = store.audioEndpoint(rid) {
                GSection("עוצמה · \(a.name)") {
                    HStack {
                        Button { Task { await store.roomVolume(rid, .volDown) } } label: {
                            Image(systemName: "speaker.minus").frame(maxWidth: .infinity, minHeight: 32)
                        }
                        Button { Task { await store.roomVolume(rid, .mute) } } label: {
                            Image(systemName: "speaker.slash").frame(maxWidth: .infinity, minHeight: 32)
                        }
                        Button { Task { await store.roomVolume(rid, .volUp) } } label: {
                            Image(systemName: "speaker.plus").frame(maxWidth: .infinity, minHeight: 32)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .navigationTitle("האזנה")
    }
}

// MARK: - Lights

struct LightsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let devs = store.roomDevices(store.selectedRoomID).filter { $0.kind == .light || $0.kind == .plug }
        GList {
            GSection { ForEach(devs) { d in LightRow(d: d) } }
        }
        .navigationTitle("תאורה")
    }
}

struct LightRow: View {
    @EnvironmentObject var store: Store
    let d: Device
    @State private var level: Double = 80

    var body: some View {
        let on = store.statuses[d.ip]?.power == true
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DeviceIcon(kind: d.kind, on: on, size: 30)
                Text(d.name).font(.body.weight(.semibold))
                Spacer()
                Toggle("", isOn: Binding(get: { on }, set: { v in
                    store.statuses[d.ip]?.power = v
                    runOn(store, d.ip, v ? "הדלקה" : "כיבוי") { try await $0.power(v) }
                }))
                .labelsHidden()
            }
            if d.kind == .light {
                HStack {
                    Image(systemName: "sun.min").foregroundStyle(.secondary)
                    Slider(value: $level, in: 1...100, step: 1) { editing in
                        if !editing {
                            let v = Int(level)
                            runOn(store, d.ip, "בהירות \(v)%") { try await $0.setLevel(v) }
                        }
                    }
                    Image(systemName: "sun.max").foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear { if let l = store.statuses[d.ip]?.level { level = Double(max(1, l)) } }
    }
}

// MARK: - Shades

struct ShadesView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let devs = store.roomDevices(store.selectedRoomID).filter { $0.kind == .curtain || $0.kind == .blind }
        GList {
            GSection {
            ForEach(devs) { d in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        DeviceIcon(kind: d.kind, size: 30).foregroundStyle(Color.accentColor)
                        Text(d.name).font(.body.weight(.semibold))
                        Spacer()
                        if let l = store.statuses[d.ip]?.level {
                            Text("\(l)%").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    CoverButtons(kind: d.kind) { c in
                        runOn(store, d.ip, c == .open ? "פתיחה" : (c == .close ? "סגירה" : "עצירה")) { try await $0.cover(c) }
                    }
                }
                .padding(.vertical, 4)
            }
            }
        }
        .navigationTitle("וילונות ותריסים")
    }
}

// MARK: - Room devices

struct RoomDevicesView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        GList {
            GSection {
                ForEach(store.roomDevices(store.selectedRoomID)) { d in
                    GLink(value: Route.device(d.ip)) { DeviceRow(d: d) }
                }
            }
        }
        .navigationTitle(store.roomName(store.selectedRoomID))
    }
}
