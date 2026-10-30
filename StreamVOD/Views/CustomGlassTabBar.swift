import SwiftUI

public enum TabItemType: Int, CaseIterable {
    case home = 0
    case movies = 1
    case series = 2
    case favorites = 3
    case downloads = 4
    
    public var title: String {
        switch self {
        case .home: return "Keşfet"
        case .movies: return "Filmler"
        case .series: return "Diziler"
        case .favorites: return "Favoriler"
        case .downloads: return "İndirilenler"
        }
    }
    
    public var icon: String {
        switch self {
        case .home: return "sparkles.tv"
        case .movies: return "film"
        case .series: return "tv"
        case .favorites: return "heart.fill"
        case .downloads: return "arrow.down.circle"
        }
    }
}

public struct GlassmorphicTabBar: View {
    @Binding public var selectedTab: TabItemType
    
    public var body: some View {
        HStack(spacing: 0) {
            ForEach(TabItemType.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: isSelected ? 20 : 17, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? Color.red : Color.gray.opacity(0.85))
                            .scaleEffect(isSelected ? 1.12 : 1.0)
                        
                        Text(tab.title)
                            .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                            .foregroundColor(isSelected ? Color.white : Color.gray.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        // Glassmorphism Stili: UltraThinMaterial + Hafif Yarı Saydamlık + Kavisli Sınır
        .background(
            ZStack {
                // Blur efekti
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.ultraThinMaterial)
                
                // Koyu yarı saydam tabaka
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                
                // İnce şık cam ışıltısı kenarlık (Glass Border)
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.05),
                                Color.red.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        // Yumuşak derinlik gölgesi
        .shadow(color: Color.black.opacity(0.6), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
