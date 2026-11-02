import Foundation

public struct ByteRangeMeta: Codable, Sendable {
    public let duration: Double
    public let length: Int
    public let offset: Int
    
    public init(duration: Double, length: Int, offset: Int) {
        self.duration = duration
        self.length = length
        self.offset = offset
    }
}

public struct DownloadProgressMeta: Codable, Sendable {
    public let completedSegments: Int
    public let byteRangeEntries: [ByteRangeMeta]
    
    public init(completedSegments: Int, byteRangeEntries: [ByteRangeMeta]) {
        self.completedSegments = completedSegments
        self.byteRangeEntries = byteRangeEntries
    }
}

public enum DownloadStatus: String, Codable {
    case queued = "Kuyrukta"
    case downloading = "İndiriliyor"
    case completed = "Tamamlandı"
    case failed = "Başarısız"
    case paused = "Duraklatıldı"
    case stopped = "Durduruldu"
}

public struct DownloadTaskItem: Identifiable, Codable {
    public let id: UUID
    public var mediaItem: MediaItem
    public var status: DownloadStatus
    public var progress: Double // 0.0 ... 1.0
    public var speedText: String?
    public var localFilePath: String?
    public var errorMessage: String?
    public var addedDate: Date
    public var isSelected: Bool = false
    
    public init(mediaItem: MediaItem) {
        self.id = UUID()
        self.mediaItem = mediaItem
        self.status = .queued
        self.progress = 0.0
        self.speedText = nil
        self.localFilePath = nil
        self.errorMessage = nil
        self.addedDate = Date()
        self.isSelected = false
    }
}
