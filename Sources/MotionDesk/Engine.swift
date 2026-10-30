import AVFoundation
import AppKit
import Combine
import ServiceManagement

enum WallpaperMode: String, CaseIterable, Identifiable {
    case video, standard
    var id: String { rawValue }
}

enum Framing: String, CaseIterable, Identifiable {
    case fit, fill
    var id: String { rawValue }
}

/// Single shared player + settings. Both the desktop wallpaper windows and the
/// preview in the Studio window render this same player.
final class Engine: ObservableObject {
    static let shared = Engine()

    let player = AVPlayer()
    private var bag = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard

    @Published private(set) var videoURL: URL? = nil
    @Published private(set) var isPlaying = false
    @Published var statusText = "No video selected"

    @Published var volume: Double {
        didSet {
            defaults.set(volume, forKey: "volume")
            if volume > 0 && muted { muted = false }
            applyAudio()
        }
    }
    @Published var speed: Double {
        didSet {
            defaults.set(speed, forKey: "speed")
            player.defaultRate = Float(speed)
            if isPlaying { player.rate = Float(speed) }
        }
    }
    @Published var loop: Bool {
        didSet { defaults.set(loop, forKey: "loop") }
    }
    @Published var muted: Bool {
        didSet { defaults.set(muted, forKey: "muted"); applyAudio() }
    }
    @Published var framing: Framing {
        didSet { defaults.set(framing.rawValue, forKey: "framing") }
    }
    @Published var rotation: Int {
        didSet { defaults.set(rotation, forKey: "rotation") }
    }
    @Published var mode: WallpaperMode {
        didSet { defaults.set(mode.rawValue, forKey: "mode"); modeChanged() }
    }
    @Published var showOnDesktop: Bool {
        didSet { defaults.set(showOnDesktop, forKey: "showOnDesktop") }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("MotionDesk: launch at login change failed: \(error)")
            }
        }
    }

    private init() {
        let d = UserDefaults.standard
        volume = d.object(forKey: "volume") as? Double ?? 60
        speed = d.object(forKey: "speed") as? Double ?? 1.0
        loop = d.object(forKey: "loop") as? Bool ?? true
        muted = d.object(forKey: "muted") as? Bool ?? false
        framing = Framing(rawValue: d.string(forKey: "framing") ?? "") ?? .fill
        rotation = d.object(forKey: "rotation") as? Int ?? 0
        mode = WallpaperMode(rawValue: d.string(forKey: "mode") ?? "") ?? .video
        showOnDesktop = d.object(forKey: "showOnDesktop") as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled

        player.actionAtItemEnd = .pause
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.defaultRate = Float(speed)
        applyAudio()

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.isPlaying = (status != .paused) }
            .store(in: &bag)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.itemEnded() }
            .store(in: &bag)
    }

    private func applyAudio() {
        player.volume = Float(volume / 100.0)
        player.isMuted = muted
    }

    private func modeChanged() {
        if mode == .standard { player.pause() }
        else if videoURL != nil { player.play() }
    }

    private func itemEnded() {
        guard loop else { return }
        player.seek(to: .zero)
        player.play()
    }

    /// Restore the last-used video on launch.
    func restore() {
        guard let path = defaults.string(forKey: "videoPath"),
              FileManager.default.fileExists(atPath: path) else { return }
        let savedMode = mode
        let savedRotation = rotation
        load(URL(fileURLWithPath: path))
        rotation = savedRotation
        mode = savedMode
    }

    func load(_ url: URL) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        videoURL = url
        defaults.set(url.path, forKey: "videoPath")
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        statusText = url.lastPathComponent + String(format: " · %.1f MB", Double(bytes) / 1_048_576.0)
        applyAudio()
        mode = .video
        player.play()
        autoRotatePortrait(url)
    }

    /// Portrait videos get turned sideways so they fill a landscape screen.
    private func autoRotatePortrait(_ url: URL) {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { rotation = 0; return }
        let size = track.naturalSize.applying(track.preferredTransform)
        rotation = abs(size.height) > abs(size.width) ? -90 : 0
    }

    func togglePlay() {
        if isPlaying { player.pause() }
        else if videoURL != nil && mode == .video { player.play() }
    }

    func rotate(by degrees: Int) {
        rotation = ((rotation + degrees) % 360 + 360) % 360
    }
}
