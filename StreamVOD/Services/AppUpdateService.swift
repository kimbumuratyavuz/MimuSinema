import Foundation
import SwiftUI
import Combine

public struct GitHubReleaseInfo: Codable {
    public let tag_name: String
    public let name: String?
    public let body: String?
    public let html_url: String
    public let assets: [GitHubReleaseAsset]
}

public struct GitHubReleaseAsset: Codable {
    public let name: String
    public let browser_download_url: String
    public let size: Int
}

@MainActor
public final class AppUpdateService: ObservableObject {
    public static let shared = AppUpdateService()
    
    private let releaseApiUrl = URL(string: "https://api.github.com/repos/kimbumuratyavuz/MimuSinema/releases/latest")!
    private let skippedVersionKey = "mimusinema_skipped_version"
    
    @Published public var hasUpdate: Bool = false
    @Published public var latestVersionTag: String = ""
    @Published public var releaseNotes: String = ""
    @Published public var ipaDownloadUrl: URL? = nil
    @Published public var releasePageUrl: URL? = nil
    
    // Cihazdaki Mevcut Sürüm
    public var currentVersion: String {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return ver.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private init() {}
    
    /// Uygulama açılışında yeni sürüm kontrolü yapar
    public func checkForUpdates() {
        Task {
            do {
                var request = URLRequest(url: releaseApiUrl)
                request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = 10
                
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else { return }
                
                let release = try JSONDecoder().decode(GitHubReleaseInfo.self, from: data)
                
                let remoteTag = release.tag_name.replacingOccurrences(of: "v", with: "").trimmingCharacters(in: .whitespaces)
                let localVer = self.currentVersion.replacingOccurrences(of: "v", with: "").trimmingCharacters(in: .whitespaces)
                
                // KULLANICI BU SÜRÜMÜ DAHA ÖNCE ATLADIYSA VEYA AYNI SÜRÜMSE UYARI VERME
                let skipped = UserDefaults.standard.string(forKey: self.skippedVersionKey) ?? ""
                if remoteTag == skipped {
                    return
                }
                
                // YALNIZCA GERÇEKTEN DAHA BÜYÜK BİR SÜRÜM VARSA UYARI VER
                if isVersion(remoteTag, strictlyGreaterThan: localVer) {
                    self.latestVersionTag = release.tag_name
                    self.releaseNotes = release.body ?? "Hata düzeltmeleri ve performans iyileştirmeleri yapıldı."
                    self.releasePageUrl = URL(string: release.html_url)
                    
                    if let ipaAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".ipa") }) {
                        self.ipaDownloadUrl = URL(string: ipaAsset.browser_download_url)
                    } else {
                        self.ipaDownloadUrl = URL(string: release.html_url)
                    }
                    
                    self.hasUpdate = true
                } else {
                    self.hasUpdate = false
                }
            } catch {
                print("Update check error: \(error.localizedDescription)")
            }
        }
    }
    
    public func skipThisVersion() {
        UserDefaults.standard.set(latestVersionTag.replacingOccurrences(of: "v", with: ""), forKey: skippedVersionKey)
        hasUpdate = false
    }
    
    /// Kesin büyüklük karşılaştırması (remote > local)
    private func isVersion(_ v1: String, strictlyGreaterThan v2: String) -> Bool {
        if v1 == v2 { return false } // AYNI SÜRÜMDE KESİNLİKLE FALSE
        
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }
        
        let count = max(parts1.count, parts2.count)
        for i in 0..<count {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return true }
            if p1 < p2 { return false }
        }
        return false
    }
}
