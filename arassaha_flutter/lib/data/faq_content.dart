/// Yardım Merkezi / SSS (Modül) — statik soru-cevap içeriği.
///
/// BİLİNÇLİ olarak backend'den ÇEKİLMEZ: bu içerik uygulamanın kendi
/// davranışını açıklar, kullanıcıya özel bir veri değildir, bu yüzden bir
/// API çağrısına gerek yoktur. Her satırın karşılığı gerçek bir ekran/
/// davranıştır — kod tabanında doğrulanmadan buraya madde eklenmez (bkz.
/// help_center_screen.dart dosya başı notu).
class FaqItem {
  final String category;
  final String question;
  final String answer;

  /// Bu soruyu görebilecek roller — backend `users.role` ile birebir aynı
  /// ham string'ler ('teknisyen' | 'dispecer' | 'yonetici'), bkz.
  /// AuthProvider.currentUser.role ve theme/app_colors.dart roleColor().
  final List<String> visibleToRoles;

  const FaqItem({
    required this.category,
    required this.question,
    required this.answer,
    required this.visibleToRoles,
  });
}

const List<String> allRoles = ['teknisyen', 'dispecer', 'yonetici'];

/// Kategorilerin Yardım Merkezi'nde gösterileceği sabit sıra — Dart'ta
/// `List.groupBy` gibi bir üst kategori sıralaması olmadığı için elle
/// tanımlanır; aksi halde kategoriler ilk soruların listedeki rastgele
/// sırasına göre karışık görünürdü.
const List<String> faqCategoryOrder = [
  'Genel',
  'İş Emirleri',
  'Ekipman',
  'Bakım Planlama',
  'Harita',
  'İSG',
  'ArasAI',
  'Bildirimler',
  'Malzeme',
  'Acil Durum',
  'Mesajlar',
  'Raporlar',
  'Yönetim',
  'Profil',
];

