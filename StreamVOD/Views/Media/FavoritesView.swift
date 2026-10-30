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
    
    private let columns = [
        GridItem(.adaptive(minimum: 125, maximum: 145), spacing: 14)
    ]
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.1).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Filtreleme Segmenti
                    Picker("Filtre", selection: $filterIndex) {
                        Text("Tümü (\(favoritesService.favoriteItems.count))").tag(0)
                        Text("Filmler").tag(1)
                        Text("Diziler").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    if filteredItems.isEmpty {
                        emptyFavoritesView
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 16) {
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
                            .padding()
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
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("Henüz favori eklemediniz")
                .font(.headline)
                .foregroundColor(.white)
            Text("Beğendiğiniz film ve dizileri afişlerindeki kalp ikonuna dokunarak buraya ekleyebilirsiniz.")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}
