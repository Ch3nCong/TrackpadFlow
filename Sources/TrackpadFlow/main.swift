import AppKit
import SwiftUI
import ApplicationServices
import TrackpadBridge

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var model: AppModel!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        model = AppModel()
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "轻划窗口管理")
        statusItem.button?.toolTip = "轻划 · Trackpad Flow"
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu
        showSettings()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
    private func installMainMenu() {
        let main = NSMenu()
        let appRoot = NSMenuItem(); main.addItem(appRoot)
        let appMenu = NSMenu(title: "轻划"); appRoot.submenu = appMenu
        add(appMenu, title: "手势与设置…", selector: #selector(showSettings), key: ",")
        appMenu.addItem(.separator())
        let hide = NSMenuItem(title: "隐藏轻划", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = NSApp; appMenu.addItem(hide)
        add(appMenu, title: "退出轻划", selector: #selector(quit), key: "q")
        let windowRoot = NSMenuItem(); main.addItem(windowRoot)
        let windowMenu = NSMenu(title: "窗口"); windowRoot.submenu = windowMenu
        windowMenu.addItem(NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        NSApp.mainMenu = main; NSApp.windowsMenu = windowMenu
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: "轻划 · \(model.status)", action: nil, keyEquivalent: ""); title.isEnabled = false; menu.addItem(title)
        menu.addItem(.separator())
        add(menu, title: "手势与设置…", selector: #selector(showSettings), key: ",")
        add(menu, title: model.enabled ? "暂停窗口手势" : "开启窗口手势", selector: #selector(toggle))
        add(menu, title: "重新连接触控板", selector: #selector(reconnect))
        menu.addItem(.separator())
        add(menu, title: "退出轻划", selector: #selector(quit), key: "q")
    }
    private func add(_ menu: NSMenu, title: String, selector: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key); item.target = self; menu.addItem(item)
    }
    @objc private func toggle() {
        if model.enabled { model.enabled = false; model.diagnosticOnly = true } else { model.activate() }
    }
    @objc private func reconnect() { model.rescan() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "轻划 · Trackpad Flow"
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.minSize = NSSize(width: 880, height: 710)
            window.isReleasedWhenClosed = false
            window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindow?.isMiniaturized == true { settingsWindow?.deminiaturize(nil) }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

if CommandLine.arguments.contains("--probe") {
    let result = TFStart { _, _, _, _ in }
    print("Multitouch bridge: \(result >= 0 ? "loaded" : "unavailable")")
    print("Multitouch devices: \(max(result, 0))")
    print("Accessibility: \(AXIsProcessTrusted())")
    print("Input monitoring: \(CGPreflightListenEventAccess())")
    TFStop()
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
