import Foundation
import Combine

@MainActor
public final class DataManagerService: ObservableObject {
    public static let shared = DataManagerService()
    
    public static let movieM3UUrl = URL(string: "https://raw.githubusercontent.com/kimbumuratyavuz/capcanli/main/filmuygulama.m3u")!
    public static let seriesM3UUrl = URL(string: "https://raw.githubusercontent.com/kimbumuratyavuz/capcanli/main/diziuygulama.m3u")!
    
    private var allMoviesPool: [MediaItem] = []
    private var allSeriesPool: [SeriesGroup] = []
    
    @Published public var visibleMovies: [MediaItem] = []
    @Published public var visibleSeries: [SeriesGroup] = []
    
    @Published public var isLoadingMovies: Bool = false
    @Published public var isLoadingSeries: Bool = false
    @Published public var errorMessage: String? = nil
    
    private let pageSize = 50
    private var currentMoviePage = 0
    private var currentSeriesPage = 0
    
    private init() {
        // Disk Cache Yapılandırması (100MB RAM, 300MB Disk)
        let cache = URLCache(memoryCapacity: 100 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024, diskPath: "mimusinema_cache")
        URLCache.shared = cache
        
        // 1. ANINDA AÇILMA: Yerel önbellekten hemen verileri yükle
        loadLocalCache()
    }
    
    public func fetchAllData() {
        Task {
            await fetchMovies()
            await fetchSeries()
        }
    }
    
    public func fetchMovies() async {
        guard !isLoadingMovies else { return }
        if visibleMovies.isEmpty { isLoadingMovies = true }
        
        do {
            var request = URLRequest(url: Self.movieM3UUrl)
            request.cachePolicy = .useProtocolCachePolicy
            request.timeoutInterval = 15
            
            let (data, _) = try await URLSession.shared.data(for: request)
            if let content = String(data: data, encoding: .utf8) {
                let parsed = await Task.detached(priority: .userInitiated) {
                    M3UParserService.shared.parse(m3uContent: content, isSeriesOverride: false)
                }.value
                
                self.allMoviesPool = parsed
                self.currentMoviePage = 0
                self.visibleMovies = []
                self.loadMoreMovies()
                
                // Diske kaydet (sonraki açılışta 0 ms için)
                self.saveMoviesToDisk(items: parsed)
            }
        } catch {
            if visibleMovies.isEmpty {
                self.errorMessage = "Filmler yüklenemedi: \(error.localizedDescription)"
            }
        }
        
        isLoadingMovies = false
    }
    
    public func fetchSeries() async {
        guard !isLoadingSeries else { return }
        if visibleSeries.isEmpty { isLoadingSeries = true }
        
        do {
            var request = URLRequest(url: Self.seriesM3UUrl)
            request.cachePolicy = .useProtocolCachePolicy
            request.timeoutInterval = 15
            
            let (data, _) = try await URLSession.shared.data(for: request)
            if let content = String(data: data, encoding: .utf8) {
                let parsedGroups = await Task.detached(priority: .userInitiated) {
                    let items = M3UParserService.shared.parse(m3uContent: content, isSeriesOverride: true)
                    return M3UParserService.shared.groupSeries(items: items)
                }.value
                
                self.allSeriesPool = parsedGroups
                self.currentSeriesPage = 0
                self.visibleSeries = []
                self.loadMoreSeries()
                
                // Diske kaydet
                self.saveSeriesToDisk(groups: parsedGroups)
            }
        } catch {
            if visibleSeries.isEmpty {
                self.errorMessage = "Diziler yüklenemedi: \(error.localizedDescription)"
            }
        }
        
        isLoadingSeries = false
    }
    
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
    
    // MARK: - Anında Açılış İçin Disk Önbelleği
    private var moviesCacheFile: URL {
        let docs = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("cached_movies.json")
    }
    
    private var seriesCacheFile: URL {
        let docs = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("cached_series.json")
    }
    
    private func saveMoviesToDisk(items: [MediaItem]) {
        Task.detached(priority: .background) {
            if let data = try? JSONEncoder().encode(items) {
                try? data.write(to: self.moviesCacheFile)
            }
        }
    }
    
    private func saveSeriesToDisk(groups: [SeriesGroup]) {
        // SeriesGroup'ların bölümlerini kaydet
        Task.detached(priority: .background) {
            let allEps = groups.flatMap { $0.episodes }
            if let data = try? JSONEncoder().encode(allEps) {
                try? data.write(to: self.seriesCacheFile)
            }
        }
    }
    
    private func loadLocalCache() {
        if let data = try? Data(contentsOf: moviesCacheFile),
           let cached = try? JSONDecoder().decode([MediaItem].self, from: data),
           !cached.isEmpty {
            self.allMoviesPool = cached
            self.loadMoreMovies()
        }
        
        if let sData = try? Data(contentsOf: seriesCacheFile),
           let cachedEps = try? JSONDecoder().decode([MediaItem].self, from: sData),
           !cachedEps.isEmpty {
            let grouped = M3UParserService.shared.groupSeries(items: cachedEps)
            self.allSeriesPool = grouped
            self.loadMoreSeries()
        }
    }
}
