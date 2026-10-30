import Foundation
import Combine

@MainActor
public final class DownloadManagerService: NSObject, ObservableObject {
    public static let shared = DownloadManagerService()
    
    @Published public var queue: [DownloadTaskItem] = []
    @Published public var isDownloading: Bool = false
    @Published public var currentProcessingId: UUID? = nil
    
    private var activeDownloadTask: URLSessionDownloadTask?
    private var urlSession: URLSession!
    
    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        self.urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: .main)
        loadSavedState()
    }
    
    // MARK: - Klasör Yolları
    public var moviesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Movies", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    public var seriesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Series", isDirectory: true)
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
        
        if media.isSeries {
            let sFolder = seriesFolderUrl(for: media.seriesName ?? "Diziler")
            return sFolder.appendingPathComponent("\(sanitizedTitle).mp4")
        } else {
            return moviesDirectory.appendingPathComponent("\(sanitizedTitle).mp4")
        }
    }
    
    private func sanitizeFileName(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }
    
    // MARK: - Kuyruk Yönetimi
    public func addToQueue(media: MediaItem) {
        if queue.contains(where: { $0.mediaItem.streamUrl == media.streamUrl }) {
            return
        }
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
    
    // MARK: - Cihazdan & Listeden Silme İşlemleri
    
    /// Tek bir indirilmiş görevi hem listeden hem de cihazın diskinden kalıcı olarak siler
    public func deleteDownloadedItem(id: UUID) {
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        let task = queue[idx]
        
        // 1. Eğer şu an indiriliyorsa durdur
        if task.status == .downloading {
            activeDownloadTask?.cancel()
            isDownloading = false
            currentProcessingId = nil
        }
        
        // 2. Cihazdaki fiziksel dosyayı sil
        if let filePath = task.localFilePath {
            if FileManager.default.fileExists(atPath: filePath) {
                try? FileManager.default.removeItem(atPath: filePath)
            }
        } else {
            // Alternatif hedef yolu da kontrol et
            let dest = destinationUrl(for: task.mediaItem)
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
        }
        
        let isSeries = task.mediaItem.isSeries
        let seriesName = task.mediaItem.seriesName ?? "Diziler"
        
        // 3. Listeden kaldır
        queue.remove(at: idx)
        saveState()
        
        // 4. Eğer bir dizi bölümü silindiyse ve o dizinin başka bölümü kalmadıysa, dizi klasörünü de sil
        if isSeries {
            cleanupEmptySeriesFolder(seriesName: seriesName)
        }
    }
    
    /// Tüm bir diziyi, tüm bölümlerini ve dizinin klasörünü cihazdan tamamen siler
    public func deleteEntireSeries(seriesName: String) {
        // İlgili dizinin tüm görevlerini bul
        let tasksToDelete = queue.filter { $0.mediaItem.isSeries && ($0.mediaItem.seriesName == seriesName) }
        
        for task in tasksToDelete {
            if let filePath = task.localFilePath, FileManager.default.fileExists(atPath: filePath) {
                try? FileManager.default.removeItem(atPath: filePath)
            }
            if let idx = queue.firstIndex(where: { $0.id == task.id }) {
                queue.remove(at: idx)
            }
        }
        
        // Cihazdaki dizi klasörünü tamamen sil
        let folder = seriesFolderUrl(for: seriesName)
        if FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.removeItem(at: folder)
        }
        
        saveState()
    }
    
    /// Dizinin kalan bölümü yoksa veya klasör boşsa klasörü cihazdan temizler
    private func cleanupEmptySeriesFolder(seriesName: String) {
        let remainingForThisSeries = queue.filter {
            $0.mediaItem.isSeries &&
            ($0.mediaItem.seriesName == seriesName) &&
            $0.status == .completed
        }
        
        if remainingForThisSeries.isEmpty {
            let folder = seriesFolderUrl(for: seriesName)
            if FileManager.default.fileExists(atPath: folder.path) {
                // Klasör içindeki kalan artık dosyaları veya klasörün kendisini sil
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }
    
    // MARK: - İndirme İşlemleri
    
    public func downloadSingle(id: UUID) {
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[idx].isSelected = true
        startSelectedDownloads()
    }
    
    public func startSelectedDownloads() {
        guard !isDownloading else { return }
        processNextInQueue()
    }
    
    private func processNextInQueue() {
        guard let nextTaskIndex = queue.firstIndex(where: {
            $0.isSelected && ($0.status == .queued || $0.status == .failed || $0.status == .paused)
        }) else {
            isDownloading = false
            currentProcessingId = nil
            return
        }
        
        isDownloading = true
        currentProcessingId = queue[nextTaskIndex].id
        queue[nextTaskIndex].status = .downloading
        queue[nextTaskIndex].errorMessage = nil
        queue[nextTaskIndex].progress = 0.05
        
        let media = queue[nextTaskIndex].mediaItem
        let destination = destinationUrl(for: media)
        
        var request = URLRequest(url: media.streamUrl)
        if let ref = media.httpReferrer, !ref.isEmpty {
            request.setValue(ref, forHTTPHeaderField: "Referer")
        }
        if let ua = media.httpUserAgent, !ua.isEmpty {
            request.setValue(ua, forHTTPHeaderField: "User-Agent")
        }
        
        if media.streamUrl.pathExtension.lowercased().contains("m3u8") {
            downloadM3U8Stream(media: media, destination: destination, taskIndex: nextTaskIndex)
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
    
    private func downloadM3U8Stream(media: MediaItem, destination: URL, taskIndex: Int) {
        Task {
            do {
                var req = URLRequest(url: media.streamUrl)
                if let ref = media.httpReferrer { req.setValue(ref, forHTTPHeaderField: "Referer") }
                if let ua = media.httpUserAgent { req.setValue(ua, forHTTPHeaderField: "User-Agent") }
                
                let (data, _) = try await URLSession.shared.data(for: req)
                guard let content = String(data: data, encoding: .utf8) else {
                    throw NSError(domain: "StreamVOD", code: -1, userInfo: [NSLocalizedDescriptionKey: "M3U8 okunamadı."])
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
                    let (subData, _) = try await URLSession.shared.data(for: subReq)
                    if let subContent = String(data: subData, encoding: .utf8) {
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
                    throw NSError(domain: "StreamVOD", code: -2, userInfo: [NSLocalizedDescriptionKey: "Segment bulunamadı."])
                }
                
                if FileManager.default.fileExists(atPath: destination.path) {
                    try? FileManager.default.removeItem(at: destination)
                }
                FileManager.default.createFile(atPath: destination.path, contents: nil)
                let fileHandle = try FileHandle(forWritingTo: destination)
                
                let total = Double(segmentUrls.count)
                for (idx, segUrl) in segmentUrls.enumerated() {
                    var sReq = URLRequest(url: segUrl)
                    if let ref = media.httpReferrer { sReq.setValue(ref, forHTTPHeaderField: "Referer") }
                    if let ua = media.httpUserAgent { sReq.setValue(ua, forHTTPHeaderField: "User-Agent") }
                    
                    let (segData, _) = try await URLSession.shared.data(for: sReq)
                    fileHandle.write(segData)
                    
                    let progress = Double(idx + 1) / total
                    if taskIndex < self.queue.count {
                        self.queue[taskIndex].progress = progress
                        self.queue[taskIndex].speedText = "\(idx + 1) / \(segmentUrls.count) parça"
                    }
                }
                try fileHandle.close()
                self.markCompleted(taskIndex: taskIndex, localUrl: destination)
                self.processNextInQueue()
                
            } catch {
                self.markFailed(taskIndex: taskIndex, error: error.localizedDescription)
                self.processNextInQueue()
            }
        }
    }
    
    private func markCompleted(taskIndex: Int, localUrl: URL) {
        guard taskIndex < queue.count else { return }
        queue[taskIndex].status = .completed
        queue[taskIndex].progress = 1.0
        queue[taskIndex].localFilePath = localUrl.path
        queue[taskIndex].mediaItem.localRelativePath = localUrl.path
        queue[taskIndex].isSelected = false
        queue[taskIndex].speedText = "İndirme Tamamlandı"
        saveState()
    }
    
    private func markFailed(taskIndex: Int, error: String) {
        guard taskIndex < queue.count else { return }
        queue[taskIndex].status = .failed
        queue[taskIndex].errorMessage = error
        saveState()
    }
    
    // MARK: - Kalıcılık
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
