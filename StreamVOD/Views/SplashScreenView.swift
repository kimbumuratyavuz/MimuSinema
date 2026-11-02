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
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 1. ARKA PLAN: Her açılışta rastgele tek bir film veya dizi afişi
            ZStack {
                if let posterUrl = selectedPosterUrl {
                    CachedAsyncImage(urlString: posterUrl) { img in
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color(red: 0.08, green: 0.08, blue: 0.1)
                    }
                } else {
                    Color(red: 0.08, green: 0.08, blue: 0.1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea()
            
            // Sinematik Karartma Katmanı (Afişin üzerinde logonun ve progress barın net görünmesi için)
            LinearGradient(
                colors: [
                    Color.black.opacity(0.82),
                    Color.black.opacity(0.45),
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
                    .shadow(color: .red.opacity(0.5), radius: 12, x: 0, y: 0)
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
