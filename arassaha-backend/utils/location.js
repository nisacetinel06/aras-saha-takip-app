// Konum tutarlılığı — tek gerçek kaynak (single source of truth) ilkesi.
//
// il/ilce/mahalle YAPISAL alanları bir ekipmanın konumunun gerçek kaynağıdır.
// `location_name` (örn. "Erzurum / Yakutiye / Merkez Mah.") bu üç alanın
// insan tarafından okunabilir birleşimidir ve HER ZAMAN bu fonksiyonla
// üretilir — hiçbir yerde elle ayrı ayrı yazılmaz. Bu, "il/ilçe/mahalle" ile
// "location_name" metninin birbirinden zamanla sapmasını (örn. biri
// güncellenip diğeri unutulursa oluşacak tutarsızlığı) yapısal olarak
// imkansız hale getirir.
const VALID_ILLER = ['Erzurum', 'Erzincan', 'Ağrı', 'Kars', 'Iğdır', 'Ardahan', 'Bayburt'];

function formatLocationName({ il, ilce, mahalle }) {
  return `${il} / ${ilce} / ${mahalle}`;
}

module.exports = { VALID_ILLER, formatLocationName };
