//
//  YouTubePlayerWebView.swift
//  gThai
//
import SwiftUI
import YouTubeiOSPlayerHelper

/// Wraps Google's official `YTPlayerView` (youtube-ios-player-helper), which handles the
/// embedding-origin requirements correctly out of the box — avoiding the origin-validation
/// failures a hand-rolled WKWebView + IFrame API wrapper runs into. Also lets us reliably
/// distinguish "this video can't be embedded" (`.notEmbeddable`) from other failures via the
/// delegate, instead of guessing from an on-screen error message.
@Observable final class YouTubePlayerBridge {
    var currentTime: Double = 0
    var isReady = false
    var notEmbeddable = false
    weak var playerView: YTPlayerView?
    private var pollTimer: Timer?

    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.playerView?.currentTime { [weak self] time, _ in
                self?.currentTime = Double(time)
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func seekAndPlay(to seconds: Int) {
        playerView?.seek(toSeconds: Float(seconds), allowSeekAhead: true)
        playerView?.playVideo()
    }
}

struct YouTubePlayerWebView: UIViewRepresentable {
    let videoId: String
    let bridge: YouTubePlayerBridge

    func makeCoordinator() -> Coordinator {
        Coordinator(bridge: bridge)
            
    }

    func makeUIView(context: Context) -> YTPlayerView {
        let playerView = YTPlayerView()
        playerView.delegate = context.coordinator
        bridge.playerView = playerView
        let playerVars: [String: Any] = ["playsinline": 1, "rel": 0, "modestbranding": 1, "autoplay": 1]
        playerView.load(withVideoId: videoId, playerVars: playerVars)
        return playerView
    }

    func updateUIView(_ uiView: YTPlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: YTPlayerView, coordinator: Coordinator) {
        coordinator.bridge.stopPolling()
        uiView.stopVideo()
    }

    final class Coordinator: NSObject, YTPlayerViewDelegate {
        let bridge: YouTubePlayerBridge
        init(bridge: YouTubePlayerBridge) { self.bridge = bridge }

        func playerViewDidBecomeReady(_ playerView: YTPlayerView) {
            bridge.isReady = true
            bridge.startPolling()
        }

        func playerView(_ playerView: YTPlayerView, receivedError error: YTPlayerError) {
            if error == .notEmbeddable {
                bridge.notEmbeddable = true
            }
        }
    }
}
