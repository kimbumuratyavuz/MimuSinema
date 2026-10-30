import SwiftUI

public struct UpdateDialogView: View {
    @ObservedObject private var updateService = AppUpdateService.shared
    
    public var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                // İkon
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.red)
                }
                
                VStack(spacing: 4) {
                    Text("Yeni Sürüm Mevcut!")
                        .font(.headline)
                        .fontWeight(.black)
                        .foregroundColor(.white)
                    
                    Text("MimuSinema \(updateService.latestVersionTag)")
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .fontWeight(.bold)
                    
                    Text("Yüklü Sürümünüz: v\(updateService.currentVersion)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                
                // Güncelleme Notları
                if !updateService.releaseNotes.isEmpty {
                    ScrollView {
                        Text(updateService.releaseNotes)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(maxHeight: 100)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                }
                
                // Bilgilendirme Notu
                Text("Yeni sürümü bilgisayardan (Sideloadly) veya telefonunuzdaki AltStore/SideStore/TrollStore ile güncelleyebilirsiniz.")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                
                // Eylem Butonları
                VStack(spacing: 8) {
                    // 1. RELEASES & IPA SAYFASINA GİT BUTONU
                    Button(action: {
                        if let url = updateService.releasePageUrl ?? updateService.ipaDownloadUrl {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "safari.fill")
                            Text("GitHub'da Güncellemeyi Aç")
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    
                    // 2. BU SÜRÜMÜ BİR DAHA GÖSTERME
                    Button(action: {
                        withAnimation {
                            updateService.skipThisVersion()
                        }
                    }) {
                        Text("Bu Sürümü Bir Daha Gösterme")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.9))
                            .padding(.vertical, 4)
                    }
                    
                    // 3. KAPAT
                    Button(action: {
                        withAnimation {
                            updateService.hasUpdate = false
                        }
                    }) {
                        Text("Kapat")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.7))
                    }
                }
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.13))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 32)
            .shadow(color: .black.opacity(0.85), radius: 25)
        }
    }
}
