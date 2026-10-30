import SwiftUI

public struct SeriesDetailView: View {
    public let series: SeriesGroup
    @ObservedObject private var downloadManager = DownloadManagerService.shared
    
    @State private var selectedSeason: String = ""
    @State private var selectedAudioFilter: AudioLanguageType = .all
    @State private var playingIndex: Int? = nil
    
    // O sezonun filtrelenmiş bölümleri
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
            Color(red: 0.08, green: 0.08, blue: 0.1).ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Dizi Başlık ve Kapak Alanı
                    HStack(spacing: 14) {
                        if let logo = series.logoUrl, let url = URL(string: logo) {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    Rectangle().fill(Color.gray.opacity(0.3))
                                }
                            }
                            .frame(width: 90, height: 130)
                            .cornerRadius(8)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(series.name)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Toplam \(series.episodes.count) Bölüm")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Button(action: addSeasonToQueue) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down.to.line.circle")
                                    Text("Bu Sezonu İndir")
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
                    .padding(.horizontal)
                    
                    // SEZON SEÇİCİ (Sezon 1, Sezon 2, ...)
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
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
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
                            HStack(spacing: 12) {
                                // İZLE BUTONU (Oynatıcıyı açar)
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
                                
                                // İNDİR BUTONU
                                Button(action: {
                                    downloadManager.addToQueue(media: ep)
                                }) {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.title3)
                                        .foregroundColor(.white.opacity(0.85))
                                        .padding(6)
                                        .background(Circle().fill(Color.white.opacity(0.12)))
                                }
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
                // Dizinin tüm bölümlerini veriyoruz; geri çıkınca doğrudan buraya döner
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
    
    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 14)
    ]
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.1).ignoresSafeArea()
                
                if dataManager.isLoadingSeries && dataManager.visibleSeries.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView("Diziler yükleniyor (50'şer)...")
                            .tint(.white)
                            .foregroundColor(.white)
                    }
                } else if filteredSeries.isEmpty {
                    Text("Dizi bulunamadı.")
                        .foregroundColor(.gray)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(filteredSeries) { group in
                                NavigationLink(destination: SeriesDetailView(series: group)) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        // Kapak & Rozetler
                                        ZStack(alignment: .topTrailing) {
                                            if let logo = group.logoUrl, let url = URL(string: logo) {
                                                AsyncImage(url: url) { phase in
                                                    if let img = phase.image {
                                                        img.resizable().aspectRatio(contentMode: .fill)
                                                    } else {
                                                        Rectangle().fill(Color.gray.opacity(0.3))
                                                    }
                                                }
                                                .frame(height: 170)
                                                .cornerRadius(8)
                                            } else {
                                                Rectangle()
                                                    .fill(Color.gray.opacity(0.2))
                                                    .frame(height: 170)
                                                    .overlay(Image(systemName: "tv").foregroundColor(.gray))
                                                    .cornerRadius(8)
                                            }
                                            
                                            // Bölüm Sayısı Rozeti
                                            VStack {
                                                Spacer()
                                                HStack {
                                                    Spacer()
                                                    Text("\(group.episodes.count) Bölüm")
                                                        .font(.caption2)
                                                        .fontWeight(.bold)
                                                        .foregroundColor(.white)
                                                        .padding(4)
                                                        .background(Color.black.opacity(0.75))
                                                        .cornerRadius(4)
                                                        .padding(6)
                                                }
                                            }
                                        }
                                        .frame(height: 170)
                                        
                                        Text(group.name)
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        
                                        // Kartın Altındaki "İzle (Bölümler)" Butonu
                                        HStack(spacing: 4) {
                                            HStack(spacing: 3) {
                                                Image(systemName: "play.fill")
                                                    .font(.system(size: 9))
                                                Text("İzle / Sezonlar")
                                                    .font(.caption2)
                                                    .fontWeight(.bold)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                            .background(Color.red)
                                            .foregroundColor(.white)
                                            .cornerRadius(6)
                                        }
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
                        .padding()
                        
                        if dataManager.hasMoreSeries {
                            ProgressView()
                                .tint(.red)
                                .padding()
                                .onAppear {
                                    dataManager.loadMoreSeries()
                                }
                        }
                    }
                }
            }
            .navigationTitle("Diziler")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Dizi ara...")
        }
    }
}
