// AI Asistan / Sohbet Arayüzü (Modül 16) — izin verilen niyet (intent) ve
// filtre şeması.
//
// KRİTİK MİMARİ KARAR — LLM'e asla doğrudan SQL yazdırılmaz: Gemini'ye
// kullanıcının doğal dil sorusunu göndererek "SQL üret" istemek hem SQL
// injection riski taşır hem de modelin yanlış/tehlikeli bir sorgu üretmesine
// açık kapı bırakır. Bunun yerine Gemini'den yalnızca burada TANIMLI, sabit
// bir "intent" (niyet) ve "filters" (filtre) şemasına uyan bir JSON üretmesi
// istenir (bkz. assistantService.parseUserIntent). Gerçek veritabanı sorgusu
// bu niyete göre, Node.js'in KENDİSİ, önceden yazılmış parametreli sorgularla
// çalıştırır (bkz. assistantQueries.js) — LLM'in ürettiği metin hiçbir zaman
// bir SQL string'ine karışmaz.
//
// Filtre enum'ları (VALID_STATUSES, VALID_ILLER vb.) burada TEKRAR
// tanımlanmaz; ilgili route dosyalarındaki TEK gerçek kaynaktan içe
// aktarılır (bkz. o dosyalardaki "AI Asistan (Modül 16)" yorumu ile eklenen
// module.exports.VALID_* satırları) — iki yerde senkron tutulması gereken
// enum listesi riskini ortadan kaldırır.
const { VALID_STATUSES: WORK_ORDER_STATUSES, VALID_PRIORITIES } = require('../routes/workOrders');
const { VALID_CATEGORIES: MATERIAL_CATEGORIES, VALID_EQUIPMENT_TYPES } = require('../routes/materials');
const { VALID_CATEGORIES: ISG_CATEGORIES, VALID_STATUSES: ISG_STATUSES } = require('../routes/isg');
const { VALID_ILLER } = require('../utils/location');

// "Beni X sayfasına götür" tarzı sorular için izin verilen ekranlar.
// `roles` yoksa TÜM roller erişebilir; varsa yalnızca listelenen roller —
// bu kısıtlama, Ana Sayfa modül ızgarasındaki AYNI `auth.isYonetici` /
// `auth.canCreateWorkOrders` görünürlük kurallarının (bkz. home_screen.dart)
// birebir sunucu tarafı karşılığıdır; asistan bu kuralları atlayan bir arka
// kapı OLAMAZ (bkz. routes/assistant.js NAV_TARGETS kullanımı).
const NAV_TARGETS = {
  ana_sayfa: { label: 'Ana Sayfa' },
  is_emirleri: { label: 'İş Emirleri' },
  harita: { label: 'Harita' },
  dashboard: { label: 'Panel' },
  profil: { label: 'Profil' },
  ekipman: { label: 'Ekipman' },
  stok: { label: 'Stok / Malzeme' },
  isg: { label: 'İSG Bildirimleri' },
  bildirimler: { label: 'Bildirimler' },
  qr_tara: { label: 'QR Kod Tarama' },
  is_emri_olustur: { label: 'Yeni İş Emri Oluşturma', roles: ['dispecer', 'yonetici'] },
  bakim_planlama: { label: 'Bakım Planlama', roles: ['dispecer', 'yonetici'] },
  raporlar: { label: 'Raporlar', roles: ['yonetici'] },
  cihaz_yonetimi: { label: 'Cihaz Yönetimi', roles: ['yonetici'] },
  kullanici_yonetimi: { label: 'Kullanıcı Yönetimi', roles: ['yonetici'] },
  supheli_sayaclar: { label: 'Şüpheli Sayaçlar', roles: ['yonetici'] },
  kullanim_analitigi: { label: 'Kullanım Analitiği', roles: ['yonetici'] },
};

