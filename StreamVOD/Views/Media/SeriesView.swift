import SwiftUI

public struct SeriesDetailView: View {
    public let series: SeriesGroup
    @ObservedObject private var downloadManager = DownloadManagerService.shared
    @ObservedObject private var favoritesService = FavoritesService.shared
    
    @State private var selectedSeason: String = ""
    @State private var selectedAudioFilter: AudioLanguageType = .all
    @State private var playingIndex: Int? = nil
    
    private var isSeriesFav: Bool {
        favoritesService.isSeriesFavorite(seriesName: series.name)
    }
    
    private var currentSeasonEpisodes: [MediaItem] {
        let eps = series.seasons[selectedSeason] ?? series.episodes
        return eps.filter { item in
            switch selectedAudioFilter {
            case .all: return true
            case .dubbing: return item.audioType == .dubbing
            case .subtitle: return item.audioType == .subtitle
            case .original: return item.audioType == .original
            }
        }
    }
    
    public var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        CachedAsyncImage(urlString: series.logoUrl) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(Color.gray.opacity(0.2))
                        }
                        .frame(width: 90, height: 130)
                        .cornerRadius(8)
                        .clipped()
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(series.name)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Toplam \(series.episodes.count) Bölüm")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            HStack(spacing: 8) {
                                Button(action: {
                                    favoritesService.toggleSeriesFavorite(series: series)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: isSeriesFav ? "heart.fill" : "heart")
                                            .font(.caption2)
                                        Text(isSeriesFav ? "Listemde" : "Listeme Ekle")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSeriesFav ? Color.white.opacity(0.2) : Color.white.opacity(0.12))
                                    .foregroundColor(isSeriesFav ? .red : .white)
                                    .cornerRadius(6)
                                }
                                
                                Button(action: addSeasonToQueue) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.down.to.line.circle")
                                        Text("Sezonu İndir")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // SEZON SEÇİCİ
                    if series.sortedSeasonKeys.count > 1 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SEZON SEÇİN")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.gray)
                                .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(series.sortedSeasonKeys, id: \.self) { seasonKey in
                                        Button(action: {
                                            selectedSeason = seasonKey
                                        }) {
                                            Text(seasonKey)
                                                .font(.subheadline)
                                                .fontWeight(selectedSeason == seasonKey ? .bold : .medium)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 7)
                                                .background(selectedSeason == seasonKey ? Color.red : Color.white.opacity(0.12))
                                                .foregroundColor(.white)
                                                .cornerRadius(8)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    // DİL FİLTRESİ
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(AudioLanguageType.allCases, id: \.self) { type in
                                Button(action: { selectedAudioFilter = type }) {
                                    Text(type.rawValue)
                                        .font(.caption2)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .background(selectedAudioFilter == type ? Color.red : Color.white.opacity(0.1))
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    Divider().background(Color.gray.opacity(0.3))
                    
                    // BÖLÜMLER LİSTESİ
                    LazyVStack(spacing: 8) {
                        ForEach(Array(currentSeasonEpisodes.enumerated()), id: \.element.id) { index, ep in
                            let isEpQueued = downloadManager.isItemQueued(media: ep)
                            
                            HStack(spacing: 12) {
                                Button(action: {
                                    if let originalIndex = series.episodes.firstIndex(where: { $0.id == ep.id }) {
                                        playingIndex = originalIndex
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "play.fill")
                                            .font(.caption)
                                        Text("İzle")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                                }
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ep.cleanTitle)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    
                                    if ep.audioType != .original {
                                        Text(ep.audioType.rawValue)
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(ep.audioType == .dubbing ? Color.green : Color.blue)
                                            .cornerRadius(4)
                                    }
                                }
                                
                                Spacer()
                                
                                // BÖLÜM İNDİRME BUTONU (KUYRUKTAYSA PASİF)
                                Button(action: {
                                    if !isEpQueued {
                                        downloadManager.addToQueue(media: ep)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: isEpQueued ? "checkmark.circle.fill" : "arrow.down.circle")
                                            .font(.title3)
                                        if isEpQueued {
                                            Text("Kuyrukta")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                        }
                                    }
                                    .foregroundColor(isEpQueued ? .green : .white.opacity(0.85))
                                    .padding(6)
                                    .background(isEpQueued ? Color.green.opacity(0.2) : Color.white.opacity(0.12))
                                    .cornerRadius(6)
                                }
                                .disabled(isEpQueued) // KUYRUKTAYSA PASİFLEŞİR
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .navigationTitle(series.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedSeason.isEmpty {
                selectedSeason = series.sortedSeasonKeys.first ?? "1. Sezon"
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { playingIndex != nil },
            set: { if !$0 { playingIndex = nil } }
        )) {
            if let idx = playingIndex {
                CustomPlayerView(mediaList: series.episodes, initialIndex: idx)
            }
        }
    }
    
    private func addSeasonToQueue() {
        for ep in currentSeasonEpisodes {
            downloadManager.addToQueue(media: ep)
        }
    }
}

public struct SeriesView: View {
    @ObservedObject private var dataManager = DataManagerService.shared
    @ObservedObject private var favoritesService = FavoritesService.shared
    @ObservedObject private var downloadManager = DownloadManagerService.shared
    
    @State private var searchText: String = ""
    
    private var filteredSeries: [SeriesGroup] {
        if searchText.isEmpty {
            return dataManager.visibleSeries
        }
        return dataManager.visibleSeries.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private let gridColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
                
                if dataManager.isLoadingSeries && dataManager.visibleSeries.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView("Diziler yükleniyor...")
                            .tint(.red)
                            .foregroundColor(.white)
                    }
                } else if filteredSeries.isEmpty {
                    Text("Dizi bulunamadı.")
                        .foregroundColor(.gray)
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 14) {
                            ForEach(filteredSeries) { group in
                                let isFav = favoritesService.isSeriesFavorite(seriesName: group.name)
                                
                                NavigationLink(destination: SeriesDetailView(series: group)) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        ZStack(alignment: .topLeading) {
                                            CachedAsyncImage(urlString: group.logoUrl) { img in
                                                img.resizable().aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                Rectangle()
                                                    .fill(Color.gray.opacity(0.18))
                                                    .overlay(Image(systemName: "tv").foregroundColor(.gray.opacity(0.5)))
                                            }
                                            .frame(height: 160)
                                            .frame(maxWidth: .infinity)
                                            .cornerRadius(8)
                                            .clipped()
                                            
                                            Button(action: {
                                                favoritesService.toggleSeriesFavorite(series: group)
                                            }) {
                                                Image(systemName: isFav ? "heart.fill" : "heart")
                                                    .font(.system(size: 13))
                                                    .foregroundColor(isFav ? .red : .white)
                                                    .padding(5)
                                                    .background(Circle().fill(Color.black.opacity(0.65)))
                                            }
                                            .padding(5)
                                            .buttonStyle(.plain)
                                            
                                            VStack {
                                                Spacer()
                                                HStack {
                                                    Spacer()
                                                    Text("\(group.episodes.count) Bölüm")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(.white)
                                                        .padding(3)
                                                        .background(Color.black.opacity(0.75))
                                                        .cornerRadius(4)
                                                        .padding(4)
                                                }
                                            }
                                        }
                                        .frame(height: 160)
                                        
                                        Text(group.name)
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        
                                        HStack(spacing: 3) {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 8))
                                            Text("İzle / Sezon")
                                                .font(.system(size: 10, weight: .bold))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 5)
                                        .background(Color.red)
                                        .foregroundColor(.white)
                                        .cornerRadius(6)
                                    }
                                }
                                .buttonStyle(.plain)
                                .onAppear {
                                    if group.id == dataManager.visibleSeries.last?.id && dataManager.hasMoreSeries {
                                        dataManager.loadMoreSeries()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                        
                        if dataManager.hasMoreSeries {
                            ProgressView()
                                .tint(.red)
                                .padding()
                                .onAppear {
                                    dataManager.loadMoreSeries()
                                }
                        }
                        
                        Spacer().frame(height: 85)
                    }
                }
            }
            .navigationTitle("Diziler")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Dizi ara...")
        }
    }
}
