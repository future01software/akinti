<p align="center"><img src="Assets/AppIcon-1024.png" width="128" alt="Akıntı simgesi"></p>

# Akıntı

Apple Silicon Mac için SwiftUI ile geliştirilen açık kaynak indirme yöneticisi. Doğrudan dosya bağlantılarının yanında YouTube ve diğer video sitelerinden de indirir. MIT lisanslıdır. macOS 14 veya üzeri gerekir.

<p align="center"><img src="docs/ekran-ana.png" alt="Akıntı ana penceresi: kategoriler, çok bağlantılı indirmeler ve parçalı ilerleme çubuğu"></p>

| YouTube ve video siteleri | Ayarlar |
|---|---|
| <img src="docs/ekran-video.png" alt="Bir YouTube videosunun önizlemesini ve kalite seçimini gösteren ekleme penceresi"> | <img src="docs/ekran-ayarlar.png" alt="Dil, bağlantı sayısı ve hız sınırı ayarları"> |

<p align="center"><img src="docs/screen-english-light.png" width="80%" alt="English interface in light mode"><br><sub>İngilizce arayüz, açık tema</sub></p>

## Çalıştırma

Swift araçları (Xcode veya Command Line Tools) kuruluysa:

```sh
swift run Akinti
```

Uygulama paketi oluşturmak için:

```sh
./scripts/bundle.sh
open dist/Akıntı.app
```

Paket yerel ad hoc imzalıdır; dağıtım için Developer ID imzası ve notarizasyon henüz yapılmamıştır.

## Çok bağlantılı hızlı indirme

Sunucu bayt aralıklarını (HTTP Range) destekliyorsa dosya parçalara bölünür ve her parça ayrı bir bağlantıyla aynı anda indirilir (varsayılan 8, ayarlardan 1–16). Ayrıntı panelindeki parçalı çubuk her bağlantının ilerlemesini gösterir. Duraklatınca veya uygulama kapanınca her parçanın kaldığı yer kaydedilir; devam edince yalnızca eksik kısımlar iner. Sunucu aralıkları desteklemiyorsa tek bağlantıya geçilir. Yarım dosyalar `~/Library/Application Support/Akinti/partial` içinde tutulur.

## Hız sınırı

Alt çubuktaki hız göstergesinden veya Ayarlar’dan toplam hız sınırı seçilir (Sınırsız, 256 KB/sn … 25 MB/sn). Sınır tüm HTTP indirmelerine anında uygulanır; video indirmelerinde yeni başlayanlara yt-dlp’nin `--limit-rate` seçeneğiyle uygulanır.

## Video siteleri (YouTube, Vimeo…)

