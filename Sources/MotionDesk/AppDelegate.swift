import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var desktop: DesktopController!
    private var resumeAfterWake = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        Engine.shared.restore()
        desktop = DesktopController()
        buildWindow()
        buildStatusItem()
        observeSleep()

        // When started automatically at login, stay in the menu bar instead of popping up a window.
        let startedAtLogin = Engine.shared.launchAtLogin && ProcessInfo.processInfo.systemUptime < 180
        if !startedAtLogin { showWindow() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: UI

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 660),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered,
                          defer: false)
        window.title = "MotionDesk"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ControlView())
        window.center()
    }

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About MotionDesk",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit MotionDesk",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu

        let winItem = NSMenuItem()
        main.addItem(winItem)
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = winMenu

        NSApp.mainMenu = main
        NSApp.windowsMenu = winMenu
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "play.rectangle.fill",
                                           accessibilityDescription: "MotionDesk")

        let menu = NSMenu()
        let open = NSMenuItem(title: "Open MotionDesk", action: #selector(showWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let toggle = NSMenuItem(title: "Play / Pause", action: #selector(togglePlay), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit MotionDesk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func togglePlay() {
        Engine.shared.togglePlay()
    }

    // MARK: Sleep handling (pause video while the display is asleep)

    private func observeSleep() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resumeAfterWake = Engine.shared.isPlaying
            Engine.shared.player.pause()
        }
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            if self?.resumeAfterWake == true { Engine.shared.player.play() }
            self?.resumeAfterWake = false
        }
    }
}
