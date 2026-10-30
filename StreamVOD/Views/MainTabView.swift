import SwiftUI

public struct MainTabView: View {
    @ObservedObject private var dataManager = DataManagerService.shared
    @State private var selectedTab: TabItemType = .home
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            // Arka Plan Karartması
            Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
            
            // SEKMELERİN İÇERİĞİ
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
            
            // GLASSMORPHISM ŞEFFAF VE KAVİSLİ TAB MENÜ
            GlassmorphicTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            dataManager.fetchAllData()
        }
    }
}
