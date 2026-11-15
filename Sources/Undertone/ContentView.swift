import SwiftUI
import UndertoneCore

private enum Palette {
    static let mint = Color(red: 0.41, green: 0.94, blue: 0.76)
    static let coral = Color(red: 1, green: 0.50, blue: 0.42)
}

struct ContentView: View {
    @ObservedObject var viewModel: NowPlayingViewModel
    @State private var queueExpanded = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "waveform").foregroundStyle(Palette.mint)
                Text("UNDERTONE").tracking(2)
                Spacer()
                Circle().fill(viewModel.isPlaying ? Palette.mint : .white.opacity(0.2))
                    .frame(width: 5, height: 5)
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white.opacity(0.45))

            if viewModel.showDefaultPlayerOffer {
                defaultPlayerCard
            }

            HStack(spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 5) {
                    Text(viewModel.title == "No Track" ? "A little less noise." : viewModel.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white).lineLimit(2)
                    Text(viewModel.artist.isEmpty ? (viewModel.duration > 0 ? "Local audio" : "Open something worth hearing.") : viewModel.artist)
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                    if !viewModel.album.isEmpty {
                        Text(viewModel.album).font(.system(size: 10))
                            .foregroundStyle(Palette.mint.opacity(0.75)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                Slider(value: Binding(get: { viewModel.currentTime }, set: { viewModel.currentTime = $0 }),
                       in: 0...max(viewModel.duration, 0.001), onEditingChanged: { editing in
                    viewModel.isScrubbing = editing
                    if !editing { viewModel.seek(to: viewModel.currentTime) }
                })
                .tint(Palette.mint).disabled(viewModel.duration <= 0)
                .accessibilityLabel("Playback position")
                HStack {
                    Text(viewModel.currentTime.asClockString)
                    Spacer()
                    Text(viewModel.duration.asClockString)
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
            }

            HStack(spacing: 28) {
                transport("backward.end.fill", label: "Previous track", action: viewModel.previous)
                Button(action: viewModel.togglePlay) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .offset(x: viewModel.isPlaying ? 0 : 1)
                        .foregroundStyle(Color(red: 0.04, green: 0.12, blue: 0.10))
                        .frame(width: 48, height: 48)
                        .background(Palette.mint, in: Circle())
                        .shadow(color: Palette.mint.opacity(0.17), radius: 12, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
                .help(viewModel.isPlaying ? "Pause" : "Play")
                .disabled(viewModel.duration <= 0)
                transport("forward.end.fill", label: "Next track", action: viewModel.next)
            }

            HStack(spacing: 9) {
                Image(systemName: viewModel.volume == 0 ? "speaker.slash.fill" : "speaker.wave.1.fill")
                Slider(value: Binding(get: { viewModel.volume }, set: { viewModel.setVolume($0) }), in: 0...1)
                    .tint(.white.opacity(0.5)).accessibilityLabel("Volume")
                Image(systemName: "speaker.wave.3.fill")
            }
            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))

            if let message = viewModel.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Palette.coral)
                    Text(message).font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(action: viewModel.dismissError) { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Dismiss error")
                }
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                .padding(10).background(Palette.coral.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            HStack {
                Button(action: viewModel.openFilesPanel) {
                    Label("Open files", systemImage: "plus")
                }.help("Open local audio files")
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { queueExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text("Queue · \(viewModel.queueItems.count)")
                        Image(systemName: queueExpanded ? "chevron.up" : "chevron.down").font(.system(size: 7, weight: .bold))
                    }
                }.accessibilityLabel("Toggle queue")
                Button(action: viewModel.quitApp) { Image(systemName: "power") }
                    .padding(.leading, 8).help("Quit Undertone").accessibilityLabel("Quit Undertone")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.45)).buttonStyle(.plain)

            if queueExpanded {
                if viewModel.queueItems.isEmpty {
                    Text("No files in the queue.").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(viewModel.queueItems) { item in
                                Button { viewModel.selectTrack(item.id) } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: item.isCurrent ? "waveform" : "music.note").frame(width: 12)
                                        Text(item.name).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .font(.system(size: 10))
                                    .foregroundStyle(item.isCurrent ? Palette.mint : .white.opacity(0.45))
                                    .padding(7)
                                    .background(item.isCurrent ? Palette.mint.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 5))
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }.frame(height: min(CGFloat(viewModel.queueItems.count) * 30, 110))
                }
            }
        }
        .padding(18)
        .frame(width: 320)
        .background(LinearGradient(colors: [Color(red: 0.075, green: 0.095, blue: 0.10), Color(red: 0.045, green: 0.05, blue: 0.065)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(.dark)
    }

    /// First-run offer. Stays until one of its two buttons is clicked.
    private var defaultPlayerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Make Undertone your default player for music files?")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Text("MP3, M4A, FLAC, AIFF and WAV files will open here.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Button(action: viewModel.declineDefaultPlayerOffer) {
                    Text("Not now").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                Button(action: viewModel.acceptDefaultPlayerOffer) {
                    Text("Make default").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.04, green: 0.12, blue: 0.10))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Palette.mint, in: Capsule())
                }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Palette.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.mint.opacity(0.18)))
    }

    private var artwork: some View {
        ZStack {
            if let image = viewModel.artwork {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Palette.mint.opacity(0.23), Palette.coral.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "waveform").font(.system(size: 25, weight: .light)).foregroundStyle(Palette.mint)
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))
    }

    private func transport(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.65)).frame(width: 30, height: 32)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
            .disabled(viewModel.duration <= 0)
    }
}
