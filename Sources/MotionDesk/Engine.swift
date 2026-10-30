import AVFoundation
import AppKit
import Combine
import CoreImage
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
    @Published var enhance: Bool {
        didSet { defaults.set(enhance, forKey: "enhance"); applyEnhance() }
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
        enhance = d.object(forKey: "enhance") as? Bool ?? true
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

    // MARK: Loading + saving

    private func supportDir() -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("MotionDesk", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Keeps its own copy of the chosen video so the wallpaper survives restarts
    /// even if the original file is moved, deleted, or in a protected folder.
    private func importCopy(_ src: URL) -> URL? {
        guard let dir = supportDir() else { return nil }
        let ext = src.pathExtension.isEmpty ? "mp4" : src.pathExtension
        let dest = dir.appendingPathComponent("wallpaper-\(Int(Date().timeIntervalSince1970)).\(ext)")
        do {
            try FileManager.default.copyItem(at: src, to: dest)
            return dest
        } catch {
            NSLog("MotionDesk: could not copy video (\(error)); using original file")
            return nil
        }
    }

    private func cleanOldCopies(keeping keep: URL) {
        guard let dir = supportDir(),
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for f in files where f.hasPrefix("wallpaper-") && f != keep.lastPathComponent {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
    }

    /// Restore the saved video on launch.
    func restore() {
        guard let path = defaults.string(forKey: "videoPath"),
              FileManager.default.fileExists(atPath: path) else { return }
        let url = URL(fileURLWithPath: path)
        let savedMode = mode
        let savedRotation = rotation
        play(url, name: defaults.string(forKey: "videoName") ?? url.lastPathComponent)
        rotation = savedRotation
        mode = savedMode
    }

    /// Called when the user picks or drops a new video.
    func load(_ picked: URL) {
        let name = picked.lastPathComponent
        let playURL = importCopy(picked) ?? picked
        defaults.set(name, forKey: "videoName")
        play(playURL, name: name)
        cleanOldCopies(keeping: playURL)
    }

    private func play(_ url: URL, name: String) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        videoURL = url
        defaults.set(url.path, forKey: "videoPath")
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        statusText = name + String(format: " · %.1f MB", Double(bytes) / 1_048_576.0)
        applyAudio()
        mode = .video
        player.play()
        autoRotatePortrait(url)
        applyEnhance()
    }

    /// Portrait videos get turned sideways so they fill a landscape screen.
    private func autoRotatePortrait(_ url: URL) {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { rotation = 0; return }
        let size = track.naturalSize.applying(track.preferredTransform)
        rotation = abs(size.height) > abs(size.width) ? -90 : 0
    }

    // MARK: Quality

    /// Upscales low-resolution video with a high-quality (Lanczos) filter and sharpens it,
    /// so it looks much cleaner when stretched across a 5K screen.
    private func applyEnhance() {
        guard let item = player.currentItem else { return }
        guard enhance else { item.videoComposition = nil; return }
        let asset = item.asset
        guard let track = asset.tracks(withMediaType: .video).first else { return }
        let s = track.naturalSize.applying(track.preferredTransform)
        let w = abs(s.width)
        let h = abs(s.height)
        let longSide = max(w, h)
        // Already high resolution: nothing to gain.
        guard longSide > 0, longSide < 3000 else { item.videoComposition = nil; return }

        let factor = min(3.0, 3840.0 / Double(longSide))
        let target = CGSize(width: ((Double(w) * factor) / 2).rounded() * 2,
                            height: ((Double(h) * factor) / 2).rounded() * 2)

        let comp = AVMutableVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
            let src = request.sourceImage
            let scale = Double(target.width) / Double(src.extent.width)
            var out = src
            if abs(scale - 1.0) > 0.001 {
                out = src.applyingFilter("CILanczosScaleTransform",
                                         parameters: [kCIInputScaleKey: scale,
                                                      kCIInputAspectRatioKey: 1.0])
            }
            out = out.applyingFilter("CIUnsharpMask",
                                     parameters: [kCIInputRadiusKey: 2.5,
                                                  kCIInputIntensityKey: 0.6])
            request.finish(with: out.cropped(to: CGRect(origin: .zero, size: target)), context: nil)
        })
        comp.renderSize = target
        item.videoComposition = comp
    }

    func togglePlay() {
        if isPlaying { player.pause() }
        else if videoURL != nil && mode == .video { player.play() }
    }

    func rotate(by degrees: Int) {
        rotation = ((rotation + degrees) % 360 + 360) % 360
    }
}
