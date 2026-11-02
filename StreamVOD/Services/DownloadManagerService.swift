import Foundation
import Combine
import AVFoundation
import UIKit

@MainActor
public final class DownloadManagerService: NSObject, ObservableObject {
    public static let shared = DownloadManagerService()
    
    @Published public var queue: [DownloadTaskItem] = []
    @Published public var isDownloading: Bool = false
    @Published public var currentProcessingId: UUID? = nil
    
    // Cihazda kalıcı olarak indirilmiş içerikler (Kuyruktan bağımsızdır, kuyruk silinse bile korunur)
    @Published public var downloadedMovies: [DownloadTaskItem] = []
    @Published public var downloadedSeriesGrouped: [String: [DownloadTaskItem]] = [:]
    
    public var totalDownloadedCount: Int {
        downloadedMovies.count + downloadedSeriesGrouped.values.reduce(0, { $0 + $1.count })
    }
    
    private var activeDownloadTask: URLSessionDownloadTask?
    private var currentDownloadTask: Task<Void, Never>? = nil
    private var isCancelled: Bool = false
    private var isPausedCurrent: Bool = false
    private var isStoppedCurrent: Bool = false
    private var urlSession: URLSession!
    
    // Yüksek hızlı eşzamanlı segment indirici URLSession (24 bağlantı kapasitesi)
    private let downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 3600
        config.httpMaximumConnectionsPerHost = 24
        config.httpShouldUsePipelining = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    
    // Arka plan görevi kimliği
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    
    // Yüksek hızlı eşzamanlı kanal sayısı (12 kanal ile 3-5 kat daha hızlı)
    private let concurrentWorkers = 12
    
    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600
        config.httpMaximumConnectionsPerHost = 12
        self.urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: .main)
        loadSavedState()
    }
    
    // MARK: - Klasör Yolları
    public var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    public var moviesDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("Movies", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    public var seriesDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("Series", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    public func seriesFolderUrl(for seriesName: String) -> URL {
        let folderName = sanitizeFileName(seriesName)
        let dir = seriesDirectory.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    public func destinationUrl(for media: MediaItem) -> URL {
        let sanitizedTitle = sanitizeFileName(media.cleanTitle.isEmpty ? media.title : media.cleanTitle)
        let isHls = media.streamUrl.absoluteString.lowercased().contains("m3u8")
        let ext = isHls ? "ts" : "mp4"
        
        if media.isSeries {
            let sFolder = seriesFolderUrl(for: media.seriesName ?? "Diziler")
            return sFolder.appendingPathComponent("\(sanitizedTitle).\(ext)")
        } else {
            return moviesDirectory.appendingPathComponent("\(sanitizedTitle).\(ext)")
        }
    }
    
    /// Dinamik yerel dosya çözücü (Dosyanın gerçek yerini bulur ve doğrular)
    public func resolvedLocalUrl(for media: MediaItem) -> URL? {
        // 1. Doğrudan localRelativePath kontrolü (Tam yol veya göreceli yol olabilir)
        if let rel = media.localRelativePath, !rel.isEmpty {
            let direct = URL(fileURLWithPath: rel)
            if FileManager.default.fileExists(atPath: direct.path) {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: direct.path),
                   let size = attrs[.size] as? Int64, size > 1024 * 1024 {
                    return direct
                }
            }
            
            let docAppended = documentsDirectory.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: docAppended.path) {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: docAppended.path),
                   let size = attrs[.size] as? Int64, size > 1024 * 1024 {
                    return docAppended
                }
            }
            
            let inMovies = moviesDirectory.appendingPathComponent(URL(fileURLWithPath: rel).lastPathComponent)
            if FileManager.default.fileExists(atPath: inMovies.path) {
                return inMovies
            }
            
            if let sName = media.seriesName {
                let inSeries = seriesFolderUrl(for: sName).appendingPathComponent(URL(fileURLWithPath: rel).lastPathComponent)
                if FileManager.default.fileExists(atPath: inSeries.path) {
                    return inSeries
                }
            }
        }
        
        // 2. İndirme kuyruğundaki kayıtlı görevlerden yerel dosya yolunu ara
        if let task = queue.first(where: {
            $0.status == .completed && (
                $0.mediaItem.streamUrl == media.streamUrl ||
                $0.mediaItem.cleanTitle == media.cleanTitle ||
                $0.mediaItem.id == media.id
            )
        }), let savedPath = task.localFilePath {
            let savedUrl = URL(fileURLWithPath: savedPath)
            if FileManager.default.fileExists(atPath: savedUrl.path) {
                return savedUrl
            }
            
            let fileName = savedUrl.lastPathComponent
            let movieCandidate = moviesDirectory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: movieCandidate.path) {
                return movieCandidate
            }
            
            if let sName = media.seriesName ?? task.mediaItem.seriesName {
                let seriesCandidate = seriesFolderUrl(for: sName).appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: seriesCandidate.path) {
                    return seriesCandidate
                }
            }
        }
        
        // 3. Varsayılan hedef dosya yolu kontrolü
        let target = destinationUrl(for: media)
        if FileManager.default.fileExists(atPath: target.path) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: target.path),
               let size = attrs[.size] as? Int64, size > 1024 * 1024 {
                return target
            }
        }
        
        // Alternatif format kontrolü (.ts yerine .mp4 veya tersi)
        let altExt = target.pathExtension.lowercased() == "ts" ? "mp4" : "ts"
        let altTarget = target.deletingPathExtension().appendingPathExtension(altExt)
        if FileManager.default.fileExists(atPath: altTarget.path) {
            return altTarget
        }
        
        // 4. Klasörlerde başlık bazlı tarama
        let sanitized = sanitizeFileName(media.cleanTitle.isEmpty ? media.title : media.cleanTitle)
        for ext in ["ts", "mp4", "m4v", "mov"] {
            let mCandidate = moviesDirectory.appendingPathComponent("\(sanitized).\(ext)")
            if FileManager.default.fileExists(atPath: mCandidate.path) {
                return mCandidate
            }
            if let sName = media.seriesName {
                let sCandidate = seriesFolderUrl(for: sName).appendingPathComponent("\(sanitized).\(ext)")
                if FileManager.default.fileExists(atPath: sCandidate.path) {
                    return sCandidate
                }
            }
        }
        
        return nil
    }
    
    /// TS dosyası için anında standart byte-range M3U8 index dosyası oluşturur / doğrular
    @discardableResult
    public func ensureM3U8Exists(for tsUrl: URL) -> URL {
        return LocalStreamServer.generateM3U8Synchronously(for: tsUrl)
    }
    
    /// Oynatıcı için yerel akış URL'si (TS dosyalarını yerel HTTP HLS sunucusu, MP4 dosyalarını doğrudan dosya URL'si olarak sunar)
    public func playbackUrl(for media: MediaItem) -> URL? {
        guard let localUrl = resolvedLocalUrl(for: media) else { return nil }
        let ext = localUrl.pathExtension.lowercased()
        if ext == "ts" {
            LocalStreamServer.shared.start()
            let m3u8Url = ensureM3U8Exists(for: localUrl)
            return LocalStreamServer.shared.url(for: m3u8Url)
        } else {
            return localUrl
        }
    }
    
    private func sanitizeFileName(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }
    
    // MARK: - Durum Kontrolleri
    public func isItemQueued(media: MediaItem) -> Bool {
        queue.contains(where: { $0.mediaItem.streamUrl == media.streamUrl })
    }
    
    public func isItemCompleted(media: MediaItem) -> Bool {
        if resolvedLocalUrl(for: media) != nil {
            return true
        }
        return false
    }
    
    // MARK: - Kuyruk Yönetimi
    public func addToQueue(media: MediaItem) {
        if isItemQueued(media: media) { return }
        let task = DownloadTaskItem(mediaItem: media)
        queue.append(task)
        saveState()
    }
    
    public func toggleSelection(id: UUID) {
        if let idx = queue.firstIndex(where: { $0.id == id }) {
            queue[idx].isSelected.toggle()
        }
    }
    
    public func selectAll(_ select: Bool) {
        for i in 0..<queue.count {
            queue[i].isSelected = select
        }
    }
    
    // MARK: - Kuyruk ve Dosya Yönetimi
    
    /// Yalnızca indirme kuyruğundan görevi kaldırır. Cihazdaki video dosyasını ASLA silmez!
    public func removeFromQueue(id: UUID) {
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        let task = queue[idx]
        
        if task.status == .downloading {
            isCancelled = true
            activeDownloadTask?.cancel()
            isDownloading = false
            currentProcessingId = nil
            stopBackgroundProtection()
        }
        
        queue.remove(at: idx)
        saveState()
        refreshDownloadedLibrary()
    }
    
    /// Cihaz hafızasındaki indirilmiş dosyayı kalıcı olarak siler
    public func deleteDownloadedFile(item: DownloadTaskItem) {
        if let localUrl = resolvedLocalUrl(for: item.mediaItem) {
            try? FileManager.default.removeItem(at: localUrl)
            let m3u8 = localUrl.deletingPathExtension().appendingPathExtension("m3u8")
            try? FileManager.default.removeItem(at: m3u8)
        } else if let savedPath = item.localFilePath {
            let u = URL(fileURLWithPath: savedPath)
            try? FileManager.default.removeItem(at: u)
            let m3u8 = u.deletingPathExtension().appendingPathExtension("m3u8")
            try? FileManager.default.removeItem(at: m3u8)
        }
        
        // Eğer kuyrukta varsa oradan da kaldır
        if let idx = queue.firstIndex(where: { $0.id == item.id }) {
            queue.remove(at: idx)
            saveState()
        }
        
        let isSeries = item.mediaItem.isSeries
        if isSeries, let seriesName = item.mediaItem.seriesName {
            cleanupEmptySeriesFolder(seriesName: seriesName)
        }
        
        refreshDownloadedLibrary()
    }
    
    public func deleteDownloadedItem(id: UUID) {
        if let task = queue.first(where: { $0.id == id }) {
            deleteDownloadedFile(item: task)
        } else if let movie = downloadedMovies.first(where: { $0.id == id }) {
            deleteDownloadedFile(item: movie)
        } else {
            for (_, episodes) in downloadedSeriesGrouped {
                if let ep = episodes.first(where: { $0.id == id }) {
                    deleteDownloadedFile(item: ep)
                    return
                }
            }
        }
    }
    
    public func deleteEntireSeries(seriesName: String) {
        let tasksToDelete = queue.filter { $0.mediaItem.isSeries && ($0.mediaItem.seriesName == seriesName) }
        
        for task in tasksToDelete {
            if let localUrl = resolvedLocalUrl(for: task.mediaItem) {
                try? FileManager.default.removeItem(at: localUrl)
                let m3u8 = localUrl.deletingPathExtension().appendingPathExtension("m3u8")
                try? FileManager.default.removeItem(at: m3u8)
            }
            if let idx = queue.firstIndex(where: { $0.id == task.id }) {
                queue.remove(at: idx)
            }
        }
        
        let folder = seriesFolderUrl(for: seriesName)
        if FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.removeItem(at: folder)
        }
        
        saveState()
        refreshDownloadedLibrary()
    }
    
    private func cleanupEmptySeriesFolder(seriesName: String) {
        let remainingForThisSeries = queue.filter {
            $0.mediaItem.isSeries &&
            ($0.mediaItem.seriesName == seriesName) &&
            $0.status == .completed
        }
        
        if remainingForThisSeries.isEmpty {
            let folder = seriesFolderUrl(for: seriesName)
            if FileManager.default.fileExists(atPath: folder.path) {
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }
    
    // MARK: - İndirme İşlemleri & Arka Plan Koruma
    
    public func downloadSingle(id: UUID) {
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[idx].isSelected = true
        startSelectedDownloads()
    }
    
    public func startSelectedDownloads() {
        guard !isDownloading else { return }
        startBackgroundProtection()
        processNextInQueue()
    }
    
    // MARK: - Duraklatma, Durdurma & Devam Ettirme
    
    public func pauseDownload(id: UUID) {
        if currentProcessingId == id {
            isPausedCurrent = true
            currentDownloadTask?.cancel()
            activeDownloadTask?.cancel()
            isDownloading = false
            currentProcessingId = nil
            stopBackgroundProtection()
        }
        if let idx = queue.firstIndex(where: { $0.id == id }) {
            queue[idx].status = .paused
            queue[idx].speedText = "Duraklatıldı"
            saveState()
        }
    }
    
    public func resumeDownload(id: UUID) {
        if let idx = queue.firstIndex(where: { $0.id == id }) {
            queue[idx].status = .queued
            queue[idx].isSelected = true
            queue[idx].errorMessage = nil
            queue[idx].speedText = "Sıraya alındı"
            saveState()
        }
        startSelectedDownloads()
    }
    
    public func stopDownload(id: UUID) {
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        let task = queue[idx]
        let destination = destinationUrl(for: task.mediaItem)
        let tempDestination = destination.deletingLastPathComponent().appendingPathComponent("temp_\(destination.lastPathComponent)")
        let metaUrl = destination.deletingLastPathComponent().appendingPathComponent("meta_\(destination.lastPathComponent).json")
        
        if currentProcessingId == id {
            isStoppedCurrent = true
            currentDownloadTask?.cancel()
            activeDownloadTask?.cancel()
            isDownloading = false
            currentProcessingId = nil
            stopBackgroundProtection()
        }
        
        // Geçici dosyaları temizle ve ilerlemeyi sıfırla
        try? FileManager.default.removeItem(at: tempDestination)
        try? FileManager.default.removeItem(at: metaUrl)
        
        queue[idx].status = .stopped
        queue[idx].progress = 0.0
        queue[idx].speedText = "Durduruldu"
        queue[idx].errorMessage = nil
        saveState()
    }
    
    public func pauseAllDownloads() {
        isPausedCurrent = true
        currentDownloadTask?.cancel()
        activeDownloadTask?.cancel()
        isDownloading = false
        currentProcessingId = nil
        stopBackgroundProtection()
        
        for i in 0..<queue.count {
            if queue[i].status == .downloading || queue[i].status == .queued {
                queue[i].status = .paused
                queue[i].speedText = "Duraklatıldı"
            }
        }
        saveState()
    }
    
    public func stopAllDownloads() {
        isStoppedCurrent = true
        currentDownloadTask?.cancel()
        activeDownloadTask?.cancel()
        isDownloading = false
        currentProcessingId = nil
        stopBackgroundProtection()
        
        for i in 0..<queue.count {
            if queue[i].status == .downloading || queue[i].status == .paused || queue[i].status == .queued {
                let dest = destinationUrl(for: queue[i].mediaItem)
                let temp = dest.deletingLastPathComponent().appendingPathComponent("temp_\(dest.lastPathComponent)")
                let meta = dest.deletingLastPathComponent().appendingPathComponent("meta_\(dest.lastPathComponent).json")
                try? FileManager.default.removeItem(at: temp)
                try? FileManager.default.removeItem(at: meta)
                
                queue[i].status = .stopped
                queue[i].progress = 0.0
                queue[i].speedText = "Durduruldu"
            }
        }
        saveState()
    }
    
    private func startBackgroundProtection() {
        UIApplication.shared.isIdleTimerDisabled = true
        if backgroundTaskId == .invalid {
            backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "MimuSinemaDownloader") { [weak self] in
                self?.stopBackgroundProtection()
            }
        }
    }
    
    private func stopBackgroundProtection() {
        UIApplication.shared.isIdleTimerDisabled = false
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
    }
    
    private func processNextInQueue() {
        guard let nextTaskIndex = queue.firstIndex(where: {
            $0.isSelected && ($0.status == .queued || $0.status == .failed || $0.status == .paused || $0.status == .stopped)
        }) else {
            isDownloading = false
            currentProcessingId = nil
            stopBackgroundProtection()
            return
        }
        
        isDownloading = true
        isCancelled = false
        isPausedCurrent = false
        isStoppedCurrent = false
        currentProcessingId = queue[nextTaskIndex].id
        queue[nextTaskIndex].status = .downloading
        queue[nextTaskIndex].errorMessage = nil
        if queue[nextTaskIndex].progress <= 0.01 {
            queue[nextTaskIndex].progress = 0.02
        }
        queue[nextTaskIndex].speedText = "Yüksek hızla bağlanıyor..."
        
        let media = queue[nextTaskIndex].mediaItem
        let destination = destinationUrl(for: media)
        
        var request = URLRequest(url: media.streamUrl)
        let ref = (media.httpReferrer?.isEmpty == false) ? media.httpReferrer! : "https://twitter.com/"
        let ua = (media.httpUserAgent?.isEmpty == false) ? media.httpUserAgent! : "googleusercontent"
        request.setValue(ref, forHTTPHeaderField: "Referer")
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        
        if media.streamUrl.absoluteString.lowercased().contains("m3u8") {
            downloadM3U8Safely(media: media, destination: destination, taskIndex: nextTaskIndex)
        } else {
            downloadDirectFile(request: request, destination: destination, taskIndex: nextTaskIndex)
        }
    }
    
    private func downloadDirectFile(request: URLRequest, destination: URL, taskIndex: Int) {
        let task = downloadSession.downloadTask(with: request) { [weak self] tempUrl, response, error in
            Task { @MainActor in
                guard let self = self else { return }
                if self.isPausedCurrent {
                    if taskIndex < self.queue.count {
                        self.queue[taskIndex].status = .paused
                        self.queue[taskIndex].speedText = "Duraklatıldı"
                    }
                    self.isDownloading = false
                    self.currentProcessingId = nil
                    self.stopBackgroundProtection()
                    return
                }
                if self.isStoppedCurrent {
                    if taskIndex < self.queue.count {
                        self.queue[taskIndex].status = .stopped
                        self.queue[taskIndex].progress = 0.0
                        self.queue[taskIndex].speedText = "Durduruldu"
                    }
                    self.isDownloading = false
                    self.currentProcessingId = nil
                    self.stopBackgroundProtection()
                    return
                }
                if let error = error {
                    self.markFailed(taskIndex: taskIndex, error: error.localizedDescription)
                    self.processNextInQueue()
                    return
                }
                guard let tempUrl = tempUrl else {
                    self.markFailed(taskIndex: taskIndex, error: "Dosya alınamadı.")
                    self.processNextInQueue()
                    return
                }
                
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: tempUrl, to: destination)
                    self.markCompleted(taskIndex: taskIndex, localUrl: destination)
                } catch {
                    self.markFailed(taskIndex: taskIndex, error: error.localizedDescription)
                }
                self.processNextInQueue()
            }
        }
        self.activeDownloadTask = task
        task.resume()
    }
    
    // MARK: - Yüksek Hızlı, Kesintisiz Pipeline HLS İndirici
    private func downloadM3U8Safely(media: MediaItem, destination: URL, taskIndex: Int) {
        let session = self.downloadSession
        let workers = self.concurrentWorkers
        
        self.currentDownloadTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let ref = (media.httpReferrer?.isEmpty == false) ? media.httpReferrer! : "https://twitter.com/"
                let ua = (media.httpUserAgent?.isEmpty == false) ? media.httpUserAgent! : "googleusercontent"
                
                var req = URLRequest(url: media.streamUrl)
                req.setValue(ref, forHTTPHeaderField: "Referer")
                req.setValue(ua, forHTTPHeaderField: "User-Agent")
                
                let (data, response) = try await session.data(for: req)
                guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                      let content = String(data: data, encoding: .utf8) else {
                    throw NSError(domain: "MimuSinema", code: -1, userInfo: [NSLocalizedDescriptionKey: "Playlist indirilemedi (HTTP Hata)."])
                }
                
                let lines = content.components(separatedBy: .newlines)
                var segmentUrls: [URL] = []
                var segmentDurations: [Double] = []
                var currentExtinfDuration: Double = 6.0
                let baseUrl = media.streamUrl.deletingLastPathComponent()
                
                var masterPlaylistUrl: URL? = nil
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { continue }
                    if trimmed.hasPrefix("#EXTINF:") {
                        let durStr = trimmed.replacingOccurrences(of: "#EXTINF:", with: "").components(separatedBy: ",")[0]
                        currentExtinfDuration = Double(durStr) ?? 6.0
                    } else if !trimmed.hasPrefix("#") {
                        if trimmed.contains(".m3u8") {
                            masterPlaylistUrl = URL(string: trimmed, relativeTo: baseUrl)?.absoluteURL
                            break
                        } else {
                            if let sUrl = URL(string: trimmed, relativeTo: baseUrl)?.absoluteURL {
                                segmentUrls.append(sUrl)
                                segmentDurations.append(currentExtinfDuration)
                            }
                        }
                    }
                }
                
                if let master = masterPlaylistUrl {
                    segmentUrls.removeAll()
                    segmentDurations.removeAll()
                    currentExtinfDuration = 6.0
                    
                    var subReq = URLRequest(url: master)
                    subReq.setValue(ref, forHTTPHeaderField: "Referer")
                    subReq.setValue(ua, forHTTPHeaderField: "User-Agent")
                    let (subData, subRes) = try await session.data(for: subReq)
                    if let sRes = subRes as? HTTPURLResponse, sRes.statusCode == 200,
                       let subContent = String(data: subData, encoding: .utf8) {
                        let subLines = subContent.components(separatedBy: .newlines)
                        let subBase = master.deletingLastPathComponent()
                        for sLine in subLines {
                            let tr = sLine.trimmingCharacters(in: .whitespacesAndNewlines)
                            if tr.hasPrefix("#EXTINF:") {
                                let durStr = tr.replacingOccurrences(of: "#EXTINF:", with: "").components(separatedBy: ",")[0]
                                currentExtinfDuration = Double(durStr) ?? 6.0
                            } else if !tr.isEmpty && !tr.hasPrefix("#") {
                                if let seg = URL(string: tr, relativeTo: subBase)?.absoluteURL {
                                    segmentUrls.append(seg)
                                    segmentDurations.append(currentExtinfDuration)
                                }
                            }
                        }
                    }
                }
                
                guard !segmentUrls.isEmpty else {
                    throw NSError(domain: "MimuSinema", code: -2, userInfo: [NSLocalizedDescriptionKey: "Video parçaları bulunamadı."])
                }
                
                let tempDestination = destination.deletingLastPathComponent().appendingPathComponent("temp_\(destination.lastPathComponent)")
                let metaUrl = destination.deletingLastPathComponent().appendingPathComponent("meta_\(destination.lastPathComponent).json")
                
                var completedSegments = 0
                var byteRangeEntries: [(duration: Double, length: Int, offset: Int)] = []
                var currentByteOffset = 0
                
                // Kaldığı yerden devam kontrolü (Pause -> Resume)
                if FileManager.default.fileExists(atPath: tempDestination.path),
                   FileManager.default.fileExists(atPath: metaUrl.path),
                   let metaData = try? Data(contentsOf: metaUrl),
                   let meta = try? JSONDecoder().decode(DownloadProgressMeta.self, from: metaData),
                   meta.completedSegments > 0 && meta.completedSegments < segmentUrls.count {
                    completedSegments = meta.completedSegments
                    byteRangeEntries = meta.byteRangeEntries.map { ($0.duration, $0.length, $0.offset) }
                    currentByteOffset = (try? FileManager.default.attributesOfItem(atPath: tempDestination.path)[.size] as? Int) ?? 0
                } else {
                    if FileManager.default.fileExists(atPath: tempDestination.path) {
                        try? FileManager.default.removeItem(at: tempDestination)
                    }
                    try? FileManager.default.removeItem(at: metaUrl)
                    FileManager.default.createFile(atPath: tempDestination.path, contents: nil)
                }
                
                let fileHandle = try FileHandle(forWritingTo: tempDestination)
                fileHandle.seekToEndOfFile()
                
                let totalSegments = segmentUrls.count
                var nextSegmentToFetch = completedSegments
                var nextSegmentToWrite = completedSegments
                var buffer: [Int: Data] = [:]
                
                try await withThrowingTaskGroup(of: (Int, Data?).self) { group in
                    // İlk eşzamanlı kanalları başlat
                    let initialBatch = min(workers, totalSegments - nextSegmentToFetch)
                    for _ in 0..<initialBatch {
                        let segIdx = nextSegmentToFetch
                        nextSegmentToFetch += 1
                        let segUrl = segmentUrls[segIdx]
                        group.addTask {
                            return await Self.fetchSingleSegmentWithRetry(
                                session: session,
                                url: segUrl,
                                referrer: ref,
                                userAgent: ua,
                                index: segIdx
                            )
                        }
                    }
                    
                    // Her parça indiğinde yaz ve yeni kanal başlat
                    for try await (idx, segDataOpt) in group {
                        if Task.isCancelled {
                            group.cancelAll()
                            break
                        }
                        
                        guard let data = segDataOpt, data.count > 128 else {
                            throw NSError(domain: "MimuSinema", code: -4, userInfo: [NSLocalizedDescriptionKey: "Parça \(idx+1) indirilemedi."])
                        }
                        
                        buffer[idx] = data
                        
                        // Sırası gelen ardışık parçaları sırayla diske yaz
                        while let nextData = buffer[nextSegmentToWrite] {
                            fileHandle.write(nextData)
                            buffer.removeValue(forKey: nextSegmentToWrite)
                            let dur = nextSegmentToWrite < segmentDurations.count ? segmentDurations[nextSegmentToWrite] : 6.0
                            byteRangeEntries.append((duration: dur, length: nextData.count, offset: currentByteOffset))
                            currentByteOffset += nextData.count
                            nextSegmentToWrite += 1
                            completedSegments += 1
                        }
                        
                        // İlerlemeyi güncelle
                        let progress = Double(completedSegments) / Double(totalSegments)
                        let percent = Int(progress * 100)
                        await MainActor.run {
                            guard let self = self else { return }
                            if taskIndex < self.queue.count {
                                self.queue[taskIndex].progress = progress
                                self.queue[taskIndex].speedText = "% \(percent) (\(completedSegments)/\(totalSegments) parça - Yüksek Hız)"
                            }
                        }
                        
                        // Daha indirilecek parça varsa anında yeni kanal aç (12 kanal daima tam dolu kalır)
                        if nextSegmentToFetch < totalSegments && !Task.isCancelled {
                            let nextIdx = nextSegmentToFetch
                            nextSegmentToFetch += 1
                            let nextUrl = segmentUrls[nextIdx]
                            group.addTask {
                                return await Self.fetchSingleSegmentWithRetry(
                                    session: session,
                                    url: nextUrl,
                                    referrer: ref,
                                    userAgent: ua,
                                    index: nextIdx
                                )
                            }
                        }
                    }
                }
                
                try? fileHandle.close()
                
                let (isPaused, isStopped) = await MainActor.run { () -> (Bool, Bool) in
                    guard let self = self else { return (false, false) }
                    return (self.isPausedCurrent, self.isStoppedCurrent)
                }
                
                // Duraklatıldıysa metadata kaydet ve dur
                if isPaused {
                    let metaEntries = byteRangeEntries.map { ByteRangeMeta(duration: $0.duration, length: $0.length, offset: $0.offset) }
                    let meta = DownloadProgressMeta(completedSegments: completedSegments, byteRangeEntries: metaEntries)
                    if let mData = try? JSONEncoder().encode(meta) {
                        try? mData.write(to: metaUrl)
                    }
                    await MainActor.run {
                        guard let self = self else { return }
                        if taskIndex < self.queue.count {
                            self.queue[taskIndex].status = .paused
                            self.queue[taskIndex].speedText = "Duraklatıldı (\(completedSegments)/\(totalSegments) parça)"
                        }
                        self.isDownloading = false
                        self.currentProcessingId = nil
                        self.stopBackgroundProtection()
                    }
                    return
                }
                
                // Durdurulduysa dosyaları temizle ve dur
                if isStopped {
                    try? FileManager.default.removeItem(at: tempDestination)
                    try? FileManager.default.removeItem(at: metaUrl)
                    await MainActor.run {
                        guard let self = self else { return }
                        if taskIndex < self.queue.count {
                            self.queue[taskIndex].status = .stopped
                            self.queue[taskIndex].progress = 0.0
                            self.queue[taskIndex].speedText = "Durduruldu"
                        }
                        self.isDownloading = false
                        self.currentProcessingId = nil
                        self.stopBackgroundProtection()
                    }
                    return
                }
                
                if Task.isCancelled {
                    return
                }
                
                // İndirilen dosya boyutu kontrolü (En az 1MB olmalı)
                let attrs = try? FileManager.default.attributesOfItem(atPath: tempDestination.path)
                let finalSize = (attrs?[.size] as? Int64) ?? 0
                
                guard finalSize > 1024 * 1024 else {
                    try? FileManager.default.removeItem(at: tempDestination)
                    try? FileManager.default.removeItem(at: metaUrl)
                    throw NSError(domain: "MimuSinema", code: -3, userInfo: [NSLocalizedDescriptionKey: "Video verisi eksik indirildi."])
                }
                
                if FileManager.default.fileExists(atPath: destination.path) {
                    try? FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempDestination, to: destination)
                try? FileManager.default.removeItem(at: metaUrl)
                
                // HLS için standart .m3u8 index dosyasını oluştur
                let m3u8Destination = destination.deletingPathExtension().appendingPathExtension("m3u8")
                let encodedFileName = destination.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? destination.lastPathComponent
                var m3u8Content = "#EXTM3U\n#EXT-X-VERSION:4\n#EXT-X-TARGETDURATION:15\n#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-PLAYLIST-TYPE:VOD\n"
                for entry in byteRangeEntries.sorted(by: { $0.offset < $1.offset }) {
                    m3u8Content += "#EXT-X-BYTERANGE:\(entry.length)@\(entry.offset)\n"
                    m3u8Content += String(format: "#EXTINF:%.3f,\n", entry.duration)
                    m3u8Content += "\(encodedFileName)\n"
                }
                m3u8Content += "#EXT-X-ENDLIST\n"
                try? m3u8Content.write(to: m3u8Destination, atomically: true, encoding: .utf8)
                
                await MainActor.run {
                    guard let self = self else { return }
                    self.markCompleted(taskIndex: taskIndex, localUrl: destination)
                    self.processNextInQueue()
                }
                
            } catch {
                await MainActor.run {
                    guard let self = self else { return }
                    if !self.isPausedCurrent && !self.isStoppedCurrent && !Task.isCancelled {
                        self.markFailed(taskIndex: taskIndex, error: error.localizedDescription)
                        self.processNextInQueue()
                    }
                }
            }
        }
    }
    
    private static func fetchSingleSegmentWithRetry(
        session: URLSession,
        url: URL,
        referrer: String?,
        userAgent: String?,
        index: Int
    ) async -> (Int, Data?) {
        for attempt in 1...3 {
            if Task.isCancelled { return (index, nil) }
            do {
                var sReq = URLRequest(url: url)
                sReq.timeoutInterval = 20
                if let ref = referrer { sReq.setValue(ref, forHTTPHeaderField: "Referer") }
                if let ua = userAgent { sReq.setValue(ua, forHTTPHeaderField: "User-Agent") }
                
                let (data, response) = try await session.data(for: sReq)
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200, data.count > 128 {
                    return (index, data)
                }
            } catch {
                if attempt == 3 { return (index, nil) }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        return (index, nil)
    }
    
    private func markCompleted(taskIndex: Int, localUrl: URL) {
        guard taskIndex < queue.count else { return }
        let completedTask = queue[taskIndex]
        if currentProcessingId == completedTask.id {
            currentProcessingId = nil
        }
        // İndirme bittiğinde kuyruktan otomatik kaldır (İndirilenler kütüphanesinde korunur)
        queue.remove(at: taskIndex)
        saveState()
        refreshDownloadedLibrary()
    }
    
    private func markFailed(taskIndex: Int, error: String) {
        guard taskIndex < queue.count else { return }
        queue[taskIndex].status = .failed
        queue[taskIndex].errorMessage = error
        queue[taskIndex].speedText = "Hata"
        saveState()
    }
    
    private func saveState() {
        if let data = try? JSONEncoder().encode(queue) {
            UserDefaults.standard.set(data, forKey: "saved_download_queue")
        }
    }
    
    private func loadSavedState() {
        if let data = UserDefaults.standard.data(forKey: "saved_download_queue"),
           let loaded = try? JSONDecoder().decode([DownloadTaskItem].self, from: data) {
            // Tamamlanmış olanları kuyruktan temizle, indirme esnasında kapananları duraklatıldı yap
            self.queue = loaded.filter { $0.status != .completed }.map {
                var item = $0
                if item.status == .downloading {
                    item.status = .paused
                    item.speedText = "Duraklatıldı"
                }
                return item
            }
        }
        refreshDownloadedLibrary()
    }
    
    // MARK: - Disk Dosya Taraması (Kuyruktan bağımsız İndirilenler Kütüphanesi)
    public func refreshDownloadedLibrary() {
        var movies: [DownloadTaskItem] = []
        var seriesMap: [String: [DownloadTaskItem]] = [:]
        
        // 1. Movies klasöründeki dosyaları tara
        if let movieFiles = try? FileManager.default.contentsOfDirectory(atPath: moviesDirectory.path) {
            for file in movieFiles {
                let ext = URL(fileURLWithPath: file).pathExtension.lowercased()
                guard ext == "ts" || ext == "mp4" || ext == "m4v" || ext == "mov" else { continue }
                let fullPath = moviesDirectory.appendingPathComponent(file)
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath.path),
                      let size = attrs[.size] as? Int64, size > 1024 * 1024 else { continue }
                
                let rawTitle = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
                if let existing = queue.first(where: {
                    $0.mediaItem.cleanTitle == rawTitle ||
                    $0.mediaItem.title == rawTitle ||
                    ($0.localFilePath != nil && URL(fileURLWithPath: $0.localFilePath!).lastPathComponent == file)
                }) {
                    var item = existing
                    item.status = .completed
                    item.localFilePath = fullPath.path
                    movies.append(item)
                } else {
                    let media = MediaItem(
                        title: rawTitle,
                        streamUrl: fullPath,
                        isSeriesOverride: false,
                        localRelativePath: "Movies/\(file)"
                    )
                    var task = DownloadTaskItem(mediaItem: media)
                    task.status = DownloadStatus.completed
                    task.progress = 1.0
                    task.localFilePath = fullPath.path
                    movies.append(task)
                }
            }
        }
        
        // 2. Series klasöründeki alt klasör ve bölümleri tara
        if let seriesFolders = try? FileManager.default.contentsOfDirectory(atPath: seriesDirectory.path) {
            for sFolder in seriesFolders {
                let folderUrl = seriesDirectory.appendingPathComponent(sFolder)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: folderUrl.path, isDirectory: &isDir), isDir.boolValue else { continue }
                
                if let episodeFiles = try? FileManager.default.contentsOfDirectory(atPath: folderUrl.path) {
                    var episodes: [DownloadTaskItem] = []
                    for eFile in episodeFiles {
                        let ext = URL(fileURLWithPath: eFile).pathExtension.lowercased()
                        guard ext == "ts" || ext == "mp4" || ext == "m4v" || ext == "mov" else { continue }
                        let fullPath = folderUrl.appendingPathComponent(eFile)
                        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath.path),
                              let size = attrs[.size] as? Int64, size > 1024 * 1024 else { continue }
                        
                        let rawTitle = URL(fileURLWithPath: eFile).deletingPathExtension().lastPathComponent
                        if let existing = queue.first(where: {
                            $0.mediaItem.cleanTitle == rawTitle ||
                            $0.mediaItem.title == rawTitle ||
                            ($0.localFilePath != nil && URL(fileURLWithPath: $0.localFilePath!).lastPathComponent == eFile)
                        }) {
                            var item = existing
                            item.status = .completed
                            item.localFilePath = fullPath.path
                            episodes.append(item)
                        } else {
                            let media = MediaItem(
                                title: rawTitle,
                                groupTitle: sFolder,
                                streamUrl: fullPath,
                                isSeriesOverride: true,
                                localRelativePath: "Series/\(sFolder)/\(eFile)"
                            )
                            var task = DownloadTaskItem(mediaItem: media)
                            task.status = DownloadStatus.completed
                            task.progress = 1.0
                            task.localFilePath = fullPath.path
                            episodes.append(task)
                        }
                    }
                    if !episodes.isEmpty {
                        seriesMap[sFolder] = episodes
                    }
                }
            }
        }
        
        self.downloadedMovies = movies
        self.downloadedSeriesGrouped = seriesMap
    }
}
