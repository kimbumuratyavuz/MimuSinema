import SwiftUI

public struct DownloadsView: View {
    @ObservedObject private var downloadManager = DownloadManagerService.shared
    @State private var selectedTab: Int = 0 // 0: Kuyruk, 1: İndirilen Dosyalar
    
    // Oynatıcı Durumu
    @State private var playingItem: MediaItem? = nil
    @State private var playingLocalUrl: URL? = nil
    
    // Silme Onay Durumları
    @State private var showDeleteFileAlert: Bool = false
    @State private var itemToDelete: DownloadTaskItem? = nil
    
    @State private var showDeleteSeriesAlert: Bool = false
    @State private var seriesNameToDelete: String? = nil
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.1).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Segment Seçici
                    Picker("Sayfa", selection: $selectedTab) {
                        Text("Kuyruk (\(downloadManager.queue.filter { $0.status != .completed }.count))").tag(0)
                        Text("İndirilenler (\(downloadManager.queue.filter { $0.status == .completed }.count))").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    if selectedTab == 0 {
                        queueSectionView
                    } else {
                        downloadedLibraryView
                    }
                }
            }
            .navigationTitle("İndirme Yöneticisi")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $playingItem) { item in
                CustomPlayerView(mediaList: [item], initialIndex: 0)
            }
            .fullScreenCover(isPresented: Binding(
                get: { playingLocalUrl != nil },
                set: { if !$0 { playingLocalUrl = nil } }
            )) {
                if let url = playingLocalUrl {
                    QuickLookController(url: url) {
                        playingLocalUrl = nil
                    }
                    .ignoresSafeArea()
                }
            }
            // 1. Tekil Dosya / Bölüm Silme Onay Uyarısı
            .alert("Dosyayı Sil", isPresented: $showDeleteFileAlert) {
                Button("Sil", role: .destructive) {
                    if let item = itemToDelete {
                        downloadManager.deleteDownloadedItem(id: item.id)
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
            // 2. Tüm Diziyi ve Klasörünü Silme Onay Uyarısı
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
                                    if let resolved = downloadManager.resolvedLocalUrl(for: task.mediaItem) {
                                        playingLocalUrl = resolved
                                    } else {
                                        playingItem = task.mediaItem
                                    }
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
                            
                            // Silme Butonu (Çöp Kutusu)
                            Button(action: {
                                itemToDelete = task
                                showDeleteFileAlert = true
                            }) {
                                Image(systemName: "trash")
                                    .font(.subheadline)
                                    .foregroundColor(.red.opacity(0.8))
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
        let completed = downloadManager.queue.filter { $0.status == .completed }
        let movies = completed.filter { !$0.mediaItem.isSeries }
        let seriesTasks = completed.filter { $0.mediaItem.isSeries }
        let seriesGrouped = Dictionary(grouping: seriesTasks, by: { $0.mediaItem.seriesName ?? "Diziler" })
        
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                
                // FİLMLER KLASÖRÜ
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
                    
                    if movies.isEmpty {
                        Text("Cihazınızda kayıtlı film bulunmuyor.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                    } else {
                        ForEach(movies) { item in
                            downloadedItemRow(item: item)
                        }
                    }
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                // DİZİLER KLASÖRÜ
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.yellow)
                        Text("Dizi Klasörü (Documents/Series)")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(seriesGrouped.keys.count) Dizi")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal)
                    
                    if seriesGrouped.isEmpty {
                        Text("Cihazınızda kayıtlı dizi bölümü bulunmuyor.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                    } else {
                        ForEach(Array(seriesGrouped.keys.sorted()), id: \.self) { seriesName in
                            DisclosureGroup {
                                ForEach(seriesGrouped[seriesName] ?? []) { item in
                                    downloadedItemRow(item: item)
                                        .padding(.leading, 8)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "folder")
                                        .foregroundColor(.orange)
                                    Text(seriesName)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    Text("\((seriesGrouped[seriesName] ?? []).count) Bölüm")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    
                                    // TÜM DİZİYİ VE KLASÖRÜNÜ SİL BUTONU
                                    Button(action: {
                                        seriesNameToDelete = seriesName
                                        showDeleteSeriesAlert = true
                                    }) {
                                        HStack(spacing: 2) {
                                            Image(systemName: "trash.fill")
                                                .font(.system(size: 11))
                                            Text("Diziyi Sil")
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.red.opacity(0.15))
                                        .cornerRadius(4)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .accentColor(.white)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
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
                if let resolved = downloadManager.resolvedLocalUrl(for: item.mediaItem) {
                    playingLocalUrl = resolved
                } else {
                    playingItem = item.mediaItem
                }
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
            
            // Tekil Silme Butonu (Onay uyarılı)
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
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("İndirme kuyruğunuz boş")
                .font(.headline)
                .foregroundColor(.white)
            Text("Film veya dizi bölümlerinin altındaki 'İndir' butonuna dokunarak kuyruğa ekleyebilirsiniz.")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
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
