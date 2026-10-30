# MimuSinema - Netflix Stili iOS Film & Dizi Uygulaması

**MimuSinema**, özel HTTP Referer ve User-Agent destekli M3U listelerini işleyen, Netflix benzeri modern karanlık temaya ve **Glassmorphism (şeffaf & kavisli)** yüzen tab menüye sahip üst düzey bir iOS (SwiftUI) uygulamasıdır.

---

## 🌟 Yeni Eklenen Tasarım & Keşfet Özellikleri

### 1. Netflix Benzeri Sinematik Keşfet (Discover) Sayfası
- **Kayan Hero Header (Carousel Slider):** Sayfanın en üstünde Netflix tarzı büyük afişli, otomatik/parmakla kaydırılabilen öne çıkan film ve diziler yer alır.
  - Alttan yukarı pürüzsüz siyah gradyan geçişi.
  - Dublaj / Altyazı rozeti ve kategori başlığı.
  - Doğrudan **"Oynat"**, **"Listem (+ / Favori)"** ve **"İndir"** eylem butonları.
- **"Tamamını Gör" Yönlendirmesi:**
  - **Önerilen Filmler** başlığının yanındaki *"Tamamını Gör >"* butonuna dokunulduğunda doğrudan **Filmler** sekmesine geçer.
  - **Trend Diziler** başlığının yanındaki *"Tamamını Gör >"* butonuna dokunulduğunda doğrudan **Diziler** sekmesine geçer.

### 2. Glassmorphism Şeffaf ve Kavisli Tab Bar (`GlassmorphicTabBar`)
- Standart sistem tab çubuğu yerine iOS `ultraThinMaterial` ve koyu şeffaf katmandan oluşan, köşeleri oval (kapsül) **yüzen cam bar** tasarlandı.
- Cam kenarlığı (Glass Border) ve yumuşak derinlik gölgesiyle içeriklerin üzerinde şık bir şekilde süzülür.
- 5 Ana Sekme:
  1. 🌟 **Keşfet**
  2. 🎬 **Filmler**
  3. 📺 **Diziler**
  4. ❤️ **Favoriler**
  5. 📥 **İndirilenler**

### 3. Akıllı Veri & Performans (50'şerli Lazy Loading)
- M3U kaynakları arka planda okunur ve ekrana **50'şer 50'şer** verilir.
- Sayfa sonuna yaklaşıldıkça sonraki 50 öğe eklenir, uygulama hiçbir zaman donmaz veya belleği tüketmez.

### 4. Gelişmiş Video Oynatıcı (`CustomPlayerView`)
- Tam ekran & otomatik yatay (landscape) mod.
- Sağ ve sol basılı tutunca **2x hızlı oynatma**.
- Sağa çift tık: **+5 sn**, sola çift tık: **-5 sn**.
- Kontroller dokunma olmadığında 3.5 sn içinde gizlenir.
- **Boyut butonu:** Fit, Fill ve Stretch modları.
- Dizilerde **"Sonraki Bölüm"** butonu.

### 5. Güvenli Silme & Klasör Temizliği
- İndirilen film ve diziler onay penceresiyle ("Emin misiniz?") silinir.
- Dizi silindiğinde veya tüm bölümleri bittiğinde `Documents/Series/<Dizi_Adı>` klasörü cihazdan kalıcı olarak yok edilir.
