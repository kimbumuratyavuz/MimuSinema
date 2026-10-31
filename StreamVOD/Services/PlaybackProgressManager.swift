import Foundation

public final class PlaybackProgressManager {
    public static let shared = PlaybackProgressManager()
    
    private let storageKey = "saved_media_playback_progress_map"
    private var progressCache: [String: Double] = [:]
    private let lock = NSLock()
    
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
        lock.lock()
        defer { lock.unlock() }
        let k = cacheKey(for: media)
        if let val = progressCache[k], val > 8.0 {
            return val
        }
        return nil
    }
    
    public func saveProgress(for media: MediaItem, currentTime: Double, totalDuration: Double) {
        guard currentTime > 5.0 else { return }
        let k = cacheKey(for: media)
        
        lock.lock()
        // Eğer video son 15 saniyeye geldiyse ya da bittiyse sıfırla
        if totalDuration > 30.0 && currentTime >= (totalDuration - 15.0) {
            progressCache.removeValue(forKey: k)
        } else {
            progressCache[k] = currentTime
        }
        let snapshot = progressCache
        lock.unlock()
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            self.persist(snapshot)
        }
    }
    
    public func clearProgress(for media: MediaItem) {
        let k = cacheKey(for: media)
        lock.lock()
        progressCache.removeValue(forKey: k)
        let snapshot = progressCache
        lock.unlock()
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            self.persist(snapshot)
        }
    }
    
    private func persist(_ snapshot: [String: Double]) {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
