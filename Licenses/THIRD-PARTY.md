# Üçüncü taraf bileşenler / Third-party components

Akıntı'nın kendi kodu MIT lisanslıdır (`Akinti-LICENSE.txt`). Aşağıdaki açık kaynak bileşenler kullanılır.

## Uygulamayla birlikte dağıtılanlar (torrent desteği)

Bu dosyalar `Akıntı.app/Contents/Helpers` ve `Contents/Frameworks` içinde, Homebrew derlemelerinden değiştirilmeden (yalnızca kütüphane yolları paket içini gösterecek şekilde) kopyalanır. Akıntı onları ayrı bir program olarak çalıştırır; Akıntı'nın koduyla birleştirilmez.

| Bileşen | Sürüm | Lisans | Kaynak kodu |
|---|---|---|---|
| aria2 | 1.37.0 | GPL v2 veya sonrası, OpenSSL istisnasıyla (`aria2-COPYING.txt`, `aria2-LICENSE.OpenSSL.txt`) | https://github.com/aria2/aria2/releases/tag/release-1.37.0 |
| OpenSSL | 4.x | Apache 2.0 (`openssl-LICENSE.txt`) | https://github.com/openssl/openssl |
| libssh2 | 1.11.x | BSD 3 maddeli (`libssh2-COPYING.txt`) | https://github.com/libssh2/libssh2 |
| c-ares | 1.34.x | MIT (`c-ares-LICENSE.md`) | https://github.com/c-ares/c-ares |
| SQLite | 3.x | Kamu malı (public domain) | https://sqlite.org/src |
| GNU gettext (libintl) | 0.21.x | LGPL 2.1 veya sonrası (`LGPL-2.1.txt`) | https://ftp.gnu.org/gnu/gettext/ |

GPL v2 gereği: aria2'nin kaynak kodu yukarıdaki bağlantıdan alınabilir; ayrıca istek üzerine sağlanır (GitHub'da issue açın). libintl ayrı bir dinamik kütüphanedir (`Contents/Frameworks/libintl.8.dylib`); LGPL gereği kullanıcı tarafından değiştirilebilir.

## İlk kullanımda kullanıcının isteğiyle indirilenler

Bunlar Akıntı ile dağıtılmaz; kullanıcı “Kur” dediğinde resmi kaynaklarından `~/Library/Application Support/Akinti/Tools` içine indirilir.

| Bileşen | Lisans | Kaynak | Doğrulama |
|---|---|---|---|
| yt-dlp | Unlicense | https://github.com/yt-dlp/yt-dlp | Aynı sürümdeki `SHA2-256SUMS` ile SHA-256 |
| FFmpeg (Martin Riedl derlemesi) | LGPL/GPL (derlemeye göre) | https://ffmpeg.martin-riedl.de · https://ffmpeg.org | Developer ID imzası (Team ID KU3N25YGLU), Apple onaylı |
