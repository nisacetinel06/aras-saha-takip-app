# Katkı Rehberi

## Hata ve Boş Durum Standartları (Zorunlu)

Yeni bir ekran veya özellik eklerken:

1. Veri çeken her ekran, boş/hata durumlarında MUTLAKA `widgets/empty_state.dart`'taki `EmptyState`
   bileşenini kullanmalı. Özel bir "boş durum" ya da "hata durumu" widget'ı yazma — hem liste boşken
   hem de yükleme başarısız olduğunda aynı `EmptyState` kullanılır (`icon`/`title`/`subtitle` ekrana
   özgü olsun, ama alttaki bileşen hep aynı olsun). "Tekrar Dene" aksiyonu varsa
   `primaryActionVariant: AppButtonVariant.secondary` ile geçirilir — bu, uygulama genelinde TEK
   "Tekrar Dene" buton stilidir.
2. Her `catch` bloğu, kullanıcıya gösterilecek mesajı MUTLAKA `utils/error_mapper.dart`'taki
   `mapExceptionToUserMessage()` üzerinden üretmeli. `e.toString()`, `'$e'` ya da ham hata metnini
   ASLA doğrudan bir Text/SnackBar/dialog'a verme.
3. Yeni bir exception tipiyle karşılaşırsan (örn. yeni bir paket entegre ettiğinde), onu
   `mapExceptionToUserMessage()`'a yeni bir dal olarak ekle — kendi yerel hata mesajını yazma.
   Fonksiyonun bilinmeyen-hata dalı her zaman makul bir genel mesaj döndürmeli; yeni bir dal eklemek
   bu güvenli varsayılanı bozmamalı.
4. Bu kurallardan biri eksikse, PR/kod incelemesinde reddedilme sebebidir.

### İstisnalar

Bu kurallar **sayfa/bölüm seviyesindeki** boş/hata durumları içindir. Aşağıdakiler kapsam dışıdır,
kendi inline stillerini korurlar:

- Tek bir form alanının doğrulama hatası (örn. yanlış kod, eksik zorunlu alan).
- Bir mesaj/gönderim işleminin anlık "gönderilemedi" göstergesi (retry aksiyonu zaten gönderme
  butonunun kendisidir).
- Kendi özel görsel dili olan, uygulamanın normal temasını BİLİNÇLİ olarak kullanmayan tam ekran
  deneyimler (örn. `qr_scanner_screen.dart`'ın siyah kamera arayüzü) — bu durumda bile TÜM butonlar
  yine `AppButton` olmalı (rengi `color:` parametresiyle geçersiz kılınabilir), asla çıplak
  `TextButton`/`OutlinedButton` kullanılmamalı.

Bu notu ekleyerek, ileride yeni bir modül eklendiğinde bu tutarlılığın korunmasını sağlıyoruz —
bir kerelik temizlik ile kalıcı bir standart arasındaki fark budur. Otomatik bir kontrol için bkz.
`scripts/check_error_handling.sh`.
