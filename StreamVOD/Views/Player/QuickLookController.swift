import SwiftUI
import QuickLook

/// Apple'ın yerel Dosyalar (Files) uygulamasında kullanılan ve .ts / MPEG-TS dahil
/// tüm yerel video formatlarını donanımsal olarak sorunsuz oynatan QuickLook video oynatıcısı.
public struct QuickLookController: UIViewControllerRepresentable {
    public let url: URL
    public var onDismiss: (() -> Void)? = nil
    
    public init(url: URL, onDismiss: (() -> Void)? = nil) {
        self.url = url
        self.onDismiss = onDismiss
    }
    
    public func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        return controller
    }
    
    public func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    public class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let parent: QuickLookController
        
        init(parent: QuickLookController) {
            self.parent = parent
        }
        
        public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }
        
        public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return parent.url as NSURL
        }
        
        public func previewControllerDidDismiss(_ controller: QLPreviewController) {
            parent.onDismiss?()
        }
    }
}
