import SwiftUI

public struct MainTabView: View {
    @ObservedObject private var dataManager = DataManagerService.shared
    @ObservedObject private var updateService = AppUpdateService.shared
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    
    @State private var selectedTab: TabItemType = .home
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            Color(red: 0.05, green: 0.05, blue: 0.07)
                .ignoresSafeArea()
            
            Group {
                switch selectedTab {
                case .home:
                    DiscoverHomeView(selectedTab: $selectedTab)
                case .movies:
                    MoviesView()
                case .series:
                    SeriesView()
                case .favorites:
                    FavoritesView()
                case .downloads:
                    DownloadsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .top)
            
            GlassmorphicTabBar(selectedTab: $selectedTab)
            
            // YENİ VERSİYON GÜNCELLEME PENCERESİ
            if updateService.hasUpdate {
                UpdateDialogView()
                    .transition(.opacity)
                    .zIndex(100)
            }
            
            // İNTERNET BAĞLANTISI YOK UYARI KATMANI
            if !networkMonitor.isConnected && !networkMonitor.isOfflineModeActive {
                ZStack {
                    // Arkasından uygulama hafif görünecek şekilde yarı saydam siyah katman
                    Color.black.opacity(0.88)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 22) {
                        Spacer()
                        
                        // Tam ortasına Kırmızı Alert ikonu
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 72))
                            .foregroundColor(.red)
                            .shadow(color: .red.opacity(0.4), radius: 12)
                        
                        // Lütfen İnternet Bağlantınızı Kontrol Ediniz
                        Text("Lütfen İnternet Bağlantınızı\nKontrol Ediniz")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        
                        VStack(spacing: 12) {
                            // Tekrar Dene Butonu
                            Button(action: {
                                Task {
                                    let success = await networkMonitor.testConnection()
                                    if success {
                                        dataManager.fetchAllData()
                                        updateService.checkForUpdates()
                                    }
                                }
                            }) {
                                HStack(spacing: 8) {
                                    if networkMonitor.isChecking {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text(networkMonitor.isChecking ? "Kontrol Ediliyor..." : "Tekrar Dene")
                                        .fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .disabled(networkMonitor.isChecking)
                            
                            // İndirilenlere Git Butonu
                            Button(action: {
                                selectedTab = .downloads
                                networkMonitor.isOfflineModeActive = true
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("İndirilenlere Git")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.18))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal, 36)
                        
                        // İnternet yine yoksa hata mesajı
                        if let errorMsg = networkMonitor.checkFailedMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "wifi.slash")
                                Text(errorMsg)
                            }
                            .font(.footnote)
                            .foregroundColor(.red)
                            .padding(.horizontal, 24)
                            .transition(.opacity)
                        }
                        
                        Spacer()
                    }
                }
                .zIndex(200)
                .transition(.opacity)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            if networkMonitor.isConnected {
                dataManager.fetchAllData()
                updateService.checkForUpdates()
            }
        }
    }
}
