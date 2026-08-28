# Katkı Rehberi

## Kritik Yol Tablosu Güncelleme Kuralı (Zorunlu)

Backend'e yeni bir modül eklerken, eğer bu modül şunlardan birini içeriyorsa:
- Kimlik doğrulama veya yetkilendirme (RBAC) mantığı
- Veri değiştiren (yazma) bir işlem
- Kullanıcılar arası veri görünürlüğü/sahiplik ayrımı
- Finansal/stok gibi bütünlük gerektiren bir kaynak

O modül için MUTLAKA:
1. `test/integration/` veya `test/unit/` altında en az bir test dosyası yazılmalı
2. [README.md](README.md)'deki "Kritik Yol Tablosu"na yeni bir satır eklenmeli (modül adı, ilgili dosya, hangi test kartı kapsadığı)
3. Bu iki adım tamamlanmadan modül "tamamlandı" sayılmamalı

Bu kural olmadan, coverage raporu zamanla gerçeği yansıtmayan, yanıltıcı bir belge hâline gelir.

**Neden bu kural TEST-17'de eklendi:** TEST-13'ten (coverage analizi) sonra
eklenen en az 10 modül (Login Rate Limiting, 2FA, Refresh Token Rotasyonu,
KVKK, Orphan Dosya Temizleme, Dosya Yükleme Sıkılaştırma, RBAC Boşlukları,
Profil Fotoğrafı Yetkilendirmesi, Audit Log, Malzeme Atanmamış-İş-Emri Kaydı)
kendi test dosyasını yazdırmıştı ama README'ye hiç yansıtılmamıştı — üstelik
README'de o zamana kadar literal bir "Kritik Yol Tablosu" **hiç var olmamıştı**
(TEST-14/15/16 yorumlarındaki "TEST-13'te oluşturduğumuz tablo" referansı
yanlıştı, gerçekte yalnızca test dosyalarına yazılan inline yorum
konvansiyonuydu). Bir modülün "kritik olduğu için testi var" olması,
bunun herkes tarafından görünür/izlenebilir olduğu anlamına gelmiyordu — bu
kural o boşluğu kapatıyor.

**Bilinen bir örnek (bu kuralın neden gerekli olduğunun kanıtı):**
`POST /api/auth/change-password` (bkz. [routes/auth.js](routes/auth.js))
hâlâ HİÇ test dosyasına sahip değil — coverage raporunda `routes/auth.js`
satır 259-310 (change-password'un tüm gövdesi) kapsanmıyor. Bu, ayrı bir
görev kartı olarak açılmalı, bu kuralın gelecekte tam olarak önlemesi
gereken durumun canlı bir örneği.
