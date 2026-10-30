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
            
            // Sezon tespiti: "1.S", "2.S", "1. Sezon", "S01", "Season 1" vb.
            let seasonPattern = "((\\d+)\\s*\\.?\\s*(S|Sezon|Season))|(S(\\d+))"
            if let regex = try? NSRegularExpression(pattern: seasonPattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: title, options: [], range: NSRange(location: 0, length: title.utf16.count)),
               let range = Range(match.range, in: title) {
                let seasonStr = String(title[range])
                // Sadece sayıyı alıp "X. Sezon" formatına dönüştürelim
                let numbers = seasonStr.filter { "0123456789".contains($0) }
                self.seasonName = numbers.isEmpty ? "1. Sezon" : "\(numbers). Sezon"
            } else {
                self.seasonName = "1. Sezon"
            }
        } else {
            self.seriesName = nil
            self.episodeTitle = nil
            self.seasonName = ""
        }
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
