import Foundation
import Network

/// iOS AVPlayer'ın yerel .ts ve .m3u8 dosyalarını HTTP Live Streaming standardında
/// kesintisiz oynatabilmesi için dahili yerel HTTP sunucusu.
public final class LocalStreamServer: ObservableObject {
    public static let shared = LocalStreamServer()
    
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.mimusinema.localserver", qos: .userInitiated)
    public private(set) var port: UInt16 = 18080
    public private(set) var isRunning: Bool = false
    
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    private init() {
        start()
    }
    
    public func start() {
        guard !isRunning else { return }
        startListener(startingAt: port)
    }
    
    private func startListener(startingAt testPort: UInt16) {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            
            guard let nwPort = NWEndpoint.Port(rawValue: testPort) else { return }
            let newListener = try NWListener(using: params, on: nwPort)
            
            newListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    print("[LocalStreamServer] 127.0.0.1:\(testPort) portunda aktif.")
                    self.port = testPort
                    self.isRunning = true
                case .failed(let err):
                    print("[LocalStreamServer] Port \(testPort) hatası: \(err)")
                    self.isRunning = false
                    if testPort < 18090 {
                        self.startListener(startingAt: testPort + 1)
                    }
                default:
                    break
                }
            }
            
            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            self.listener?.cancel()
            self.listener = newListener
            newListener.start(queue: queue)
        } catch {
            print("[LocalStreamServer] Başlatılamadı: \(error)")
            if testPort < 18090 {
                startListener(startingAt: testPort + 1)
            }
        }
    }
    
    /// Yerel dosya URL'sini localhost HTTP stream URL'sine çevirir (iOS /var ve /private/var sembolik bağlarına karşı dayanıklı)
    public func url(for fileUrl: URL) -> URL {
        let relativePath = relativePathFromDocuments(for: fileUrl)
        let encodedPath = relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relativePath
        return URL(string: "http://127.0.0.1:\(self.port)/\(encodedPath)")!
    }
    
    private func relativePathFromDocuments(for fileUrl: URL) -> String {
        let comps = fileUrl.standardizedFileURL.pathComponents
        if let docIndex = comps.firstIndex(of: "Documents"), docIndex + 1 < comps.count {
            let sub = comps.suffix(from: docIndex + 1)
            return sub.joined(separator: "/")
        }
        
        let pathStr = fileUrl.path
        if let range = pathStr.range(of: "/Documents/") {
            return String(pathStr[range.upperBound...])
        }
        
        return fileUrl.lastPathComponent
    }
    
    // MARK: - Senkron M3U8 Üretici (Thread-Safe & Anında)
    @discardableResult
    public static func generateM3U8Synchronously(for tsUrl: URL) -> URL {
        let m3u8Url = tsUrl.deletingPathExtension().appendingPathExtension("m3u8")
        
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: tsUrl.path),
              let totalSize = attrs[.size] as? Int64, totalSize > 0 else {
            return m3u8Url
        }
        
        // Eğer m3u8 zaten varsa ve geçerliyse tekrar oluşturma
        if let existing = try? String(contentsOf: m3u8Url, encoding: .utf8),
           existing.contains("#EXT-X-BYTERANGE:") && existing.contains("#EXT-X-ENDLIST") {
            return m3u8Url
        }
        
        let packetSize: Int64 = 188
        let packetsPerSeg: Int64 = 10_000
        let segSize: Int64 = packetSize * packetsPerSeg // 1,880,000 bayt (~1.8 MB)
        let segDuration: Double = 5.0
        
        var content = "#EXTM3U\n#EXT-X-VERSION:4\n#EXT-X-TARGETDURATION:10\n#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-PLAYLIST-TYPE:VOD\n"
        var offset: Int64 = 0
        let fileName = tsUrl.lastPathComponent
        
        while offset < totalSize {
            let remaining = totalSize - offset
            let currentLen = min(segSize, remaining)
            content += "#EXT-X-BYTERANGE:\(currentLen)@\(offset)\n"
            content += String(format: "#EXTINF:%.3f,\n", segDuration)
            content += "\(fileName)\n"
            offset += currentLen
        }
        
        content += "#EXT-X-ENDLIST\n"
        try? content.write(to: m3u8Url, atomically: true, encoding: .utf8)
        print("[LocalStreamServer] Senkron M3U8 diske yazıldı: \(m3u8Url.lastPathComponent)")
        return m3u8Url
    }
    
    // MARK: - İstek İşleme
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                connection.cancel()
                return
            }
            
            guard let requestStr = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            
            let lines = requestStr.components(separatedBy: "\r\n")
            guard let firstLine = lines.first, !firstLine.isEmpty else {
                connection.cancel()
                return
            }
            
            let parts = firstLine.components(separatedBy: " ")
            guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD" else {
                self.send400(connection: connection)
                return
            }
            
            let rawPath = parts[1]
            let cleanPath = rawPath.components(separatedBy: "?")[0]
            let decodedPath = cleanPath.removingPercentEncoding ?? cleanPath
            let trimmedRelPath = decodedPath.hasPrefix("/") ? String(decodedPath.dropFirst()) : decodedPath
            
            // Range Başlığı Kontrolü
            var rangeHeader: String? = nil
            for line in lines {
                if line.lowercased().hasPrefix("range:") {
                    rangeHeader = line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            
            self.servePath(trimmedRelPath, rangeHeader: rangeHeader, connection: connection, isHeadOnly: parts[0] == "HEAD")
        }
    }
    
    private func servePath(_ relPath: String, rangeHeader: String?, connection: NWConnection, isHeadOnly: Bool) {
        var fileUrl = documentsDirectory.appendingPathComponent(relPath)
        
        // 1. Dosya doğrudan bulunamazsa Movies veya Series altında ara
        if !FileManager.default.fileExists(atPath: fileUrl.path) {
            let inMovies = documentsDirectory.appendingPathComponent("Movies").appendingPathComponent(relPath)
            if FileManager.default.fileExists(atPath: inMovies.path) {
                fileUrl = inMovies
            } else {
                let inSeries = documentsDirectory.appendingPathComponent("Series").appendingPathComponent(relPath)
                if FileManager.default.fileExists(atPath: inSeries.path) {
                    fileUrl = inSeries
                } else {
                    let lastComp = URL(fileURLWithPath: relPath).lastPathComponent
                    let inMoviesByName = documentsDirectory.appendingPathComponent("Movies").appendingPathComponent(lastComp)
                    if FileManager.default.fileExists(atPath: inMoviesByName.path) {
                        fileUrl = inMoviesByName
                    } else {
                        // Series alt klasörlerinde ara
                        let seriesDir = documentsDirectory.appendingPathComponent("Series")
                        if let subfolders = try? FileManager.default.contentsOfDirectory(atPath: seriesDir.path) {
                            for folder in subfolders {
                                let cand = seriesDir.appendingPathComponent(folder).appendingPathComponent(lastComp)
                                if FileManager.default.fileExists(atPath: cand.path) {
                                    fileUrl = cand
                                    break
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // 2. Dosya .m3u8 istenmiş ama henüz yoksa fakat .ts dosyası varsa: Senkron olarak anında M3U8 üret!
        if relPath.lowercased().hasSuffix(".m3u8") && !FileManager.default.fileExists(atPath: fileUrl.path) {
            let tsUrl = fileUrl.deletingPathExtension().appendingPathExtension("ts")
            if FileManager.default.fileExists(atPath: tsUrl.path) {
                fileUrl = LocalStreamServer.generateM3U8Synchronously(for: tsUrl)
            }
        }
        
        // 3. Dosya Doğrulaması
        guard FileManager.default.fileExists(atPath: fileUrl.path) else {
            print("[LocalStreamServer] 404 Bulunamadı: \(fileUrl.path)")
            send404(connection: connection)
            return
        }
        
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileUrl.path),
              let totalSize = attrs[.size] as? Int64, totalSize > 0 else {
            send404(connection: connection)
            return
        }
        
        let ext = fileUrl.pathExtension.lowercased()
        let mime = mimeType(for: ext)
        
        // 4. HEAD İsteği Yanıtı
        if isHeadOnly {
            let headHeader = """
            HTTP/1.1 200 OK\r\n\
            Content-Type: \(mime)\r\n\
            Content-Length: \(totalSize)\r\n\
            Accept-Ranges: bytes\r\n\
            Access-Control-Allow-Origin: *\r\n\
            Connection: close\r\n\
            \r\n
            """
            connection.send(content: headHeader.data(using: .utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ _ in }))
            return
        }
        
        // 5. Küçük Dosyalar (.m3u8 gibi küçük metin dosyaları tek seferde gönderilir)
        if ext == "m3u8" || totalSize < 512 * 1024 {
            if let data = try? Data(contentsOf: fileUrl) {
                let header = """
                HTTP/1.1 200 OK\r\n\
                Content-Type: \(mime)\r\n\
                Content-Length: \(data.count)\r\n\
                Accept-Ranges: bytes\r\n\
                Access-Control-Allow-Origin: *\r\n\
                Connection: close\r\n\
                \r\n
                """
                var fullRes = header.data(using: .utf8)!
                fullRes.append(data)
                connection.send(content: fullRes, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ _ in }))
                return
            }
        }
        
        // 6. Range Talebi (AVPlayer segmentleri parça parça talep eder)
        if let range = rangeHeader, range.hasPrefix("bytes=") {
            let spec = range.replacingOccurrences(of: "bytes=", with: "").trimmingCharacters(in: .whitespaces)
            let byteParts = spec.components(separatedBy: "-")
            
            var start: Int64 = 0
            var end: Int64 = totalSize - 1
            
            if let startVal = Int64(byteParts[0]) {
                start = max(0, min(startVal, totalSize - 1))
            }
            if byteParts.count > 1, !byteParts[1].isEmpty, let endVal = Int64(byteParts[1]) {
                end = max(start, min(endVal, totalSize - 1))
            }
            
            let length = end - start + 1
            let header = """
            HTTP/1.1 206 Partial Content\r\n\
            Content-Type: \(mime)\r\n\
            Content-Range: bytes \(start)-\(end)/\(totalSize)\r\n\
            Content-Length: \(length)\r\n\
            Accept-Ranges: bytes\r\n\
            Access-Control-Allow-Origin: *\r\n\
            Connection: close\r\n\
            \r\n
            """
            
            streamData(
                fileUrl: fileUrl,
                startOffset: UInt64(start),
                totalBytesToSend: length,
                headerString: header,
                connection: connection
            )
            return
        }
        
        // 7. Range Olmayan Büyük Dosya Doğrudan Akışı (Normal GET)
        let header = """
        HTTP/1.1 200 OK\r\n\
        Content-Type: \(mime)\r\n\
        Content-Length: \(totalSize)\r\n\
        Accept-Ranges: bytes\r\n\
        Access-Control-Allow-Origin: *\r\n\
        Connection: close\r\n\
        \r\n
        """
        
        streamData(
            fileUrl: fileUrl,
            startOffset: 0,
            totalBytesToSend: totalSize,
            headerString: header,
            connection: connection
        )
    }
    
    // MARK: - Kesintisiz & Bellek Dostu Parçalı Akış Gönderici
    private func streamData(
        fileUrl: URL,
        startOffset: UInt64,
        totalBytesToSend: Int64,
        headerString: String,
        connection: NWConnection
    ) {
        guard let handle = try? FileHandle(forReadingFrom: fileUrl) else {
            send500(connection: connection)
            return
        }
        
        guard let headerData = headerString.data(using: .utf8) else {
            try? handle.close()
            connection.cancel()
            return
        }
        
        // Önce HTTP Başlığını gönder
        connection.send(content: headerData, isComplete: false, completion: .contentProcessed({ [weak self] error in
            guard let self = self, error == nil else {
                try? handle.close()
                connection.cancel()
                return
            }
            
            self.sendNextChunk(
                handle: handle,
                currentOffset: startOffset,
                remainingBytes: totalBytesToSend,
                connection: connection
            )
        }))
    }
    
    private func sendNextChunk(
        handle: FileHandle,
        currentOffset: UInt64,
        remainingBytes: Int64,
        connection: NWConnection
    ) {
        guard remainingBytes > 0 else {
            try? handle.close()
            return
        }
        
        let chunkSize = min(256 * 1024, Int(remainingBytes))
        do {
            try handle.seek(toOffset: currentOffset)
            let chunk = handle.readData(ofLength: chunkSize)
            guard !chunk.isEmpty else {
                try? handle.close()
                return
            }
            
            let newOffset = currentOffset + UInt64(chunk.count)
            let newRemaining = remainingBytes - Int64(chunk.count)
            let isLast = (newRemaining == 0)
            
            connection.send(
                content: chunk,
                contentContext: isLast ? .finalMessage : .defaultMessage,
                isComplete: isLast,
                completion: .contentProcessed({ [weak self] error in
                    guard let self = self, error == nil else {
                        try? handle.close()
                        return
                    }
                    if isLast {
                        try? handle.close()
                        // .finalMessage ile TCP FIN tamamlanır; connection.cancel() çağırma (RST'yi önle!)
                    } else {
                        self.queue.async {
                            self.sendNextChunk(
                                handle: handle,
                                currentOffset: newOffset,
                                remainingBytes: newRemaining,
                                connection: connection
                            )
                        }
                    }
                })
            )
        } catch {
            try? handle.close()
        }
    }
    
    private func send404(connection: NWConnection) {
        let res = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: res.data(using: .utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ _ in }))
    }
    
    private func send400(connection: NWConnection) {
        let res = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: res.data(using: .utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ _ in }))
    }
    
    private func send500(connection: NWConnection) {
        let res = "HTTP/1.1 500 Internal Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: res.data(using: .utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ _ in }))
    }
    
    private func mimeType(for ext: String) -> String {
        switch ext {
        case "m3u8": return "application/vnd.apple.mpegurl"
        case "ts":   return "video/mp2t"
        case "mp4":  return "video/mp4"
        case "m4v":  return "video/mp4"
        case "mov":  return "video/quicktime"
        case "aac":  return "audio/aac"
        case "mp3":  return "audio/mpeg"
        default:     return "application/octet-stream"
        }
    }
}
