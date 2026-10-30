import SwiftUI

public struct UpdateDialogView: View {
    @ObservedObject private var updateService = AppUpdateService.shared
    
    public var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 18) {
                // İkon
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 70, height: 70)
                    
                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: 34))
                        .foregroundColor(.red)
                }
                
                VStack(spacing: 6) {
                    Text("Yeni Sürüm Mevcut!")
                        .font(.title3)
                        .fontWeight(.black)
                        .foregroundColor(.white)
                    
                    Text("MimuSinema \(updateService.latestVersionTag) hazır.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    Text("Mevcut Sürüm: v\(updateService.currentVersion)")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.8))
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
                    .frame(maxHeight: 120)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                }
                
                // Eylem Butonları
                VStack(spacing: 10) {
                    // İNDİR VE GÜNCELLE BUTONU
                    Button(action: {
                        if let url = updateService.ipaDownloadUrl ?? updateService.releasePageUrl {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Yeni Sürümü İndir (.ipa)")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    
                    // DAHA SONRA BUTONU
                    Button(action: {
                        withAnimation {
                            updateService.hasUpdate = false
                        }
                    }) {
                        Text("Daha Sonra")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.vertical, 6)
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.13))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 36)
            .shadow(color: .black.opacity(0.8), radius: 25)
        }
    }
}
