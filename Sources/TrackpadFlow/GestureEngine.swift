import Foundation
import CoreGraphics

enum SwipeDirection: String, CaseIterable, Identifiable {
    case left, right, up, down
    var id: String { rawValue }
    var title: String { switch self { case .left: return "左滑"; case .right: return "右滑"; case .up: return "上滑"; case .down: return "下滑" } }
    var symbol: String { "arrow." + rawValue }
}

struct Contact: Equatable {
    let id: Int32
    let x: Double
    let y: Double
}

enum PinchPhase: Equatable { case began, changed, ended, cancelled }
struct PinchUpdate: Equatable { let phase: PinchPhase; let scale: Double }

/// Compares the distances between the same three fingers. Translation and
/// rotation preserve these distances; a pinch changes at least two of them.
struct PinchEngine {
    private var origins: [Int32: Contact] = [:]
    private var active = false
    private var blocked = false
    private var lastFrame: Double?
    private var began = 0.0
    private var lastScale = 1.0

    private func cancel() -> PinchUpdate? { active ? PinchUpdate(phase: .cancelled, scale: lastScale) : nil }
    mutating func consume(_ points: [Contact], at time: Double) -> PinchUpdate? {
        guard time.isFinite else { let event = cancel(); active = false; blocked = true; return event }
        if let lastFrame, time < lastFrame || time - lastFrame > 0.25 {
            let event = cancel(); active = false; blocked = true; self.lastFrame = time
            if points.isEmpty { self = PinchEngine() }
            return event
        }
        lastFrame = time
        if points.isEmpty {
            let event = active ? PinchUpdate(phase: .ended, scale: lastScale) : nil
            self = PinchEngine(); return event
        }
        guard !blocked else { return nil }
        if points.count > 3 {
            let event = cancel(); active = false; blocked = true; return event
        }
        if points.count < 3 {
            guard !origins.isEmpty else { return nil }
            let event = active ? PinchUpdate(phase: .ended, scale: lastScale) : nil
            active = false; blocked = true; return event
        }
        let ids = Set(points.map(\.id))
        guard ids.count == 3, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
            let event = cancel(); active = false; blocked = true; return event
        }
        if origins.isEmpty {
            origins = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) }); began = time
            return nil
        }
        guard Set(origins.keys) == ids else { let event = cancel(); active = false; blocked = true; return event }
        let start = points.map { origins[$0.id]! }
        var initialDistances: [Double] = [], currentDistances: [Double] = []
        for i in 0..<2 {
            for j in (i + 1)..<3 {
                initialDistances.append(hypot(start[i].x - start[j].x, start[i].y - start[j].y))
                currentDistances.append(hypot(points[i].x - points[j].x, points[i].y - points[j].y))
            }
        }
        let initialSpan = sqrt(initialDistances.map { $0 * $0 }.reduce(0, +) / 3)
        guard initialSpan >= 0.07, initialDistances.allSatisfy({ $0 > 0.025 }) else {
            let event = cancel(); active = false; blocked = true; return event
        }
        let dx = zip(points, start).map { $0.x - $1.x }.reduce(0, +) / 3
        let dy = zip(points, start).map { $0.y - $1.y }.reduce(0, +) / 3
        guard hypot(dx, dy) <= max(0.06, initialSpan * 0.5) else {
            let event = cancel(); active = false; blocked = true; return event
        }
        let ratio = sqrt(currentDistances.map { $0 * $0 }.reduce(0, +) / 3) / initialSpan
        guard ratio.isFinite, ratio >= 0.20, ratio <= 4 else {
            let event = cancel(); active = false; blocked = true; return event
        }
        if !active {
            let ratios = zip(currentDistances, initialDistances).map { $0 / $1 }
            let sign = ratio > 1 ? 1.0 : -1.0
            let coherentPairs = ratios.filter { ($0 - 1) * sign >= 0.04 }.count
            guard time - began >= 0.06, abs(log(ratio)) >= 0.08, coherentPairs >= 2 else { return nil }
            active = true; lastScale = ratio
            return PinchUpdate(phase: .began, scale: ratio)
        }
        lastScale = ratio
        return PinchUpdate(phase: .changed, scale: ratio)
    }
}

