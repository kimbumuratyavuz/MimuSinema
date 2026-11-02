import SwiftUI
import Combine

public struct SplashScreenView: View {
    @ObservedObject private var dataManager = DataManagerService.shared
    @Binding public var isFinished: Bool
    
    @State private var progress: CGFloat = 0.0
    @State private var moviePosterUrl: String? = nil
    @State private var seriesPosterUrl: String? = nil
    
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
            
            // Sinematik Karartma Katmanı
            LinearGradient(
                colors: [
                    Color.black.opacity(0.85),
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
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 6)
                        
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
            startSplashScreen()
            dataManager.fetchAllData()
        }
        .onReceive(dataManager.$allMoviesPool) { movies in
            if moviePosterUrl == nil, let random = movies.prefix(100).compactMap({ $0.logoUrl }).randomElement() {
                moviePosterUrl = random
            }
        }
        .onReceive(dataManager.$allSeriesPool) { series in
            if seriesPosterUrl == nil, let random = series.prefix(100).compactMap({ $0.logoUrl }).randomElement() {
                seriesPosterUrl = random
            }
        }
    }
    
    private func pickRandomPosters() {
        if let randomMovie = dataManager.allMoviesPool.prefix(100).compactMap({ $0.logoUrl }).randomElement() {
            self.moviePosterUrl = randomMovie
        }
        if let randomSeries = dataManager.allSeriesPool.prefix(100).compactMap({ $0.logoUrl }).randomElement() {
            self.seriesPosterUrl = randomSeries
        }
    }
    
    private func startSplashScreen() {
        withAnimation(.linear(duration: 6.0)) {
            progress = 1.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            withAnimation(.easeInOut(duration: 0.5)) {
                isFinished = true
            }
        }
    }
}
