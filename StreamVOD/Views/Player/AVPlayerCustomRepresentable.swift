import SwiftUI
import AVKit

public enum VideoAspectRatioMode: String, CaseIterable {
    case fit = "En/Boy Koru (Fit)"
    case fill = "Ekranı Doldur (Fill)"
    case stretch = "Uzat (Stretch)"
    
    public var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fit: return .resizeAspect
        case .fill: return .resizeAspectFill
        case .stretch: return .resize
        }
    }
    
    public var icon: String {
        switch self {
        case .fit: return "arrow.down.right.and.arrow.up.left"
        case .fill: return "arrow.up.left.and.arrow.down.right.full"
        case .stretch: return "aspectratio"
        }
    }
}

public struct AVPlayerCustomRepresentable: UIViewControllerRepresentable {
    public let player: AVPlayer
    public var videoGravity: AVLayerVideoGravity
    
    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false // Kendi özel arayüzümüzü kullanıyoruz
        controller.videoGravity = videoGravity
        return controller
    }
    
    public func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
        uiViewController.videoGravity = videoGravity
    }
}
