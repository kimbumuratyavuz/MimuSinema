import Foundation

public final class PlaybackProgressManager {
    public static let shared = PlaybackProgressManager()
    
    private let storageKey = "saved_media_playback_progress_map"
    private var progressCache: [String: Double] = [:]
    private let queue = DispatchQueue(label: "com.mimusinema.playbackprogress", qos: .utility)
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let dict = try? JSONDecoder().decode([String: Double].self, from: data) {
            self.progressCache = dict
        }
    }
    
    private func cacheKey(for media: MediaItem) -> String {
        if let rel = media.localRelativePath, !rel.isEmpty {
            return URL(fileURLWithPath: rel).lastPathComponent
        }
        return media.cleanTitle.isEmpty ? media.title : media.cleanTitle
    }
    
    public func getSavedProgress(for media: MediaItem) -> Double? {
        let k = cacheKey(for: media)
        if let val = progressCache[k], val > 8.0 {
            return val
        }
        return nil
    }
    
    public func saveProgress(for media: MediaItem, currentTime: Double, totalDuration: Double) {
        guard currentTime > 5.0 else { return }
        let k = cacheKey(for: media)
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Eğer video son 15 saniyeye geldiyse ya da bittiyse sıfırla
            if totalDuration > 30.0 && currentTime >= (totalDuration - 15.0) {
                self.progressCache.removeValue(forKey: k)
            } else {
                self.progressCache[k] = currentTime
            }
            self.persist()
        }
    }
    
    public func clearProgress(for media: MediaItem) {
        let k = cacheKey(for: media)
        queue.async { [weak self] in
            guard let self = self else { return }
            self.progressCache.removeValue(forKey: k)
            self.persist()
        }
    }
    
    private func persist() {
        if let data = try? JSONEncoder().encode(progressCache) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
