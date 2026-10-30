import SwiftUI

public struct MainTabView: View {
    @ObservedObject private var dataManager = DataManagerService.shared
    @ObservedObject private var updateService = AppUpdateService.shared
    
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
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            dataManager.fetchAllData()
            // Açılışta Otomatik Versiyon Kontrolü
            updateService.checkForUpdates()
        }
    }
}
