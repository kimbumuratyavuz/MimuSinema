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
    
    /// Dizi adı ve bölüm başlıklarından sezon bilgisini ayrıştırıp standartlaştırır ("1. Sezon", "2. Sezon" vb.)
    public static func extractSeasonName(title: String, groupTitle: String) -> String {
        // Kontrol sırası: önce bölüm başlığı (title), ardından grup başlığı (groupTitle)
        let candidates = [title, groupTitle]
        
        // 1. Sayı ve sezon belirteçleri içeren regex desenleri:
        // Pattern 1: Sayı önce ("1.S", "2. S", "1. Sezon", "1 Sezon", "1.Season", "2.Seazon", "1S")
        // Pattern 2: Sezon kelimesi önce ("Sezon 1", "Season 2", "Seazon 1", "Sezon1")
        // Pattern 3: S harfi ve sayı ("S1", "S01", "S 1", "s2")
        let regexPatterns = [
            "(?i)(?:^|[^\\w])(\\d+)\\s*\\.?\\s*(?:sezon|season|seazon|s)\\b",
            "(?i)\\b(?:sezon|season|seazon)\\s*(\\d+)\\b",
            "(?i)(?:^|[\\s\\.\\-_\\[\\(])S\\s*(\\d+)\\b"
        ]
        
        for candidate in candidates {
            for pattern in regexPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: candidate, options: [], range: NSRange(location: 0, length: candidate.utf16.count)),
                   match.numberOfRanges > 1 {
                    let range = match.range(at: 1)
                    if range.location != NSNotFound, let r = Range(range, in: candidate) {
                        let numStr = String(candidate[r])
                        if let num = Int(numStr), num > 0 {
                            return "\(num). Sezon"
                        }
                    }
                }
            }
        }
        
        // 2. Sayı belirtilmemiş fakat tek başına "Sezon", "Season", "Seazon" geçen durumlar -> Varsayılan 1. Sezon
        let genericPattern = "(?i)\\b(?:sezon|season|seazon)\\b"
        if let regex = try? NSRegularExpression(pattern: genericPattern) {
            for candidate in candidates {
                let range = NSRange(location: 0, length: candidate.utf16.count)
                if regex.firstMatch(in: candidate, options: [], range: range) != nil {
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
