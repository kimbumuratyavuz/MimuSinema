import Foundation

public enum AudioLanguageType: String, Codable, CaseIterable {
    case all = "Tümü"
    case dubbing = "Dublaj"
    case subtitle = "Altyazı"
    case original = "Orijinal"
}

public struct MediaItem: Identifiable, Codable, Hashable {
    public let id: String
    public var title: String
    public var cleanTitle: String
    public var logoUrl: String?
    public var groupTitle: String
    public var streamUrl: URL
    public var httpReferrer: String?
    public var httpUserAgent: String?
    public var audioType: AudioLanguageType
    public var isSeries: Bool
    public var seriesName: String?
    public var seasonName: String
    public var episodeTitle: String?
    public var localRelativePath: String?
    
    public init(
        id: String? = nil,
        title: String,
        logoUrl: String? = nil,
        groupTitle: String = "Genel",
        streamUrl: URL,
        httpReferrer: String? = nil,
        httpUserAgent: String? = nil,
        isSeriesOverride: Bool? = nil,
        localRelativePath: String? = nil
    ) {
        self.id = id ?? streamUrl.absoluteString
        self.title = title
        self.logoUrl = logoUrl
        self.groupTitle = groupTitle
        self.streamUrl = streamUrl
        self.httpReferrer = httpReferrer
        self.httpUserAgent = httpUserAgent
        self.localRelativePath = localRelativePath
        
        // 1. Dublaj / Altyazı tespiti
        let lower = title.lowercased()
        if lower.contains("dublaj") || lower.contains("türkçe dublaj") || lower.contains("tr dublaj") {
            self.audioType = .dubbing
        } else if lower.contains("altyazı") || lower.contains("altyazili") || lower.contains("alt yazı") || lower.contains("tr altyazı") {
            self.audioType = .subtitle
        } else {
            self.audioType = .original
        }
        
        // 2. Film vs Dizi tespiti
        let groupLower = groupTitle.lowercased()
        let isSeriesDetected = isSeriesOverride ?? (groupLower.contains("dizi") || groupLower.contains("series") || lower.contains("sezon") || lower.contains("bölüm") || lower.contains(".s dublaj") || lower.contains(".s altyazı"))
        self.isSeries = isSeriesDetected
        
        // 3. Başlık temizleme
        var cleaned = title
        let cleanupPatterns = [
            " - Dublaj", " - dublaj", " Dublaj", " dublaj",
            " - Altyazı", " - altyazı", " Altyazı", " altyazı",
            " - Türkçe Dublaj", " Türkçe Dublaj", " TR Dublaj",
            " - Türkçe Altyazı", " Türkçe Altyazı"
        ]
        for pattern in cleanupPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "")
        }
        self.cleanTitle = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 4. Dizi için Sezon ve Dizi Adı Çözümleme
        if isSeriesDetected {
            self.seriesName = groupTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            self.episodeTitle = cleaned
            
            // Sezon tespiti: "1.S", "2.S", "Sezon 1", "1. Sezon", "S01", "S1", "Seazon" vb.
            self.seasonName = MediaItem.extractSeasonName(title: title, groupTitle: groupTitle)
        } else {
            self.seriesName = nil
            self.episodeTitle = nil
            self.seasonName = ""
        }
    }
    
    // Önceden derlenmiş statik regex'ler (60.000 bölüm taranırken CPU kilitlenmesini ve bellek sızıntısını önler)
    private static let seasonRegexList: [NSRegularExpression] = {
        let patterns = [
            "(?i)(?:^|[^\\w])(\\d+)\\s*\\.?\\s*(?:sezon|season|seazon|s)\\b",
            "(?i)\\b(?:sezon|season|seazon)\\s*(\\d+)\\b",
            "(?i)(?:^|[\\s\\.\\-_\\[\\(])S\\s*(\\d+)\\b"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()
    
    private static let genericSeasonRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "(?i)\\b(?:sezon|season|seazon)\\b")
    }()

    /// Dizi adı ve bölüm başlıklarından sezon bilgisini ayrıştırıp standartlaştırır ("1. Sezon", "2. Sezon" vb.)
    public static func extractSeasonName(title: String, groupTitle: String) -> String {
        let candidates = [title, groupTitle]
        
        for candidate in candidates {
            let utf16Count = candidate.utf16.count
            if utf16Count == 0 { continue }
            let range = NSRange(location: 0, length: utf16Count)
            
            for regex in seasonRegexList {
                if let match = regex.firstMatch(in: candidate, options: [], range: range),
                   match.numberOfRanges > 1 {
                    let groupRange = match.range(at: 1)
                    if groupRange.location != NSNotFound, let r = Range(groupRange, in: candidate) {
                        let numStr = String(candidate[r])
                        if let num = Int(numStr), num > 0 {
                            return "\(num). Sezon"
                        }
                    }
                }
            }
        }
        
        // 2. Sayı belirtilmemiş fakat tek başına "Sezon", "Season", "Seazon" geçen durumlar -> Varsayılan 1. Sezon
        if let genericRegex = genericSeasonRegex {
            for candidate in candidates {
                let utf16Count = candidate.utf16.count
                if utf16Count == 0 { continue }
                let range = NSRange(location: 0, length: utf16Count)
                if genericRegex.firstMatch(in: candidate, options: [], range: range) != nil {
                    return "1. Sezon"
                }
            }
        }
        
        return "1. Sezon"
    }
}

public struct SeriesGroup: Identifiable {
    public var id: String { name }
    public let name: String
    public var logoUrl: String?
    public var episodes: [MediaItem]
    
    // Sezonlara göre gruplandırılmış bölümler
    public var seasons: [String: [MediaItem]] {
        Dictionary(grouping: episodes, by: { $0.seasonName })
    }
    
    public var sortedSeasonKeys: [String] {
        seasons.keys.sorted { s1, s2 in
            let n1 = Int(s1.filter { "0123456789".contains($0) }) ?? 0
            let n2 = Int(s2.filter { "0123456789".contains($0) }) ?? 0
            return n1 < n2
        }
    }
    
    /// Dizinin bölümlerinde Dublaj (TR) olup olmadığı
    public var hasDubbing: Bool {
        episodes.contains { $0.audioType == .dubbing }
    }
    
    /// Dizinin bölümlerinde Altyazı (CC) olup olmadığı
    public var hasSubtitle: Bool {
        episodes.contains { $0.audioType == .subtitle }
    }
    
    public init(name: String, logoUrl: String? = nil, episodes: [MediaItem] = []) {
        self.name = name
        self.logoUrl = logoUrl
        self.episodes = episodes
    }
}

// MARK: - Akıllı Arama & Türkçe Karakter Toleransı Eklentileri
public extension String {
    func matchesSearch(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if self.localizedCaseInsensitiveContains(trimmed) { return true }
        if self.localizedStandardContains(trimmed) { return true }
        
        // Türkçe karakter ve aksan duyarsız eşleştirme (örn: ç/c, ğ/g, ı/i, ö/o, ş/s, ü/u)
        let normSelf = self.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr"))
        let normQuery = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr"))
        return normSelf.contains(normQuery)
    }
}

public extension MediaItem {
    func matchesQuery(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if cleanTitle.matchesSearch(trimmed) { return true }
        if title.matchesSearch(trimmed) { return true }
        if groupTitle.matchesSearch(trimmed) { return true }
        if let ep = episodeTitle, ep.matchesSearch(trimmed) { return true }
        if let ser = seriesName, ser.matchesSearch(trimmed) { return true }
        return false
    }
}
