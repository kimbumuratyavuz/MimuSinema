import SwiftUI

public struct MoviesView: View {
    @ObservedObject private var dataManager = DataManagerService.shared
    @ObservedObject private var downloadManager = DownloadManagerService.shared
    
    @State private var selectedCategory: String = "Tüm Kategoriler"
    @State private var selectedAudioFilter: AudioLanguageType = .all
    @State private var searchText: String = ""
    @State private var playingMovie: MediaItem? = nil
    
    // Açılır Liste Kategorileri (Tüm M3U dosyasını kapsar)
    private var allCategories: [String] {
        dataManager.allMovieCategories
    }
    
    // Filtrelenmiş veya Aranmış Filmler (Arama yapıldığında 50 ile sınırlı kalmaz, tüm M3U havuzunu tarar)
    private var filteredMovies: [MediaItem] {
        dataManager.searchMovies(query: searchText, category: selectedCategory, audio: selectedAudioFilter)
    }
    
    // Varsayılan sayfalama modunda mı yoksa arama/filtreleme modunda mı?
    private var isSearchingOrFiltered: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        selectedCategory != "Tüm Kategoriler" ||
        selectedAudioFilter != .all
    }
    
    // Ekranı dolduran 3'lü kolon ızgarası
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
                    // Üst Kategori Açılır Menü ve Filtre Barı
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
                            if !searchText.isEmpty {
                                Text("'\(searchText)' ile eşleşen film bulunamadı.")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            } else {
                                Text("Uygun film bulunamadı.")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            // VARSAYILAN M3U SIRALAMASI İLE GRID
                            LazyVGrid(columns: gridColumns, spacing: 14) {
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
                                        if !isSearchingOrFiltered && movie.id == dataManager.visibleMovies.last?.id && dataManager.hasMoreMovies {
                                            dataManager.loadMoreMovies()
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 4)
                            
                            if !isSearchingOrFiltered && dataManager.hasMoreMovies {
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
    
    private var filterHeaderBar: some View {
        HStack(spacing: 8) {
            // KATEGORİLER AÇILIR LİSTESİ (DROPDOWN)
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
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 13))
                    Text(selectedCategory)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.red)
                .cornerRadius(8)
            }
            
            // DİL FİLTRE ÇİPLERİ
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(AudioLanguageType.allCases, id: \.self) { type in
                        Button(action: {
                            selectedAudioFilter = type
                        }) {
                            Text(type.rawValue)
                                .font(.caption2)
                                .fontWeight(selectedAudioFilter == type ? .bold : .medium)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    selectedAudioFilter == type
                                        ? Color.white.opacity(0.3)
                                        : Color.white.opacity(0.1)
                                )
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
    }
}
