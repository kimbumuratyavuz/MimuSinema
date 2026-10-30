import Foundation

public final class M3UParserService {
    public static let shared = M3UParserService()
    
    private init() {}
    
    /// Verilen raw M3U metnini parse ederek MediaItem listesi üretir
    public func parse(m3uContent: String, isSeriesOverride: Bool? = nil) -> [MediaItem] {
        var items: [MediaItem] = []
        let lines = m3uContent.components(separatedBy: .newlines)
        
        var currentTitle: String = ""
        var currentLogo: String? = nil
        var currentGroup: String = "Genel"
        var currentReferrer: String? = nil
        var currentUserAgent: String? = nil
        var isInItem = false
        
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            
            if line.hasPrefix("#EXTINF:") {
                isInItem = true
                currentLogo = extractAttribute(line: line, key: "tvg-logo")
                
                // group-title ayrıştırma (Örn: group-title="RecTV Filmler - Komedi" veya kapanmayan tırnaklar)
                currentGroup = extractGroupTitle(from: line)
                
                // Başlık ayrıştırma
                currentTitle = extractTitle(from: line, fallbackGroup: currentGroup)
                
                // Headerları sıfırla
                currentReferrer = nil
                currentUserAgent = nil
            } else if line.hasPrefix("#EXTVLCOPT:http-referrer=") {
                currentReferrer = line.replacingOccurrences(of: "#EXTVLCOPT:http-referrer=", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("#EXTVLCOPT:http-user-agent=") {
                currentUserAgent = line.replacingOccurrences(of: "#EXTVLCOPT:http-user-agent=", with: "").trimmingCharacters(in: .whitespaces)
            } else if !line.hasPrefix("#") {
                // Stream URL
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
    
    private func extractGroupTitle(from line: String) -> String {
        // 1. group-title="..." normal tırnak kontrolü
        if let regex = try? NSRegularExpression(pattern: "group-title=\"([^\"]+)\"", options: .caseInsensitive),
           let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)),
           let range = Range(match.range(at: 1), in: line) {
            return String(line[range]).trimmingCharacters(in: .whitespaces)
        }
        
        // 2. Kapanmayan tırnak kontrolü: group-title="RecTV Filmler - Komedi, Başlık
        if let range = line.range(of: "group-title=\"") {
            let rest = line[range.upperBound...]
            if let commaIndex = rest.firstIndex(of: ",") {
                let groupCandidate = rest[..<commaIndex]
                return String(groupCandidate).replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        
        return "Genel"
    }
    
    private func extractTitle(from line: String, fallbackGroup: String) -> String {
        // En son virgülü bulup başlık olarak alalım
        if let commaIndex = line.lastIndex(of: ",") {
            let titlePart = line[line.index(after: commaIndex)...]
            let clean = titlePart.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                return clean
            }
        }
        return fallbackGroup
    }
    
    private func extractAttribute(line: String, key: String) -> String? {
        let pattern = "\(key)=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(location: 0, length: line.utf16.count)
        if let match = regex.firstMatch(in: line, options: [], range: range),
           let keyRange = Range(match.range(at: 1), in: line) {
            return String(line[keyRange])
        }
        return nil
    }
    
    /// Dizi listesini dizi adına göre gruplar
    public func groupSeries(items: [MediaItem]) -> [SeriesGroup] {
        var groups: [String: [MediaItem]] = [:]
        var logos: [String: String?] = [:]
        
        for item in items {
            let sName = item.seriesName ?? item.groupTitle
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