/// One action per complete contact sequence. Finger identities and coherent movement
/// distinguish a swipe from a pinch, staggered lift-off, or adding a fourth finger.
struct GestureEngine {
    var fingerCount = 3
    var threshold = 0.14
    private var origins: [Int32: Contact] = [:]
    private var began: Double = 0
    private var locked = false
    private var lastTime: Double = 0
    private var lastTrigger: Double = -.infinity

    mutating func reset() { origins.removeAll(); locked = false; began = 0; lastTime = 0 }

    mutating func consume(_ contacts: [Contact], at time: Double) -> SwipeDirection? {
        guard time.isFinite else { return nil }
        if lastTime > 0 && (time - lastTime > 0.25 || time < lastTime) { reset() }
        lastTime = time
        if contacts.isEmpty { reset(); return nil }
        guard !locked else { return nil }
        if contacts.count > fingerCount { locked = true; return nil }
        guard contacts.count == fingerCount else {
            if !origins.isEmpty { locked = true }
            return nil
        }
        let ids = Set(contacts.map(\.id))
        guard ids.count == contacts.count, contacts.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
            locked = true; return nil
        }
        if origins.isEmpty {
            origins = Dictionary(uniqueKeysWithValues: contacts.map { ($0.id, $0) }); began = time
            return nil
        }
        guard Set(origins.keys) == ids, time - began <= 1.4 else { locked = true; return nil }
        guard time - began >= 0.06, time - lastTrigger >= 0.4 else { return nil }
        let deltas = contacts.map { (x: $0.x - origins[$0.id]!.x, y: $0.y - origins[$0.id]!.y) }
        let dx = deltas.map(\.x).reduce(0, +) / Double(fingerCount)
        let dy = deltas.map(\.y).reduce(0, +) / Double(fingerCount)
        let horizontal = abs(dx) > abs(dy) * 1.35
        let vertical = abs(dy) > abs(dx) * 1.35
        guard horizontal || vertical else { return nil }
        let distance = horizontal ? dx : dy
        guard abs(distance) >= threshold else { return nil }
        // Every finger must move in the same direction, with limited relative spread.
        guard deltas.allSatisfy({ delta in
            let component = horizontal ? delta.x : delta.y
            return component * distance > 0 && abs(component - distance) < threshold * 0.65
        }) else { return nil }
        locked = true; lastTrigger = time
        if horizontal { return dx < 0 ? .left : .right }
        return dy > 0 ? .up : .down
    }
}

enum WindowAction: String, CaseIterable, Identifiable {
    case leftHalf, rightHalf, maximize, minimize, close, showDesktop, restore, topHalf, bottomHalf, center, nextDisplay, previousWindow, nextWindow, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .leftHalf: return "左半屏"
        case .rightHalf: return "右半屏"
        case .maximize: return "最大化"
        case .minimize: return "最小化"
        case .close: return "关闭窗口"
        case .showDesktop: return "显示桌面"
        case .restore: return "恢复原位"
        case .topHalf: return "上半屏"
        case .bottomHalf: return "下半屏"
        case .center: return "居中"
        case .nextDisplay: return "移到下一显示器"
        case .previousWindow: return "同应用上一个窗口"
        case .nextWindow: return "同应用下一个窗口"
        case .none: return "不执行"
        }
    }
}

enum TrackpadCorner: String, CaseIterable, Identifiable, Codable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }
    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }
    var title: String {
        switch self { case .topLeft: return "左上角"; case .topRight: return "右上角"; case .bottomLeft: return "左下角"; case .bottomRight: return "右下角" }
    }
    var action: WindowAction {
        switch self { case .topLeft: return .maximize; case .topRight: return .minimize; case .bottomLeft: return .close; case .bottomRight: return .showDesktop }
    }
}

