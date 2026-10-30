import Foundation
import Combine

@MainActor
public final class DataManagerService: ObservableObject {
    public static let shared = DataManagerService()
    
    // M3U URL'leri
    public static let movieM3UUrl = URL(string: "https://raw.githubusercontent.com/kimbumuratyavuz/capcanli/main/filmuygulama.m3u")!
    public static let seriesM3UUrl = URL(string: "https://raw.githubusercontent.com/kimbumuratyavuz/capcanli/main/diziuygulama.m3u")!
    
    // Tüm Ham Veri Havuzu (Arka planda tutulur)
    private var allMoviesPool: [MediaItem] = []
    private var allSeriesPool: [SeriesGroup] = []
    
    // UI İçin 50'şer Sayfalanmış Veriler (Donmayı önler)
    @Published public var visibleMovies: [MediaItem] = []
    @Published public var visibleSeries: [SeriesGroup] = []
    
    @Published public var isLoadingMovies: Bool = false
    @Published public var isLoadingSeries: Bool = false
    @Published public var errorMessage: String? = nil
    
    private let pageSize = 50
    private var currentMoviePage = 0
    private var currentSeriesPage = 0
    
    private init() {}
    
    // MARK: - Verileri Yükle
    public func fetchAllData() {
        Task {
            await fetchMovies()
            await fetchSeries()
        }
    }
    
    public func fetchMovies() async {
        guard !isLoadingMovies else { return }
        isLoadingMovies = true
        
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.movieM3UUrl)
            if let content = String(data: data, encoding: .utf8) {
                // Arka planda parse et
                let parsed = await Task.detached(priority: .userInitiated) {
                    M3UParserService.shared.parse(m3uContent: content, isSeriesOverride: false)
                }.value
                
                self.allMoviesPool = parsed
                self.currentMoviePage = 0
                self.visibleMovies = []
                self.loadMoreMovies()
            }
        } catch {
            self.errorMessage = "Filmler yüklenemedi: \(error.localizedDescription)"
        }
        
        isLoadingMovies = false
    }
    
    public func fetchSeries() async {
        guard !isLoadingSeries else { return }
        isLoadingSeries = true
        
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.seriesM3UUrl)
            if let content = String(data: data, encoding: .utf8) {
                // Arka planda parse et ve dizi adına göre grupla
                let parsedGroups = await Task.detached(priority: .userInitiated) {
                    let items = M3UParserService.shared.parse(m3uContent: content, isSeriesOverride: true)
                    return M3UParserService.shared.groupSeries(items: items)
                }.value
                
                self.allSeriesPool = parsedGroups
                self.currentSeriesPage = 0
                self.visibleSeries = []
                self.loadMoreSeries()
            }
        } catch {
            self.errorMessage = "Diziler yüklenemedi: \(error.localizedDescription)"
        }
        
        isLoadingSeries = false
    }
    
    // MARK: - 50'şer 50'şer Sayfalama (Pagination / Lazy Loading)
    
    public func loadMoreMovies() {
        let startIndex = currentMoviePage * pageSize
        guard startIndex < allMoviesPool.count else { return }
        
        let endIndex = min(startIndex + pageSize, allMoviesPool.count)
        let nextBatch = Array(allMoviesPool[startIndex..<endIndex])
        
        visibleMovies.append(contentsOf: nextBatch)
        currentMoviePage += 1
    }
    
    public func loadMoreSeries() {
        let startIndex = currentSeriesPage * pageSize
        guard startIndex < allSeriesPool.count else { return }
        
        let endIndex = min(startIndex + pageSize, allSeriesPool.count)
        let nextBatch = Array(allSeriesPool[startIndex..<endIndex])
        
        visibleSeries.append(contentsOf: nextBatch)
        currentSeriesPage += 1
    }
    
    public var hasMoreMovies: Bool {
        visibleMovies.count < allMoviesPool.count
    }
    
    public var hasMoreSeries: Bool {
        visibleSeries.count < allSeriesPool.count
    }
}