final List<FaqItem> faqItems = [
  // GENEL
  const FaqItem(
    category: 'Genel',
    question: 'ArasSaha nedir?',
    answer:
        'ArasSaha, Aras EDAŞ saha ekiplerinin arıza takibi, bakım planlama ve '
        'iş güvenliği süreçlerini tek bir uygulamadan yönetmesini sağlayan '
        'bir saha operasyon uygulamasıdır.',
    visibleToRoles: allRoles,
  ),
  const FaqItem(
    category: 'Genel',
    question: 'Uygulama internet olmadan çalışır mı?',
    answer:
        'Kısmen. Daha önce görüntülediğiniz veriler çevrimdışıyken de '
        'gösterilir, ama yeni veri çekmek veya fotoğraf gerektiren işlemler '
        '(İSG bildirimi gibi) için internet bağlantısı gereklidir.',
    visibleToRoles: allRoles,
  ),

  // İŞ EMİRLERİ
  const FaqItem(
    category: 'İş Emirleri',
    question: 'Bir iş emrinin durumunu nasıl güncellerim?',
    answer:
        'İş emri detay ekranını açın, altta size uygun durum butonuna '
        '(Yolda, Sahadayım, Çözüldü) dokunun. Durumlar sırayla ilerler, '
        'adım atlanamaz.',
    visibleToRoles: allRoles,
  ),
  const FaqItem(
    category: 'İş Emirleri',
    question: 'Neden bazı iş emirlerini göremiyorum?',
    answer:
        'Teknisyen olarak sadece size atanmış iş emirlerini görürsünüz. '
        'Tüm iş emirlerini görmek dispeçer/yönetici yetkisi gerektirir.',
    visibleToRoles: ['teknisyen'],
  ),
  const FaqItem(
    category: 'İş Emirleri',
    question: 'Yeni bir iş emrini nasıl oluştururum/atarım?',
    answer:
        'Ana Sayfa\'daki "Yeni İş Emri Ata" ile ekipman seçip bir '
        'teknisyene atayabilirsiniz. Konum bilgisi seçtiğiniz ekipmandan '
        'otomatik gelir, elle girilmez.',
    visibleToRoles: ['dispecer', 'yonetici'],
  ),
  const FaqItem(
    category: 'İş Emirleri',
    question: 'İş emrine fotoğraf eklerken internet yoksa ne olur?',
    answer:
        'Fotoğraf yükleme çevrimdışı kuyruğa hiç alınmaz — internet yoksa '
        '"Fotoğraf Ekle" butonu devre dışı kalır ve net bir uyarı '
        'gösterilir. Fotoğraflar sunucuda gerçekten saklanır, bu yüzden '
        'başka bir cihazdan (örn. amirinizin telefonundan) da '
        'görüntülenebilir.',
    visibleToRoles: allRoles,
  ),

  // EKİPMAN / QR
  const FaqItem(
    category: 'Ekipman',
    question: 'QR kod okutunca ekipman bulunamıyor, ne yapmalıyım?',
    answer:
        'Kamera izninin verildiğinden emin olun. QR kod okunamıyorsa, '
        'ekranın altındaki "Manuel Kod Gir" seçeneğiyle ekipman kodunu '
        'elle girebilirsiniz.',
    visibleToRoles: allRoles,
  ),
  const FaqItem(
    category: 'Ekipman',
    question: 'Risk skoru rozeti ne anlama geliyor?',
    answer:
        'Kırmızı: yüksek arıza riski, sarı: orta risk, yeşil: düşük risk. '
        'Bu skor, ekipmanın yaşı, bakım geçmişi ve geçmiş arıza sayısına '
        'göre bir yapay zeka modeli tarafından hesaplanır, kesin bir '
        'teşhis değildir.',
    visibleToRoles: allRoles,
  ),
  const FaqItem(
    category: 'Ekipman',
    question: 'Ekipman detayındaki "Geçmiş Arıza Kayıtları" nereden geliyor?',
    answer:
        'Bu, ekipmana bağlı geçmiş iş emirlerinin gerçek listesidir — '
        'örnek/gösterim amaçlı bir veri değildir. Bir kayda dokunduğunuzda '
        'ilgili iş emrinin tam detayına gidersiniz; bir iş emri "Çözüldü" '
        'durumuna getirildiğinde ekipmanın "Son Bakım" tarihi otomatik '
        'güncellenir.',
    visibleToRoles: allRoles,
  ),

  // BAKIM PLANLAMA
  const FaqItem(
    category: 'Bakım Planlama',
    question: 'Bakım önerileri nereden geliyor, bir yapay zeka mı öneriyor?',
    answer:
        'Hayır, bu bir yapay zeka önerisi değildir. Öneriler, ekipmanın risk '
        'skorunu sabit eşiklerle bir bakım önerisine çeviren bir iş kuralı '
        'ile üretilir: skor yüksekse "yüksek aciliyet" (7 gün içinde), '
        'ortaysa "orta aciliyet" (30 gün içinde) önerilir; düşük skorlu '
        'ekipmanlar için hiç öneri üretilmez.',
    visibleToRoles: ['dispecer', 'yonetici'],
  ),
  const FaqItem(
    category: 'Bakım Planlama',
    question:
        'Bir bakım önerisiyle ne yapabilirim, onaylamak zorunda mıyım?',
    answer:
        'Bekleyen bir öneriyi "Önleyici İş Emri Oluştur" ile bir '
        'teknisyene atayabilir ya da gerekçe belirtmeden "Reddet" '
        'diyebilirsiniz. Bir kez iş emrine dönüştürülen (planlanan) öneri '
        'geri alınamaz.',
    visibleToRoles: ['dispecer', 'yonetici'],
  ),
  const FaqItem(
    category: 'Bakım Planlama',
    question: '"Önerileri Yeniden Hesapla" butonu ne işe yarar?',
    answer:
        'Bu buton, tüm ekipmanların güncel risk skorlarını yeniden tarayıp '
        'öneri listesini tazeler. Sistem genelinde ağır bir işlem olduğu '
        'için yalnızca yönetici rolüne görünür.',
    visibleToRoles: ['yonetici'],
  ),

  // HARİTA
  const FaqItem(
    category: 'Harita',
    question: 'Haritadaki pinler gerçek mi, yoksa örnek veri mi?',
    answer:
        'Her pin, sistemdeki gerçek bir iş emrinin konumuna karşılık gelir '
        '— sahte ya da örnek bir pin yoktur. Acil öncelikli işler pin '
        'üzerinde küçük bir ünlem ikonuyla ayrıca vurgulanır.',
    visibleToRoles: allRoles,
  ),
  const FaqItem(
    category: 'Harita',
    question: 'Haritada durum filtresi nasıl çalışıyor?',
    answer:
        'Üstteki filtre çubuğundan Tümü/Açık/Yolda/Sahada/Çözüldü '
        'statülerine göre pinleri daraltabilirsiniz. Bu filtre, elinizdeki '
        'listeyi anında süzer, yeni bir sunucu isteği göndermez.',
    visibleToRoles: allRoles,
  ),

  // İSG
  const FaqItem(
    category: 'İSG',
    question: 'İSG bildirimi gönderirken konum zorunlu mu?',
    answer:
        'Evet, gerçek GPS konumunuz gerekiyor. Konum izni kalıcı olarak '
        'reddedildiyse, "Ayarları Aç" butonuyla doğrudan telefon '
        'ayarlarına gidip izin verebilirsiniz.',
    visibleToRoles: allRoles,
  ),
  const FaqItem(
    category: 'İSG',
    question: 'Fotoğraftaki hasar analizi ne kadar güvenilir?',
    answer:
        'Bu, görüntü işleme tabanlı bir ön değerlendirmedir, kesin bir '
        'teşhis değildir. "Belirsiz" sonucu çıkarsa, fotoğrafı kendiniz '
        'değerlendirmeniz önerilir.',
    visibleToRoles: allRoles,
  ),

  // ARASAI
  const FaqItem(
    category: 'ArasAI',
    question: 'ArasAI\'a ne tür sorular sorabilirim?',
    answer:
        '"Erzurum\'da kaç açık arıza var?", "En riskli ekipmanlar '
        'hangileri?", "Kritik stoktaki malzemeler neler?" gibi verilerle '
        'ilgili sorular sorabilirsiniz. ArasAI sadece elinizdeki gerçek '
        'verilere göre cevap verir, tahmin yürütmez.',
    visibleToRoles: allRoles,
  ),
  const FaqItem(
    category: 'ArasAI',
    question: 'ArasAI benim görmediğim verileri gösterebilir mi?',
    answer:
        'Hayır. ArasAI, sizin rolünüzün görebildiği verilerle sınırlıdır — '
        'teknisyen olarak sadece kendi işlerinizle ilgili soru '
        'sorabilirsiniz.',
    visibleToRoles: allRoles,
  ),

  // BİLDİRİMLER
  const FaqItem(
    category: 'Bildirimler',
    question: 'Bildirimler neden bazen geç geliyor?',
    answer:
        'Uygulama kapalıyken de anlık bildirim alırsınız (push bildirim). '
        'Eğer almıyorsanız, Ayarlar\'dan bildirim izninin açık olduğunu '
        'kontrol edin.',
    visibleToRoles: allRoles,
  ),

  // MALZEME/STOK
  const FaqItem(
    category: 'Malzeme',
    question: 'Kullandığım malzemeyi nasıl kaydederim?',
    answer:
        'İş emri detay ekranındaki "Malzeme Ekle" ile kullandığınız '
        'malzemeyi ve miktarı seçin. Stokta yeterli miktar yoksa sistem '
        'kaydı reddeder.',
    visibleToRoles: allRoles,
  ),
  const FaqItem(
    category: 'Malzeme',
    question: 'Bana atanmamış bir işe malzeme ekleyebilir miyim?',
    answer:
        'Evet ama sistem bunu özel olarak işaretler ve loglar (örn. bir '
        'meslektaşınıza yardım ettiyseniz). Onay dialogu çıkacaktır.',
    visibleToRoles: ['teknisyen'],
  ),
  const FaqItem(
    category: 'Malzeme',
    question:
        '"Sadece Kritik Stok" filtresi neyi gösterir, yeni malzeme tipini kim ekleyebilir?',
    answer:
        'Bu filtre, stok miktarı belirlenen kritik eşiğin altına düşen '
        'malzemeleri listeler. Malzeme listesini (depoda ne olduğunu) '
        'herkes görebilir, ama yeni bir malzeme tipi tanımlama ve stok '
        'ikmali yalnızca yönetici rolüne açıktır.',
    visibleToRoles: allRoles,
  ),

  // SOS
  const FaqItem(
    category: 'Acil Durum',
    question: 'SOS butonuna yanlışlıkla bastım, ne olur?',
    answer:
        'Gönderim öncesi 3 saniyelik bir geri sayım ve büyük bir "İPTAL" '
        'butonu görürsünüz — bu sürede iptal ederseniz hiçbir bildirim '
        'gitmez.',
    visibleToRoles: allRoles,
  ),
  const FaqItem(
    category: 'Acil Durum',
    question: 'SOS gönderdim ama kimse cevap vermiyor, ne yapmalıyım?',
    answer:
        'Uygulama içi bildirim tek başvuru yolu olmamalı — SOS ekranındaki '
        '"Ara" butonuyla doğrudan yöneticinizi/acil durum hattını arayın, '
        'bu daha hızlı ve güvenilir bir yöntemdir.',
    visibleToRoles: allRoles,
  ),

  // MESAJLAR
  const FaqItem(
    category: 'Mesajlar',
    question: 'Yöneticimden gelen bir mesaja cevap verebilir miyim?',
    answer:
        'Hayır, bu bir tek yönlü duyuru sistemidir. Bir mesaja cevap '
        'vermeniz gerekiyorsa yöneticinizle doğrudan (telefon/yüz yüze) '
        'iletişime geçin.',
    visibleToRoles: ['teknisyen', 'dispecer'],
  ),

  // RAPORLAR
  const FaqItem(
    category: 'Raporlar',
    question: 'Raporlar sayfasını neden göremiyorum?',
    answer:
        'Raporlar (Bölgesel Görünüm, Eğilimler, Malzeme Kullanımı) '
        'yalnızca yönetici rolüne açıktır — teknisyen ve dispeçer '
        'hesaplarında bu modül hiç görünmez.',
    visibleToRoles: ['yonetici'],
  ),
  const FaqItem(
    category: 'Raporlar',
    question:
        '"Risk Modeli Performansı" ve "Hasar Tespiti Modeli Performansı" ne gösteriyor?',
    answer:
        'Bu kartlar, ArasSaha\'nın kendi gerçek kullanım geçmişinden '
        '(gerçekleşen arızalar ve doğrulanan İSG fotoğrafları) hesaplanan '
        'bir başarı oranı gösterir — modelin ilk eğitiminde kullanılan '
        'test verisinden değil. Yeterli veri birikmeden "henüz yeterli '
        'veri birikmedi" yazar.',
    visibleToRoles: ['yonetici'],
  ),

  // YÖNETİM
  const FaqItem(
    category: 'Yönetim',
    question:
        'Bir kullanıcıyı nasıl pasifleştiririm, pasifleştirilen kullanıcıya ne olur?',
    answer:
        'Kullanıcı Yönetimi listesindeki "Pasifleştir" butonuna basıp '
        'onay dialogunu geçtiğinizde kullanıcı pasif duruma alınır ve '
        'artık ona yeni iş emri ataması yapılamaz. "Aktifleştir" ile geri '
        'dönüş her zaman mümkündür.',
    visibleToRoles: ['yonetici'],
  ),
  const FaqItem(
    category: 'Yönetim',
    question: 'Bir çalışanın şifresini unuttum, nasıl sıfırlarım?',
    answer:
        'Kullanıcı Düzenle ekranındaki "Şifreyi Sıfırla" butonuyla, en az '
        '4 karakterlik yeni bir şifre belirleyerek sıfırlayabilirsiniz — '
        'teknisyen/dispeçer kendi profilinden şifresini değiştiremediği '
        'için bu, yönetici tarafından yapılan bir kurtarma aracıdır.',
    visibleToRoles: ['yonetici'],
  ),
  const FaqItem(
    category: 'Yönetim',
    question:
        'Cihaz Yönetimi\'ndeki "Kilitle" / "Hesabı Sil" cihaza gerçekten komut mu gönderiyor?',
    answer:
        'Hayır — bu bir simülasyondur; bu aksiyonlar yalnızca sistemdeki '
        'kaydı değiştirir, fiziksel cihaza uzaktan bir komut göndermez. '
        'Yalnızca "Zorla Senkronize Et" farklıdır: o an kullanılan '
        'cihazın gerçek pil/model/işletim sistemi bilgisini okuyup '
        'sisteme gönderir.',
    visibleToRoles: ['yonetici'],
  ),
  const FaqItem(
    category: 'Yönetim',
    question:
        'Denetim Logu ile Kullanıcı/Cihaz Detayı\'ndaki "İşlem Geçmişi" aynı şey mi?',
    answer:
        'Hayır, birbirinden bağımsızdır. Denetim Logu, sistemdeki tüm '
        'işlemlerin (giriş denemeleri, kullanıcı/cihaz yönetimi, stok '
        'hareketleri, KVKK talepleri vb.) tek ve salt-okunur bir '
        'görünümüdür; modüle özel geçmişler kendi kaydını ayrıca tutar.',
    visibleToRoles: ['yonetici'],
  ),

  // PROFİL/AYARLAR
  const FaqItem(
    category: 'Profil',
    question: 'Profil fotoğrafımı nasıl değiştiririm?',
    answer:
        'Profil fotoğrafı değişikliği sadece yönetici tarafından, '
        'Kullanıcı Yönetimi panelinden yapılabilir. Kendi profilinizden '
        'değiştiremezsiniz.',
    visibleToRoles: ['teknisyen', 'dispecer'],
  ),
  const FaqItem(
    category: 'Profil',
    question: 'Şifremi nasıl değiştiririm?',
    answer:
        'Ayarlar > Şifremi Değiştir bölümünden, mevcut şifrenizi girerek '
        'yeni bir şifre belirleyebilirsiniz.',
    visibleToRoles: allRoles,
  ),
  const FaqItem(
    category: 'Profil',
    question: 'İki faktörlü doğrulamayı (2FA) nasıl etkinleştiririm?',
    answer:
        'Ayarlar > İki Faktörlü Doğrulama bölümünden, bir authenticator '
        'uygulamasıyla (Google Authenticator vb.) QR kodu okutarak '
        'etkinleştirebilirsiniz. Bu özellik sadece yönetici hesapları '
        'için.',
    visibleToRoles: ['yonetici'],
  ),
  const FaqItem(
    category: 'Profil',
    question:
        'Kişisel verilerimi nasıl görebilirim/silme talebinde bulunabilirim?',
    answer:
        'Profil > Kişisel Verilerim ve Gizlilik bölümünden verilerinizin '
        'özetini görebilir, silme talebi oluşturabilirsiniz.',
    visibleToRoles: allRoles,
  ),
];
