import AVFoundation
import AVKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A piece of portfolio media. `id` is the source portfolio item's id so the
/// grid tile and the gallery page refer to the same entry (swipe-to-target works).
struct PortfolioMedia: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let isVideo: Bool
}

/// Identifiable wrapper so a `portfolio_items` row id can drive `.sheet(item:)`
/// for the Guideline 1.2 report flow on portfolio media.
struct ReportablePortfolioItem: Identifiable, Equatable {
    let id: UUID
}

// MARK: - Audio session

/// Audio routing for portfolio video playback.
///
/// Without this, portfolio videos play **silently**, for two compounding reasons:
///
/// 1. The process default category is `.soloAmbient`, which is silenced by the
///    hardware Ring/Silent switch — so a muted phone (i.e. most phones) gets no
///    video audio at all.
/// 2. `VoiceMemoRecordingSheet` switches the shared session to `.record` and only
///    calls `setActive(false)` afterwards. Deactivating does **not** restore the
///    category, so once a user records a voice memo the session stays
///    record-oriented and video audio is dead for the rest of the launch.
///
/// A full-screen video the user explicitly tapped is "playback" media, so
/// `.playback` + `.moviePlayback` is the correct category (matching Photos and
/// every other media viewer): it plays through the Silent switch and reclaims the
/// session from whatever the voice-memo flow left behind.
enum MediaAudioSession {
    /// Claim the session for movie playback. Idempotent — safe to call per page.
    static func activatePlayback() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
        #endif
    }

    /// Hand the session back so other audio (voice memos, music) resumes.
    static func deactivate() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

/// A video's first frame with a play badge — used for portfolio grid tiles and
/// the editor row, so videos read like Instagram (poster + play) instead of a
/// blank async image.
struct VideoThumbnailView: View {
    let url: URL
    var playGlyphSize: Font = .title

    @State private var poster: Image?

    var body: some View {
        ZStack {
            if let poster {
                poster.resizable().scaledToFill()
            } else {
                Rectangle().fill(Color.black.opacity(0.85))
            }
            Image(systemName: "play.circle.fill")
                .font(playGlyphSize)
                .foregroundStyle(.white.opacity(0.92))
                .shadow(radius: 3)
        }
        .task { await generatePoster() }
    }

    private func generatePoster() async {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 800)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        #if canImport(UIKit)
        if let cg = try? await generator.image(at: time).image {
            poster = Image(uiImage: UIImage(cgImage: cg))
        }
        #endif
    }
}

/// Full-screen, swipeable gallery over a vendor's portfolio media — open one item
/// and page left/right through the rest without closing (Instagram-style).
struct MediaGalleryView: View {
    let items: [PortfolioMedia]

    @State private var selection: UUID
    @Environment(\.dismiss) private var dismiss

    init(items: [PortfolioMedia], initial: PortfolioMedia) {
        self.items = items
        _selection = State(initialValue: initial.id)
    }

    private var currentIndex: Int? { items.firstIndex { $0.id == selection } }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(items) { media in
                    MediaPage(media: media, isActive: media.id == selection)
                        .tag(media.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) { topBar }
        // Own the audio session for the whole gallery, not per page: swiping
        // between two videos must not tear the session down and back up.
        .onAppear {
            if items.contains(where: \.isVideo) { MediaAudioSession.activatePlayback() }
        }
        .onDisappear { MediaAudioSession.deactivate() }
    }

    private var topBar: some View {
        HStack {
            if let index = currentIndex, items.count > 1 {
                Text("\(index + 1) / \(items.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.4), in: Capsule())
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .accessibilityLabel(String(localized: "Close"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

/// One page of the gallery: a fit-to-screen photo, or a video that plays only
/// while it's the active page (paused as you swipe away).
private struct MediaPage: View {
    let media: PortfolioMedia
    let isActive: Bool

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if media.isVideo {
                VideoPlayer(player: player)
                    .onAppear {
                        // Covers swiping into a video from a photo-only gallery,
                        // where the gallery's onAppear didn't claim the session.
                        MediaAudioSession.activatePlayback()
                        let p = player ?? AVPlayer(url: media.url)
                        p.isMuted = false
                        player = p
                        if isActive { p.play() }
                    }
                    .onChange(of: isActive) { _, active in
                        if active {
                            MediaAudioSession.activatePlayback()
                            player?.play()
                        } else {
                            player?.pause()
                        }
                    }
                    .onDisappear { player?.pause() }
            } else {
                AsyncImage(url: media.url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView().tint(.white)
                }
            }
        }
        .ignoresSafeArea()
    }
}
