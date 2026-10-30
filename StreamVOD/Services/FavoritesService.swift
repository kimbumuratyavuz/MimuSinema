import Foundation
import Combine

@MainActor
public final class FavoritesService: ObservableObject {
    public static let shared = FavoritesService()
    
    @Published public var favoriteItems: [MediaItem] = []
    
    private let storageKey = "streamvod_favorites_list"
    
    private init() {
        loadFavorites()
    }
    
    // MARK: - Film ve Bölüm Favori Kontrolleri
    public func isFavorite(media: MediaItem) -> Bool {
        favoriteItems.contains(where: { $0.id == media.id })
    }
    
    public func toggleFavorite(media: MediaItem) {
        if let index = favoriteItems.firstIndex(where: { $0.id == media.id }) {
            favoriteItems.remove(at: index)
        } else {
            favoriteItems.append(media)
        }
        saveFavorites()
    }
    
    // MARK: - Dizi (SeriesGroup) Favori Kontrolleri
    public func isSeriesFavorite(seriesName: String) -> Bool {
        favoriteItems.contains(where: { $0.isSeries && ($0.seriesName == seriesName || $0.cleanTitle == seriesName) })
    }
    
    public func toggleSeriesFavorite(series: SeriesGroup) {
        if isSeriesFavorite(seriesName: series.name) {
            favoriteItems.removeAll(where: { $0.isSeries && ($0.seriesName == series.name || $0.cleanTitle == series.name) })
        } else {
            // Diziyi temsilen ilk bölümü veya jenerik dizi nesnesini favorilere ekle
            if var firstEp = series.episodes.first {
                firstEp.title = series.name
                firstEp.cleanTitle = series.name
                firstEp.seriesName = series.name
                firstEp.logoUrl = series.logoUrl ?? firstEp.logoUrl
                firstEp.isSeries = true
                favoriteItems.append(firstEp)
            } else {
                let dummy = MediaItem(
                    title: series.name,
                    logoUrl: series.logoUrl,
                    groupTitle: series.name,
                    streamUrl: URL(string: "https://mimusinema.local/series")!,
                    isSeriesOverride: true
                )
                favoriteItems.append(dummy)
            }
        }
        saveFavorites()
    }
    
    public func removeFavorite(media: MediaItem) {
        favoriteItems.removeAll(where: { $0.id == media.id })
        saveFavorites()
    }
    
    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favoriteItems) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let items = try? JSONDecoder().decode([MediaItem].self, from: data) {
            self.favoriteItems = items
        }
    }
}
