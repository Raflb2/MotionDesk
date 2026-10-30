import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct WallpaperPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> WallpaperView { WallpaperView(frame: .zero) }
    func updateNSView(_ nsView: WallpaperView, context: Context) {}
}

struct ControlView: View {
    @ObservedObject var e = Engine.shared
    @State private var dropping = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 20) {
                previewPanel.frame(maxWidth: .infinity, alignment: .top)
                controlsPanel.frame(width: 340)
            }
            .padding(20)
            Spacer(minLength: 0)
        }
        .frame(minWidth: 960, minHeight: 600)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.accentColor)
                Image(systemName: "play.fill").foregroundColor(.white)
            }
            .frame(width: 34, height: 34)
            Text("MotionDesk").font(.title2.bold())
            Text("Wallpaper Studio").foregroundColor(.secondary)
            Spacer()
            Text("MAC VIDEO WALLPAPER")
                .font(.caption2.bold())
                .padding(.horizontal, 10).padding(.vertical, 5)
                .overlay(Capsule().stroke(Color.secondary.opacity(0.5)))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("01 / VIDEO PREVIEW").font(.caption.bold()).foregroundColor(.secondary)

            ZStack {
                WallpaperPreview()
                if e.videoURL == nil && e.mode == .video {
                    VStack(spacing: 6) {
                        Image(systemName: "film").font(.system(size: 30))
                        Text("Drop in your wallpaper video").font(.headline)
                        Text("or choose an MP4 from your Mac").font(.caption)
                    }
                    .foregroundColor(Color.white.opacity(0.85))
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(dropping ? Color.accentColor : Color.secondary.opacity(0.35),
                            lineWidth: dropping ? 3 : 1)
            )
            .onDrop(of: [UTType.fileURL], isTargeted: $dropping) { providers in
                handleDrop(providers)
            }

            HStack(spacing: 10) {
                Button("＋ Choose video…") { pickVideo() }
                    .buttonStyle(.borderedProminent)
                Button(e.isPlaying ? "Ⅱ Pause" : "▶ Play") { e.togglePlay() }
                    .disabled(e.videoURL == nil || e.mode != .video)
                Button(e.muted ? "Sound off" : "Sound on") { e.muted.toggle() }
                    .disabled(e.videoURL == nil)
            }

            HStack(spacing: 10) {
                Button("↶ Rotate left") { e.rotate(by: -90) }
                Button("↷ Rotate right") { e.rotate(by: 90) }
                Button("Reset rotation") { e.rotation = 0 }
            }
            .disabled(e.videoURL == nil)

            Text(e.statusText).font(.caption).foregroundColor(.secondary)
                .lineLimit(2)
        }
    }

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("02 / PLAYBACK & SOUND").font(.caption.bold()).foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Video volume").font(.subheadline.bold())
                    Spacer()
                    Text("\(Int(e.volume))%").foregroundColor(.accentColor)
                }
                Slider(value: $e.volume, in: 0...100)
                HStack {
                    Text("Muted"); Spacer(); Text("Full volume")
                }.font(.caption2).foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Playback speed").font(.subheadline.bold())
                    Spacer()
                    Text(String(format: "%.2f×", e.speed)).foregroundColor(.accentColor)
                }
                Slider(value: $e.speed, in: 0.25...2.0, step: 0.25)
                HStack {
                    Text("0.25×"); Spacer(); Text("2.0×")
                }.font(.caption2).foregroundColor(.secondary)
            }

            Toggle("Loop video", isOn: $e.loop).toggleStyle(.switch)
            Toggle("Mute audio", isOn: $e.muted).toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 4) {
                Text("Video framing").font(.subheadline.bold())
                Picker("", selection: $e.framing) {
                    Text("Fill screen (crop edges)").tag(Framing.fill)
                    Text("Fit entire video").tag(Framing.fit)
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Wallpaper mode").font(.subheadline.bold())
                Picker("", selection: $e.mode) {
                    Text("Video wallpaper").tag(WallpaperMode.video)
                    Text("Default static wallpaper").tag(WallpaperMode.standard)
                }
                .labelsHidden()
            }

            Divider()

            Toggle("Show on my desktop", isOn: $e.showOnDesktop).toggleStyle(.switch)
            Toggle("Open at login", isOn: $e.launchAtLogin).toggleStyle(.switch)

            Text("Closing this window keeps the wallpaper running. Use the ▶ icon in the menu bar to reopen it or quit.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private func pickVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a video for your wallpaper"
        if panel.runModal() == .OK, let url = panel.url {
            e.load(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url = url else { return }
            DispatchQueue.main.async { Engine.shared.load(url) }
        }
        return true
    }
}
