import Foundation

public final class M3UParserService {
    public static let shared = M3UParserService()
    
    // Önceden derlenmiş (pre-compiled) regex'ler - 60.000 satır için tek bir kez derlenir
    private static let cleanSeriesRegexes: [NSRegularExpression] = {
        let patterns = [
            "(?i)\\s*-\\s*\\d+\\s*\\.?\\s*(?:sezon|season|seazon|s)\\b.*",
            "(?i)\\s*-\\s*(?:sezon|season|seazon)\\s*\\d+\\b.*",
            "(?i)\\s*-\\s*S\\s*\\d+\\b.*",
            "(?i)\\s+\\d+\\s*(?:-\\s*\\d+)?\\s*\\.?\\s*(?:sezon|season|seazon)(?:lar)?\\b.*",
            "(?i)\\s+(?:sezon|season|seazon)\\s+\\d+\\b.*"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()
    
    private init() {}
    
    /// Verilen raw M3U metnini parse ederek MediaItem listesi üretir (Bellek sızıntısı ve OOM'u önleyecek akış mimarisi)
    public func parse(m3uContent: String, isSeriesOverride: Bool? = nil) -> [MediaItem] {
        var items: [MediaItem] = []
        items.reserveCapacity(min(m3uContent.count / 200, 30_000))
        
        var currentTitle: String = ""
        var currentLogo: String? = nil
        var currentGroup: String = "Genel"
        var currentReferrer: String? = nil
        var currentUserAgent: String? = nil
        var isInItem = false
        
        // components(separatedBy:) yerine enumerateLines kullanarak 120.000 geçici string tahsisini engelliyoruz
        m3uContent.enumerateLines { rawLine, _ in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { return }
            
            if line.hasPrefix("#EXTINF:") {
                isInItem = true
                currentLogo = self.extractAttributeFast(line: line, key: "tvg-logo")
                currentGroup = self.extractGroupTitleFast(from: line)
                currentTitle = self.extractTitleFast(from: line, fallbackGroup: currentGroup)
                currentReferrer = nil
                currentUserAgent = nil
            } else if line.hasPrefix("#EXTVLCOPT:http-referrer=") {
                currentReferrer = line.replacingOccurrences(of: "#EXTVLCOPT:http-referrer=", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("#EXTVLCOPT:http-user-agent=") {
                currentUserAgent = line.replacingOccurrences(of: "#EXTVLCOPT:http-user-agent=", with: "").trimmingCharacters(in: .whitespaces)
            } else if !line.hasPrefix("#") {
                if isInItem, let url = URL(string: line) {
                    let item = MediaItem(
                        title: currentTitle,
                        logoUrl: currentLogo,
                        groupTitle: currentGroup,
                        streamUrl: url,
                        httpReferrer: currentReferrer,
                        httpUserAgent: currentUserAgent,
                        isSeriesOverride: isSeriesOverride
                    )
                    items.append(item)
                }
                isInItem = false
            }
        }
        
        return items
    }
    
    // MARK: - Regex Olmadan Ultra Hızlı String Ayrıştırma (0 ms CPU, 0 MB Bellek)
    
    private func extractAttributeFast(line: String, key: String) -> String? {
        let prefix = "\(key)=\""
        guard let startRange = line.range(of: prefix) else { return nil }
        let rest = line[startRange.upperBound...]
        guard let endRange = rest.range(of: "\"") else { return nil }
        return String(rest[..<endRange.lowerBound])
    }
    
    private func extractGroupTitleFast(from line: String) -> String {
        let prefix = "group-title=\""
        if let startRange = line.range(of: prefix) {
            let rest = line[startRange.upperBound...]
            if let endRange = rest.range(of: "\"") {
                let group = rest[..<endRange.lowerBound].trimmingCharacters(in: .whitespaces)
                if !group.isEmpty { return String(group) }
            } else if let commaRange = rest.range(of: ",") {
                let group = rest[..<commaRange.lowerBound].trimmingCharacters(in: .whitespaces)
                if !group.isEmpty { return String(group) }
            }
        }
        return "Genel"
    }
    
    private func extractTitleFast(from line: String, fallbackGroup: String) -> String {
        if let commaIndex = line.lastIndex(of: ",") {
            let titlePart = line[line.index(after: commaIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !titlePart.isEmpty {
                return titlePart
            }
        }
        return fallbackGroup
    }
    
    /// Dizi adındaki sezon eklerini önceden derlenmiş statik regex'ler ile anında temizler
    public static func cleanSeriesName(_ rawName: String) -> String {
        var name = rawName
        for regex in cleanSeriesRegexes {
            let count = name.utf16.count
            if count == 0 { break }
            let range = NSRange(location: 0, length: count)
            name = regex.stringByReplacingMatches(in: name, options: [], range: range, withTemplate: "")
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? rawName : trimmed
    }

    /// Dizi listesini dizi adına göre gruplar
    public func groupSeries(items: [MediaItem]) -> [SeriesGroup] {
        var groups: [String: [MediaItem]] = [:]
        var logos: [String: String?] = [:]
        
        for item in items {
            let rawName = item.seriesName ?? item.groupTitle
            let sName = Self.cleanSeriesName(rawName)
            if groups[sName] == nil {
                groups[sName] = []
                logos[sName] = item.logoUrl
            }
            groups[sName]?.append(item)
        }
        
        return groups.map { name, episodes in
            SeriesGroup(name: name, logoUrl: logos[name] ?? episodes.first?.logoUrl, episodes: episodes)
        }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}