struct CornerZone: Codable, Equatable {
    var width = 0.18
    var height = 0.22
    var enabled = true
    var clamped: CornerZone {
        CornerZone(width: width.isFinite ? min(max(width, 0.05), 0.45) : 0.18,
                   height: height.isFinite ? min(max(height, 0.05), 0.45) : 0.22, enabled: enabled)
    }
    func contains(_ point: Contact, corner: TrackpadCorner) -> Bool {
        let zone = clamped
        guard zone.enabled, point.x.isFinite, point.y.isFinite, (0...1).contains(point.x), (0...1).contains(point.y) else { return false }
        return (corner.isLeft ? point.x <= zone.width : point.x >= 1 - zone.width) &&
            (corner.isTop ? point.y >= 1 - zone.height : point.y <= zone.height)
    }
    static var defaults: [String: CornerZone] { Dictionary(uniqueKeysWithValues: TrackpadCorner.allCases.map { ($0.rawValue, CornerZone()) }) }
}

/// A corner tap starts and ends with one finger, stays inside its zone, and has
/// little motion. A rejected sequence stays rejected until all fingers lift.
struct CornerTapEngine {
    var zones = CornerZone.defaults
    private var started = false
    private var origin: Contact?
    private var candidate: TrackpadCorner?
    private var began = 0.0
    private var lastFrame = 0.0

    mutating func reset() { started = false; origin = nil; candidate = nil; began = 0; lastFrame = 0 }
    mutating func consume(_ points: [Contact], at time: Double) -> TrackpadCorner? {
        guard time.isFinite else { candidate = nil; return nil }
        if started && (time < lastFrame || time - lastFrame > 0.25) { candidate = nil }
        lastFrame = time
        if points.isEmpty {
            let elapsed = time - began
            let result = started && elapsed >= 0.02 && elapsed <= 0.30 ? candidate : nil
            reset(); return result
        }
        guard points.count == 1 else { started = true; candidate = nil; return nil }
        let point = points[0]
        if !started {
            started = true; began = time; origin = point
            candidate = TrackpadCorner.allCases.first { (zones[$0.rawValue] ?? CornerZone()).contains(point, corner: $0) }
            return nil
        }
        guard let corner = candidate, let origin, origin.id == point.id,
              time - began <= 0.30,
              hypot(point.x - origin.x, point.y - origin.y) <= 0.025,
              (zones[corner.rawValue] ?? CornerZone()).contains(point, corner: corner) else {
            candidate = nil; return nil
        }
        return nil
    }
}

enum WindowGeometry {
    static func pinched(initial: CGRect, scale: Double, visible: CGRect, gap: Double) -> CGRect {
        guard scale.isFinite, scale > 0 else { return initial }
        let area = visible.insetBy(dx: gap, dy: gap)
        guard area.width > 0, area.height > 0, initial.width > 0, initial.height > 0 else { return initial }
        let minimumScale = min(1, max(min(240, area.width) / initial.width, min(160, area.height) / initial.height))
        let maximumScale = min(area.width / initial.width, area.height / initial.height)
        let bounded = min(max(scale, minimumScale), maximumScale)
        let width = initial.width * bounded, height = initial.height * bounded
        return CGRect(x: min(max(initial.midX - width / 2, area.minX), area.maxX - width),
                      y: min(max(initial.midY - height / 2, area.minY), area.maxY - height), width: width, height: height)
    }
    static func target(_ action: WindowAction, visible: CGRect, current: CGRect, gap: Double) -> CGRect {
        let area = visible.insetBy(dx: gap, dy: gap)
        switch action {
        case .leftHalf: return CGRect(x: area.minX, y: area.minY, width: (area.width - gap) / 2, height: area.height)
        case .rightHalf: return CGRect(x: area.midX + gap / 2, y: area.minY, width: (area.width - gap) / 2, height: area.height)
        case .topHalf: return CGRect(x: area.minX, y: area.minY, width: area.width, height: (area.height - gap) / 2)
        case .bottomHalf: return CGRect(x: area.minX, y: area.midY + gap / 2, width: area.width, height: (area.height - gap) / 2)
        case .center:
            let w = min(current.width, area.width), h = min(current.height, area.height)
            return CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
        default: return area
        }
    }
    static func axRect(from screenRect: CGRect, primaryHeight: Double) -> CGRect {
        CGRect(x: screenRect.minX, y: primaryHeight - screenRect.maxY, width: screenRect.width, height: screenRect.height)
    }
}
