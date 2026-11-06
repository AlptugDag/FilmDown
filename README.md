# FilmDown
### Ultra High Quality Video & Media Downloader
> Powered by Alptuğ Dağ

<p align="center">
  <img src="icon.png" width="140" alt="FilmDown Logo" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Author-Alptu%C4%9F%20Da%C4%9F-blue.svg?style=flat-square" alt="Author">
  <img src="https://img.shields.io/badge/Architecture-Swift%20%2B%20Python-black.svg?style=flat-square" alt="Architecture">
  <img src="https://img.shields.io/badge/Platform-macOS%20(Native%20Liquid%20Glass)-cyan.svg?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/License-MIT-orange.svg?style=flat-square" alt="License">
</p>

---

## Hakkında

**FilmDown**, internet üzerindeki video akışlarını, HLS/M3U8 yayınlarını ve sosyal medya platformlarındaki içerikleri en yüksek çözünürlük ve ses kalitesinde (`bestvideo+bestaudio/best`) indiren, macOS için yerel **Liquid Glass** arayüzüne sahip yeni nesil bir masaüstü uygulamasıdır.

Geliştirici: **Alptuğ Dağ**

---

## Öne Çıkan Yenilikler (Sürüm 2.0)

- **Liquid Glass Arayüz:** macOS görsel efekt motoru (`NSVisualEffectView`) ile çalışan, şeffaf buzlu cam estetiğine sahip modern ve sade kullanıcı deneyimi.
- **Toplu İndirme ve Ayrı Klasörleme:** Birden fazla bağlantı girildiğinde her videoyu kendi adını taşıyan bağımsız bir klasöre organize etme seçeneği.
- **Çakışma Koruması (Anti-Collision):** Aynı ada sahip videoların asla birbirinin üzerine yazılmaması; mevcut dosya veya klasör tespit edildiğinde otomatik olarak artımlı adlandırma (`(1)`, `(2)`).
- **Yalın İlerleme Çubuğu:** Canlı konsol ve terminal çıktı kutusu yerine yumuşak geçişli, yüzdelik oran, anlık hız ve kalan süre gösteren modern yükleme çubuğu.
- **Sıfır Uyarı ve Yerel Hız:** Python sürüm/konsol uyarıları tamamen filtrelenmiş olup, Mach-O 64-bit yerel ikili dosya üzerinden anında açılır.
- **Kayıpsız Birleştirme:** Video ve ses akışlarını pürüzsüz MP4 formatında kayıpsız birleştirir.

---

## Sistem Gereksinimleri

- **macOS 12.0+** (Apple Silicon ve Intel)
- **ffmpeg** (video ve sesi birleştirmek için):
  ```bash
  brew install ffmpeg
  ```
- **yt-dlp**:
  ```bash
  brew install yt-dlp
  # veya
  pip3 install yt-dlp
  ```

---

## Derleme ve Kurulum

### Yerel macOS Uygulamasını Derleme (`FilmDown.app`)
Projeyi klonladıktan sonra tek komutla yerel Swift Mach-O uygulamasını derleyebilirsiniz:
```bash
make build
```
Oluşturulan `FilmDown.app` paketini `/Applications` veya istediğiniz bir klasöre taşıyabilirsiniz.

Masaüstündeki çalışma klasörüne doğrudan kurmak için:
```bash
make install
```

### Python Üzerinden Çalıştırma (Çapraz Platform)
```bash
pip install -r requirements.txt
python3 app.py
```

---

## Yapımcı & İletişim

**Alptuğ Dağ**  
GitHub: [@AlptugDag](https://github.com/AlptugDag)

---

## Lisans
Bu proje [MIT](LICENSE) lisansı ile korunmaktadır.
