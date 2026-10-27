import SwiftUI

// MARK: - שליטה במכשיר

struct DeviceControlView: View {
    @EnvironmentObject var store: Store
    let ip: String
    @State private var inputs: [String] = []
    @State private var level: Double = 50
    @State private var msg = ""
    @State private var busy = false

    var body: some View {
        if let d = store.device(ip) {
            content(d)
        } else {
            Text("המכשיר הוסר").foregroundStyle(.secondary)
        }
    }

    func act(_ title: String, _ block: @escaping @MainActor (Controller) async throws -> Void) {
        guard let d = store.device(ip) else { return }
        busy = true
        msg = ""
        Task { @MainActor in
            do {
                try await block(store.controller(for: d))
                store.addLog("\(d.name): \(title)")
            } catch {
                msg = error.localizedDescription
            }
            busy = false
        }
    }

    func stateText(_ st: Status?, _ k: Kind) -> String {
        guard let st = st else { return "—" }
        if !st.reachable { return "לא זמין" }
        if k == .curtain || k == .blind { return st.level.map { "פתוח \($0)%" } ?? "זמין" }
        switch st.power {
        case .some(true): return k == .light ? "דולקת" : "דולק"
        case .some(false): return k == .light ? "כבויה" : "כבוי"
        case .none: return "זמין"
        }
    }

