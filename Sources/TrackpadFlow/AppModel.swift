import AppKit
import SwiftUI
import ApplicationServices
import TrackpadBridge

final class AppModel: ObservableObject {
    static weak var active: AppModel?
    @Published var selection = 0
    @Published var enabled = false { didSet { resetEngines() } }
    @Published var diagnosticOnly = true { didSet { resetEngines() } }
    @Published var pinchEnabled = true { didSet { defaults.set(pinchEnabled, forKey: "pinchEnabled"); resetEngines() } }
    @Published var pinchSensitivity = 1.0 { didSet { defaults.set(pinchSensitivity, forKey: "pinchSensitivity"); resetEngines() } }
    @Published var pinchScale = 1.0
    @Published var fingers: Int { didSet { defaults.set(fingers, forKey: "fingers"); resetEngines() } }
    @Published var threshold: Double { didSet { defaults.set(threshold, forKey: "threshold"); resetEngines() } }
    @Published var gap: Double { didSet { defaults.set(gap, forKey: "gap") } }
    @Published var mappings: [String: String] { didSet { defaults.set(mappings, forKey: "mappings") } }
    @Published var selectedCorner = TrackpadCorner.topLeft
    @Published var cornersEnabled = true { didSet { defaults.set(cornersEnabled, forKey: "cornersEnabled"); resetCornerEngines() } }
    @Published var cornerZones = CornerZone.defaults {
        didSet {
            if let data = try? JSONEncoder().encode(cornerZones) { defaults.set(data, forKey: "cornerZones") }
            resetCornerEngines()
        }
    }
    @Published var clickFilterReady = false
    @Published var contacts: [Contact] = []
    @Published var deviceCount = 0
    @Published var touchFrames = 0
    @Published var trusted = false
    @Published var inputGranted = false
    @Published var lastGesture = "等待手势"
    @Published var lastResult = "先在测试区试试多指滑动"
    @Published var lastDirection: SwipeDirection?
    @Published var lastContactTime: Date?
    @Published var bridgeError: String?
    @Published var history: [String] = []
    private let defaults = UserDefaults.standard
    private let windows = WindowManager()
    private var engines: [UInt64: GestureEngine] = [:]
    private var gestureApps: [UInt64: NSRunningApplication] = [:]
    private enum GestureOwner { case swipe, pinch }
    private var gestureOwners: [UInt64: GestureOwner] = [:]
    private var pinchEngines: [UInt64: PinchEngine] = [:]
    private var resizingDevice: UInt64?
    private var lastPinchWrite = Date.distantPast
    private var cornerEngines: [UInt64: CornerTapEngine] = [:]
    private var cornerApps: [UInt64: NSRunningApplication] = [:]
    private let clickFilter = CornerClickFilter()
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var ticks = 0
    private var lastActionAt = Date.distantPast
    private var sleeping = false
    private var preferredDevice: UInt64?

