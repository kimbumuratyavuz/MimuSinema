import SwiftUI

public struct MoviesView: View {
    @ObservedObject private var dataManager = DataManagerService.shared
    @ObservedObject private var downloadManager = DownloadManagerService.shared
    
    @State private var selectedCategory: String = "Tüm Kategoriler"
    @State private var selectedAudioFilter: AudioLanguageType = .all
    @State private var searchText: String = ""
    @State private var playingMovie: MediaItem? = nil
    
    // Mevcut Tüm Benzersiz Kategoriler (Açılır Liste İçin)
    private var allCategories: [String] {
        let cats = Set(dataManager.visibleMovies.map { $0.groupTitle })
        return ["Tüm Kategoriler"] + cats.sorted()
    }
    
    // Filtrelenmiş Filmler
    private var filteredMovies: [MediaItem] {
        dataManager.visibleMovies.filter { item in
            // 1. Kategori Filtresi (Açılır Listeden Seçilen)
            let matchesCategory = (selectedCategory == "Tüm Kategoriler") || (item.groupTitle == selectedCategory)
            
            // 2. Dil Filtresi (Dublaj / Altyazı)
            let matchesAudio: Bool
            switch selectedAudioFilter {
            case .all: matchesAudio = true
            case .dubbing: matchesAudio = item.audioType == .dubbing
            case .subtitle: matchesAudio = item.audioType == .subtitle
            case .original: matchesAudio = item.audioType == .original
            }
            
            // 3. Arama Metni
            let matchesSearch = searchText.isEmpty ||
                item.cleanTitle.localizedCaseInsensitiveContains(searchText) ||
                item.groupTitle.localizedCaseInsensitiveContains(searchText)
            
            return matchesCategory && matchesAudio && matchesSearch
        }
    }
    
    // Kategoriye Göre Gruplandırılmış Liste
    private var categorizedSections: [(category: String, items: [MediaItem])] {
        let grouped = Dictionary(grouping: filteredMovies, by: { $0.groupTitle })
        return grouped.map { (category: $0.key, items: $0.value) }
            .sorted { $0.category.localizedCompare($1.category) == .orderedAscending }
    }
    
    private let gridColumns = [
        GridItem(.adaptive(minimum: 125, maximum: 145), spacing: 14)
    ]
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // ÜST FİLTRE & AÇILIR LİSTE (DROPDOWN) BARI
                    filterHeaderBar
                        .padding(.vertical, 8)
                    
                    if dataManager.isLoadingMovies && dataManager.visibleMovies.isEmpty {
                        Spacer()
                        ProgressView("Filmler yükleniyor...")
                            .tint(.red)
                            .foregroundColor(.white)
                        Spacer()
                    } else if filteredMovies.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "film")
                                .font(.system(size: 44))
                                .foregroundColor(.gray)
                            Text("Bu filtreye uygun film bulunamadı.")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Farklı bir kategori veya dil seçeneği deneyebilirsiniz.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            // Eğer belirli bir kategori seçildiyse: Grid (Izgara) görünümü
                            if selectedCategory != "Tüm Kategoriler" {
                                LazyVGrid(columns: gridColumns, spacing: 16) {
                                    ForEach(filteredMovies) { movie in
                                        MediaCardView(
                                            item: movie,
                                            onPlay: {
                                                playingMovie = movie
                                            },
                                            onDownload: {
                                                downloadManager.addToQueue(media: movie)
                                            }
                                        )
                                        .onAppear {
                                            if movie.id == dataManager.visibleMovies.last?.id && dataManager.hasMoreMovies {
                                                dataManager.loadMoreMovies()
                                            }
                                        }
                                    }
                                }
                                .padding()
                            } else {
                                // "Tüm Kategoriler" seçildiyse: Kategorilere ayrılmış yatay satırlar
                                LazyVStack(alignment: .leading, spacing: 22) {
                                    ForEach(categorizedSections, id: \.category) { section in
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
                                                                playingMovie = movie
                                                            },
                                                            onDownload: {
                                                                downloadManager.addToQueue(media: movie)
                                                            }
                                                        )
                                                        .onAppear {
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
                                }
                                .padding(.vertical)
                            }
                            
                            // Daha fazla yükle
                            if dataManager.hasMoreMovies {
                                ProgressView()
                                    .tint(.red)
                                    .padding()
                                    .onAppear {
                                        dataManager.loadMoreMovies()
                                    }
                            }
                            
                            Spacer().frame(height: 85)
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
    
    // MARK: - Açılır Liste (Dropdown) ve Dil Filtreleri
    private var filterHeaderBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // 1. KATEGORİLER AÇILIR LİSTESİ (DROPDOWN MENU)
                Menu {
                    ForEach(allCategories, id: \.self) { cat in
                        Button(action: {
                            withAnimation {
                                selectedCategory = cat
                            }
                        }) {
                            HStack {
                                Text(cat)
                                if selectedCategory == cat {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(.system(size: 14))
                        Text(selectedCategory)
                            .font(.caption)
                            .fontWeight(.bold)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.red)
                    .cornerRadius(8)
                }
                
                // 2. DİL FİLTRE ÇİPLERİ (Tümü, Dublaj, Altyazı)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(AudioLanguageType.allCases, id: \.self) { type in
                            Button(action: {
                                selectedAudioFilter = type
                            }) {
                                Text(type.rawValue)
                                    .font(.caption2)
                                    .fontWeight(selectedAudioFilter == type ? .bold : .medium)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        selectedAudioFilter == type
                                            ? Color.white.opacity(0.28)
                                            : Color.white.opacity(0.1)
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(14)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}
