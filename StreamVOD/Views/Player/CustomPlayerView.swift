import SwiftUI
import AVKit

public struct CustomPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    
    public let mediaList: [MediaItem]
    @State public var currentIndex: Int
    
    // Oynatıcı Durumları
    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = true
    @State private var showControls: Bool = true
    @State private var controlsTimer: Timer?
    
    // Süre & İlerleme
    @State private var currentTime: Double = 0
    @State private var totalDuration: Double = 0
    @State private var isDraggingSlider: Bool = false
    
    // Ekran Boyutu Modu
    @State private var aspectModeIndex: Int = 0
    private let aspectModes = VideoAspectRatioMode.allCases
    
    // 2x Hız & Çift Dokunma Göstergeleri
    @State private var isFastForwarding: Bool = false
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
            
            // 1. Video Yansıtıcı
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
            
            // 2. Çift Dokunma & Uzun Basma Algılama Bölgeleri (Sol & Sağ)
            HStack(spacing: 0) {
                // SOL YARI (Geri Sarma -5sn & 2x)
                Color.black.opacity(0.001)
                    .onTapGesture(count: 2) {
                        seekRelative(-5)
                        triggerRewindFeedback()
                    }
                    .onTapGesture(count: 1) {
                        toggleControls()
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.3)
                            .onChanged { _ in
                                start2XSpeed()
                            }
                    )
                
                // SAĞ YARI (İleri Sarma +5sn & 2x)
                Color.black.opacity(0.001)
                    .onTapGesture(count: 2) {
                        seekRelative(5)
                        triggerForwardFeedback()
                    }
                    .onTapGesture(count: 1) {
                        toggleControls()
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.3)
                            .onChanged { _ in
                                start2XSpeed()
                            }
                    )
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { _ in
                        if isFastForwarding {
                            stop2XSpeed()
                        }
                    }
            )
            .ignoresSafeArea()
            
            // 3. Jest Görsel Geribildirimleri (+5sn, -5sn, 2x)
            HStack {
                if showRewindFeedback {
                    VStack {
                        Image(systemName: "gobackward.5")
                            .font(.system(size: 40, weight: .bold))
                        Text("-5 sn")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding(20)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
                    .transition(.opacity)
                }
                
                Spacer()
                
                if showForwardFeedback {
                    VStack {
                        Image(systemName: "goforward.5")
                            .font(.system(size: 40, weight: .bold))
                        Text("+5 sn")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding(20)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 60)
            
            // 2x Hız Rozeti (Üst Merkez)
            if isFastForwarding {
                VStack {
                    HStack(spacing: 6) {
                        Image(systemName: "forward.fill")
                        Text("2X OYNATILIYOR")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.85))
                    .clipShape(Capsule())
                    .padding(.top, 40)
                    
                    Spacer()
                }
            }
            
            // 4. Kontrol Katmanı
            if showControls {
                VStack(spacing: 0) {
                    // ÜST BAR: Geri, Başlık, Boyut Butonu
                    topBar
                    
                    Spacer()
                    
                    // MERKEZ: Oynat/Duraklat & Varsa Sonraki Bölüm
                    centerControls
                    
                    Spacer()
                    
                    // ALT BAR: Zaman, Slider, Sonraki Bölüm Kısayolu
                    bottomBar
                }
                .padding()
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.8), Color.clear, Color.black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .onAppear {
            setLandscapeOrientation(true)
            loadPlayer()
            resetControlsTimer()
        }
        .onDisappear {
            setLandscapeOrientation(false)
            player?.pause()
            player = nil
            controlsTimer?.invalidate()
        }
    }
    
    // MARK: - Alt Görünümler
    
    private var topBar: some View {
        HStack(alignment: .center, spacing: 16) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.2)))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(currentMedia.cleanTitle)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let sName = currentMedia.seriesName {
                    Text(sName)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            // Dublaj / Altyazı Rozeti
            if currentMedia.audioType != .original {
                Text(currentMedia.audioType.rawValue)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(currentMedia.audioType == .dubbing ? Color.green : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(4)
            }
            
            // Video En/Boy Boyut Değiştirici Buton
            Button(action: cycleAspectRatio) {
                HStack(spacing: 4) {
                    Image(systemName: aspectModes[aspectModeIndex].icon)
                    Text(aspectModes[aspectModeIndex].rawValue)
                        .font(.caption2)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.2)))
            }
        }
        .padding(.horizontal)
        .padding(.top, 24)
    }
    
    private var centerControls: some View {
        HStack(spacing: 50) {
            // -10 sn sarma butonu
            Button(action: { seekRelative(-10); resetControlsTimer() }) {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }
            
            // Oynat / Duraklat
            Button(action: togglePlayPause) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.white)
            }
            
            // +10 sn sarma butonu
            Button(action: { seekRelative(10); resetControlsTimer() }) {
                Image(systemName: "goforward.10")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }
        }
    }
    
    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack {
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
                
                // Sonraki Bölüm Butonu (Varsa)
                if hasNextEpisode {
                    Button(action: playNextEpisode) {
                        HStack(spacing: 4) {
                            Text("Sonraki Bölüm")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Image(systemName: "forward.end.fill")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .cornerRadius(6)
                    }
                    .padding(.leading, 8)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }
    
    // MARK: - Oynatıcı Mantığı & HTTP Referer Desteği
    
    private func loadPlayer() {
        player?.pause()
        
        let playUrl: URL
        // Yerel indirilmiş dosya var mı kontrolü
        if let localPath = currentMedia.localRelativePath, FileManager.default.fileExists(atPath: localPath) {
            playUrl = URL(fileURLWithPath: localPath)
            let playerItem = AVPlayerItem(url: playUrl)
            setupPlayerWithItem(playerItem)
        } else {
            playUrl = currentMedia.streamUrl
            
            // HTTP Header'ları ekleme (Referer & User-Agent)
            var headers: [String: String] = [:]
            if let ref = currentMedia.httpReferrer, !ref.isEmpty {
                headers["Referer"] = ref
            }
            if let ua = currentMedia.httpUserAgent, !ua.isEmpty {
                headers["User-Agent"] = ua
            }
            
            let asset = AVURLAsset(url: playUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            let playerItem = AVPlayerItem(asset: asset)
            setupPlayerWithItem(playerItem)
        }
    }
    
    private func setupPlayerWithItem(_ item: AVPlayerItem) {
        let p = AVPlayer(playerItem: item)
        self.player = p
        
        // Zaman gözlemcisi
        p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { time in
            if !isDraggingSlider {
                self.currentTime = time.seconds
                if let dur = p.currentItem?.duration.seconds, !dur.isNaN {
                    self.totalDuration = dur
                }
            }
        }
        
        // Video bittiğinde otomatik sonraki bölüme geç
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
    
    private func seekRelative(_ seconds: Double) {
        guard let p = player else { return }
        let target = max(0, min(totalDuration, currentTime + seconds))
        seekTo(seconds: target)
    }
    
    private func seekTo(seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }
    
    private func start2XSpeed() {
        guard let p = player else { return }
        p.rate = 2.0
        isFastForwarding = true
    }
    
    private func stop2XSpeed() {
        guard let p = player else { return }
        p.rate = isPlaying ? 1.0 : 0.0
        isFastForwarding = false
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
    
    private func toggleControls() {
        withAnimation {
            showControls.toggle()
        }
        if showControls {
            resetControlsTimer()
        }
    }
    
    private func resetControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { _ in
            withAnimation {
                showControls = false
            }
        }
    }
    
    private func setLandscapeOrientation(_ landscape: Bool) {
        if #available(iOS 16.0, *) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            let orientation: UIInterfaceOrientationMask = landscape ? .landscapeRight : .portrait
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
        } else {
            let orientation = landscape ? UIInterfaceOrientation.landscapeRight.rawValue : UIInterfaceOrientation.portrait.rawValue
            UIDevice.current.setValue(orientation, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
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
