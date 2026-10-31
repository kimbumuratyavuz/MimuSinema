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
                let lastComp = URL(fileURLWithPath: relPath).lastPathComponent
                let inMoviesByName = documentsDirectory.appendingPathComponent("Movies").appendingPathComponent(lastComp)
                if FileManager.default.fileExists(atPath: inMoviesByName.path) {
                    fileUrl = inMoviesByName
                }
            }
        }
        
        // 2. Dosya .m3u8 istenmiş ama henüz yoksa fakat .ts dosyası varsa: Anında dinamik M3U8 üret!
        if relPath.lowercased().hasSuffix(".m3u8") && !FileManager.default.fileExists(atPath: fileUrl.path) {
            let tsUrl = fileUrl.deletingPathExtension().appendingPathExtension("ts")
            if FileManager.default.fileExists(atPath: tsUrl.path) {
                let tsFileName = tsUrl.lastPathComponent
                let dynamicM3U8 = """
                #EXTM3U
                #EXT-X-VERSION:3
                #EXT-X-TARGETDURATION:7200
                #EXT-X-MEDIA-SEQUENCE:0
                #EXT-X-PLAYLIST-TYPE:VOD
                #EXTINF:7200.0,
                \(tsFileName)
                #EXT-X-ENDLIST
                """
                if let m3u8Data = dynamicM3U8.data(using: .utf8) {
                    sendData(m3u8Data, contentType: "application/vnd.apple.mpegurl", connection: connection, isHeadOnly: isHeadOnly)
                    return
                }
            }
        }
        
        // 3. Normal Dosya Kontrolü
        guard FileManager.default.fileExists(atPath: fileUrl.path) else {
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
        
        // Range Talebi (AVPlayer parça parça talep eder - RAM şişmesini önlemek için 2MB parçalarla yanıt verilir)
        if let range = rangeHeader, range.hasPrefix("bytes=") {
            let spec = range.replacingOccurrences(of: "bytes=", with: "").trimmingCharacters(in: .whitespaces)
            let byteParts = spec.components(separatedBy: "-")
            
            var start: Int64 = 0
            var end: Int64 = totalSize - 1
            
            if let startVal = Int64(byteParts[0]) {
                start = max(0, min(startVal, totalSize - 1))
            }
            if byteParts.count > 1, let endVal = Int64(byteParts[1]) {
                end = max(start, min(endVal, totalSize - 1))
            }
            
            // RAM patlamasını önle: En fazla 2 MB parça oku
            let maxChunk: Int64 = 2 * 1024 * 1024
            let length = min(end - start + 1, maxChunk)
            let actualEnd = start + length - 1
            
            if isHeadOnly {
                let header = """
                HTTP/1.1 206 Partial Content\r\n\
                Content-Type: \(mime)\r\n\
                Content-Range: bytes \(start)-\(actualEnd)/\(totalSize)\r\n\
                Content-Length: \(length)\r\n\
                Accept-Ranges: bytes\r\n\
                Access-Control-Allow-Origin: *\r\n\
                Connection: close\r\n\
                \r\n
                """
                connection.send(content: header.data(using: .utf8), completion: .contentProcessed({ _ in connection.cancel() }))
                return
            }
            
            guard let handle = try? FileHandle(forReadingFrom: fileUrl) else {
                send500(connection: connection)
                return
            }
            
            defer { try? handle.close() }
            
            do {
                try handle.seek(toOffset: UInt64(start))
                let slice = handle.readData(ofLength: Int(length))
                
                let header = """
                HTTP/1.1 206 Partial Content\r\n\
                Content-Type: \(mime)\r\n\
                Content-Range: bytes \(start)-\(actualEnd)/\(totalSize)\r\n\
                Content-Length: \(slice.count)\r\n\
                Accept-Ranges: bytes\r\n\
                Access-Control-Allow-Origin: *\r\n\
                Connection: close\r\n\
                \r\n
                """
                var res = header.data(using: .utf8)!
                res.append(slice)
                connection.send(content: res, completion: .contentProcessed({ _ in connection.cancel() }))
            } catch {
                send500(connection: connection)
            }
            return
        }
        
        // Range Olmayan Doğrudan Gönderim
        if ext == "m3u8" || totalSize < 5 * 1024 * 1024 {
            if let data = try? Data(contentsOf: fileUrl) {
                sendData(data, contentType: mime, connection: connection, isHeadOnly: isHeadOnly)
            } else {
                send500(connection: connection)
            }
        } else {
            // Büyük dosyalarda ilk parça ile 200 OK yanıtı ver
            guard let handle = try? FileHandle(forReadingFrom: fileUrl) else {
                send500(connection: connection)
                return
            }
            defer { try? handle.close() }
            
            let header = """
            HTTP/1.1 200 OK\r\n\
            Content-Type: \(mime)\r\n\
            Content-Length: \(totalSize)\r\n\
            Accept-Ranges: bytes\r\n\
            Access-Control-Allow-Origin: *\r\n\
            Connection: close\r\n\
            \r\n
            """
            
            if isHeadOnly {
                connection.send(content: header.data(using: .utf8), completion: .contentProcessed({ _ in connection.cancel() }))
                return
            }
            
            let initialSlice = handle.readData(ofLength: 512 * 1024)
            var res = header.data(using: .utf8)!
            res.append(initialSlice)
            connection.send(content: res, completion: .contentProcessed({ _ in connection.cancel() }))
        }
    }
    
    private func sendData(_ data: Data, contentType: String, connection: NWConnection, isHeadOnly: Bool) {
        let header = """
        HTTP/1.1 200 OK\r\n\
        Content-Type: \(contentType)\r\n\
        Content-Length: \(data.count)\r\n\
        Accept-Ranges: bytes\r\n\
        Access-Control-Allow-Origin: *\r\n\
        Connection: close\r\n\
        \r\n
        """
        var res = header.data(using: .utf8)!
        if !isHeadOnly {
            res.append(data)
        }
        connection.send(content: res, completion: .contentProcessed({ _ in connection.cancel() }))
    }
    
    private func send404(connection: NWConnection) {
        let res = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: res.data(using: .utf8), completion: .contentProcessed({ _ in connection.cancel() }))
    }
    
    private func send400(connection: NWConnection) {
        let res = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: res.data(using: .utf8), completion: .contentProcessed({ _ in connection.cancel() }))
    }
    
    private func send500(connection: NWConnection) {
        let res = "HTTP/1.1 500 Internal Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: res.data(using: .utf8), completion: .contentProcessed({ _ in connection.cancel() }))
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
