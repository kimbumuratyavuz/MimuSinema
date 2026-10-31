import SwiftUI
import AVFoundation

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.allButUpsideDown

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // SES SİSTEMİ YAPILANDIRMASI (Telefon sessiz modda olsa bile sesin gelmesini sağlar)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AVAudioSession error: \(error.localizedDescription)")
        }
        
        // Yerel HTTP Stream Sunucusunu başlat (İndirilen HLS/.ts videolarının offline kusursuz oynatımı için)
        _ = LocalStreamServer.shared
        
        return true
    }
}

@main
struct MimuSinemaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark)
                .edgesIgnoringSafeArea(.all)
        }
    }
}