    init() {
        let savedFingers = defaults.integer(forKey: "fingers")
        fingers = [3, 4].contains(savedFingers) ? savedFingers : 3
        let savedThreshold = defaults.double(forKey: "threshold")
        threshold = (0.08...0.25).contains(savedThreshold) ? savedThreshold : 0.14
        gap = defaults.object(forKey: "gap") == nil ? 8 : min(max(defaults.double(forKey: "gap"), 0), 24)
        var initialMappings = defaults.dictionary(forKey: "mappings") as? [String: String] ?? ["left": "leftHalf", "right": "rightHalf", "up": "maximize", "down": "minimize"]
        // Apply the user's requested change to existing installations once, while
        // preserving the other directions and subsequent customizations.
        if !defaults.bool(forKey: "didApplyMinimizeDownSwipeV1") {
            initialMappings["down"] = WindowAction.minimize.rawValue
            defaults.set(initialMappings, forKey: "mappings")
            defaults.set(true, forKey: "didApplyMinimizeDownSwipeV1")
        }
        mappings = initialMappings
        pinchEnabled = defaults.object(forKey: "pinchEnabled") as? Bool ?? true
        let storedSensitivity = defaults.double(forKey: "pinchSensitivity")
        pinchSensitivity = (0.5...2).contains(storedSensitivity) ? storedSensitivity : 1
        cornersEnabled = defaults.object(forKey: "cornersEnabled") as? Bool ?? true
        if let data = defaults.data(forKey: "cornerZones"), let stored = try? JSONDecoder().decode([String: CornerZone].self, from: data) {
            cornerZones = Dictionary(uniqueKeysWithValues: TrackpadCorner.allCases.map { ($0.rawValue, (stored[$0.rawValue] ?? CornerZone()).clamped) })
        }
        clickFilter.shouldReserveClick = { [weak self] in self?.shouldReserveNativeClick() ?? false }
        Self.active = self
        refreshPermissions()
        startBridge()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = true; TFStop(); self?.resetEngines()
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.sleeping = false; self?.rescan() }
        })
    }
    func shutdown() { timer?.invalidate(); windows.endPinch(); clickFilter.stop(); TFStop(); workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver); Self.active = nil }
    private func resetCornerEngines() { cornerEngines.removeAll(); cornerApps.removeAll() }
    private func resetEngines() {
        engines.removeAll(); gestureApps.removeAll(); gestureOwners.removeAll(); pinchEngines.removeAll()
        windows.endPinch(); resizingDevice = nil; pinchScale = 1
        resetCornerEngines(); preferredDevice = nil
    }
    private func tick() {
        refreshPermissions(); ticks += 1
        if enabled && cornersEnabled && trusted && !clickFilter.isRunning { clickFilterReady = clickFilter.start() }
        if !sleeping && ticks % 5 == 0 { deviceCount = Int(TFRefresh()) }
        if let lastContactTime, Date().timeIntervalSince(lastContactTime) > 0.3, !contacts.isEmpty { contacts = [] }
    }
    func refreshPermissions() {
        trusted = AXIsProcessTrusted()
        inputGranted = CGPreflightListenEventAccess()
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSettings("Privacy_Accessibility")
    }
    func requestInput() { _ = CGRequestListenEventAccess(); openSettings("Privacy_ListenEvent") }
    func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
    func openTrackpadSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    func rescan() { TFStop(); resetEngines(); startBridge() }
    private func startBridge() {
        let result = TFStart { device, points, count, time in
            let snapshot: [Contact] = points.map { pointer in
                (0..<Int(count)).map { i in Contact(id: pointer[i].identifier, x: Double(pointer[i].x), y: Double(pointer[i].y)) }
            } ?? []
            DispatchQueue.main.async { AppModel.active?.consume(device: device, contacts: snapshot, time: time) }
        }
        deviceCount = max(Int(result), 0)
        bridgeError = result < 0 ? "当前系统未能加载多指输入接口（\(result)）" : nil
    }
    private func consume(device: UInt64, contacts points: [Contact], time: Double) {
        guard !sleeping else { return }
        touchFrames += 1
        if !points.isEmpty { preferredDevice = device }
        if preferredDevice == device { contacts = points; lastContactTime = Date() }
        defer {
            if points.isEmpty {
                gestureApps.removeValue(forKey: device); cornerApps.removeValue(forKey: device); gestureOwners.removeValue(forKey: device)
                if resizingDevice == device { windows.endPinch(); resizingDevice = nil }
            }
        }
        if engines[device] == nil { engines[device] = GestureEngine(fingerCount: fingers, threshold: threshold) }
        if points.count == fingers && gestureApps[device] == nil {
            gestureApps[device] = NSWorkspace.shared.frontmostApplication
        }
        let direction = engines[device]!.consume(points, at: time)
        if pinchEngines[device] == nil { pinchEngines[device] = PinchEngine() }
        let pinch = pinchEnabled ? pinchEngines[device]!.consume(points, at: time) : nil
        if cornerEngines[device] == nil { cornerEngines[device] = CornerTapEngine(zones: cornerZones) }
        if !points.isEmpty && cornerApps[device] == nil { cornerApps[device] = NSWorkspace.shared.frontmostApplication }
        let corner = cornerEngines[device]!.consume(points, at: time)
        let tapApp = cornerApps[device]
        let swipeApp = gestureApps[device]
        if pinchEnabled, let pinch, gestureOwners[device] != .swipe {
            if pinch.phase == .began && gestureOwners[device] == nil { gestureOwners[device] = .pinch }
            if gestureOwners[device] == .pinch { processPinch(pinch, device: device, target: tapApp) }
        }
        if gestureOwners[device] == .pinch { return }
        if cornersEnabled, let corner {
            lastDirection = nil
            lastGesture = "单指轻点\(corner.title)"
            if enabled && !diagnosticOnly && !clickFilter.isRunning {
                record("四角暂未启用：无法拦截原始点击，请检查辅助功能权限"); return
            }
            performRecognized(corner.action, target: tapApp)
            return
        }
        guard let direction else { return }
        guard gestureOwners[device] == nil else { return }
        gestureOwners[device] = .swipe
        lastDirection = direction
        lastGesture = "\(fingers) 指\(direction.title)"
        performRecognized(action(for: direction), target: swipeApp)
    }
    private func processPinch(_ event: PinchUpdate, device: UInt64, target: NSRunningApplication?) {
        let scale = min(max(pow(event.scale, pinchSensitivity), 0.20), 4)
        pinchScale = scale; lastDirection = nil
        lastGesture = event.scale < 1 ? "三指向内捏合 · 缩小窗口" : "三指向外张开 · 放大窗口"
        if !enabled || diagnosticOnly {
            lastResult = "捏合缩放 \(Int((scale * 100).rounded()))%（仅测试）"
            return
        }
        if event.phase == .began {
            guard resizingDevice == nil else { return }
            if let error = windows.beginPinch(app: target, gap: gap) { record(error); return }
            resizingDevice = device; lastPinchWrite = .distantPast
        }
        guard resizingDevice == device else { return }
        if event.phase == .cancelled {
            windows.endPinch(); resizingDevice = nil; record("接触数据已改变，已停止缩放并保留当前大小"); return
        }
        if event.phase != .ended && Date().timeIntervalSince(lastPinchWrite) < 1.0 / 30 { return }
        lastPinchWrite = Date()
        switch windows.updatePinch(scale: scale) {
        case .resized(let size):
            lastResult = "窗口大小 \(Int(size.width.rounded())) × \(Int(size.height.rounded())) pt · \(Int((scale * 100).rounded()))%"
        case .stopped(let reason):
            record(reason); windows.endPinch(); resizingDevice = nil
        }
        if event.phase == .ended { windows.endPinch(); resizingDevice = nil; record(lastResult) }
    }
    private func performRecognized(_ action: WindowAction, target: NSRunningApplication?) {
        if !enabled || diagnosticOnly { record("\(lastGesture) → \(action.title)（仅测试）"); return }
        guard Date().timeIntervalSince(lastActionAt) > 0.4 else { return }
        lastActionAt = Date()
        // Use the app focused when the fingers first touched; do not redirect a
        // gesture to a different app if a system gesture changes focus mid-swipe.
        if action != .showDesktop {
            guard let target, target.processIdentifier == NSWorkspace.shared.frontmostApplication?.processIdentifier else {
                record("焦点已改变，已跳过这次窗口操作"); return
            }
        }
        record(windows.perform(action, gap: gap, app: target))
    }
    private func shouldReserveNativeClick() -> Bool {
        guard enabled, !diagnosticOnly, cornersEnabled, trusted,
              NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        var point = TFContact()
        guard TFRecentSingleContact(&point) != 0 else { return false }
        let contact = Contact(id: point.identifier, x: Double(point.x), y: Double(point.y))
        return TrackpadCorner.allCases.contains { zone(for: $0).contains(contact, corner: $0) }
    }
    func zone(for corner: TrackpadCorner) -> CornerZone { (cornerZones[corner.rawValue] ?? CornerZone()).clamped }
    func setZone(_ zone: CornerZone, for corner: TrackpadCorner) { cornerZones[corner.rawValue] = zone.clamped }
    private func record(_ result: String) {
        lastResult = result
        history.insert(result, at: 0)
        if history.count > 6 { history.removeLast() }
    }
    func action(for direction: SwipeDirection) -> WindowAction { WindowAction(rawValue: mappings[direction.rawValue] ?? "") ?? .none }
    func setAction(_ action: WindowAction, for direction: SwipeDirection) { mappings[direction.rawValue] = action.rawValue }
    func activate() {
        if !trusted { requestAccessibility(); return }
        clickFilterReady = clickFilter.start()
        diagnosticOnly = false; enabled = true
        lastResult = "已开启；切换到目标窗口后滑动、捏合或轻点四角"
    }
    var status: String {
        if let bridgeError { return bridgeError }
        if deviceCount == 0 { return "未发现多点触控设备" }
        if !trusted { return "测试可用 · 窗口控制需要权限" }
        return enabled && !diagnosticOnly ? "窗口手势已开启" : "手势测试模式"
    }
}
