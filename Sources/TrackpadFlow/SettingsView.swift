import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    private let accent = Color(red: 0.20, green: 0.36, blue: 0.88)

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    Image(nsImage: NSImage(named: "AppIcon") ?? NSImage(named: NSImage.applicationIconName) ?? NSImage())
                        .resizable().interpolation(.high).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("轻划").font(.title2.bold())
                        Text("Trackpad Flow").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.top, 18)
                VStack(spacing: 6) {
                    sidebarItem("手势与窗口", symbol: "rectangle.split.2x1", index: 0)
                    sidebarItem("四角轻点", symbol: "square.dashed.inset.filled", index: 1)
                    sidebarItem("捏合缩放", symbol: "arrow.up.left.and.arrow.down.right", index: 2)
                    sidebarItem("权限与帮助", symbol: "slider.horizontal.3", index: 3)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.enabled && !model.diagnosticOnly ? "正在运行" : "测试模式", systemImage: "circle.fill")
                        .font(.caption.weight(.medium)).foregroundStyle(model.enabled ? .green : .secondary)
                    Text("纯触控板操作\n所有设置保存在本机")
                        .font(.caption).foregroundStyle(.secondary).lineSpacing(4)
                    Text("v0.3.2 · 本地测试版").font(.caption2).foregroundStyle(.tertiary)
                }.padding(.bottom, 18)
            }.padding(.horizontal, 18).frame(width: 174).background(.quaternary.opacity(0.35))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.selection == 0 { gestures }
                    else if model.selection == 1 { corners }
                    else if model.selection == 2 { pinch }
                    else { help }
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }.background(Color(nsColor: .windowBackgroundColor))
        }.frame(minWidth: 880, minHeight: 710)
            .tint(accent)
    }
    private var pinch: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("三指捏合，窗口随之缩放。").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("向内收拢缩小窗口，向外张开放大窗口。抬手即停止。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            HStack {
                Text(model.status).font(.system(size: 12, weight: .medium))
                Spacer()
                if model.enabled {
                    Button("暂停") { model.enabled = false; model.diagnosticOnly = true }
                } else {
                    Button(model.trusted ? "开启窗口控制" : "授权窗口控制") { model.activate() }.buttonStyle(.borderedProminent)
                }
            }.padding(14).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            VStack(spacing: 18) {
                HStack {
                    Toggle("启用三指捏合", isOn: $model.pinchEnabled).toggleStyle(.switch).controlSize(.small)
                    Spacer()
                    Toggle("仅测试", isOn: $model.diagnosticOnly).toggleStyle(.switch).controlSize(.small)
                }
                TrackpadPreview(contacts: model.contacts, direction: nil).frame(width: 330, height: 205)
                Text("\(Int((model.pinchScale * 100).rounded()))%")
                    .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(accent)
                Text(model.lastGesture).font(.system(size: 13, weight: .semibold))
                Text(model.lastResult).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("缩放灵敏度").font(.headline)
                    Spacer()
                    Text(String(format: "%.1f×", model.pinchSensitivity)).font(.caption).monospacedDigit()
                }
                HStack {
                    Text("细腻").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $model.pinchSensitivity, in: 0.5...2, step: 0.1)
                    Text("灵敏").font(.caption).foregroundStyle(.secondary)
                }
                Text("在测试模式中，比例随手势变化；开启控制后，窗口会连续调整大小，并尽量保持中心位置。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 8) {
                Label("使用提示", systemImage: "info.circle").font(.system(size: 12, weight: .semibold))
                Text("三根手指留出间距，再向中心收拢或向外张开。三指一起平移仍按滑动手势处理；同一次接触只会执行其中一种。即使滑动设为四指，捏合仍使用三指。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("应用的最小窗口尺寸及桌面可用范围会限制缩放。系统全屏窗口需先退出全屏。若系统三指拖移或其他手势软件占用此手势，请先调整其设置。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var corners: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("四个角，四个快捷动作。").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("单指轻触触控板角落并抬起，无需按下。每个区域都可以单独调整。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            HStack {
                Text(model.status).font(.system(size: 12, weight: .medium))
                Spacer()
                if model.enabled {
                    Button("暂停") { model.enabled = false; model.diagnosticOnly = true }
                } else {
                    Button(model.trusted ? "开启窗口控制" : "授权窗口控制") { model.activate() }.buttonStyle(.borderedProminent)
                }
            }.padding(14).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            VStack(spacing: 14) {
                HStack {
                    Toggle("启用四角轻点", isOn: $model.cornersEnabled).toggleStyle(.switch).controlSize(.small)
                    Spacer()
                    Toggle("仅测试", isOn: $model.diagnosticOnly).toggleStyle(.switch).controlSize(.small)
                }
                TrackpadPreview(contacts: model.contacts, direction: nil, zones: model.cornerZones,
                                selectedCorner: model.selectedCorner, onSelect: { model.selectedCorner = $0 })
                    .frame(height: 245)
                HStack {
                    Text(model.lastGesture).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("当前 \(model.contacts.count) 指").font(.caption).foregroundStyle(.secondary)
                }
                Text(model.lastResult).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 14))
            HStack(spacing: 8) {
                ForEach(TrackpadCorner.allCases) { corner in
                    Button { model.selectedCorner = corner } label: {
                        VStack(spacing: 5) {
                            Text(corner.title).font(.system(size: 12, weight: .semibold))
                            Text(corner.action.title).font(.caption)
                        }.frame(maxWidth: .infinity).padding(.vertical, 10)
                            .foregroundStyle(model.selectedCorner == corner ? accent : .primary)
                            .background(model.selectedCorner == corner ? accent.opacity(0.12) : Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
            }
            cornerZoneEditor
            VStack(alignment: .leading, spacing: 7) {
                Label("轻点识别规则", systemImage: "info.circle").font(.system(size: 12, weight: .semibold))
                Text("轻点需在 0.3 秒内抬起，手指保持在区域内。移动超过约 2.5% 的触控板坐标范围、长按或多指操作不触发。四角启用后，这些区域预留给快捷动作；普通点击请使用中间区域。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("“关闭窗口”保留应用的未保存提示。“显示桌面”使用系统快捷键，再次轻点可切回。")
                    .font(.caption).foregroundStyle(.secondary)
                if model.enabled && !model.clickFilterReady {
                    Text("四角控制尚未就绪，请检查辅助功能权限；测试区仍可识别轻点。")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
    private var cornerZoneEditor: some View {
        let corner = model.selectedCorner
        let zone = model.zone(for: corner)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(corner.title) · \(corner.action.title)").font(.headline)
                Spacer()
                Toggle("启用此角", isOn: Binding(get: { model.zone(for: corner).enabled }, set: {
                    var updated = model.zone(for: corner); updated.enabled = $0; model.setZone(updated, for: corner)
                })).toggleStyle(.switch).controlSize(.small)
            }
            HStack {
                Text("区域宽度").font(.system(size: 12)).frame(width: 65, alignment: .leading)
                Slider(value: Binding(get: { model.zone(for: corner).width }, set: {
                    var updated = model.zone(for: corner); updated.width = $0; model.setZone(updated, for: corner)
                }), in: 0.05...0.45, step: 0.01)
                Text("\(Int((zone.width * 100).rounded()))%").font(.caption).monospacedDigit().frame(width: 36)
            }
            HStack {
                Text("区域高度").font(.system(size: 12)).frame(width: 65, alignment: .leading)
                Slider(value: Binding(get: { model.zone(for: corner).height }, set: {
                    var updated = model.zone(for: corner); updated.height = $0; model.setZone(updated, for: corner)
                }), in: 0.05...0.45, step: 0.01)
                Text("\(Int((zone.height * 100).rounded()))%").font(.caption).monospacedDigit().frame(width: 36)
            }
            HStack {
                Text("百分比相对于整块触控板；区域固定在所选角落。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("重置此角") { model.setZone(CornerZone(), for: corner) }.font(.caption)
            }
        }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
    private func sidebarItem(_ title: String, symbol: String, index: Int) -> some View {
        Button { model.selection = index } label: {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading).padding(11)
                .background(model.selection == index ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                .foregroundStyle(model.selection == index ? accent : .primary)
        }.buttonStyle(.plain)
    }
    private var gestures: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text("让窗口，随手而动。").font(.system(size: 27, weight: .bold, design: .rounded))
                Text("\(model.fingers) 指轻划，整理当前应用窗口。无需按键盘。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Circle().fill(model.enabled && !model.diagnosticOnly ? Color.green : Color.orange).frame(width: 8, height: 8)
                Text(model.status).font(.system(size: 12, weight: .medium))
                Spacer()
                if model.enabled {
                    Button("暂停") { model.enabled = false; model.diagnosticOnly = true }
                } else {
                    Button(model.trusted ? "开启窗口手势" : "授权窗口控制") { model.activate() }.buttonStyle(.borderedProminent)
                }
            }.padding(14).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 10) {
                    TrackpadPreview(contacts: model.contacts, direction: model.lastDirection)
                        .frame(width: 256, height: 164)
                    Text(model.lastGesture).font(.system(size: 13, weight: .semibold))
                    Text(model.touchFrames == 0 ? "在触控板上放下手指试试" : "当前 \(model.contacts.count) 指 · 已接收 \(model.touchFrames) 帧")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 13) {
                    Text("你的手势").font(.headline)
                    Picker("手指数", selection: $model.fingers) { Text("三指").tag(3); Text("四指").tag(4) }.pickerStyle(.segmented)
                    ForEach(SwipeDirection.allCases) { direction in
                        HStack {
                            Image(systemName: direction.symbol).foregroundStyle(accent).frame(width: 20)
                            Text(direction.title).font(.system(size: 12)).frame(width: 34, alignment: .leading)
                            Picker(direction.title, selection: Binding(get: { model.action(for: direction) }, set: { model.setAction($0, for: direction) })) {
                                ForEach(WindowAction.allCases) { action in Text(action.title).tag(action) }
                            }.labelsHidden().frame(maxWidth: .infinity)
                        }
                    }
                }.frame(maxWidth: .infinity)
            }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("手感与布局").font(.headline)
                    Spacer()
                    Toggle("仅测试手势", isOn: $model.diagnosticOnly).toggleStyle(.switch).controlSize(.small)
                }
                HStack {
                    Text("滑动距离").font(.system(size: 12)).frame(width: 65, alignment: .leading)
                    Text("短").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $model.threshold, in: 0.08...0.25, step: 0.01)
                    Text("长").font(.caption).foregroundStyle(.secondary)
                    Text("\(Int(model.threshold * 100))%").monospacedDigit().font(.caption).frame(width: 35)
                }
                HStack {
                    Text("窗口间距").font(.system(size: 12)).frame(width: 65, alignment: .leading)
                    Slider(value: $model.gap, in: 0...24, step: 2)
                    Text("\(Int(model.gap)) pt").font(.caption).monospacedDigit().frame(width: 44)
                }
                Text(model.lastResult).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 14))
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle").foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 7) {
                    Text("先避开系统手势冲突").font(.system(size: 12, weight: .semibold))
                    Text("使用三指时，请将系统“切换桌面、调度中心、App Exposé”改成四指或关闭，并关闭三指拖移。使用四指时，请关闭对应四指系统手势。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("打开触控板设置") { model.openTrackpadSettings() }.font(.caption)
                }
            }
        }
    }
    private var help: some View {
        Group {
            Text("准备好，就可以轻划。").font(.system(size: 26, weight: .bold, design: .rounded))
            Text("从 Dock 或菜单栏打开设置。关闭设置窗口后继续运行，点击 Dock 图标可重新打开。")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            permissionRow("1", title: "允许控制窗口", detail: "辅助功能权限用于读取当前窗口、移动位置和调整大小。", granted: model.trusted, button: "打开辅助功能设置") { model.requestAccessibility() }
            permissionRow("2", title: "检查多指输入", detail: "若测试区收不到手指数据，请授予输入监控权限，然后点击重新连接。", granted: model.inputGranted, button: "打开输入监控设置") { model.requestInput() }
            VStack(alignment: .leading, spacing: 12) {
                Text("设备诊断").font(.headline)
                LabeledContent("多点触控设备", value: "\(max(model.deviceCount, 0)) 个")
                LabeledContent("已接收数据", value: "\(model.touchFrames) 帧")
                if let error = model.bridgeError { Text(error).foregroundStyle(.orange) }
                HStack {
                    Button("重新连接触控板") { model.rescan() }
                    Button("刷新权限状态") { model.refreshPermissions() }
                }
            }.font(.system(size: 12)).padding(18).background(.background, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 10) {
                Text("使用说明").font(.headline)
                Text("• 手势作用于开始滑动时的当前应用窗口。\n• 上滑“最大化”保留菜单栏与 Dock，不进入系统全屏。\n• 下滑将当前窗口最小化到 Dock。\n• 系统全屏窗口、固定大小窗口可能无法调整。\n• “上一个／下一个窗口”只切换同应用的普通窗口。\n• Bluetooth 重新连接后若无输入，可点击“重新连接触控板”。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(6)
            }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 8) {
                Text("关于这个版本").font(.headline)
                Text("纯多指全局识别依赖 macOS 非公开 MultitouchSupport 接口，系统升级后可能需要适配。这是本机测试版；首次使用请先在测试模式中验证手势。应用无网络功能，接触坐标只在内存中处理。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func permissionRow(_ number: String, title: String, detail: String, granted: Bool, button: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.headline).foregroundStyle(accent).frame(width: 30, height: 30)
                .background(accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 9) {
                HStack { Text(title).font(.headline); Spacer(); Text(granted ? "已授权" : "待检查").font(.caption).foregroundStyle(granted ? .green : .secondary) }
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                Button(button, action: action)
            }
        }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct TrackpadPreview: View {
    let contacts: [Contact]
    let direction: SwipeDirection?
    var zones: [String: CornerZone]? = nil
    var selectedCorner: TrackpadCorner? = nil
    var onSelect: ((TrackpadCorner) -> Void)? = nil
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [Color(nsColor: .controlBackgroundColor), Color.gray.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: 16).strokeBorder(.gray.opacity(0.25), lineWidth: 1)
                if let zones {
                    ForEach(TrackpadCorner.allCases) { corner in
                        let zone = (zones[corner.rawValue] ?? CornerZone()).clamped
                        let width = (geometry.size.width - 24) * zone.width
                        let height = (geometry.size.height - 24) * zone.height
                        let selected = selectedCorner == corner
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.accentColor.opacity(zone.enabled ? (selected ? 0.23 : 0.1) : 0.03))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor.opacity(selected ? 0.8 : 0.2), lineWidth: selected ? 2 : 1))
                            .overlay(Text(corner.action.title).font(.system(size: 10, weight: .medium)).foregroundStyle(zone.enabled ? .primary : .tertiary).padding(3))
                            .frame(width: width, height: height)
                            .position(x: corner.isLeft ? 12 + width / 2 : geometry.size.width - 12 - width / 2,
                                      y: corner.isTop ? 12 + height / 2 : geometry.size.height - 12 - height / 2)
                            .onTapGesture { onSelect?(corner) }
                    }
                }
                if contacts.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "hand.draw").font(.system(size: 35, weight: .light))
                        Text("实时触控预览").font(.caption)
                    }.foregroundStyle(.tertiary)
                }
                ForEach(contacts, id: \.id) { contact in
                    Circle().fill(Color.accentColor.opacity(0.75))
                        .frame(width: 23, height: 23)
                        .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 2))
                        .position(x: 12 + contact.x * (geometry.size.width - 24), y: 12 + (1 - contact.y) * (geometry.size.height - 24))
                }
            }
        }
    }
}
