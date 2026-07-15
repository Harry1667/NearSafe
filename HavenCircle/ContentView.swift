import SwiftUI
import SwiftData
import MapKit
import UserNotifications

@Model
final class LocalSafetyEvent {
    @Attribute(.unique) var eventKey: String
    var title: String; var eventType: String; var occurredAt: Date; var updatedAt: Date
    var approximateLocation: String; var latitude: Double; var longitude: Double; var precisionMeters: Int
    var sourceName: String; var sourceURL: String; var trustStatus: String; var severity: String
    var deduplicationGroup: String; var expiresAt: Date
    init(eventKey: String, title: String, eventType: String, occurredAt: Date = .now, updatedAt: Date = .now, approximateLocation: String, latitude: Double, longitude: Double, precisionMeters: Int, sourceName: String, sourceURL: String, trustStatus: String, severity: String, deduplicationGroup: String, expiresAt: Date) { self.eventKey = eventKey; self.title = title; self.eventType = eventType; self.occurredAt = occurredAt; self.updatedAt = updatedAt; self.approximateLocation = approximateLocation; self.latitude = latitude; self.longitude = longitude; self.precisionMeters = precisionMeters; self.sourceName = sourceName; self.sourceURL = sourceURL; self.trustStatus = trustStatus; self.severity = severity; self.deduplicationGroup = deduplicationGroup; self.expiresAt = expiresAt }
}

@Model
final class LocalFamilyMember {
    @Attribute(.unique) var memberKey: String
    var name: String; var relationship: String; var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \LocalLifeCircle.member) var lifeCircles: [LocalLifeCircle] = []
    init(memberKey: String = UUID().uuidString, name: String, relationship: String) { self.memberKey = memberKey; self.name = name; self.relationship = relationship; self.createdAt = .now }
}

@Model
final class LocalLifeCircle {
    @Attribute(.unique) var circleKey: String
    var name: String; var encryptedAddress: String; var latitude: Double; var longitude: Double; var radiusMeters: Int; var alertTypes: String
    var member: LocalFamilyMember?
    init(circleKey: String = UUID().uuidString, name: String, encryptedAddress: String, latitude: Double, longitude: Double, radiusMeters: Int, alertTypes: String, member: LocalFamilyMember? = nil) { self.circleKey = circleKey; self.name = name; self.encryptedAddress = encryptedAddress; self.latitude = latitude; self.longitude = longitude; self.radiusMeters = radiusMeters; self.alertTypes = alertTypes; self.member = member }
}

enum DemoSeed {
    @MainActor static func insertIfNeeded(into context: ModelContext) {
        guard (try? context.fetch(FetchDescriptor<LocalSafetyEvent>())).map(\.isEmpty) == true else { return }
        context.insert(LocalSafetyEvent(eventKey: "taipei-fire-demo-1", title: "火警通報", eventType: "火災", approximateLocation: "信義區松仁路附近", latitude: 25.0333, longitude: 121.5688, precisionMeters: 500, sourceName: "台北市政府消防局", sourceURL: "https://www.119.gov.taipei/", trustStatus: "官方已確認", severity: "需要注意", deduplicationGroup: "fire-xinyi-20260715", expiresAt: .now.addingTimeInterval(86_400)))
        try? context.save()
    }
}

enum LocalNotifications {
    static func requestPermission() async -> Bool { (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false }
    static func schedule(title: String, body: String, id: String) async { guard await requestPermission() else { return }; let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default; try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) }
}

struct ContentView: View {
    @Query private var members: [LocalFamilyMember]
    var body: some View {
        Group { if members.isEmpty { OnboardingView() } else { AppTabs() } }
    }
}

private struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var name = ""; @State private var placeName = "住家"; @State private var address = "台北市南港區"; @State private var radius = 1000
    var body: some View { NavigationStack { Form {
        Section { Image(systemName: "shield.lefthalf.filled").font(.system(size: 54)).foregroundStyle(.indigo).frame(maxWidth: .infinity).padding(.vertical, 12); Text("守護家人的日常生活圈。").font(.title2.bold()).frame(maxWidth: .infinity); Text("資料只儲存在這支手機；不會追蹤任何人的即時位置。").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity) }
        Section("先建立你的生活圈") { TextField("你的名稱", text: $name); TextField("地點名稱", text: $placeName); TextField("城市或地址", text: $address); Stepper("提醒半徑：\(radius) 公尺", value: $radius, in: 300...3000, step: 100) }
        Section { Button("完成設定") { let me = LocalFamilyMember(name: name.isEmpty ? "我" : name, relationship: "擁有者"); context.insert(me); context.insert(LocalLifeCircle(name: placeName.isEmpty ? "住家" : placeName, encryptedAddress: address, latitude: 25.0525, longitude: 121.6072, radiusMeters: radius, alertTypes: "火災、重大事故、天災", member: me)); try? context.save() }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity) }
    }.navigationTitle("歡迎使用安心圈") } }
}

