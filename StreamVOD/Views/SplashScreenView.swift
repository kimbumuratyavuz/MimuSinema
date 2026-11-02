import SwiftUI
import Combine

public struct SplashScreenView: View {
    @ObservedObject private var dataManager = DataManagerService.shared
    @Binding public var isFinished: Bool
    
    @State private var progress: CGFloat = 0.0
    @State private var selectedPosterUrl: String? = nil
    
    public init(isFinished: Binding<Bool>) {
        self._isFinished = isFinished
    }
    
    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()
                
                // 1. ARKA PLAN: Her açılışta rastgele tek bir film veya dizi afişi
                ZStack {
                    if let posterUrl = selectedPosterUrl {
                        CachedAsyncImage(urlString: posterUrl) { img in
                            img
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        } placeholder: {
                            Color(red: 0.08, green: 0.08, blue: 0.1)
                        }
                    } else {
                        Color(red: 0.08, green: 0.08, blue: 0.1)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                
                // Sinematik Karartma Katmanı (Afişin üzerinde logonun ve progress barın net görünmesi için)
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.85),
                        Color.black.opacity(0.40),
                        Color.black.opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: geo.size.width, height: geo.size.height)
                
                // 2. SOL ÜST: MimuFlix Başlığı
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 2) {
                        Text("Mimu")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("Flix")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.red)
                    }
                    .shadow(color: .red.opacity(0.6), radius: 14, x: 0, y: 0)
                    .padding(.leading, 24)
                    .padding(.top, max(geo.safeAreaInsets.top, 24) + 12)
                    
                    Spacer()
                }
                .frame(width: geo.size.width, alignment: .leading)
                
                // 3. ALT: Yükleniyor Yazısı ve 6 Saniyelik Kırmızı Progress Bar
                VStack(spacing: 14) {
                    Spacer()
                    
                    Text("Yükleniyor...")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black, radius: 4, x: 0, y: 2)
                    
                    // Kırmızı İlerleme Çubuğu (Progress Bar)
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
                            .frame(width: max(0, 240 * progress), height: 6)
                            .shadow(color: .red.opacity(0.8), radius: 6, x: 0, y: 0)
                    }
                    .frame(width: 240, height: 6)
                    
                    Spacer().frame(height: max(geo.safeAreaInsets.bottom, 20) + 34)
                }
                .frame(width: geo.size.width, alignment: .center)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .onAppear {
            pickRandomPoster()
            startSplashScreen()
            dataManager.fetchAllData()
        }
        .onReceive(dataManager.$allMoviesPool) { movies in
            if selectedPosterUrl == nil, let random = movies.prefix(100).compactMap({ $0.logoUrl }).randomElement() {
                selectedPosterUrl = random
            }
        }
        .onReceive(dataManager.$allSeriesPool) { series in
            if selectedPosterUrl == nil, let random = series.prefix(100).compactMap({ $0.logoUrl }).randomElement() {
                selectedPosterUrl = random
            }
        }
    }
    
    /// Her açılışta film veya dizi havuzundan rastgele tek bir afiş belirler
    private func pickRandomPoster() {
        var candidates: [String] = []
        let moviePosters = dataManager.allMoviesPool.prefix(100).compactMap { $0.logoUrl }
        let seriesPosters = dataManager.allSeriesPool.prefix(100).compactMap { $0.logoUrl }
        candidates.append(contentsOf: moviePosters)
        candidates.append(contentsOf: seriesPosters)
        
        if let random = candidates.randomElement() {
            self.selectedPosterUrl = random
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
