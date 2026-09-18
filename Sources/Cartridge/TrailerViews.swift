import SwiftUI
import WebKit

/// Plays a YouTube trailer through YouTube's own embedded player (downloading the video would break YouTube's terms)
/// and reports what the player is doing.
final class TrailerWebView: NSView {
    enum Event: Equatable {
        case playing, buffering, ended
        /// YouTube's error code: 2 bad id, 5 HTML5 error, 100 removed, 101/150 embedding disabled, 153 missing referrer.
        case failed(Int)
    }

    var onEvent: ((Event) -> Void)?
    private(set) var videoID: String?
    private let webView: WKWebView

    /// Embeds need an https page origin to send as the referrer, or YouTube refuses to play (error 153).
    static let pageOrigin = URL(string: "https://app.cartridge.launcher/")!

    override init(frame: NSRect) {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        let relay = MessageRelay()
        config.userContentController.add(relay, name: "trailer")
        webView = WKWebView(frame: frame, configuration: config)
        super.init(frame: frame)
        relay.owner = self
        webView.autoresizingMask = [.width, .height]
        webView.frame = bounds
        addSubview(webView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Clicks go to the app, not the player, so selecting around the inspector never pauses the video by accident.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func load(videoID: String, muted: Bool) {
        guard YouTube.videoID(from: videoID) == videoID else {
            onEvent?(.failed(2))
            return
        }
        self.videoID = videoID
        webView.loadHTMLString(Self.html(videoID: videoID, muted: muted), baseURL: Self.pageOrigin)
    }

    func setMuted(_ muted: Bool) {
        webView.evaluateJavaScript("window.player && player.\(muted ? "mute" : "unMute")()", completionHandler: nil)
    }

    func stop() {
        videoID = nil
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.loadHTMLString("", baseURL: nil)
    }

    fileprivate func received(_ body: Any) {
        guard let message = body as? [String: Any] else { return }
        if let code = message["error"] as? Int {
            onEvent?(.failed(code))
        } else if let state = message["state"] as? Int {
            switch state {
            case 1: onEvent?(.playing)
            case 3: onEvent?(.buffering)
            case 0: onEvent?(.ended)
            default: break
            }
        }
    }

    /// `videoID` must already be validated: it is placed into the page as-is.
    static func html(videoID: String, muted: Bool) -> String {
        """
        <!doctype html>
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#player{position:absolute;inset:0;width:100%;height:100%}</style>
        </head><body><div id="player"></div>
        <script>
        function post(message) { window.webkit.messageHandlers.trailer.postMessage(message); }
        function onYouTubeIframeAPIReady() {
          window.player = new YT.Player('player', {
            host: 'https://www.youtube-nocookie.com',
            videoId: '\(videoID)',
            playerVars: { autoplay: 1, controls: 0, disablekb: 1, fs: 0, iv_load_policy: 3, modestbranding: 1, playsinline: 1, rel: 0 },
            events: {
              onReady: function (e) { e.target.setVolume(45); \(muted ? "e.target.mute();" : "") e.target.playVideo(); },
              onStateChange: function (e) { post({ state: e.data }); },
              onError: function (e) { post({ error: e.data }); }
            }
          });
        }
        </script>
        <script src="https://www.youtube.com/iframe_api" onerror="post({ error: 5 })"></script>
        </body></html>
        """
    }
}

/// WKUserContentController holds its handlers strongly; relaying through a weak reference avoids a retain cycle.
private final class MessageRelay: NSObject, WKScriptMessageHandler {
    weak var owner: TrailerWebView?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.received(message.body)
    }
}

struct TrailerPlayer: NSViewRepresentable {
    let videoID: String
    let muted: Bool
    let onEvent: (TrailerWebView.Event) -> Void

    func makeNSView(context: Context) -> TrailerWebView {
        let view = TrailerWebView(frame: .zero)
        view.onEvent = onEvent
        view.load(videoID: videoID, muted: muted)
        return view
    }

    func updateNSView(_ view: TrailerWebView, context: Context) {
        view.onEvent = onEvent
        if view.videoID != videoID { view.load(videoID: videoID, muted: muted) }
        view.setMuted(muted)
    }

    static func dismantleNSView(_ view: TrailerWebView, coordinator: ()) {
        view.stop()
    }
}

/// A game's cover that, once it has been looked at for a moment, turns into the game's trailer.
struct CoverWithTrailer: View {
    let game: Game
    var playsTrailers = true

    @Environment(Library.self) private var library
    @AppStorage("trailersMuted") private var muted = false
    @State private var videoID: String?
    @State private var phase = Phase.cover
    @State private var width: CGFloat = 268

    enum Phase { case cover, loading, playing }

    static let dwell: Duration = .milliseconds(2500)

    var body: some View {
        ZStack {
            Rectangle().fill(.black)
            ArtView(game: game)
                .opacity(phase == .playing ? 0 : 1)
            if let videoID {
                TrailerPlayer(videoID: videoID, muted: muted, onEvent: handle)
                    .opacity(phase == .playing ? 1 : 0)
                    .allowsHitTesting(false)
            }
            if phase == .loading {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini).tint(.white)
                        Text("Loading trailer…").font(.caption.weight(.medium)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(8)
                }
                .transition(.opacity)
            }
            if phase == .playing {
                VStack {
                    HStack(spacing: 6) {
                        Spacer()
                        overlayButton(muted ? "speaker.slash.fill" : "speaker.wave.2.fill", help: muted ? "Unmute trailer" : "Mute trailer") {
                            muted.toggle()
                        }
                        overlayButton("xmark", help: "Stop trailer") { stop() }
                    }
                    Spacer()
                }
                .padding(6)
                .transition(.opacity)
            }
        }
        .frame(height: phase == .playing ? width * 9 / 16 : 250)
        .frame(maxWidth: .infinity)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { _, new in width = new }
        })
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .animation(.easeInOut(duration: 0.45), value: phase)
        .task(id: game.id) { await waitThenPlay() }
        .onChange(of: library.sessions[game.id] != nil || library.status[game.id] != nil) { _, busy in
            if busy { stop() }
        }
    }

    private func overlayButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func waitThenPlay() async {
        stop()
        guard playsTrailers else { return }
        try? await Task.sleep(for: Self.dwell)
        guard !Task.isCancelled, library.sessions[game.id] == nil, library.status[game.id] == nil else { return }
        guard let id = await library.trailerID(for: game.id), !Task.isCancelled else { return }
        videoID = id
        phase = .loading
        // A slow connection shouldn't leave the spinner up forever; the next selection tries again.
        try? await Task.sleep(for: .seconds(20))
        if !Task.isCancelled, phase == .loading { stop() }
    }

    private func handle(_ event: TrailerWebView.Event) {
        switch event {
        case .playing:
            if videoID != nil { phase = .playing }
        case .buffering:
            break
        case .ended:
            stop()
        case .failed:
            library.trailerFailed(game.id)
            stop()
        }
    }

    private func stop() {
        phase = .cover
        videoID = nil
    }
}
