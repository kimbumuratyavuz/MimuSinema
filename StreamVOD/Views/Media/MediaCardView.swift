import SwiftUI

public struct MediaCardView: View {
    public let item: MediaItem
    public var cardWidth: CGFloat? = nil
    public var onPlay: () -> Void
    public var onDownload: () -> Void
    
    @ObservedObject private var favoritesService = FavoritesService.shared
    @ObservedObject private var downloadManager = DownloadManagerService.shared
    
    private var isFav: Bool {
        favoritesService.isFavorite(media: item)
    }
    
    private var isAlreadyQueuedOrDownloaded: Bool {
        downloadManager.isItemQueued(media: item)
    }
    
    public init(
        item: MediaItem,
        cardWidth: CGFloat? = nil,
        onPlay: @escaping () -> Void,
        onDownload: @escaping () -> Void
    ) {
        self.item = item
        self.cardWidth = cardWidth
        self.onPlay = onPlay
        self.onDownload = onDownload
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Poster Alanı
            ZStack(alignment: .topTrailing) {
                CachedAsyncImage(urlString: item.logoUrl) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.18))
                        .overlay(
                            Image(systemName: "film")
                                .font(.title3)
                                .foregroundColor(.gray.opacity(0.5))
                        )
                }
                .frame(height: 170)
                .frame(maxWidth: cardWidth ?? .infinity)
                .clipped()
                .cornerRadius(8)
                
                // Sol Üst: Favori Kalp Butonu
                VStack {
                    HStack {
                        Button(action: {
                            favoritesService.toggleFavorite(media: item)
                        }) {
                            Image(systemName: isFav ? "heart.fill" : "heart")
                                .font(.system(size: 13))
                                .foregroundColor(isFav ? .red : .white)
                                .padding(5)
                                .background(Circle().fill(Color.black.opacity(0.65)))
                        }
                        .padding(5)
                        
                        Spacer()
                    }
                    Spacer()
                }
                
                // Sağ Üst: Dublaj / Altyazı Rozeti
                if item.audioType != .original {
                    Text(item.audioType.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(item.audioType == .dubbing ? Color.green : Color.blue)
                        .cornerRadius(4)
                        .padding(5)
                }
            }
            .frame(height: 170)
            
            // Başlık & Kategori (Genişlik Kilitli)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.cleanTitle)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Text(item.groupTitle)
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(height: 28, alignment: .topLeading)
            
            // Kartın Altındaki "İzle" ve "İndir" Butonları
            HStack(spacing: 4) {
                Button(action: onPlay) {
                    HStack(spacing: 2) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8))
                        Text("İzle")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(5)
                }
                
                Button(action: {
                    if !isAlreadyQueuedOrDownloaded {
                        onDownload()
                    }
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: isAlreadyQueuedOrDownloaded ? "checkmark.circle.fill" : "arrow.down")
                            .font(.system(size: 8))
                        Text(isAlreadyQueuedOrDownloaded ? "Kuyrukta" : "İndir")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(isAlreadyQueuedOrDownloaded ? Color.green.opacity(0.35) : Color.white.opacity(0.15))
                    .foregroundColor(isAlreadyQueuedOrDownloaded ? Color.green : Color.white)
                    .cornerRadius(5)
                }
                .disabled(isAlreadyQueuedOrDownloaded)
            }
        }
        .frame(width: cardWidth)
        .frame(maxWidth: cardWidth == nil ? .infinity : nil)
    }
}
