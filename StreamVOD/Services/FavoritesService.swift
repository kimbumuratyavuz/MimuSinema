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