private struct AppTabs: View {
    var body: some View { TabView { SafetyMapView().tabItem { Label("安全地圖", systemImage: "map.fill") }; EventListView().tabItem { Label("提醒中心", systemImage: "bell.badge.fill") }; FamilyListView().tabItem { Label("家人", systemImage: "person.2.fill") }; SettingsView().tabItem { Label("設定", systemImage: "slider.horizontal.3") } }.tint(.indigo) }
}

private struct SafetyMapView: View {
    @Query private var events: [LocalSafetyEvent]
    @Query private var members: [LocalFamilyMember]
    @State private var selected: LocalSafetyEvent?
    @State private var isPaused = UserDefaults.standard.bool(forKey: "alertsPaused")
    private let camera = MapCameraPosition.region(MKCoordinateRegion(center: .init(latitude: 25.035, longitude: 121.54), span: .init(latitudeDelta: 0.12, longitudeDelta: 0.18)))
    var body: some View { NavigationStack { VStack(spacing: 10) {
        HStack { Image(systemName: "checkmark.shield.fill").foregroundStyle(.green); VStack(alignment: .leading) { Text("生活圈附近暫無立即危險").font(.subheadline.bold()); Text("事件以來源、時間與距離篩選；未驗證線索不會推播。").font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(12).background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal)
        Map(initialPosition: camera) { ForEach(members.flatMap(\.lifeCircles)) { p in MapCircle(center: .init(latitude: p.latitude, longitude: p.longitude), radius: CLLocationDistance(p.radiusMeters)).foregroundStyle(.indigo.opacity(0.08)).stroke(.indigo.opacity(0.4), lineWidth: 1) }; ForEach(events.filter { $0.expiresAt > .now }) { e in Annotation(e.eventType, coordinate: .init(latitude: e.latitude, longitude: e.longitude)) { Button { selected = e } label: { Image(systemName: e.trustStatus == "官方已確認" ? "exclamationmark.triangle.fill" : "eye.fill").foregroundStyle(.white).padding(9).background(e.trustStatus == "官方已確認" ? .red : .orange, in: Circle()) } } } }.clipShape(RoundedRectangle(cornerRadius: 20)).padding(.horizontal).overlay(alignment: .bottomTrailing) { Button(isPaused ? "提醒已暫停" : "暫停提醒", systemImage: "bell.slash") { isPaused.toggle(); UserDefaults.standard.set(isPaused, forKey: "alertsPaused") }.font(.caption.bold()).padding(10).background(.thinMaterial, in: Capsule()).padding(26) }
        VStack(alignment: .leading) { Text("附近更新").font(.headline); if events.isEmpty { ContentUnavailableView("目前沒有事件", systemImage: "checkmark.shield") } else { ForEach(events.prefix(2)) { e in Button { selected = e } label: { EventRow(event: e, members: members) }.buttonStyle(.plain) } } }.padding(.horizontal)
    }.navigationTitle("安心圈").sheet(item: $selected) { EventDetailView(event: $0, members: members) } } }
}

private struct EventRow: View {
    let event: LocalSafetyEvent; let members: [LocalFamilyMember]
    var body: some View { HStack { Image(systemName: event.eventType == "火災" ? "flame.fill" : "exclamationmark.triangle.fill").foregroundStyle(event.trustStatus == "官方已確認" ? .red : .orange).frame(width: 25); VStack(alignment: .leading) { Text(event.title).font(.subheadline.bold()); Text("\(event.approximateLocation) · \(relativeDistance(event, members))").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(event.trustStatus).font(.caption2).foregroundStyle(event.trustStatus == "官方已確認" ? .red : .orange) }.padding(10).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12)) }
}

