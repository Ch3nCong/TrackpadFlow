import AppKit
import ApplicationServices

enum PinchResizeOutcome { case resized(CGSize); case stopped(String) }

final class WindowManager {
    private struct SavedFrame { let window: AXUIElement; let pid: pid_t; let frame: CGRect }
    private var saved: [SavedFrame] = []
    private var cycleOrder: [pid_t: [AXUIElement]] = [:]
    private struct PinchSession {
        let app: NSRunningApplication
        let application: AXUIElement
        let window: AXUIElement
        let initial: CGRect
        let visible: CGRect
        let gap: Double
        var lastTarget: CGRect?
        var lastSize: CGSize
    }
    private var pinchSession: PinchSession?

    func endPinch() { pinchSession = nil }

    /// Returns an explanation on failure; nil means the window was captured.
    func beginPinch(app: NSRunningApplication?, gap: Double) -> String? {
        pinchSession = nil
        guard AXIsProcessTrusted() else { return "请先授予辅助功能权限" }
        guard let app, !app.isTerminated, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.processIdentifier == NSWorkspace.shared.frontmostApplication?.processIdentifier else { return "请在目标应用窗口中捏合" }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.15)
        guard let window = element(application, kAXFocusedWindowAttribute) ?? element(application, kAXMainWindowAttribute) else { return "未找到可缩放的窗口" }
        AXUIElementSetMessagingTimeout(window, 0.15)
        guard (value(window, "AXFullScreen") as? Bool) != true else { return "请先退出系统全屏，再捏合缩放" }
        var movable = DarwinBoolean(false), resizable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &movable)
        AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &resizable)
        guard movable.boolValue && resizable.boolValue, let initial = frame(window), let (_, visible) = screen(for: initial) else {
            return "该窗口不支持捏合调整大小"
        }
        saved.removeAll { NSRunningApplication(processIdentifier: $0.pid)?.isTerminated != false }
        if !saved.contains(where: { $0.pid == app.processIdentifier && CFEqual($0.window, window) }) {
            if saved.count >= 100 { saved.removeFirst() }
            saved.append(SavedFrame(window: window, pid: app.processIdentifier, frame: initial))
        }
        pinchSession = PinchSession(app: app, application: application, window: window, initial: initial,
                                    visible: visible, gap: gap, lastSize: initial.size)
        return nil
    }

    func updatePinch(scale: Double) -> PinchResizeOutcome {
        guard var session = pinchSession else { return .stopped("捏合已结束") }
        guard AXIsProcessTrusted(), !session.app.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == session.app.processIdentifier,
              let focused = element(session.application, kAXFocusedWindowAttribute), CFEqual(focused, session.window) else {
            pinchSession = nil; return .stopped("当前窗口已改变，已停止捏合缩放")
        }
        let target = WindowGeometry.pinched(initial: session.initial, scale: scale, visible: session.visible, gap: session.gap)
        if let previous = session.lastTarget, abs(previous.width - target.width) < 2, abs(previous.height - target.height) < 2 {
            return .resized(session.lastSize)
        }
        var dimensions = target.size
        guard let sizeValue = AXValueCreate(.cgSize, &dimensions),
              AXUIElementSetAttributeValue(session.window, kAXSizeAttribute as CFString, sizeValue) == .success,
              let actual = frame(session.window) else {
            pinchSession = nil; return .stopped("应用未能完成窗口缩放，已停止本次捏合")
        }
        // Read the actual size: apps can enforce their own minimum dimensions.
        let area = session.visible.insetBy(dx: session.gap, dy: session.gap)
        var point = CGPoint(x: max(area.minX, min(session.initial.midX - actual.width / 2, area.maxX - actual.width)),
                            y: max(area.minY, min(session.initial.midY - actual.height / 2, area.maxY - actual.height)))
        guard let position = AXValueCreate(.cgPoint, &point),
              AXUIElementSetAttributeValue(session.window, kAXPositionAttribute as CFString, position) == .success else {
            pinchSession = nil; return .stopped("窗口已调整大小，但应用未允许调整位置")
        }
        session.lastTarget = target; session.lastSize = actual.size; pinchSession = session
        return .resized(actual.size)
    }

    private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }
    private func element(_ source: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let result = value(source, attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }
    private func frame(_ window: AXUIElement) -> CGRect? {
        guard let position = value(window, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = value(window, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
    private func screen(for window: CGRect) -> (NSScreen, CGRect)? {
        guard let first = NSScreen.screens.first else { return nil }
        let candidates = NSScreen.screens.map { screen in
            (screen, WindowGeometry.axRect(from: screen.visibleFrame, primaryHeight: first.frame.height))
        }
        return candidates.max { a, b in
            let ia = a.1.intersection(window), ib = b.1.intersection(window)
            return (ia.isNull ? 0 : ia.width * ia.height) < (ib.isNull ? 0 : ib.width * ib.height)
        }
    }

    func perform(_ action: WindowAction, gap: Double, app: NSRunningApplication? = nil) -> String {
        guard action != .none else { return "此方向未设置动作" }
        guard AXIsProcessTrusted() else { return "请先授予辅助功能权限" }
        if action == .showDesktop { return showDesktop() }
        guard let running = app ?? NSWorkspace.shared.frontmostApplication,
              running.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !running.isTerminated else { return "请切换到要管理的应用窗口" }
        let application = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.25)
        guard let window = element(application, kAXFocusedWindowAttribute) ?? element(application, kAXMainWindowAttribute) else {
            return "未找到可调整的窗口（\(running.localizedName ?? "当前应用")）"
        }
        AXUIElementSetMessagingTimeout(window, 0.25)
        if let fullScreen = value(window, "AXFullScreen") as? Bool, fullScreen {
            return "请先退出系统全屏，再调整窗口"
        }
        if action == .close {
            guard let button = element(window, kAXCloseButtonAttribute),
                  (value(button, kAXEnabledAttribute) as? Bool) != false else { return "该窗口没有可用的关闭按钮" }
            let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
            return result == .success ? "已请求关闭窗口；如有未保存内容，请处理应用提示" : "关闭请求未确认，请检查应用窗口"
        }
        if action == .minimize {
            var settable = DarwinBoolean(false)
            AXUIElementIsAttributeSettable(window, kAXMinimizedAttribute as CFString, &settable)
            guard settable.boolValue else { return "该窗口不支持最小化" }
            let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            guard result == .success else { return "该应用未允许最小化窗口" }
            return (value(window, kAXMinimizedAttribute) as? Bool) == true
                ? "\(running.localizedName ?? "窗口") · 最小化" : "已发送最小化请求"
        }
        guard let current = frame(window), let (display, visible) = screen(for: current) else {
            return "无法读取当前窗口的位置和大小"
        }
        if action == .nextWindow || action == .previousWindow {
            guard let windows = value(application, kAXWindowsAttribute) as? [AXUIElement] else { return "无法读取当前应用的窗口" }
            let live = windows.filter {
                (value($0, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole &&
                (value($0, kAXMinimizedAttribute) as? Bool) != true
            }
            // AXWindows can change order after raising a window; retain a stable ring.
            var available = (cycleOrder[running.processIdentifier] ?? []).filter { old in live.contains { CFEqual($0, old) } }
            for candidate in live where !available.contains(where: { CFEqual($0, candidate) }) { available.append(candidate) }
            cycleOrder[running.processIdentifier] = available
            cycleOrder = cycleOrder.filter { NSRunningApplication(processIdentifier: $0.key)?.isTerminated == false }
            guard available.count > 1, let index = available.firstIndex(where: { CFEqual($0, window) }) else {
                return "当前应用只有一个可切换窗口"
            }
            let offset = action == .nextWindow ? 1 : available.count - 1
            let next = available[(index + offset) % available.count]
            let result = AXUIElementPerformAction(next, kAXRaiseAction as CFString)
            return result == .success ? action.title : "该应用未允许切换窗口"
        }
        var positionSettable = DarwinBoolean(false), sizeSettable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &positionSettable)
        AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &sizeSettable)
        guard positionSettable.boolValue && sizeSettable.boolValue else { return "该窗口不支持移动或调整大小" }
        saved.removeAll { NSRunningApplication(processIdentifier: $0.pid)?.isTerminated != false }
        let savedIndex = saved.firstIndex { $0.pid == running.processIdentifier && CFEqual($0.window, window) }
        var target: CGRect
        if action == .restore {
            guard let savedIndex else { return "尚无原始位置；先对这个窗口分屏或最大化" }
            let original = saved[savedIndex].frame
            let restoreArea = screen(for: original)?.1 ?? visible
            target = CGRect(x: min(max(original.minX, restoreArea.minX), restoreArea.maxX - min(original.width, restoreArea.width)),
                            y: min(max(original.minY, restoreArea.minY), restoreArea.maxY - min(original.height, restoreArea.height)),
                            width: min(original.width, restoreArea.width), height: min(original.height, restoreArea.height))
        } else if action == .nextDisplay {
            guard NSScreen.screens.count > 1, let index = NSScreen.screens.firstIndex(of: display), let first = NSScreen.screens.first else {
                return "当前只有一个显示器"
            }
            let next = NSScreen.screens[(index + 1) % NSScreen.screens.count]
            let area = WindowGeometry.axRect(from: next.visibleFrame, primaryHeight: first.frame.height)
            target = WindowGeometry.target(.center, visible: area, current: current, gap: gap)
        } else { target = WindowGeometry.target(action, visible: visible, current: current, gap: gap) }
        if action != .restore && savedIndex == nil {
            if saved.count >= 100 { saved.removeFirst() }
            saved.append(SavedFrame(window: window, pid: running.processIdentifier, frame: current))
        }
        var point = target.origin, dimensions = target.size
        guard let sizeValue = AXValueCreate(.cgSize, &dimensions), let pointValue = AXValueCreate(.cgPoint, &point) else { return "无法计算窗口位置" }
        // Shrink before moving, then repeat size: some apps clamp against the old screen.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pointValue)
        let resized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        guard moved == .success && resized == .success else { return "窗口仅部分调整；该应用可能限制了窗口大小" }
        guard let actual = frame(window) else { return "已发送窗口调整请求" }
        let matches = abs(actual.minX - target.minX) < 8 && abs(actual.minY - target.minY) < 8 &&
            abs(actual.width - target.width) < 8 && abs(actual.height - target.height) < 8
        if action == .restore && matches, let savedIndex { saved.remove(at: savedIndex) }
        return matches ? "\(running.localizedName ?? "窗口") · \(action.title)" : "已调整；窗口受应用最小尺寸等限制"
    }

    private func showDesktop() -> String {
        // Honor a configured system shortcut. With no override, macOS uses Fn-F11.
        let hotkeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString) as? [String: Any]
        let binding = hotkeys?["36"] as? [String: Any]
        if let enabled = binding?["enabled"] as? Bool, !enabled { return "系统“显示桌面”快捷键已关闭，请在键盘快捷键中启用" }
        var key: CGKeyCode = 103
        var flags = CGEventFlags.maskSecondaryFn
        if let value = binding?["value"] as? [String: Any], let parameters = value["parameters"] as? [NSNumber], parameters.count >= 3 {
            let code = parameters[1].intValue
            guard (0..<128).contains(code) else { return "无法读取“显示桌面”快捷键，请在系统设置中重新设置" }
            key = CGKeyCode(code); flags = CGEventFlags(rawValue: parameters[2].uint64Value)
        }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return "无法创建显示桌面操作" }
        down.flags = flags; up.flags = flags
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        return "已触发系统“显示桌面”；再次轻点可切回窗口"
    }
}
