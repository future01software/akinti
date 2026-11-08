# Değişiklik günlüğü

Akıntı'daki tüm önemli değişiklikler bu dosyada yer alır. Biçim [Keep a Changelog](https://keepachangelog.com/tr-TR/1.1.0/) düzenini, sürüm numaraları [Anlamsal Sürümleme](https://semver.org/lang/tr/) kurallarını izler.

Yeni bir sürüm yayınlamadan önce değişiklikleri **Yayınlanmamış** başlığının altına yazın; sürüm etiketi gönderilirken bu bölüm `## [x.y.z] - tarih` olarak adlandırılır ve GitHub sürüm notları buradan otomatik oluşturulur.

## [Yayınlanmamış]

## [0.7.0] - 2026-11-08

### Eklendi
- **Torrent ve magnet desteği** ([aria2](https://aria2.github.io) ile; `brew install aria2`).
  - Magnet bağlantısı yapıştırma, `.torrent` dosyasını pencereye sürükleme, **Dosya → Torrent dosyası aç… (⌘O)**.
  - Tarayıcıda magnet bağlantısına tıklayınca Akıntı açılır; güvenlik için önce ekleme penceresi gösterilir.
  - Finder'da `.torrent` dosyasını Akıntı ile açma.
  - Yeni **Torrentler** kategorisi.
  - Ayrıntı panelinde ve indirme penceresinde **parça haritası** ile **kaynak / eş** sayısı.
  - Duraklat/devam; uygulama yeniden açıldığında kaldığı yerden sürme.
  - İsteğe bağlı paylaşım (seed): Ayarlar → Torrent (varsayılan kapalı).
- Torrent testleri: yerel tracker ve paylaşımcı ile internet gerektirmeyen gerçek aktarım.

### Değişti
- aria2, Akıntı kapanınca kendiliğinden kapanır; arka planda süreç kalmaz.
- CI: testler ayrı süreçlerde (`--parallel`) ve süre sınırıyla çalışır; sürüm işi testleri tekrarlamaz.

### Düzeltildi
- macOS'un önceki oturumdan boş "hayalet" indirme pencereleri geri yüklemesi.

## [0.6.0] - 2026-11-08

### Eklendi
- **IDM tarzı indirme penceresi**: indirme başlayınca açılır; parçalı çubuk, hız, kalan süre, bağlantı sayısı, Duraklat/İptal/Gizle.
- İndirme bitince **"İndirme tamamlandı"** ekranı (Aç, Finder'da göster).
- "Bu pencereyi bir daha gösterme" seçeneği ve Ayarlar anahtarı.
- **GitHub Releases**: `v*` etiketiyle otomatik paketleme ve yayın; sabit dosya adı (`Akinti-macOS.zip`) sayesinde "en son sürümü indir" bağlantısı.
- README'ye uygulama simgesi ve ekran görüntüleri.

### Değişti
- Sürüm numarası git etiketinden gelir; Ayarlar sürümü uygulamanın kendisinden okur.

### Düzeltildi
- GitHub'daki eski Swift sürümünde derleme hatası (`main.swift` → `AkintiApp.swift`).
- Uygulama açılırken eklenen indirmelerde pencerenin açılmaması; aynı anda birden fazla pencerenin açılamaması.

> Not: v0.6.0 etiketi için GitHub sürümü yayınlanamadı (sürüm işi takıldı ve iptal edildi). Bu sürümün tüm içeriği 0.7.0'da yer alır.

## [0.5.0] - 2026-11-08

### Eklendi
- **Çok bağlantılı (parçalı) indirme**: sunucu destekliyorsa dosya 1–16 parçaya bölünüp aynı anda indirilir (varsayılan 8).
- Parça bazında devam: duraklatınca veya uygulama kapanınca her parçanın kaldığı yer kaydedilir.
- Ayrıntı panelinde her bağlantının ilerlemesini gösteren **parçalı çubuk**.
- **Toplam hız sınırı** (Sınırsız … 25 MB/sn); alt çubuktan hızlı seçim. Video indirmelerinde yt-dlp `--limit-rate`.
- **Oynatma listeleri**: YouTube listesi, SoundCloud seti, Bandcamp albümü; her video ayrı indirme olarak eklenir.
- Geliştirici başlatma seçenekleri: `--state-dir`, `--add`, `--select-first`, `--open-settings`.

### Değişti
- HTTP indirme motoru baştan yazıldı (URLSession veri görevleri, tek seri kuyrukta dosya yazma).
- Aktif indirmelerin ilerlemesi 5 saniyede bir kaydedilir.

### Düzeltildi
- İngilizce arayüzde yüzde biçimi (`34%`) ve hız sınırı etiketi (`5 MB/s`).
- Ayarlar penceresinin programla açılamaması.

## [0.4.1] - 2026-11-08

### Eklendi
- **Uygulama simgesi**: dalgalı mavi su yüzeyine inen indirme oku (`scripts/make-icon.swift` ile çizilir).

### Düzeltildi
- Video duraklatılıp hemen sürdürülünce aynı dosyaya ikinci yt-dlp başlaması.
- Uygulamadan çıkınca yt-dlp'nin arka planda çalışmaya devam etmesi.
- yt-dlp çıktısı kapanırken boşa işlemci kullanımı.
- Ekleme penceresinde her tuş vuruşunda yt-dlp çalıştırılması.
- yt-dlp'ye verilen bağlantının seçenek olarak yorumlanabilmesi (`--`).

## [0.4.0] - 2026-11-08

### Eklendi
- **YouTube ve video siteleri** ([yt-dlp](https://github.com/yt-dlp/yt-dlp) ile; `brew install yt-dlp ffmpeg`).
- Ekleme penceresinde başlık, süre ve küçük resim önizlemesi.
- Kalite seçimi (En iyi, 4K, 1080p, 720p, 480p) ve yalnızca ses (M4A/MP3).
- Bağlantı türü: Otomatik / Dosya / Video sayfası.

### Değişti
- Video indirmeleri QuickTime ile uyumlu olsun diye aynı çözünürlükte H.264 + AAC tercih edilir.

## [0.3.0] - 2026-11-08

### Eklendi
- **IDM düzeninde, macOS tarzında yeni arayüz**: kategoriler, durum grupları, sıralanabilir sütunlar (Dosya adı, Boyut, Durum, Hız, Kalan süre, Eklenme), ayrıntı paneli, durum çubuğu.
- Kopyalanan indirme bağlantılarını yakalama ve pencereye sürükle-bırak.
- Çoklu seçim, sağ tık menüsü, çift tıkla açma, "Sonra indir", dosyayı Çöp Sepeti'ne taşıyarak silme.
- Dock simgesinde aktif indirme sayısı; ⌘N, ⇧⌘R, ⇧⌘P kısayolları.
- **Türkçe / English** dil seçeneği (Ayarlar → Dil).

### Değişti
- "Nasıl kullanılır?" kenar çubuğundan Ayarlar'a ve Yardım menüsüne taşındı; alt çubuk yazıları büyütüldü.

## [0.2.0] - 2026-11-08

### Eklendi
- Ayarlar ekranı: indirme klasörü, eşzamanlı indirme sayısı, otomatik yeniden deneme, tema.
- Uygulama içi "Nasıl kullanılır?" rehberi.

## [0.1.0] - 2026-11-08

### Eklendi
- İlk sürüm: HTTP/HTTPS indirme, kuyruk, duraklat/devam, planlı başlatma, otomatik yeniden deneme, geçmiş ve arama.

[Yayınlanmamış]: https://github.com/future01software/akinti/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/future01software/akinti/releases/tag/v0.7.0
