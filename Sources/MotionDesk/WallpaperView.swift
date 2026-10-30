import AVFoundation
import AppKit
import Combine

/// Gradient used for the "Default static wallpaper" mode (and when no video is loaded).
final class StaticWallpaperLayer: CALayer {
    private let base = CAGradientLayer()
    private let glow = CAGradientLayer()

    private func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        return CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }

    override init() {
        super.init()
        base.colors = [color(0x09132f), color(0x173b68), color(0x291d50)]
        base.locations = [0, 0.48, 1]
        base.startPoint = CGPoint(x: 0, y: 1)
        base.endPoint = CGPoint(x: 1, y: 0)
        glow.type = .radial
        glow.colors = [color(0xffb36b, 0.85), color(0xc66b91, 0.45), color(0xc66b91, 0)]
        glow.locations = [0, 0.35, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0)
        glow.endPoint = CGPoint(x: 1.0, y: 0.75)
        addSublayer(base)
        addSublayer(glow)
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSublayers() {
        super.layoutSublayers()
        base.frame = bounds
        glow.frame = bounds
    }
}

/// Renders the shared player (with framing + rotation) or the static wallpaper.
/// Used both on the desktop and in the Studio preview.
final class WallpaperView: NSView {
    private let playerLayer = AVPlayerLayer()
    private let staticLayer = StaticWallpaperLayer()
    private var bag = Set<AnyCancellable>()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        layer?.addSublayer(staticLayer)
        playerLayer.player = Engine.shared.player
        layer?.addSublayer(playerLayer)

        Engine.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &bag)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        refresh()
    }

    func refresh() {
        let e = Engine.shared
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let b = bounds
        staticLayer.frame = b
        let showVideo = (e.mode == .video && e.videoURL != nil)
        staticLayer.isHidden = showVideo
        playerLayer.isHidden = (e.mode != .video)
        playerLayer.videoGravity = (e.framing == .fill) ? .resizeAspectFill : .resizeAspect

        let sideways = abs(e.rotation) % 180 == 90
        let size = sideways ? CGSize(width: b.height, height: b.width) : b.size
        playerLayer.setAffineTransform(.identity)
        playerLayer.bounds = CGRect(origin: .zero, size: size)
        playerLayer.position = CGPoint(x: b.midX, y: b.midY)
        playerLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(-Double(e.rotation) * Double.pi / 180.0)))

        CATransaction.commit()
    }
}
