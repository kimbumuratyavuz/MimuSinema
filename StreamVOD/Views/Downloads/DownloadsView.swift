import SwiftUI

public struct DownloadsView: View {
    @ObservedObject private var downloadManager = DownloadManagerService.shared
    @State private var selectedTab: Int = 0 // 0: Kuyruk, 1: İndirilen Dosyalar
    
    // Oynatıcı Durumu
    @State private var playingItem: MediaItem? = nil
    
    // Kuyruktan Kaldırma Onay Durumları (Dosya silinmez!)
    @State private var showRemoveQueueAlert: Bool = false
    @State private var itemToRemoveFromQueue: DownloadTaskItem? = nil
    
    // Cihazdan Kalıcı Silme Onay Durumları (İndirilenler Sekmesi)
    @State private var showDeleteFileAlert: Bool = false
    @State private var itemToDelete: DownloadTaskItem? = nil
    
    @State private var showDeleteSeriesAlert: Bool = false
    @State private var seriesNameToDelete: String? = nil
    
    // İndirilen Dizi Detay Sayfası için Seçilen Dizi
    @State private var selectedDownloadedSeries: DownloadedSeriesSheetItem? = nil
    
    public var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                Color(red: 0.08, green: 0.08, blue: 0.1).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Segment Seçici
                    Picker("Sayfa", selection: $selectedTab) {
                        Text("Kuyruk (\(downloadManager.queue.count))").tag(0)
                        Text("İndirilenler (\(downloadManager.totalDownloadedCount))").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    
                    if selectedTab == 0 {
                        queueSectionView
                    } else {
                        downloadedLibraryView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle("İndirme Yöneticisi")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                downloadManager.refreshDownloadedLibrary()
            }
            .fullScreenCover(item: $playingItem) { item in
                CustomPlayerView(mediaList: [item], initialIndex: 0)
            }
            // 1. Kuyruktan Kaldırma Uyarısı (Dosya silinmez)
            .alert("Kuyruktan Kaldır", isPresented: $showRemoveQueueAlert) {
                Button("Kuyruktan Kaldır", role: .destructive) {
                    if let item = itemToRemoveFromQueue {
                        downloadManager.removeFromQueue(id: item.id)
                        itemToRemoveFromQueue = nil
                    }
                }
                Button("Vazgeç", role: .cancel) {
                    itemToRemoveFromQueue = nil
                }
            } message: {
                if let item = itemToRemoveFromQueue {
                    Text("'\(item.mediaItem.cleanTitle)' indirme kuyruğundan kaldırılacaktır. Varsa indirilmiş video dosyanız silinmez.")
                }
            }
            // 2. Cihaz Hafızasından Kalıcı Silme Onay Uyarısı
            .alert("Cihazdan Kalıcı Olarak Sil", isPresented: $showDeleteFileAlert) {
                Button("Kalıcı Olarak Sil", role: .destructive) {
                    if let item = itemToDelete {
                        downloadManager.deleteDownloadedFile(item: item)
                        itemToDelete = nil
                    }
                }
                Button("Vazgeç", role: .cancel) {
                    itemToDelete = nil
                }
            } message: {
                if let item = itemToDelete {
                    Text("'\(item.mediaItem.cleanTitle)' cihazınızın hafızasından kalıcı olarak silinecektir. Emin misiniz?")
                } else {
                    Text("Bu içeriği silmek istediğinize emin misiniz?")
                }
            }
            // 3. Tüm Diziyi ve Klasörünü Silme Onay Uyarısı
            .alert("Diziyi ve Klasörünü Sil", isPresented: $showDeleteSeriesAlert) {
                Button("Tümünü Sil", role: .destructive) {
                    if let sName = seriesNameToDelete {
                        downloadManager.deleteEntireSeries(seriesName: sName)
                        seriesNameToDelete = nil
                    }
                }
                Button("Vazgeç", role: .cancel) {
                    seriesNameToDelete = nil
                }
            } message: {
                if let sName = seriesNameToDelete {
                    Text("'\(sName)' dizisine ait tüm indirilen bölümler ve cihazdaki '\(sName)' klasörü kalıcı olarak silinecektir. Emin misiniz?")
                } else {
                    Text("Diziyi silmek istediğinize emin misiniz?")
                }
            }
            .sheet(item: $selectedDownloadedSeries) { sheetItem in
                DownloadedSeriesDetailView(
                    seriesName: sheetItem.seriesName,
                    onPlay: { item in
                        selectedDownloadedSeries = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            playingItem = item.mediaItem
                        }
                    },
                    onDelete: { item in
                        downloadManager.deleteDownloadedFile(item: item)
                    },
                    onDeleteAll: {
                        downloadManager.deleteEntireSeries(seriesName: sheetItem.seriesName)
                        selectedDownloadedSeries = nil
                    }
                )
            }
        }
    }
    
    // MARK: - 1. KUYRUK GÖRÜNÜMÜ
    
    private var queueSectionView: some View {
        VStack(spacing: 0) {
            // Toplu İşlem Barı
            HStack {
                Button(action: {
                    let hasSelected = downloadManager.queue.contains(where: { $0.isSelected })
                    downloadManager.selectAll(!hasSelected)
                }) {
                    Text(downloadManager.queue.contains(where: { $0.isSelected }) ? "Seçimi Kaldır" : "Tümünü Seç")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.12))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                
                Spacer()
                
                // Seçilenleri İndir Butonu
                Button(action: {
                    downloadManager.startSelectedDownloads()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text(downloadManager.isDownloading ? "İndiriliyor..." : "Seçilenleri İndir")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(downloadManager.isDownloading ? Color.orange : Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .disabled(downloadManager.isDownloading)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            if downloadManager.queue.isEmpty {
                emptyQueueView
                Spacer(minLength: 0)
            } else {
                List {
                    ForEach($downloadManager.queue) { $task in
                        HStack(spacing: 12) {
                            // Checkbox
                            Button(action: {
                                downloadManager.toggleSelection(id: task.id)
                            }) {
                                Image(systemName: task.isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(task.isSelected ? .red : .gray)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                            
                            // Bilgiler
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.mediaItem.cleanTitle)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                
                                HStack(spacing: 8) {
                                    Text(task.mediaItem.isSeries ? (task.mediaItem.seriesName ?? "Dizi") : "Film")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    
                                    Text("•")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    
                                    Text(task.status.rawValue)
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(statusColor(task.status))
                                }
                                
                                // İlerleme Çubuğu
                                if task.status == .downloading {
                                    ProgressView(value: task.progress, total: 1.0)
                                        .progressViewStyle(LinearProgressViewStyle(tint: .red))
                                    
                                    if let speed = task.speedText {
                                        Text(speed)
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                } else if let err = task.errorMessage {
                                    Text(err)
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                        .lineLimit(1)
                                }
                            }
                            
                            Spacer()
                            
                            // Tekil İndir / Oynat Butonu
                            if task.status == .completed {
                                Button(action: {
                                    playingItem = task.mediaItem
                                }) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.green)
                                }
                                .buttonStyle(.plain)
                            } else if task.status != .downloading {
                                Button(action: {
                                    downloadManager.downloadSingle(id: task.id)
                                }) {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            // Kuyruktan Kaldırma Butonu (Dosya silmez!)
                            Button(action: {
                                itemToRemoveFromQueue = task
                                showRemoveQueueAlert = true
                            }) {
                                Image(systemName: "xmark.circle")
                                    .font(.title3)
                                    .foregroundColor(.gray.opacity(0.8))
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.white.opacity(0.05))
                    }
                    .listStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - 2. İNDİRİLENLER / KLASÖR GÖRÜNÜMÜ
    
    private var downloadedLibraryView: some View {
        let movies = downloadManager.downloadedMovies
        let seriesGrouped = downloadManager.downloadedSeriesGrouped
        
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // iPhone Dosyalar Uygulaması Bilgi Rozeti
                HStack(spacing: 12) {
                    Image(systemName: "folder.badge.person.crop")
                        .foregroundColor(.blue)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iPhone 'Dosyalar' Klasörü")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("İndirdiğiniz videolara iPhone'unuzdaki **Dosyalar > iPhone'umda > MimuSinema** klasöründen de doğrudan ulaşabilirsiniz.")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.3), lineWidth: 1))
                .padding(.horizontal)
                
                // Hiçbir dosya indirilmemişse bilgi mesajı
                if movies.isEmpty && seriesGrouped.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 56))
                            .foregroundColor(.gray)
                        Text("İndirilmiş İçerik Bulunmuyor")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("İndirdiğiniz filmler ve diziler burada listelenir. İnternet bağlantınız olmasa dahi bu alandan çevrimdışı izleyebilirsiniz.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                }
                
                // FİLMLER KLASÖRÜ
                if !movies.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.yellow)
                            Text("Film Klasörü (Documents/Movies)")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(movies.count) film")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal)
                        
                        ForEach(movies) { item in
                            downloadedItemRow(item: item)
                        }
                    }
                }
                
                if !movies.isEmpty && !seriesGrouped.isEmpty {
                    Divider().background(Color.gray.opacity(0.3))
                }
                
                // DİZİLER (AFİŞ KARTLARI)
                if !seriesGrouped.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "tv.fill")
                                .foregroundColor(.red)
                            Text("İndirilen Diziler")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(seriesGrouped.keys.count) Dizi")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal)
                        
                        let sortedSeriesNames = Array(seriesGrouped.keys.sorted())
                        let columns = [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ]
                        
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(sortedSeriesNames, id: \.self) { seriesName in
                                let episodes = seriesGrouped[seriesName] ?? []
                                let posterUrl = episodes.first(where: { !($0.mediaItem.logoUrl ?? "").isEmpty })?.mediaItem.logoUrl
                                
                                Button(action: {
                                    selectedDownloadedSeries = DownloadedSeriesSheetItem(seriesName: seriesName)
                                }) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ZStack(alignment: .topTrailing) {
                                            CachedAsyncImage(urlString: posterUrl) { img in
                                                img
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                Rectangle()
                                                    .fill(Color.gray.opacity(0.18))
                                                    .overlay(
                                                        Image(systemName: "tv")
                                                            .font(.title2)
                                                            .foregroundColor(.gray.opacity(0.5))
                                                    )
                                            }
                                            .frame(height: 150)
                                            .clipped()
                                            .cornerRadius(8)
                                            
                                            // Bölüm Sayısı Rozeti
                                            Text("\(episodes.count) Bölüm")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 3)
                                                .background(Color.red.opacity(0.85))
                                                .cornerRadius(4)
                                                .padding(5)
                                        }
                                        
                                        Text(seriesName)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private func downloadedItemRow(item: DownloadTaskItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.mediaItem.cleanTitle)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let path = item.localFilePath {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Oynat Butonu
            Button(action: {
                playingItem = item.mediaItem
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                    Text("İzle")
                }
                .font(.caption)
                .fontWeight(.bold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            
            // Cihazdan Kalıcı Silme Butonu
            Button(action: {
                itemToDelete = item
                showDeleteFileAlert = true
            }) {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .padding(6)
                    .background(Circle().fill(Color.red.opacity(0.15)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .cornerRadius(6)
        .padding(.horizontal)
    }
    
    private var emptyQueueView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("İndirme Kuyruğu Boş")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Film veya dizi detay sayfalarından 'İndir' butonuna basarak içerikleri bu kuyruğa ekleyebilirsiniz.")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.top, 24)
    }
    
    private func statusColor(_ status: DownloadStatus) -> Color {
        switch status {
        case .queued: return .yellow
        case .downloading: return .orange
        case .completed: return .green
        case .failed: return .red
        case .paused: return .gray
        }
    }
}

// MARK: - İndirilen Dizi Detay Sayfası / Modalı
public struct DownloadedSeriesSheetItem: Identifiable {
    public var id: String { seriesName }
    public let seriesName: String
    
    public init(seriesName: String) {
        self.seriesName = seriesName
    }
}

public struct DownloadedSeriesDetailView: View {
    public let seriesName: String
    public var onPlay: (DownloadTaskItem) -> Void
    public var onDelete: (DownloadTaskItem) -> Void
    public var onDeleteAll: () -> Void
    
    @ObservedObject private var downloadManager = DownloadManagerService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteAllAlert = false
    
    public init(
        seriesName: String,
        onPlay: @escaping (DownloadTaskItem) -> Void,
        onDelete: @escaping (DownloadTaskItem) -> Void,
        onDeleteAll: @escaping () -> Void
    ) {
        self.seriesName = seriesName
        self.onPlay = onPlay
        self.onDelete = onDelete
        self.onDeleteAll = onDeleteAll
    }
    
    private var seriesEpisodes: [DownloadTaskItem] {
        downloadManager.downloadedSeries[seriesName] ?? []
    }
    
    private var headerPosterUrl: String? {
        seriesEpisodes.first(where: { !($0.mediaItem.logoUrl ?? "").isEmpty })?.mediaItem.logoUrl
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.1).ignoresSafeArea()
                
                if seriesEpisodes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("Bu diziye ait indirilmiş bölüm kalmadı.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Üst Başlık Kartı
                            HStack(spacing: 14) {
                                CachedAsyncImage(urlString: headerPosterUrl) { img in
                                    img
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .overlay(Image(systemName: "tv").foregroundColor(.gray))
                                }
                                .frame(width: 80, height: 110)
                                .cornerRadius(8)
                                .clipped()
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(seriesName)
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .lineLimit(2)
                                    
                                    Text("\(seriesEpisodes.count) Bölüm İndirildi")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                    
                                    Button(action: {
                                        showDeleteAllAlert = true
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "trash.fill")
                                                .font(.caption2)
                                            Text("Tüm Diziyi Sil")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                        }
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.red.opacity(0.15))
                                        .cornerRadius(6)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.top, 12)
                            
                            Divider().background(Color.gray.opacity(0.3))
                            
                            // Bölümler Listesi
                            VStack(alignment: .leading, spacing: 10) {
                                Text("İndirilen Bölümler")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal)
                                
                                ForEach(seriesEpisodes) { item in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.mediaItem.cleanTitle)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.white)
                                                .lineLimit(2)
                                            
                                            HStack(spacing: 8) {
                                                if let path = item.localFilePath {
                                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                                        .font(.caption2)
                                                        .foregroundColor(.gray)
                                                        .lineLimit(1)
                                                }
                                                if item.totalBytes > 0 {
                                                    Text(ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file))
                                                        .font(.caption2)
                                                        .foregroundColor(.gray.opacity(0.8))
                                                }
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        // Oynat
                                        Button(action: {
                                            onPlay(item)
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "play.fill")
                                                Text("İzle")
                                            }
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.green)
                                            .foregroundColor(.white)
                                            .cornerRadius(6)
                                        }
                                        .buttonStyle(.plain)
                                        
                                        // Sil
                                        Button(action: {
                                            onDelete(item)
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.subheadline)
                                                .foregroundColor(.red)
                                                .padding(6)
                                                .background(Circle().fill(Color.red.opacity(0.15)))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.04))
                                    .cornerRadius(8)
                                    .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle(seriesName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kapat") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .alert("Tüm Diziyi Sil", isPresented: $showDeleteAllAlert) {
                Button("Tümünü Sil", role: .destructive) {
                    onDeleteAll()
                    dismiss()
                }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("'\(seriesName)' dizisine ait tüm indirilmiş bölümler silinecektir. Emin misiniz?")
            }
        }
    }
}
