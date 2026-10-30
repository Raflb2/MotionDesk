import AppKit
import Combine

/// Puts one borderless window per display just above the system wallpaper and
/// below the desktop icons, so the video plays "behind" everything.
final class DesktopController {
    private var windows: [NSWindow] = []
    private var bag = Set<AnyCancellable>()

    init() {
        Engine.shared.$showOnDesktop
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in self?.rebuild(enabled: on) }
            .store(in: &bag)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuild(enabled: Engine.shared.showOnDesktop) }
            .store(in: &bag)
    }

    private func rebuild(enabled: Bool) {
        for w in windows {
            w.orderOut(nil)
            w.close()
        }
        windows.removeAll()
        guard enabled else { return }

        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame,
                             styleMask: [.borderless],
                             backing: .buffered,
                             defer: false)
            w.isReleasedWhenClosed = false
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            w.isOpaque = true
            w.backgroundColor = .black
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.contentView = WallpaperView(frame: NSRect(origin: .zero, size: screen.frame.size))
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            windows.append(w)
        }
    }
}
