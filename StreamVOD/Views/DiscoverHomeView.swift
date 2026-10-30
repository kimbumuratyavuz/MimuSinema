import SwiftUI

public struct DiscoverHomeView: View {
    @ObservedObject private var dataManager = DataManagerService.shared
    @ObservedObject private var favoritesService = FavoritesService.shared
    @ObservedObject private var downloadManager = DownloadManagerService.shared
    
    @Binding public var selectedTab: TabItemType
    
    @State private var playingMovie: MediaItem? = nil
    @State private var selectedSeries: SeriesGroup? = nil
    @State private var currentHeroIndex: Int = 0
    
    private var heroItems: [MediaItem] {
        var items: [MediaItem] = []
        if !dataManager.visibleMovies.isEmpty {
            items.append(contentsOf: dataManager.visibleMovies.prefix(4))
        }
        for s in dataManager.visibleSeries.prefix(3) {
            if let firstEp = s.episodes.first {
                items.append(firstEp)
            }
        }
        return items
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        netflixHeaderView
                        
                        if !heroItems.isEmpty {
                            heroCarouselSection
                        } else if dataManager.isLoadingMovies {
                            ProgressView()
                                .tint(.red)
                                .frame(height: 320)
                        }
                        
                        // Önerilen Filmler
                        VStack(spacing: 12) {
                            sectionHeader(
                                title: "Önerilen Filmler",
                                seeAllAction: {
                                    withAnimation { selectedTab = .movies }
                                }
                            )
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 14) {
                                    ForEach(dataManager.visibleMovies.prefix(15)) { movie in
                                        MediaCardView(
                                            item: movie,
                                            onPlay: {
                                                playingMovie = movie
                                            },
                                            onDownload: {
                                                downloadManager.addToQueue(media: movie)
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // Trend Diziler
                        VStack(spacing: 12) {
                            sectionHeader(
                                title: "Trend Diziler",
                                seeAllAction: {
                                    withAnimation { selectedTab = .series }
                                }
                            )
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 14) {
                                    ForEach(dataManager.visibleSeries.prefix(15)) { group in
                                        Button(action: {
                                            selectedSeries = group
                                        }) {
                                            VStack(alignment: .leading, spacing: 6) {
                                                ZStack(alignment: .bottomTrailing) {
                                                    CachedAsyncImage(urlString: group.logoUrl) { img in
                                                        img.resizable().aspectRatio(contentMode: .fill)
                                                    } placeholder: {
                                                        Rectangle()
                                                            .fill(Color.gray.opacity(0.18))
                                                            .overlay(Image(systemName: "tv").foregroundColor(.gray.opacity(0.5)))
                                                    }
                                                    .frame(width: 135, height: 180)
                                                    .cornerRadius(8)
                                                    .clipped()
                                                    
                                                    Text("\(group.episodes.count) Bölüm")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(.white)
                                                        .padding(3)
                                                        .background(Color.black.opacity(0.75))
                                                        .cornerRadius(4)
                                                        .padding(5)
                                                }
                                                
                                                Text(group.name)
                                                    .font(.caption)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                    .frame(width: 135, alignment: .leading)
                                                
                                                HStack(spacing: 3) {
                                                    Image(systemName: "play.fill")
                                                        .font(.system(size: 9))
                                                    Text("İzle / Sezonlar")
                                                        .font(.caption2)
                                                        .fontWeight(.bold)
                                                }
                                                .frame(width: 135)
                                                .padding(.vertical, 5)
                                                .background(Color.red)
                                                .foregroundColor(.white)
                                                .cornerRadius(6)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        Spacer().frame(height: 85)
                    }
                }
            }
            .navigationBarHidden(true)
            .fullScreenCover(item: $playingMovie) { movie in
                CustomPlayerView(mediaList: [movie], initialIndex: 0)
            }
            .sheet(item: $selectedSeries) { series in
                NavigationView {
                    SeriesDetailView(series: series)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Kapat") {
                                    selectedSeries = nil
                                }
                                .foregroundColor(.white)
                            }
                        }
                }
            }
        }
    }
    
    private var netflixHeaderView: some View {
        HStack {
            HStack(spacing: 6) {
                Text("M")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(.red)
                
                Text("MIMUSINEMA")
                    .font(.system(size: 18, weight: .black))
                    .tracking(2.5)
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            Button(action: {
                selectedTab = .movies
            }) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }
    
    private var heroCarouselSection: some View {
        TabView(selection: $currentHeroIndex) {
            ForEach(Array(heroItems.enumerated()), id: \.element.id) { index, item in
                ZStack(alignment: .bottom) {
                    CachedAsyncImage(urlString: item.logoUrl) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.gray.opacity(0.2))
                    }
                    .frame(maxWidth: .infinity, maxHeight: 380)
                    .clipped()
                    
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color(red: 0.05, green: 0.05, blue: 0.07).opacity(0.3),
                            Color(red: 0.05, green: 0.05, blue: 0.07).opacity(0.85),
                            Color(red: 0.05, green: 0.05, blue: 0.07)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Text(item.groupTitle)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white.opacity(0.8))
                            
                            if item.audioType != .original {
                                Text(item.audioType.rawValue)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(item.audioType == .dubbing ? Color.green : Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                        }
                        
                        Text(item.cleanTitle)
                            .font(.title2)
                            .fontWeight(.black)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 24)
                        
                        HStack(spacing: 16) {
                            Button(action: {
                                favoritesService.toggleFavorite(media: item)
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: favoritesService.isFavorite(media: item) ? "checkmark" : "plus")
                                        .font(.system(size: 18, weight: .bold))
                                    Text("Listem")
                                        .font(.caption2)
                                }
                                .foregroundColor(.white)
                                .frame(width: 70)
                            }
                            
                            Button(action: {
                                playingMovie = item
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill")
                                        .font(.headline)
                                    Text("Oynat")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                }
                                .foregroundColor(.black)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .cornerRadius(6)
                            }
                            
                            Button(action: {
                                downloadManager.addToQueue(media: item)
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "arrow.down.to.line")
                                        .font(.system(size: 18, weight: .bold))
                                    Text("İndir")
                                        .font(.caption2)
                                }
                                .foregroundColor(.white)
                                .frame(width: 70)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(.bottom, 20)
                }
                .tag(index)
            }
        }
        .frame(height: 380)
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
    }
    
    private func sectionHeader(title: String, seeAllAction: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Spacer()
            
            Button(action: seeAllAction) {
                HStack(spacing: 3) {
                    Text("Tamamını Gör")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
                .foregroundColor(.red)
            }
        }
        .padding(.horizontal)
    }
}