private func relativeDistance(_ event: LocalSafetyEvent, _ members: [LocalFamilyMember]) -> String {
    let point = CLLocation(latitude: event.latitude, longitude: event.longitude)
    let distances = members.flatMap(\.lifeCircles).map { point.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) }
    guard let nearest = distances.min() else { return "尚未設定生活圈" }
    return "距離生活圈 \(Int(nearest / 100) * 100) 公尺"
}

private struct EventDetailView: View {
    let event: LocalSafetyEvent; let members: [LocalFamilyMember]
    @Environment(\.modelContext) private var context; @Environment(\.dismiss) private var dismiss; @State private var unrelated = false
    var body: some View { NavigationStack { List {
        Section { Label(event.trustStatus, systemImage: event.trustStatus == "官方已確認" ? "checkmark.seal.fill" : "clock.badge.questionmark").foregroundStyle(event.trustStatus == "官方已確認" ? .red : .orange); Text(event.trustStatus == "官方已確認" ? "官方來源已確認。若有立即危險，請直接撥打 110 或 119。" : "資料仍在確認中，不會自動通知家人。") }
        Section("事件資訊") { LabeledContent("類型", value: event.eventType); LabeledContent("概略位置", value: event.approximateLocation); LabeledContent("影響範圍", value: relativeDistance(event, members)); LabeledContent("嚴重程度", value: event.severity); LabeledContent("位置精準度", value: "約 \(event.precisionMeters) 公尺") }
        Section("來源") { LabeledContent("資訊來源", value: event.sourceName); Link("查看原始來源", destination: URL(string: event.sourceURL)!) }
        Section { Button(unrelated ? "已隱藏相似提醒" : "此事件與我無關", systemImage: unrelated ? "checkmark" : "hand.thumbsdown") { unrelated = true }; Button("標記為已結束") { event.expiresAt = .now; try? context.save(); dismiss() }; Button("緊急情況請撥打 119", systemImage: "phone.fill") { UIApplication.shared.open(URL(string: "tel://119")!) }.foregroundStyle(.red) }
    }.navigationTitle(event.title).navigationBarTitleDisplayMode(.inline) } }
}

private struct EventListView: View {
    @Environment(\.modelContext) private var context; @Query(sort: \LocalSafetyEvent.occurredAt, order: .reverse) private var events: [LocalSafetyEvent]; @Query private var members: [LocalFamilyMember]; @State private var adding = false
    var body: some View { NavigationStack { List { ForEach(events.filter { $0.expiresAt > .now }) { EventRow(event: $0, members: members) }.onDelete { offsets in offsets.forEach { context.delete(events[$0]) }; try? context.save() } }.navigationTitle("提醒中心").toolbar { Button("新增事件", systemImage: "plus") { adding = true } }.sheet(isPresented: $adding) { EventEditorView() } } }
}

private struct EventEditorView: View {
    @Environment(\.modelContext) private var context; @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var type = "火災"; @State private var location = "台北市"; @State private var source = "手動測試"; @State private var official = true
    var body: some View { NavigationStack { Form { TextField("事件名稱", text: $title); Picker("類型", selection: $type) { ForEach(["火災", "重大交通事故", "天災", "公共安全"], id: \.self) { Text($0) } }; TextField("概略位置", text: $location); TextField("來源名稱", text: $source); Toggle("官方已確認", isOn: $official); Text("手動新增僅供 MVP 測試；上線前應接正式資料來源。 ").font(.caption).foregroundStyle(.secondary) }.navigationTitle("新增測試事件").toolbar { ToolbarItem(placement: .confirmationAction) { Button("儲存") { let e = LocalSafetyEvent(eventKey: UUID().uuidString, title: title.isEmpty ? "測試事件" : title, eventType: type, approximateLocation: location, latitude: 25.035, longitude: 121.54, precisionMeters: 800, sourceName: source, sourceURL: "https://www.apple.com", trustStatus: official ? "官方已確認" : "持續確認中", severity: official ? "需要注意" : "持續確認中", deduplicationGroup: UUID().uuidString, expiresAt: .now.addingTimeInterval(86_400)); context.insert(e); try? context.save(); if official { Task { await LocalNotifications.schedule(title: e.title, body: "\(e.approximateLocation)附近有需要注意的事件。", id: e.eventKey) } }; dismiss() } }; ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } } } }
}

