import Foundation
import Combine

@MainActor
public final class DataManagerService: ObservableObject {
    public static let shared = DataManagerService()
    
    // YALNIZCA KULLANICININ VERDİĞİ ORİJİNAL ADRESLER
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
        let cache = URLCache(memoryCapacity: 100 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024, diskPath: "mimusinema_cache")
        URLCache.shared = cache
        
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
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 60
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Eğer HTTP 200 geldiyse parse et
            if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
               let content = String(data: data, encoding: .utf8), content.contains("#EXT") {
                let parsed = await Task.detached(priority: .userInitiated) {
                    M3UParserService.shared.parse(m3uContent: content, isSeriesOverride: false)
                }.value
                
                if !parsed.isEmpty {
                    self.allMoviesPool = parsed
                    self.currentMoviePage = 0
                    self.visibleMovies = []
                    self.loadMoreMovies()
                    self.saveMoviesToDisk(items: parsed)
                }
            } else if let content = String(data: data, encoding: .utf8), content.contains("#EXT") {
                let parsed = await Task.detached(priority: .userInitiated) {
                    M3UParserService.shared.parse(m3uContent: content, isSeriesOverride: false)
                }.value
                if !parsed.isEmpty {
                    self.allMoviesPool = parsed
                    self.currentMoviePage = 0
                    self.visibleMovies = []
                    self.loadMoreMovies()
                    self.saveMoviesToDisk(items: parsed)
                }
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
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 60
            
            let (data, _) = try await URLSession.shared.data(for: request)
            if let content = String(data: data, encoding: .utf8), content.contains("#EXT") {
                let parsedGroups = await Task.detached(priority: .userInitiated) {
                    let items = M3UParserService.shared.parse(m3uContent: content, isSeriesOverride: true)
                    return M3UParserService.shared.groupSeries(items: items)
                }.value
                
                if !parsedGroups.isEmpty {
                    self.allSeriesPool = parsedGroups
                    self.currentSeriesPage = 0
                    self.visibleSeries = []
                    self.loadMoreSeries()
                    self.saveSeriesToDisk(groups: parsedGroups)
                }
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
    
    private static var moviesCacheFile: URL {
        let docs = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("cached_movies.json")
    }
    
    private static var seriesCacheFile: URL {
        let docs = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("cached_series.json")
    }
    
    private func saveMoviesToDisk(items: [MediaItem]) {
        let targetUrl = Self.moviesCacheFile
        Task.detached(priority: .background) {
            if let data = try? JSONEncoder().encode(items) {
                try? data.write(to: targetUrl)
            }
        }
    }
    
    private func saveSeriesToDisk(groups: [SeriesGroup]) {
        let targetUrl = Self.seriesCacheFile
        Task.detached(priority: .background) {
            let allEps = groups.flatMap { $0.episodes }
            if let data = try? JSONEncoder().encode(allEps) {
                try? data.write(to: targetUrl)
            }
        }
    }
    
    private func loadLocalCache() {
        let mFile = Self.moviesCacheFile
        let sFile = Self.seriesCacheFile
        
        if let data = try? Data(contentsOf: mFile),
           let cached = try? JSONDecoder().decode([MediaItem].self, from: data),
           !cached.isEmpty {
            self.allMoviesPool = cached
            self.loadMoreMovies()
        }
        
        if let sData = try? Data(contentsOf: sFile),
           let cachedEps = try? JSONDecoder().decode([MediaItem].self, from: sData),
           !cachedEps.isEmpty {
            let grouped = M3UParserService.shared.groupSeries(items: cachedEps)
            self.allSeriesPool = grouped
            self.loadMoreSeries()
        }
    }
}