// Her intent'in: (a) hangi filtre alanlarını kabul ettiğini, (b) her alanın
// geçerli değer kümesini (varsa) tanımlar. assistantService.parseUserIntent,
// Gemini'nin ürettiği JSON'u bu şemaya göre DOĞRULAR — şemaya uymayan bir
// intent/filtre değeri asla sorgu fonksiyonuna ulaşmaz, 'unknown'a düşer.
const INTENT_SCHEMA = {
  count_work_orders: {
    description: 'Belirli bir bölge/durum/öncelik/ekipman tipine göre iş emri (arıza) sayısını sorar.',
    filters: {
      il: { type: 'enum', values: VALID_ILLER },
      ilce: { type: 'string' },
      status: { type: 'enum', values: WORK_ORDER_STATUSES },
      priority: { type: 'enum', values: VALID_PRIORITIES },
      equipment_type: { type: 'enum', values: VALID_EQUIPMENT_TYPES },
      date_from: { type: 'date' },
      date_to: { type: 'date' },
    },
  },
  list_work_orders: {
    description: 'İş emirlerini (arızaları) BAŞLIK/AÇIKLAMA/KONUM gibi içerik detaylarıyla birlikte listeler — "acil iş emirlerini listele", "Erzurum\'daki açık arızaların içeriğini göster" gibi sorular için (count_work_orders yalnızca SAYI döner, bu intent gerçek kayıtları döner).',
    filters: {
      il: { type: 'enum', values: VALID_ILLER },
      ilce: { type: 'string' },
      status: { type: 'enum', values: WORK_ORDER_STATUSES },
      priority: { type: 'enum', values: VALID_PRIORITIES },
      equipment_type: { type: 'enum', values: VALID_EQUIPMENT_TYPES },
      limit: { type: 'number', min: 1, max: 15, default: 8 },
    },
  },
  list_high_risk_equipment: {
    description: 'En yüksek risk skoruna sahip ekipmanları listeler (yalnızca yönetici).',
    filters: {
      il: { type: 'enum', values: VALID_ILLER },
      limit: { type: 'number', min: 1, max: 10, default: 5 },
    },
  },
  list_suspicious_meters: {
    description: 'Şüpheli (anormal tüketim) olarak işaretlenmiş sayaçları listeler.',
    filters: {
      il: { type: 'enum', values: VALID_ILLER },
      limit: { type: 'number', min: 1, max: 20, default: 10 },
    },
  },
  count_isg_reports: {
    description: 'İSG bildirimi sayısını durum/kategoriye göre sorar.',
    filters: {
      status: { type: 'enum', values: ISG_STATUSES },
      category: { type: 'enum', values: ISG_CATEGORIES },
    },
  },
  list_low_stock_materials: {
    description: 'Kritik stok seviyesinin altındaki malzemeleri listeler.',
    filters: {
      category: { type: 'enum', values: MATERIAL_CATEGORIES },
    },
  },
  equipment_lookup: {
    description: 'QR koduna göre tek bir ekipmanın durumunu/risk skorunu sorar.',
    filters: {
      qr_code: { type: 'string', required: true },
    },
  },
  navigate_to_screen: {
    description: 'Kullanıcı uygulama içinde bir ekrana GİTMEK/YÖNLENDİRİLMEK istiyor — "beni iş emirlerine götür", "haritayı aç", "stok sayfasına geç" gibi sorular için. Veri SORMUYOR, yalnızca gezinme istiyor.',
    filters: {
      screen: { type: 'enum', values: Object.keys(NAV_TARGETS), required: true },
      // Yalnızca screen='is_emirleri' ile birlikte anlamlıdır (örn. "acil iş
      // emirleri sayfasına git") — o ekran açılırken listeyi bu duruma göre
      // önceden filtreler. Diğer screen değerleriyle gelirse yok sayılır.
      status: { type: 'enum', values: WORK_ORDER_STATUSES },
    },
  },
  // LLM soruyu yukarıdaki kategorilerin hiçbirine oturtamazsa VEYA doğrulama
  // (aşağıdaki assistantService.validateIntent) başarısız olursa bu döner.
  // routes/assistant.js bu durumda LLM'e İKİNCİ bir çağrı YAPMAZ — sabit bir
  // "anlayamadım" yanıtı döner (gereksiz API maliyetinden kaçınmak için).
  unknown: {
    description: 'Soru desteklenen kategorilerin hiçbirine uymuyor.',
    filters: {},
  },
};

const ALLOWED_INTENTS = Object.keys(INTENT_SCHEMA);

module.exports = { INTENT_SCHEMA, ALLOWED_INTENTS, NAV_TARGETS };
