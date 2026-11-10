# Değişiklik günlüğü

Akıntı'daki tüm önemli değişiklikler bu dosyada yer alır. Biçim [Keep a Changelog](https://keepachangelog.com/tr-TR/1.1.0/) düzenini, sürüm numaraları [Anlamsal Sürümleme](https://semver.org/lang/tr/) kurallarını izler.

Yeni bir sürüm yayınlamadan önce değişiklikleri **Yayınlanmamış** başlığının altına yazın; sürüm etiketi gönderilirken bu bölüm `## [x.y.z] - tarih` olarak adlandırılır ve GitHub sürüm notları buradan otomatik oluşturulur.

## [Yayınlanmamış]

## [0.10.3] - 2026-11-10

### Düzeltildi
- **Chrome eklentisi kurulurken klasörün bulunamaması.** Eklenti gizli Kitaplık klasörüne konuyordu ve Chrome'un dosya seçicisinde görünmüyordu. Artık **Belgeler → Akıntı Eklentisi** klasörüne konur.

### Eklendi
- Akıntı güncellenince kurulu eklenti klasörü de kendiliğinden güncellenir.
- Ayarlar → Tarayıcı eklentisi: **Eklentiyi hazırla** ve **Chrome'da eklentileri aç** düğmeleri, adım adım kurulum.

## [0.10.2] - 2026-11-10

### Düzeltildi
- **Menü çubuğu simgesi vurgulanıyor ama panel açılmıyordu** (özellikle Sahne Yöneticisi açıkken ve Akıntı yalnızca menü çubuğunda çalışırken). SwiftUI'nin MenuBarExtra'sı paneli ayrı bir pencere olarak açıyordu; bu pencere ekrana gelmeyebiliyordu. Menü çubuğu artık macOS'un klasik yöntemiyle çalışıyor: kendi menü çubuğu öğesi (NSStatusItem) ve simgeye bağlı açılır pencere (NSPopover). Barbee/Bartender gibi düzenleyiciler simgenin yerini hatırlar.
- Menü çubuğu kipinde “Akıntı'yı aç”, “Ayarlar…” ve eklentiden gelen bağlantılar ana pencereyi güvenilir şekilde açar.

## [0.10.1] - 2026-11-10

### Düzeltildi
- **Dock'tan "Çık" dedikten sonra menü çubuğu simgesine tıklayınca panelin açılmaması.** Dock'un "çık" komutu, uygulamanın kapanma süreci başladıktan sonra iptal ediliyordu; SwiftUI bu sırada sahnelerini kapatmaya hazırlandığı için simge kalsa da paneli çalışmıyordu. Komut artık kapanma hiç başlamadan karşılanıyor. ⌘Q, menüden “Akıntı'dan çık”, oturum kapatma ve yeniden başlatma eskisi gibi gerçekten kapatır.

## [0.10.0] - 2026-11-10

