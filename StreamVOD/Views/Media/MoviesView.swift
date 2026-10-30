import SwiftUI

public struct MoviesView: View {
    @ObservedObject private var dataManager = DataManagerService.shared
    @ObservedObject private var downloadManager = DownloadManagerService.shared
    
    @State private var selectedAudioFilter: AudioLanguageType = .all
    @State private var searchText: String = ""
    @State private var playingMovie: MediaItem? = nil
    
    private var filteredMovies: [MediaItem] {
        dataManager.visibleMovies.filter { item in
            let matchesFilter: Bool
            switch selectedAudioFilter {
            case .all: matchesFilter = true
            case .dubbing: matchesFilter = item.audioType == .dubbing
            case .subtitle: matchesFilter = item.audioType == .subtitle
            case .original: matchesFilter = item.audioType == .original
            }
            
            let matchesSearch = searchText.isEmpty ||
                item.cleanTitle.localizedCaseInsensitiveContains(searchText) ||
                item.groupTitle.localizedCaseInsensitiveContains(searchText)
            
            return matchesFilter && matchesSearch
        }
    }
    
    private var categorizedMovies: [(category: String, items: [MediaItem])] {
        let grouped = Dictionary(grouping: filteredMovies, by: { $0.groupTitle })
        return grouped.map { (category: $0.key, items: $0.value) }
            .sorted { $0.category.localizedCompare($1.category) == .orderedAscending }
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.1).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Filtre Çipleri
                    filterChipsView
                        .padding(.vertical, 8)
                    
                    if dataManager.isLoadingMovies && dataManager.visibleMovies.isEmpty {
                        Spacer()
                        ProgressView("Filmler yükleniyor (50'şer)...")
                            .tint(.white)
                            .foregroundColor(.white)
                        Spacer()
                    } else if filteredMovies.isEmpty {
                        Spacer()
                        Text("Film bulunamadı.")
                            .foregroundColor(.gray)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 22) {
                                ForEach(categorizedMovies, id: \.category) { section in
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text(section.category)
                                                .font(.headline)
                                                .foregroundColor(.white)
                                            Spacer()
                                            Text("\(section.items.count)")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        .padding(.horizontal)
                                        
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            LazyHStack(spacing: 12) {
                                                ForEach(section.items) { movie in
                                                    MediaCardView(
                                                        item: movie,
                                                        onPlay: {
                                                            // Oynatıcıyı aç (kapatınca scroll yeri korunur)
                                                            playingMovie = movie
                                                        },
                                                        onDownload: {
                                                            downloadManager.addToQueue(media: movie)
                                                        }
                                                    )
                                                    .onAppear {
                                                        // Listenin sonlarına yaklaşıldıysa sonraki 50 filmi çek
                                                        if movie.id == dataManager.visibleMovies.last?.id && dataManager.hasMoreMovies {
                                                            dataManager.loadMoreMovies()
                                                        }
                                                    }
                                                }
                                            }
                                            .padding(.horizontal)
                                        }
                                    }
                                }
                                
                                // Daha Fazla Yükle İlerleme Göstergesi
                                if dataManager.hasMoreMovies {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .tint(.red)
                                            .onAppear {
                                                dataManager.loadMoreMovies()
                                            }
                                        Spacer()
                                    }
                                    .padding()
                                }
                            }
                            .padding(.vertical)
                        }
                    }
                }
            }
            .navigationTitle("Filmler")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Film veya kategori ara...")
            .fullScreenCover(item: $playingMovie) { movie in
                CustomPlayerView(mediaList: [movie], initialIndex: 0)
            }
        }
    }
    
    private var filterChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AudioLanguageType.allCases, id: \.self) { type in
                    Button(action: {
                        selectedAudioFilter = type
                    }) {
                        Text(type.rawValue)
                            .font(.caption)
                            .fontWeight(selectedAudioFilter == type ? .bold : .medium)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                selectedAudioFilter == type
                                    ? Color.red
                                    : Color.white.opacity(0.12)
                            )
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}
