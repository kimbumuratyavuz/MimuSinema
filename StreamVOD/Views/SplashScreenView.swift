import SwiftUI
import Combine

public struct SplashScreenView: View {
    @ObservedObject private var dataManager = DataManagerService.shared
    @Binding public var isFinished: Bool
    
    @State private var progress: CGFloat = 0.0
    @State private var moviePosterUrl: String? = nil
    @State private var seriesPosterUrl: String? = nil
    @State private var timerCancellable: AnyCancellable? = nil
    
    public init(isFinished: Binding<Bool>) {
        self._isFinished = isFinished
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 1. ARKA PLAN: Film ve Dizi M3U'larından Rastgele Kapaklar
            GeometryReader { geo in
                HStack(spacing: 0) {
                    // Sol Yarı: Rastgele Film Kapağı
                    ZStack {
                        if let movieUrl = moviePosterUrl {
                            CachedAsyncImage(urlString: movieUrl) { img in
                                img.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Color(red: 0.1, green: 0.1, blue: 0.12)
                            }
                        } else {
                            Color(red: 0.1, green: 0.1, blue: 0.12)
                        }
                    }
                    .frame(width: geo.size.width / 2, height: geo.size.height)
                    .clipped()
                    
                    // Sağ Yarı: Rastgele Dizi Kapağı
                    ZStack {
                        if let seriesUrl = seriesPosterUrl {
                            CachedAsyncImage(urlString: seriesUrl) { img in
                                img.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Color(red: 0.08, green: 0.08, blue: 0.1)
                            }
                        } else {
                            Color(red: 0.08, green: 0.08, blue: 0.1)
                        }
                    }
                    .frame(width: geo.size.width / 2, height: geo.size.height)
                    .clipped()
                }
            }
            .ignoresSafeArea()
            
            // Sinematik Karartma Katmanı (Afişlerin arkada hafif ve asil görünmesi için)
            LinearGradient(
                colors: [
                    Color.black.opacity(0.82),
                    Color.black.opacity(0.70),
                    Color.black.opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // 2. SOL ÜST: MimuFlix Başlığı
            VStack {
                HStack {
                    HStack(spacing: 2) {
                        Text("Mimu")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("Flix")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.red)
                    }
                    .shadow(color: .red.opacity(0.4), radius: 10, x: 0, y: 0)
                    .padding(.leading, 24)
                    .padding(.top, 48)
                    
                    Spacer()
                }
                Spacer()
            }
            .ignoresSafeArea()
            
            // 3. ALT: Yükleniyor Yazısı ve 6 Saniyelik Kırmızı Progress Bar
            VStack(spacing: 14) {
                Spacer()
                
                Text("Yükleniyor...")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black, radius: 4, x: 0, y: 2)
                
                // Kırmızı İlerleme Çubuğu (Progress Bar)
                GeometryReader { barGeo in
                    ZStack(alignment: .leading) {
                        // Arka Plan Çizgisi
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 6)
                        
                        // İlerleyen Kırmızı Çizgi
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.red, Color(red: 1.0, green: 0.3, blue: 0.3)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, barGeo.size.width * progress), height: 6)
                            .shadow(color: .red.opacity(0.8), radius: 6, x: 0, y: 0)
                    }
                }
                .frame(width: 240, height: 6)
                
                Spacer().frame(height: 54)
            }
        }
        .onAppear {
            pickRandomPosters()
            startSplashScreenTimer()
        }
        .onReceive(dataManager.$allMoviesPool) { movies in
            if moviePosterUrl == nil, let random = movies.compactMap({ $0.logoUrl }).randomElement() {
                moviePosterUrl = random
            }
        }
        .onReceive(dataManager.$allSeriesPool) { series in
            if seriesPosterUrl == nil, let random = series.compactMap({ $0.logoUrl }).randomElement() {
                seriesPosterUrl = random
            }
        }
    }
    
    private func pickRandomPosters() {
        if let randomMovie = dataManager.allMoviesPool.compactMap({ $0.logoUrl }).randomElement() {
            self.moviePosterUrl = randomMovie
        }
        if let randomSeries = dataManager.allSeriesPool.compactMap({ $0.logoUrl }).randomElement() {
            self.seriesPosterUrl = randomSeries
        }
    }
    
    private func startSplashScreenTimer() {
        let totalDuration: Double = 6.0
        let interval: Double = 0.05
        let totalSteps = totalDuration / interval
        var currentStep: Double = 0
        
        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                currentStep += 1
                withAnimation(.linear(duration: interval)) {
                    progress = min(1.0, CGFloat(currentStep / totalSteps))
                }
                
                if currentStep >= totalSteps {
                    timerCancellable?.cancel()
                    timerCancellable = nil
                    withAnimation(.easeInOut(duration: 0.6)) {
                        isFinished = true
                    }
                }
            }
    }
}
