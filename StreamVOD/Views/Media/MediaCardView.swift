import SwiftUI

public struct MediaCardView: View {
    public let item: MediaItem
    public var onPlay: () -> Void
    public var onDownload: () -> Void
    
    @ObservedObject private var favoritesService = FavoritesService.shared
    @State private var isAddedToQueue = false
    
    private var isFav: Bool {
        favoritesService.isFavorite(media: item)
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
                .frame(height: 160)
                .frame(maxWidth: .infinity)
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
            .frame(height: 160)
            
            // Başlık & Kategori
            VStack(alignment: .leading, spacing: 1) {
                Text(item.cleanTitle)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(item.groupTitle)
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                    .lineLimit(1)
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
                    onDownload()
                    withAnimation { isAddedToQueue = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { isAddedToQueue = false }
                    }
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: isAddedToQueue ? "checkmark" : "arrow.down")
                            .font(.system(size: 8))
                        Text(isAddedToQueue ? "Eklendi" : "İndir")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(isAddedToQueue ? Color.green.opacity(0.8) : Color.white.opacity(0.15))
                    .foregroundColor(.white)
                    .cornerRadius(5)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
