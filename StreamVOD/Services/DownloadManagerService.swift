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
    
    private var activeDownloadTask: URLSessionDownloadTask?
    private var isCancelled: Bool = false
    private var urlSession: URLSession!
    
    // Arka plan görevi kimliği
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    
    // RAM şişmesini önlemek için kontrollü eşzamanlı kanal sayısı (4 kanal)
    private let concurrentWorkers = 4
    
    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600
        config.httpMaximumConnectionsPerHost = 6
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
    
    /// Dinamik yerel dosya çözücü (Dosya var ve boyutu 1MB'dan büyük mü kontrol eder)
    public func resolvedLocalUrl(for media: MediaItem) -> URL? {
        let target = destinationUrl(for: media)
        if FileManager.default.fileExists(atPath: target.path) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: target.path),
               let size = attrs[.size] as? Int64, size > 1024 * 1024 {
                return target
            }
        }
        
        if let rel = media.localRelativePath {
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
        }
        return nil
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
    
    // MARK: - Silme İşlemleri
    public func deleteDownloadedItem(id: UUID) {
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        let task = queue[idx]
        
        if task.status == .downloading {
            isCancelled = true
            activeDownloadTask?.cancel()
            isDownloading = false
            currentProcessingId = nil
        }
        
        if let localUrl = resolvedLocalUrl(for: task.mediaItem) {
            try? FileManager.default.removeItem(at: localUrl)
        } else {
            let dest = destinationUrl(for: task.mediaItem)
            try? FileManager.default.removeItem(at: dest)
        }
        
        let isSeries = task.mediaItem.isSeries
        let seriesName = task.mediaItem.seriesName ?? "Diziler"
        
        queue.remove(at: idx)
        saveState()
        
        if isSeries {
            cleanupEmptySeriesFolder(seriesName: seriesName)
        }
    }
    
    public func deleteEntireSeries(seriesName: String) {
        let tasksToDelete = queue.filter { $0.mediaItem.isSeries && ($0.mediaItem.seriesName == seriesName) }
        
        for task in tasksToDelete {
            if let localUrl = resolvedLocalUrl(for: task.mediaItem) {
                try? FileManager.default.removeItem(at: localUrl)
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
            $0.isSelected && ($0.status == .queued || $0.status == .failed || $0.status == .paused)
        }) else {
            isDownloading = false
            currentProcessingId = nil
            stopBackgroundProtection()
            return
        }
        
        isDownloading = true
        isCancelled = false
        currentProcessingId = queue[nextTaskIndex].id
        queue[nextTaskIndex].status = .downloading
        queue[nextTaskIndex].errorMessage = nil
        queue[nextTaskIndex].progress = 0.02
        queue[nextTaskIndex].speedText = "Başlatılıyor..."
        
        let media = queue[nextTaskIndex].mediaItem
        let destination = destinationUrl(for: media)
        
        var request = URLRequest(url: media.streamUrl)
        if let ref = media.httpReferrer, !ref.isEmpty {
            request.setValue(ref, forHTTPHeaderField: "Referer")
        }
        if let ua = media.httpUserAgent, !ua.isEmpty {
            request.setValue(ua, forHTTPHeaderField: "User-Agent")
        }
        
        if media.streamUrl.absoluteString.lowercased().contains("m3u8") {
            downloadM3U8Safely(media: media, destination: destination, taskIndex: nextTaskIndex)
        } else {
            downloadDirectFile(request: request, destination: destination, taskIndex: nextTaskIndex)
        }
    }
    
    private func downloadDirectFile(request: URLRequest, destination: URL, taskIndex: Int) {
        let task = urlSession.downloadTask(with: request) { [weak self] tempUrl, response, error in
            Task { @MainActor in
                guard let self = self else { return }
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
    
    // MARK: - Bellek Dostu, Çökmeyen & Sağlam HLS İndirici
    private func downloadM3U8Safely(media: MediaItem, destination: URL, taskIndex: Int) {
        Task {
            do {
                var req = URLRequest(url: media.streamUrl)
                if let ref = media.httpReferrer { req.setValue(ref, forHTTPHeaderField: "Referer") }
                if let ua = media.httpUserAgent { req.setValue(ua, forHTTPHeaderField: "User-Agent") }
                
                let (data, response) = try await URLSession.shared.data(for: req)
                guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                      let content = String(data: data, encoding: .utf8) else {
                    throw NSError(domain: "MimuSinema", code: -1, userInfo: [NSLocalizedDescriptionKey: "Playlist indirilemedi (HTTP Hata)."])
                }
                
                let lines = content.components(separatedBy: .newlines)
                var segmentUrls: [URL] = []
                let baseUrl = media.streamUrl.deletingLastPathComponent()
                
                var masterPlaylistUrl: URL? = nil
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { continue }
                    if !trimmed.hasPrefix("#") {
                        if trimmed.contains(".m3u8") {
                            masterPlaylistUrl = URL(string: trimmed, relativeTo: baseUrl)?.absoluteURL
                            break
                        } else {
                            if let sUrl = URL(string: trimmed, relativeTo: baseUrl)?.absoluteURL {
                                segmentUrls.append(sUrl)
                            }
                        }
                    }
                }
                
                if let master = masterPlaylistUrl {
                    var subReq = URLRequest(url: master)
                    if let ref = media.httpReferrer { subReq.setValue(ref, forHTTPHeaderField: "Referer") }
                    if let ua = media.httpUserAgent { subReq.setValue(ua, forHTTPHeaderField: "User-Agent") }
                    let (subData, subRes) = try await URLSession.shared.data(for: subReq)
                    if let sRes = subRes as? HTTPURLResponse, sRes.statusCode == 200,
                       let subContent = String(data: subData, encoding: .utf8) {
                        let subLines = subContent.components(separatedBy: .newlines)
                        let subBase = master.deletingLastPathComponent()
                        for sLine in subLines {
                            let tr = sLine.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !tr.isEmpty && !tr.hasPrefix("#") {
                                if let seg = URL(string: tr, relativeTo: subBase)?.absoluteURL {
                                    segmentUrls.append(seg)
                                }
                            }
                        }
                    }
                }
                
                guard !segmentUrls.isEmpty else {
                    throw NSError(domain: "MimuSinema", code: -2, userInfo: [NSLocalizedDescriptionKey: "Video parçaları bulunamadı."])
                }
                
                let tempDestination = destination.deletingLastPathComponent().appendingPathComponent("temp_\(destination.lastPathComponent)")
                if FileManager.default.fileExists(atPath: tempDestination.path) {
                    try? FileManager.default.removeItem(at: tempDestination)
                }
                FileManager.default.createFile(atPath: tempDestination.path, contents: nil)
                let fileHandle = try FileHandle(forWritingTo: tempDestination)
                
                let totalSegments = segmentUrls.count
                var completedSegments = 0
                let chunkSize = self.concurrentWorkers
                
                for chunkStart in stride(from: 0, to: totalSegments, by: chunkSize) {
                    if self.isCancelled { break }
                    
                    let chunkEnd = min(chunkStart + chunkSize, totalSegments)
                    let currentBatch = Array(segmentUrls[chunkStart..<chunkEnd])
                    
                    let downloadedBatch = try await withThrowingTaskGroup(of: (Int, Data?).self) { group in
                        for (localIdx, segUrl) in currentBatch.enumerated() {
                            let globalIdx = chunkStart + localIdx
                            group.addTask {
                                return await self.fetchSingleSegmentWithRetry(
                                    url: segUrl,
                                    referrer: media.httpReferrer,
                                    userAgent: media.httpUserAgent,
                                    index: globalIdx
                                )
                            }
                        }
                        
                        var batchResults: [(Int, Data)] = []
                        for try await (idx, segDataOpt) in group {
                            if let data = segDataOpt, data.count > 512 {
                                batchResults.append((idx, data))
                            }
                        }
                        return batchResults.sorted(by: { $0.0 < $1.0 })
                    }
                    
                    // RAM boşaltma: Diske senkron yazarken autoreleasepool ile bellek temizlenir
                    autoreleasepool {
                        for (_, segData) in downloadedBatch {
                            fileHandle.write(segData)
                        }
                    }
                    
                    completedSegments += downloadedBatch.count
                    
                    let progress = Double(completedSegments) / Double(totalSegments)
                    if taskIndex < self.queue.count {
                        self.queue[taskIndex].progress = progress
                        let percent = Int(progress * 100)
                        self.queue[taskIndex].speedText = "% \(percent) (\(completedSegments)/\(totalSegments) parça)"
                    }
                }
                
                try fileHandle.close()
                
                if self.isCancelled {
                    try? FileManager.default.removeItem(at: tempDestination)
                    self.processNextInQueue()
                    return
                }
                
                // İndirilen dosya boyutu kontrolü (En az 1MB olmalı)
                let attrs = try? FileManager.default.attributesOfItem(atPath: tempDestination.path)
                let finalSize = (attrs?[.size] as? Int64) ?? 0
                
                guard finalSize > 1024 * 1024 else {
                    try? FileManager.default.removeItem(at: tempDestination)
                    throw NSError(domain: "MimuSinema", code: -3, userInfo: [NSLocalizedDescriptionKey: "Video verisi eksik indirildi."])
                }
                
                if FileManager.default.fileExists(atPath: destination.path) {
                    try? FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempDestination, to: destination)
                
                self.markCompleted(taskIndex: taskIndex, localUrl: destination)
                self.processNextInQueue()
                
            } catch {
                self.markFailed(taskIndex: taskIndex, error: error.localizedDescription)
                self.processNextInQueue()
            }
        }
    }
    
    private func fetchSingleSegmentWithRetry(url: URL, referrer: String?, userAgent: String?, index: Int) async -> (Int, Data?) {
        for attempt in 1...2 {
            do {
                var sReq = URLRequest(url: url)
                sReq.timeoutInterval = 25
                if let ref = referrer { sReq.setValue(ref, forHTTPHeaderField: "Referer") }
                if let ua = userAgent { sReq.setValue(ua, forHTTPHeaderField: "User-Agent") }
                
                let (data, response) = try await URLSession.shared.data(for: sReq)
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200, data.count > 512 {
                    return (index, data)
                }
            } catch {
                if attempt == 2 { return (index, nil) }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        return (index, nil)
    }
    
    private func markCompleted(taskIndex: Int, localUrl: URL) {
        guard taskIndex < queue.count else { return }
        queue[taskIndex].status = .completed
        queue[taskIndex].progress = 1.0
        queue[taskIndex].localFilePath = localUrl.path
        queue[taskIndex].mediaItem.localRelativePath = localUrl.lastPathComponent
        queue[taskIndex].isSelected = false
        queue[taskIndex].speedText = "Tamamlandı"
        saveState()
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
            self.queue = loaded
        }
    }
}