    @ViewBuilder
    func content(_ d: Device) -> some View {
        let st = store.statuses[ip]
        Form {
            Section {
                VStack(spacing: 8) {
                    DeviceIcon(kind: d.kind, on: st?.power == true, size: 64).foregroundStyle(Color.accentColor)
                    Text(stateText(st, d.kind)).font(.subheadline).foregroundStyle(.secondary)
                    if let i = st?.input { Text("קלט: \(i)").font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            controls(d)
            if d.kind == .tv || d.kind == .streamer {
                let list = store.apps(for: ip)
                Section {
                    if !list.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 12)], spacing: 14) {
                            ForEach(list) { a in
                                Button { act("פתיחת \(a.name)") { try await $0.openApp(a) } } label: {
                                    AppTile(ip: ip, app: a, busy: false, size: 56, favorite: store.isFavorite(ip, a.id))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { store.toggleFavorite(ip, a.id) } label: {
                                        Label(store.isFavorite(ip, a.id) ? "הסר ממועדפות" : "הוסף למועדפות", systemImage: "star")
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    Button {
                        guard let dev = store.device(ip) else { return }
                        busy = true; msg = ""
                        Task {
                            do { try await store.refreshApps(dev) } catch { msg = error.localizedDescription }
                            busy = false
                        }
                    } label: {
                        Label(list.isEmpty ? "קרא אפליקציות מהמכשיר" : "רענן", systemImage: "arrow.clockwise")
                    }
                } header: {
                    Text("אפליקציות (\(list.count))")
                }
            }
            if busy || !msg.isEmpty {
                Section {
                    if busy { ProgressView() }
                    if !msg.isEmpty { Text(msg).foregroundStyle(.red).font(.footnote) }
                }
            }
        }
        .navigationTitle(d.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(value: Route.deviceSettings(ip)) { Image(systemName: "gearshape") }
                    .accessibilityLabel("הגדרות מכשיר")
            }
        }
        .task(id: ip) {
            inputs = await store.controller(for: d).inputList()
            if let l = store.statuses[ip]?.level { level = Double(l) }
        }
    }

    @ViewBuilder
    func controls(_ d: Device) -> some View {
        switch d.kind {
        case .curtain, .blind:
            Section("שליטה") {
                CoverButtons(kind: d.kind) { c in
                    act(c == .open ? "פתיחה" : (c == .close ? "סגירה" : "עצירה")) { try await $0.cover(c) }
                }
                VStack(alignment: .leading) {
                    Text("מיקום: \(Int(level))%").font(.footnote).foregroundStyle(.secondary)
                    Slider(value: $level, in: 0...100, step: 5) { editing in
                        if !editing { act("מיקום \(Int(level))%") { try await $0.setLevel(Int(level)) } }
                    }
                }
            }
        case .light:
            Section("שליטה") {
                powerButtons
                VStack(alignment: .leading) {
                    Text("בהירות: \(Int(level))%").font(.footnote).foregroundStyle(.secondary)
                    Slider(value: $level, in: 1...100, step: 1) { editing in
                        if !editing { act("בהירות \(Int(level))%") { try await $0.setLevel(Int(level)) } }
                    }
                }
            }
        case .camera:
            Section {
                Text("צפייה בשידור חי של מצלמות עדיין לא נתמכת. האפליקציה מציגה אם המצלמה זמינה ברשת.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        default:
            Section("שליטה") {
                powerButtons
                if d.kind == .tv || d.kind == .receiver {
                    HStack {
                        Button { act("עוצמה -") { try await $0.press(.volDown) } } label: {
                            Image(systemName: "speaker.minus").frame(maxWidth: .infinity, minHeight: 32)
                        }
                        Button { act("השתקה") { try await $0.press(.mute) } } label: {
                            Image(systemName: "speaker.slash").frame(maxWidth: .infinity, minHeight: 32)
                        }
                        Button { act("עוצמה +") { try await $0.press(.volUp) } } label: {
                            Image(systemName: "speaker.plus").frame(maxWidth: .infinity, minHeight: 32)
                        }
                        if d.kind == .tv {
                            Button { act("Home") { try await $0.press(.home) } } label: {
                                Image(systemName: "house").frame(maxWidth: .infinity, minHeight: 32)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                if !inputs.isEmpty {
                    Menu("החלף קלט") {
                        ForEach(inputs, id: \.self) { i in
                            Button(i) { act("קלט \(i)") { try await $0.setInput(i) } }
                        }
                    }
                }
            }
        }
    }

    var powerButtons: some View {
        HStack {
            Button { act("הדלקה") { try await $0.power(true) } } label: {
                Text("הדלק").frame(maxWidth: .infinity, minHeight: 32)
            }
            Button { act("כיבוי") { try await $0.power(false) } } label: {
                Text("כבה").frame(maxWidth: .infinity, minHeight: 32)
            }
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - הגדרות מכשיר

struct DeviceSettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let ip: String
    @State private var confirmRemove = false

    var body: some View {
        if let d = store.device(ip) {
            form(d)
        } else {
            Text("המכשיר הוסר").foregroundStyle(.secondary)
        }
    }

    func cfg(_ key: String) -> Binding<String> {
        Binding(get: { store.device(ip)?.config[key] ?? "" }, set: { store.setConfig(ip, key, $0) })
    }

    func appsSummary(_ d: Device) -> String {
        if store.loadingApps.contains(d.ip) { return "לומד…" }
        let n = store.tvApps[d.ip]?.count ?? 0
        guard let t = store.appsUpdated[d.ip] else { return n == 0 ? "עדיין לא נלמדו" : "\(n)" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "he")
        return "\(n) · \(f.localizedString(for: t, relativeTo: Date()))"
    }

    @ViewBuilder
    func form(_ d: Device) -> some View {
        Form {
            Section("פרטים") {
                TextField("שם", text: Binding(get: { store.device(ip)?.name ?? "" }, set: { store.rename(ip, $0) }))
                Picker("סוג", selection: Binding(get: { store.device(ip)?.kind ?? d.kind }, set: { store.setKind(ip, $0) })) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("חדר", selection: Binding<UUID?>(get: { store.device(ip)?.roomID }, set: { store.setRoom(ip, $0) })) {
                    Text("ללא חדר").tag(UUID?.none)
                    ForEach(store.rooms) { r in Text(r.name).tag(Optional(r.id)) }
                }
            }
            Section {
                LabeledContent("יצרן", value: d.config["maker"] ?? d.brand.title)
                if !d.model.isEmpty { LabeledContent("דגם", value: d.model) }
                if let os = d.config["os"] { LabeledContent("מערכת", value: os) }
                if d.kind == .tv || d.kind == .streamer {
                    LabeledContent("אפליקציות", value: appsSummary(d))
                    Button {
                        Task { await store.learn(d) }
                    } label: {
                        HStack {
                            Label("זהה ולמד מחדש", systemImage: "sparkles")
                            if store.loadingApps.contains(d.ip) { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(store.loadingApps.contains(d.ip))
                }
                LabeledContent("כתובת IP", value: d.ip)
                if !d.ports.isEmpty { LabeledContent("פורטים", value: d.ports.map(String.init).joined(separator: ", ")) }
            } header: {
                Text("זיהוי")
            } footer: {
                Text("האפליקציה מזהה את המכשיר ולומדת לבד אילו אפליקציות מותקנות בו: כשמוסיפים אותו, וכל כמה שעות כשהוא דלוק.")
            }
            Section {
                TextField("כתובת MAC", text: Binding(get: { store.device(ip)?.mac ?? "" }, set: { store.setMac(ip, $0) }))
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                if d.brand == .sony {
                    TextField("Pre-Shared Key", text: cfg("psk")).autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                if d.brand == .tuya && !store.tuyaCloud.isEmpty {
                    Picker("מכשיר בחשבון Tuya", selection: Binding<String>(get: { store.device(ip)?.config["id"] ?? "" },
                                                                        set: { store.assignTuya(ip: ip, cloudID: $0) })) {
                        Text("לא נבחר").tag("")
                        ForEach(store.tuyaCloud) { Text($0.name).tag($0.id) }
                    }
                }
                if d.brand == .tuya {
                    TextField("Device ID", text: cfg("id")).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("Local Key (16 תווים)", text: cfg("key")).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("מספר DP (אופציונלי)", text: cfg("dps")).autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                if d.brand == .samsung && !(d.config["token"] ?? "").isEmpty { Text("הטלוויזיה מזווגת ✓").foregroundStyle(.green) }
                if d.brand == .lg && !(d.config["clientKey"] ?? "").isEmpty { Text("הטלוויזיה מזווגת ✓").foregroundStyle(.green) }
            } header: {
                Text("תקשורת")
            } footer: {
                Text("כתובת MAC מאפשרת להדליק טלוויזיה שכבויה לגמרי. בטלוויזיות Samsung ו-LG הזיווג נעשה באישור על המסך בפעם הראשונה.")
            }
            if !ports(for: d).isEmpty {
                Section("קישורים") {
                    NavigationLink(value: Route.deviceConnections(ip)) {
                        HStack {
                            Label("מחברים", systemImage: "cable.connector.horizontal")
                            Spacer()
                            Text("\(store.connectedCount(d))/\(ports(for: d).count)").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                NavigationLink(value: Route.device(ip)) { Label("בדיקת שליטה", systemImage: "slider.horizontal.3") }
            }
            Section {
                Button("הסר מהאפליקציה", role: .destructive) { confirmRemove = true }
            }
        }
        .navigationTitle(d.name)
        .confirmationDialog("להסיר את \(d.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("הסר", role: .destructive) {
                dismiss()
                store.remove(ip)
            }
        } message: {
            Text("גם החיבורים שלו יימחקו. אפשר להוסיף אותו שוב מהסריקה.")
        }
    }
}
