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
        VStack(alignment: .leading, spacing: 6) {
            // Poster Alanı
            ZStack(alignment: .topTrailing) {
                // Afiş Görseli
                if let logoStr = item.logoUrl, let url = URL(string: logoStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .overlay(ProgressView().tint(.white))
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            defaultPoster
                        @unknown default:
                            defaultPoster
                        }
                    }
                    .frame(height: 180)
                    .clipped()
                    .cornerRadius(10)
                } else {
                    defaultPoster
                        .frame(height: 180)
                        .cornerRadius(10)
                }
                
                // Sol Üst: Favori Kalp Butonu
                VStack {
                    HStack {
                        Button(action: {
                            favoritesService.toggleFavorite(media: item)
                        }) {
                            Image(systemName: isFav ? "heart.fill" : "heart")
                                .font(.system(size: 16))
                                .foregroundColor(isFav ? .red : .white)
                                .padding(6)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        }
                        .padding(6)
                        
                        Spacer()
                    }
                    Spacer()
                }
                
                // Sağ Üst: Dublaj / Altyazı Rozeti
                if item.audioType != .original {
                    Text(item.audioType.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(item.audioType == .dubbing ? Color.green : Color.blue)
                        .cornerRadius(4)
                        .padding(6)
                }
            }
            .frame(height: 180)
            
            // Başlık & Kategori
            VStack(alignment: .leading, spacing: 2) {
                Text(item.cleanTitle)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(item.groupTitle)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .frame(height: 32, alignment: .topLeading)
            
            // Kartın Altındaki "İzle" ve "İndir" Butonları (Yan Yana)
            HStack(spacing: 6) {
                // İZLE BUTONU
                Button(action: onPlay) {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("İzle")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                
                // İNDİR BUTONU
                Button(action: {
                    onDownload()
                    withAnimation { isAddedToQueue = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { isAddedToQueue = false }
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: isAddedToQueue ? "checkmark" : "arrow.down")
                            .font(.system(size: 10))
                        Text(isAddedToQueue ? "Eklendi" : "İndir")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(isAddedToQueue ? Color.green.opacity(0.8) : Color.white.opacity(0.15))
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
            }
        }
        .frame(width: 135)
    }
    
    private var defaultPoster: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .overlay(
                Image(systemName: "film")
                    .font(.title)
                    .foregroundColor(.gray)
            )
    }
}
