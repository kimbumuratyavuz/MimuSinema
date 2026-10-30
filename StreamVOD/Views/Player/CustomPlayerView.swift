import SwiftUI
import AVKit

// MARK: - Global Orientation Manager
public final class OrientationManager {
    public static func forceOrientation(_ orientation: UIInterfaceOrientationMask) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            if #available(iOS 16.0, *) {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { _ in }
            } else {
                let val: Int
                switch orientation {
                case .landscape, .landscapeRight: val = UIInterfaceOrientation.landscapeRight.rawValue
                case .landscapeLeft: val = UIInterfaceOrientation.landscapeLeft.rawValue
                default: val = UIInterfaceOrientation.portrait.rawValue
                }
                UIDevice.current.setValue(val, forKey: "orientation")
                UIViewController.attemptRotationToDeviceOrientation()
            }
        }
    }
}

public struct CustomPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    
    public let mediaList: [MediaItem]
    @State public var currentIndex: Int
    
    // Oynatıcı Durumları
    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = true
    @State private var showControls: Bool = true
    @State private var controlsTimer: Timer?
    
    // Süre
    @State private var currentTime: Double = 0
    @State private var totalDuration: Double = 0
    @State private var isDraggingSlider: Bool = false
    
    // Boyut (Aspect Ratio) Modu
    @State private var aspectModeIndex: Int = 0
    private let aspectModes = VideoAspectRatioMode.allCases
    
    // Manuel Yatay / Dikey Ekran Yönlendirmesi
    @State private var isLandscapeMode: Bool = false
    
    // 2x Hız Durumu & Göstergeler
    @State private var is2XActive: Bool = false
    @State private var showForwardFeedback: Bool = false
    @State private var showRewindFeedback: Bool = false
    
    public init(mediaList: [MediaItem], initialIndex: Int = 0) {
        self.mediaList = mediaList
        self._currentIndex = State(initialValue: initialIndex)
    }
    
    private var currentMedia: MediaItem {
        mediaList[currentIndex]
    }
    
    private var hasNextEpisode: Bool {
        currentIndex + 1 < mediaList.count
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 1. VİDEO YANSITICI
            if let player = player {
                AVPlayerCustomRepresentable(
                    player: player,
                    videoGravity: aspectModes[aspectModeIndex].videoGravity
                )
                .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }
            
            // 2. JEST KATMANI
            GeometryReader { geo in
                HStack(spacing: 0) {
                    // SOL ALAN (-5 sn Sarma & Sol Basılı Tutma)
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            seekRelative(-5)
                            triggerRewindFeedback()
                        }
                        .onTapGesture(count: 1) {
                            handleSingleTap()
                        }
                        .gesture(
                            LongPressGesture(minimumDuration: 0.6)
                                .onChanged { _ in
                                    start2XSpeed()
                                }
                                .onEnded { _ in
                                    stop2XSpeed()
                                }
                        )
                    
                    // SAĞ ALAN (+5 sn Sarma & Sağ Basılı Tutma)
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            seekRelative(5)
                            triggerForwardFeedback()
                        }
                        .onTapGesture(count: 1) {
                            handleSingleTap()
                        }
                        .gesture(
                            LongPressGesture(minimumDuration: 0.6)
                                .onChanged { _ in
                                    start2XSpeed()
                                }
                                .onEnded { _ in
                                    stop2XSpeed()
                                }
                        )
                }
            }
            .ignoresSafeArea()
            
            // 3. JEST BİLDİRİMLERİ (±5 SN)
            HStack {
                if showRewindFeedback {
                    VStack(spacing: 6) {
                        Image(systemName: "gobackward.5")
                            .font(.system(size: 38, weight: .bold))
                        Text("-5 sn")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding(18)
                    .background(Color.black.opacity(0.65))
                    .cornerRadius(12)
                    .transition(.opacity)
                }
                
                Spacer()
                
                if showForwardFeedback {
                    VStack(spacing: 6) {
                        Image(systemName: "goforward.5")
                            .font(.system(size: 38, weight: .bold))
                        Text("+5 sn")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding(18)
                    .background(Color.black.opacity(0.65))
                    .cornerRadius(12)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 60)
            
            // 2X HIZ ROZETİ
            if is2XActive {
                VStack {
                    HStack(spacing: 6) {
                        Image(systemName: "forward.fill")
                        Text("2X HIZLI OYNATILIYOR")
                            .font(.caption)
                            .fontWeight(.black)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.9))
                    .clipShape(Capsule())
                    .padding(.top, 40)
                    
                    Spacer()
                }
            }
            
            // 4. KONTROL KATMANI
            if showControls {
                VStack(spacing: 0) {
                    topBarView
                    
                    Spacer()
                    
                    centerControlsView
                    
                    Spacer()
                    
                    bottomBarView
                }
                .padding()
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.85), Color.clear, Color.black.opacity(0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .statusBarHidden(true)
        .onAppear {
            loadPlayer()
            resetControlsTimer()
        }
        .onDisappear {
            if isLandscapeMode {
                OrientationManager.forceOrientation(.portrait)
            }
            player?.pause()
            player = nil
            controlsTimer?.invalidate()
        }
    }
    
    // MARK: - Kontrol Bileşenleri
    
    private var topBarView: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: {
                dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.2)))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(currentMedia.cleanTitle)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let sName = currentMedia.seriesName {
                    Text(sName)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            // YATAY / DİKEY EKRAN DÖNDÜRME BUTONU
            Button(action: toggleOrientation) {
                HStack(spacing: 4) {
                    Image(systemName: isLandscapeMode ? "rectangle.portrait.rotate" : "rectangle.landscape.rotate")
                        .font(.system(size: 13))
                    Text(isLandscapeMode ? "Dikey" : "Yatay")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(isLandscapeMode ? Color.red : Color.white.opacity(0.25)))
            }
            
            // Boyut Değiştirme Butonu (Fit, Fill, Stretch)
            Button(action: cycleAspectRatio) {
                HStack(spacing: 4) {
                    Image(systemName: aspectModes[aspectModeIndex].icon)
                    Text(aspectModes[aspectModeIndex].rawValue)
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.25)))
            }
        }
        .padding(.horizontal)
        .padding(.top, 24)
    }
    
    private var centerControlsView: some View {
        HStack(spacing: 50) {
            Button(action: {
                seekRelative(-10)
                resetControlsTimer()
            }) {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 34))
                    .foregroundColor(.white)
            }
            
            Button(action: togglePlayPause) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.white)
            }
            
            Button(action: {
                seekRelative(10)
                resetControlsTimer()
            }) {
                Image(systemName: "goforward.10")
                    .font(.system(size: 34))
                    .foregroundColor(.white)
            }
        }
    }
    
    private var bottomBarView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text(formatTime(currentTime))
                    .font(.caption)
                    .foregroundColor(.white)
                
                Slider(
                    value: Binding(
                        get: { currentTime },
                        set: { newValue in
                            currentTime = newValue
                            isDraggingSlider = true
                        }
                    ),
                    in: 0...max(totalDuration, 1.0)
                ) { editing in
                    if !editing {
                        seekTo(seconds: currentTime)
                        isDraggingSlider = false
                        resetControlsTimer()
                    }
                }
                .tint(.red)
                
                Text(formatTime(totalDuration))
                    .font(.caption)
                    .foregroundColor(.white)
                
                if hasNextEpisode {
                    Button(action: playNextEpisode) {
                        HStack(spacing: 4) {
                            Text("Sonraki Bölüm")
                                .font(.caption)
                                .fontWeight(.bold)
                            Image(systemName: "forward.end.fill")
                                .font(.caption2)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .cornerRadius(6)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }
    
    private func toggleOrientation() {
        isLandscapeMode.toggle()
        if isLandscapeMode {
            OrientationManager.forceOrientation(.landscapeRight)
        } else {
            OrientationManager.forceOrientation(.portrait)
        }
        resetControlsTimer()
    }
    
    private func loadPlayer() {
        player?.pause()
        
        let playUrl: URL
        if let localPath = currentMedia.localRelativePath, FileManager.default.fileExists(atPath: localPath) {
            playUrl = URL(fileURLWithPath: localPath)
            let item = AVPlayerItem(url: playUrl)
            setupPlayerWithItem(item)
        } else {
            playUrl = currentMedia.streamUrl
            var headers: [String: String] = [:]
            if let ref = currentMedia.httpReferrer, !ref.isEmpty { headers["Referer"] = ref }
            if let ua = currentMedia.httpUserAgent, !ua.isEmpty { headers["User-Agent"] = ua }
            
            let asset = AVURLAsset(url: playUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            let item = AVPlayerItem(asset: asset)
            setupPlayerWithItem(item)
        }
    }
    
    private func setupPlayerWithItem(_ item: AVPlayerItem) {
        let p = AVPlayer(playerItem: item)
        self.player = p
        
        p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { time in
            if !isDraggingSlider {
                self.currentTime = time.seconds
                if let dur = p.currentItem?.duration.seconds, !dur.isNaN {
                    self.totalDuration = dur
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            if hasNextEpisode {
                playNextEpisode()
            }
        }
        
        p.play()
        isPlaying = true
    }
    
    private func togglePlayPause() {
        guard let p = player else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            isPlaying = true
        }
        resetControlsTimer()
    }
    
    private func handleSingleTap() {
        withAnimation {
            showControls.toggle()
        }
        if showControls {
            resetControlsTimer()
        }
    }
    
    private func seekRelative(_ seconds: Double) {
        let target = max(0, min(totalDuration, currentTime + seconds))
        seekTo(seconds: target)
        resetControlsTimer()
    }
    
    private func seekTo(seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }
    
    private func start2XSpeed() {
        guard let p = player else { return }
        p.rate = 2.0
        is2XActive = true
    }
    
    private func stop2XSpeed() {
        guard let p = player else { return }
        p.rate = isPlaying ? 1.0 : 0.0
        is2XActive = false
    }
    
    private func triggerForwardFeedback() {
        withAnimation { showForwardFeedback = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation { showForwardFeedback = false }
        }
    }
    
    private func triggerRewindFeedback() {
        withAnimation { showRewindFeedback = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation { showRewindFeedback = false }
        }
    }
    
    private func cycleAspectRatio() {
        aspectModeIndex = (aspectModeIndex + 1) % aspectModes.count
        resetControlsTimer()
    }
    
    private func playNextEpisode() {
        guard hasNextEpisode else { return }
        currentIndex += 1
        loadPlayer()
    }
    
    private func resetControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            withAnimation {
                showControls = false
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "00:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
}
