import SwiftUI

public struct FavoritesView: View {
    @ObservedObject private var favoritesService = FavoritesService.shared
    @ObservedObject private var downloadManager = DownloadManagerService.shared
    
    @State private var filterIndex: Int = 0 // 0: Tümü, 1: Filmler, 2: Diziler
    @State private var playingItem: MediaItem? = nil
    
    private var filteredItems: [MediaItem] {
        favoritesService.favoriteItems.filter { item in
            if filterIndex == 1 { return !item.isSeries }
            if filterIndex == 2 { return item.isSeries }
            return true
        }
    }
    
    // Sağ ve sol boşlukları sıfırlayan 3 sütunlu esnek ızgara
    private let gridColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Filtreleme Segmenti
                    Picker("Filtre", selection: $filterIndex) {
                        Text("Tümü (\(favoritesService.favoriteItems.count))").tag(0)
                        Text("Filmler").tag(1)
                        Text("Diziler").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    
                    if filteredItems.isEmpty {
                        emptyFavoritesView
                    } else {
                        ScrollView {
                            LazyVGrid(columns: gridColumns, spacing: 14) {
                                ForEach(filteredItems) { item in
                                    MediaCardView(
                                        item: item,
                                        onPlay: {
                                            playingItem = item
                                        },
                                        onDownload: {
                                            downloadManager.addToQueue(media: item)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 6)
                            
                            Spacer().frame(height: 85)
                        }
                    }
                }
            }
            .navigationTitle("Favorilerim")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $playingItem) { item in
                CustomPlayerView(mediaList: [item], initialIndex: 0)
            }
        }
    }
    
    private var emptyFavoritesView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("Henüz favori eklemediniz")
                .font(.headline)
                .foregroundColor(.white)
            Text("Beğendiğiniz film ve dizileri afişlerindeki kalp butonuna basarak buraya ekleyebilirsiniz.")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}
