import SwiftUI
import Combine

public final class ImageCacheService {
    public static let shared = ImageCacheService()
    private let cache = NSCache<NSString, UIImage>()
    
    private init() {
        cache.countLimit = 250 // Bellekte 250 afiş tut
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB RAM
    }
    
    public func image(for url: String) -> UIImage? {
        cache.object(forKey: url as NSString)
    }
    
    public func insertImage(_ image: UIImage, for url: String) {
        cache.setObject(image, forKey: url as NSString)
    }
}

public struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let urlString: String?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    
    @State private var loadedImage: UIImage? = nil
    @State private var isLoading: Bool = false
    
    public init(
        urlString: String?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.urlString = urlString
        self.content = content
        self.placeholder = placeholder
    }
    
    public var body: some View {
        Group {
            if let image = loadedImage {
                content(Image(uiImage: image))
            } else {
                placeholder()
                    .onAppear {
                        loadImage()
                    }
            }
        }
    }
    
    private func loadImage() {
        guard let urlStr = urlString, let url = URL(string: urlStr) else { return }
        
        // 1. RAM Cache Kontrolü (0 ms)
        if let cached = ImageCacheService.shared.image(for: urlStr) {
            self.loadedImage = cached
            return
        }
        
        // 2. Asenkron Hızlı URLSession İndirme
        guard !isLoading else { return }
        isLoading = true
        
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, let uiImage = UIImage(data: data) else { return }
            
            ImageCacheService.shared.insertImage(uiImage, for: urlStr)
            DispatchQueue.main.async {
                self.loadedImage = uiImage
                self.isLoading = false
            }
        }.resume()
    }
}