### Eklendi
- **Chrome eklentisi** (Brave, Edge, Arc, Chromium, Vivaldi'de de çalışır; Manifest V3, Türkçe/İngilizce):
  - Sağ tık → “Akıntı ile indir” (bağlantı, video/ses, seçili bağlantılar, sayfa).
  - Araç çubuğu paneli: bağlantı durumu, “Bu videoyu/sayfayı Akıntı'ya gönder”, indirme yakalamayı aç/kapat.
  - **IDM gibi indirme yakalama**: seçilen türlerdeki Chrome indirmeleri Akıntı'ya aktarılır; Akıntı'ya ulaşılamazsa indirme Chrome'da sürer.
  - Ayarlar sayfası: dosya türleri, en küçük boyut, hariç tutulan siteler, bildirimler.
- **Native Messaging köprüsü** (`akinti-bridge`): eklenti Akıntı ile açılır pencere çıkmadan konuşur; Akıntı açılınca kurulu Chromium tarayıcılarına kendini kaydeder. Köprü yalnızca Akıntı eklentisinin sabit kimliğine yanıt verir ve yalnızca http/https/magnet bağlantılarını iletir.
- `akinti://add` bağlantıları: gelen bağlantılar her zaman önce ekleme penceresinde gösterilir. Ana pencere kapalıysa (menü çubuğu kipi dahil) açılır.
- HTTP indirmelerinde tarayıcıdan gelen **Referer ve User-Agent** gönderilir.
- Ayarlar → **Tarayıcı eklentisi** bölümü; sürümlerde ayrı `Akinti-Chrome-Extension.zip`.
- Testler: köprü programı, bağlantı biçimi ve güvenliği, tarayıcı kaydı, eklenti kimliği; eklenti için Node testleri (CI'da çalışır).

## [0.9.0] - 2026-11-10

### Eklendi
- **Homebrew'suz kurulum.** Akıntı artık ek bir kurulum gerektirmeden çalışır:
  - **Torrent desteği (aria2) uygulamanın içinde gelir**; kütüphaneleri pakete gömülüdür, HTTPS tracker'lar için macOS'un sertifika listesi kullanılır.
  - **yt-dlp ve FFmpeg tek tıkla kurulur**: ilk video bağlantısında ekleme penceresindeki **Kur** düğmesi veya Ayarlar → Bileşenler.
  - yt-dlp resmi GitHub sürümünden indirilir ve SHA-256 ile doğrulanır; FFmpeg yalnızca geliştiricisinin Apple onaylı imzası doğrulanırsa kurulur.
  - **yt-dlp otomatik güncellenir** (günde bir kez denetlenir; Ayarlar'dan kapatılabilir).
- Ayarlar → **Bileşenler** bölümü: her bileşenin durumu, Kur/Güncelle düğmeleri, **Lisanslar…**
- `Licenses/` klasörü: üçüncü taraf lisansları ve kaynak kodu bağlantıları.

### Değişti
- Araç arama sırası: Akıntı'nın kurdukları → uygulamanın içindekiler → Homebrew.
- Uygulama boyutu aria2 nedeniyle ~6 MB (zip) oldu.

## [0.8.2] - 2026-11-08

### Değişti
- **Dock'tan "Çık" denince Akıntı kapanmaz**: pencereler kapanır, Dock simgesi gizlenir, menü çubuğu simgesi ve indirmeler sürer. Tamamen kapatmak için menü çubuğundaki **Akıntı'dan çık** ya da **⌘Q**. Oturum kapatma, yeniden başlatma ve kapatmada her zaman normal şekilde kapanır.
- Ayarlar → Menü çubuğu ve başlangıç: “Dock’tan çıkınca menü çubuğunda çalışmaya devam et” (varsayılan açık).

## [0.8.1] - 2026-11-08

### Düzeltildi
- Menü çubuğu simgesine ikinci kez tıklayınca panelin açılmaması: uygulamanın en üst yapısı artık indirme listesindeki her değişiklikte yeniden kurulmuyor; yalnızca menü çubuğu ayarı ve dil değişince güncelleniyor.
- Bu sayede indirme sırasında menüler ve menü çubuğu öğesi saniyede birkaç kez yeniden oluşturulmuyor (daha düşük işlemci kullanımı).

## [0.8.0] - 2026-11-08

### Eklendi
- **Menü çubuğu (üst bar) simgesi**: indirme varken yanında anlık toplam hız.
- Simgeye tıklayınca açılan panel: aktif indirmeler ve ilerlemeleri, tek tek duraklat/devam, Tümünü başlat/duraklat, hız sınırı, bağlantı ekle, Akıntı'yı aç, Ayarlar, Çık.
- **Yalnızca menü çubuğunda çalışma** seçeneği: ana pencere kapanınca Dock simgesi gizlenir, indirmeler sürer (varsayılan kapalı).
- **Mac açılınca Akıntı'yı başlat** seçeneği (macOS Giriş Öğeleri).
- Ayarlar → Menü çubuğu ve başlangıç bölümü.

### Düzeltildi
- Uygulamanın açılışta ara sıra çökmesi (SwiftUI gövdesi sadeleştirildi; menü komutları ayrı yapıya taşındı).
- Menü çubuğu öğesinin ayarı sürekli yeniden yazmasıyla oluşan yüksek işlemci kullanımı.
- Değişmeyen ayarların gereksiz yere diske yazılması.

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

[Yayınlanmamış]: https://github.com/future01software/akinti/compare/v0.10.3...HEAD
[0.10.3]: https://github.com/future01software/akinti/releases/tag/v0.10.3
[0.10.2]: https://github.com/future01software/akinti/releases/tag/v0.10.2
[0.10.1]: https://github.com/future01software/akinti/releases/tag/v0.10.1
[0.10.0]: https://github.com/future01software/akinti/releases/tag/v0.10.0
[0.9.0]: https://github.com/future01software/akinti/releases/tag/v0.9.0
[0.8.2]: https://github.com/future01software/akinti/releases/tag/v0.8.2
[0.8.1]: https://github.com/future01software/akinti/releases/tag/v0.8.1
[0.8.0]: https://github.com/future01software/akinti/releases/tag/v0.8.0
[0.7.0]: https://github.com/future01software/akinti/releases/tag/v0.7.0