private struct FamilyListView: View {
    @Environment(\.modelContext) private var context; @Query private var members: [LocalFamilyMember]; @State private var adding = false
    var body: some View { NavigationStack { List { ForEach(members) { m in NavigationLink { MemberDetailView(member: m) } label: { HStack { Image(systemName: "person.fill").foregroundStyle(.indigo); VStack(alignment: .leading) { Text(m.name); Text("\(m.lifeCircles.count) 個生活圈 · \(m.relationship)").font(.caption).foregroundStyle(.secondary) } } }.swipeActions { Button(role: .destructive) { context.delete(m); try? context.save() } label: { Label("刪除", systemImage: "trash") } } } }.navigationTitle("家人與生活圈").toolbar { Button("新增家人", systemImage: "person.badge.plus") { adding = true } }.sheet(isPresented: $adding) { MemberEditorView() } } }
}

private struct MemberEditorView: View { @Environment(\.modelContext) private var context; @Environment(\.dismiss) private var dismiss; @State private var name = ""; @State private var relationship = "家人"; var body: some View { NavigationStack { Form { TextField("名稱", text: $name); TextField("關係", text: $relationship) }.navigationTitle("新增家人").toolbar { ToolbarItem(placement: .confirmationAction) { Button("儲存") { context.insert(LocalFamilyMember(name: name.isEmpty ? "家人" : name, relationship: relationship)); try? context.save(); dismiss() } }; ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } } } } }
private struct MemberDetailView: View { let member: LocalFamilyMember; @State private var adding = false; var body: some View { List { Section { Text("僅儲存生活圈，未啟用即時位置追蹤").font(.caption).foregroundStyle(.secondary) }; Section("生活圈") { ForEach(member.lifeCircles) { p in VStack(alignment: .leading) { Text(p.name).font(.headline); Text("\(p.encryptedAddress) · 半徑 \(p.radiusMeters) 公尺").font(.subheadline).foregroundStyle(.secondary); Text("提醒：\(p.alertTypes)").font(.caption).foregroundStyle(.indigo) } } }; Button("新增生活圈", systemImage: "plus.circle.fill") { adding = true } }.navigationTitle(member.name).sheet(isPresented: $adding) { CircleEditorView(member: member) } } }

private struct CircleEditorView: View {
    let member: LocalFamilyMember; @Environment(\.modelContext) private var context; @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var address = ""; @State private var radius = 1000; @State private var found: MKMapItem?
    var body: some View { NavigationStack { Form { TextField("地點名稱", text: $name); TextField("地址或地標", text: $address); Button("使用 Apple Maps 搜尋") { Task { let request = MKLocalSearch.Request(); request.naturalLanguageQuery = address; found = try? await MKLocalSearch(request: request).start().mapItems.first } }; if let found { Text("找到：\(found.name ?? address)").foregroundStyle(.green) }; Stepper("提醒半徑：\(radius) 公尺", value: $radius, in: 300...3000, step: 100); Text("提醒類型：火災、重大事故、天災").font(.caption).foregroundStyle(.secondary) }.navigationTitle("新增生活圈").toolbar { ToolbarItem(placement: .confirmationAction) { Button("儲存") { let coordinate = found?.location.coordinate ?? .init(latitude: 25.035, longitude: 121.54); context.insert(LocalLifeCircle(name: name.isEmpty ? "生活圈" : name, encryptedAddress: found?.name ?? address, latitude: coordinate.latitude, longitude: coordinate.longitude, radiusMeters: radius, alertTypes: "火災、重大事故、天災", member: member)); try? context.save(); dismiss() } }; ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } } } }
}

private struct SettingsView: View { @AppStorage("alertsEnabled") private var alertsEnabled = true; @AppStorage("alertsPaused") private var paused = false; @AppStorage("highConfidenceOnly") private var highConfidenceOnly = true; var body: some View { NavigationStack { Form { Section("提醒偏好") { Toggle("啟用本機提醒", isOn: $alertsEnabled); Toggle("暴力事件僅高可信度提醒", isOn: $highConfidenceOnly); Toggle("暫停提醒", isOn: $paused); Button("允許通知") { Task { _ = await LocalNotifications.requestPermission() } } }; Section("資料與安全") { Text("所有家人、生活圈與事件資料皆只保存在此裝置。刪除 App 會刪除本機資料。"); Text("安心圈不是 110、119 或緊急救難服務。遇立即危險請直接撥打 110 或 119。") } }.navigationTitle("提醒設定") } } }
#Preview { ContentView().modelContainer(for: [LocalSafetyEvent.self, LocalFamilyMember.self, LocalLifeCircle.self], inMemory: true) }
