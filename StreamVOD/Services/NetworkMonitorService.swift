import Foundation
import Network
import Combine

@MainActor
public final class NetworkMonitorService: ObservableObject {
    public static let shared = NetworkMonitorService()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.mimusinema.networkmonitor")
    
    @Published public var isConnected: Bool = true
    @Published public var isOfflineModeActive: Bool = false
    @Published public var isChecking: Bool = false
    @Published public var checkFailedMessage: String? = nil
    
    private init() {
        startMonitoring()
    }
    
    public func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self = self else { return }
                let reachable = (path.status == .satisfied)
                self.isConnected = reachable
                if reachable {
                    self.checkFailedMessage = nil
                    if self.isOfflineModeActive {
                        self.isOfflineModeActive = false
                    }
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    /// Tekrar dene butonuna basıldığında aktif bağlantı testi yapar
    public func testConnection() async -> Bool {
        isChecking = true
        checkFailedMessage = nil
        
        let pathSatisfied = monitor.currentPath.status == .satisfied
        var canReachInternet = false
        
        if pathSatisfied {
            canReachInternet = await pingTest()
        }
        
        self.isChecking = false
        self.isConnected = canReachInternet
        
        if canReachInternet {
            self.isOfflineModeActive = false
            self.checkFailedMessage = nil
            return true
        } else {
            self.checkFailedMessage = "İnternet bağlantısı bulunamadı. Lütfen tekrar deneyiniz."
            return false
        }
    }
    
    private func pingTest() async -> Bool {
        guard let url = URL(string: "https://captive.apple.com/hotspot-detect.html") else {
            return monitor.currentPath.status == .satisfied
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3.5
        req.httpMethod = "HEAD"
        do {
            let (_, res) = try await URLSession.shared.data(for: req)
            if let http = res as? HTTPURLResponse, (200...399).contains(http.statusCode) {
                return true
            }
            return false
        } catch {
            return false
        }
    }
}