Video sayfası bağlantıları [yt-dlp](https://github.com/yt-dlp/yt-dlp) ile indirilir. Bir kez kurun:

```sh
brew install yt-dlp ffmpeg
```

Bağlantıyı yapıştırınca Akıntı başlığı, süreyi ve küçük resmi gösterir; kalite (En iyi, 4K, 1080p, 720p, 480p) veya yalnızca ses (M4A/MP3) seçilir. YouTube, Vimeo, Dailymotion, X, Instagram, TikTok, Twitch, SoundCloud gibi siteler otomatik tanınır; diğer siteler için ekleme penceresinde **Bağlantı türü → Video sayfası** seçilir. ffmpeg olmadan yüksek kalitede görüntü ve ses birleştirilemez (tek dosyalık sürüm indirilir). Duraklatılan video yeniden başlatıldığında yt-dlp yarım dosyadan devam eder.

**Oynatma listeleri:** YouTube listesi (`list=`), SoundCloud seti, Bandcamp albümü gibi bağlantılarda liste okunur ve her video listeye ayrı bir indirme olarak eklenir. Hem tek video hem liste içeren bağlantılarda (`watch?v=…&list=…`) “Oynatma listesinin tamamını indir” seçeneği çıkar.

Yalnızca indirme hakkınız olan içerikleri indirin; YouTube’un kullanım koşulları izinsiz indirmeyi genel olarak yasaklar.

## Arayüz

IDM düzeninde, macOS'un kendi bileşenleriyle: solda **kategoriler** (Arşivler, Belgeler, Müzik, Videolar, Görseller, Programlar, Diğer) ve **durum** grupları; ortada sıralanabilir sütunlu liste (Dosya adı, Boyut, Durum, Hız, Kalan süre, Eklenme); seçili indirme için alt ayrıntı paneli; altta toplam hız ve kuyruk özeti. Araç çubuğunda Ekle / Devam / Duraklat / Kaldır, kuyruk menüsü ve arama bulunur. Dock simgesinde aktif indirme sayısı görünür.

## Mevcut özellikler

- Gerçek HTTP/HTTPS dosya indirme, toplu bağlantı ekleme
- 1–8 eşzamanlı indirme ve kuyruk
- Duraklatma, devam etme ve elle yeniden deneme
- Tarih/saat ile planlama (uygulama açık ve Mac uyanık olmalı)
- Geçici ağ hataları ve HTTP 408/429/500/502/503/504 için artan bekleme süreleriyle otomatik yeniden deneme (varsayılan 3, ayarlardan 0–5)
- İlerleme ve aktarılan boyut gösterimi
- Kalıcı geçmiş, arama ve durum filtreleri
- Finder’da dosyayı gösterme, aynı adlı dosyaların üzerine yazmama
- Ayarlar ekranı: klasör seçimi, kalıcı eşzamanlı indirme sayısı, 0–5 otomatik tekrar ve sistem/açık/koyu tema
- Uygulama içi adım adım kullanım rehberi
- Kopyalanan dosya bağlantılarını yakalama (ayarlardan kapatılabilir) ve pencereye sürükle-bırak
- Anlık hız ve kalan süre, çoklu seçim, sağ tık menüsü, çift tıkla açma
- “Sonra indir” (duraklatılmış ekleme), kuyruktaki öğeleri duraklatma, tamamlananları temizleme
- Silerken dosyayı Çöp Sepeti’ne taşıma seçeneği (geri alınabilir)
- Türkçe / English dil seçeneği (Ayarlar → Dil)
- Kısayollar: ⌘N bağlantı ekle, ⇧⌘R tümünü başlat, ⇧⌘P tümünü duraklat, ⌫ seçileni kaldır

Varsayılan olarak dosyalar `~/Downloads/Akıntı` klasörüne, geçmiş `~/Library/Application Support/Akinti/downloads.json` dosyasına kaydedilir. Bağlantılar geçmişte tutulur; gizli bağlantıları paylaşmayın. Devam etme URLSession ve sunucu desteğine bağlıdır; desteklenmezse indirme baştan başlayabilir. Uygulamadan çıkarken aktif indirmeler sonlandırılır; sonraki açılışta elle devam ettirilir.

## Kullanım

1. **Bağlantı ekle** düğmesine basın. Web sayfası adresi yerine doğrudan dosya bağlantısını yapıştırın; her satıra bir bağlantı eklenebilir.
2. **İndir** düğmesine basın. İsterseniz **Belirli saatte başlat** seçeneğini açın.
3. Dosya satırındaki duraklat/oynat düğmeleri indirmeyi yönetir. Tamamlandıktan sonra klasör düğmesi dosyayı Finder’da gösterir.
4. Sol alttaki **Ayarlar**, üst araç çubuğundaki dişli veya **⌘,** kısayolu ile ayarları açın. Seçimler otomatik olarak `~/Library/Application Support/Akinti/settings.json` dosyasına kaydedilir. Klasör değişikliği yalnızca yeni eklenen indirmelere uygulanır. Eşzamanlı indirme sayısını azaltmak başlamış görevleri kesmez.
5. Sol alttaki **Nasıl kullanılır?** düğmesi uygulama içi rehberi açar.

Dağıtım arşivi `dist/Akinti-macOS.zip` dosyasıdır. Paket imzalanmadan önce geçici bir klasörde hazırlanır ve imzası doğrulanır; böylece Finder/bulut eşitleme metaverileri arşive girmez.

## Geliştirme planı

Henüz uygulanmamış özellikler: tarayıcı uzantısı, Developer ID imzası/notarizasyon ve oturum/kimlik doğrulama yönetimi. Bu sürüm IDM’nin tüm özelliklerini karşılamaz.

Kaynaklarda üçüncü taraf Swift bağımlılığı yoktur; video siteleri için isteğe bağlı olarak yt-dlp ve ffmpeg kullanılır. Katkılar ve hata bildirimleri GitHub üzerinden kabul edilir.

## Simge

`Assets/AppIcon.icns`, `scripts/make-icon.swift` ile çizilir (dalgalı mavi su yüzeyine inen indirme oku). Değiştirmek için betiği düzenleyip şunu çalıştırın, ardından `.icns` dosyasını `iconutil` ile yeniden üretin:

```sh
swift scripts/make-icon.swift Assets/AppIcon-1024.png
```

## Geliştirici seçenekleri

Gerçek geçmişe ve ayarlara dokunmadan denemek için uygulama Terminal’den şu seçeneklerle açılabilir:

```sh
open -n dist/Akıntı.app --args --state-dir /tmp/akinti-deneme --add https://example.org/dosya.zip --select-first --open-settings
```

## Testler

`swift test` komutu yerel Python HTTP sunucusuyla gerçek indirmeler yapar. Kuyruk, duraklatma/yeniden başlatma, bayt bütünlüğü, dosya adı çakışması, 404, geçmiş, zamanlama ve geçici 503 sonrası otomatik yeniden denemeyi kontrol eder. Testler kullanıcının indirme klasörünü kullanmaz. GitHub Actions aynı test ve paketleme komutlarını çalıştıracak şekilde hazırlanmıştır; uzak çalıştırma henüz doğrulanmadı.
