// Denetim Logu Toplayıcı (Audit Log Aggregator) — bkz. routes/auditLog.js.
//
// AMAÇ: Sistemdeki 6 ayrı log/işlem-geçmişi tablosunu (bkz. aşağıdaki
// "KAYNAK TABLO ENVANTERİ") HİÇBİRİNİ DEĞİŞTİRMEDEN, ortak bir şekle
// (timestamp, actor_id, actor_name, category, action_type, description)
// normalize edip UNION ALL ile birleştiren, SALT OKUMA amaçlı bir katman.
// Var olan modüllerin kendi ekranları (Cihaz Yönetimi'nin işlem geçmişi,
// Kullanıcı Düzenleme'nin işlem geçmişi vb.) bu dosyadan tamamen bağımsız,
// kendi orijinal tablolarını okumaya devam eder — burada yalnızca YENİ bir
// okuma yolu eklenir.
//
// KAYNAK TABLO ENVANTERİ (Adım 0 — database.js'teki GERÇEK şemalar
// doğrulandı, kod incelemesiyle iki kez kontrol edildi):
//
//   - device_action_logs (Cihaz Yönetimi, bkz. routes/devices.js):
//     (id, device_id, action_type, performed_by, created_at). performed_by
//     ZATEN bir İSİM string'idir — log anında JWT'deki kullanıcının GÜNCEL
//     adı yazılır (logDeviceAction). Ayrı bir user id sütunu YOK, bu yüzden
//     actor_id çözülemez/NULL kalır.
//   - user_action_logs (Kullanıcı Yönetimi, bkz. routes/users.js
//     logUserAction): (id, target_user_id, action_type, performed_by,
//     created_at). AYNI desen — performed_by zaten isim, actor_id yok.
//   - login_attempts (Login Rate Limiting, bkz. middleware/loginRateLimit.js):
//     (id, sicil_no, ip_address, success, created_at). sicil_no bir FOREIGN
//     KEY DEĞİLDİR — kullanıcı numaralandırmayı önlemek için var olmayan bir
//     sicil_no ile de deneme kaydedilir. users'a sicil_no üzerinden OPSİYONEL
//     bir LEFT JOIN ile, eşleşirse gerçek actor_id/isim çözülür.
//   - data_deletion_requests (KVKK Uyum Modülü, bkz. routes/kvkk.js):
//     (id, user_id, request_type, reason, status, reviewer_note,
//     reviewed_by_user_id, created_at, reviewed_at, completed_at). Hem
//     user_id hem reviewed_by_user_id GERÇEK birer FOREIGN KEY (users.id).
//     Envanterdeki "talep oluşturma, onaylama, reddetme" üç ayrı işlemi
//     yansıtmak için bu TEK tablo İKİ AYRI kaynak sorgusuna dönüştürülür:
//     (1) OLUŞTURMA olayı — her satır için her zaman üretilir (created_at,
//     actor=user_id/talebi açan kişi); (2) İNCELEME olayı — yalnızca
//     GERÇEKTEN incelenmişse (reviewed_at dolu) üretilir (reviewed_at,
//     actor=reviewed_by_user_id/inceleyen yönetici, action_type=status).
//     İkisi TEK bir satırda birleştirilmez ki "kim açtı" ile "kim
//     onayladı/reddetti" ayrı, doğru zaman damgalı iki denetim olayı olsun.
//   - file_purge_log (Otomatik Dosya Temizleme, bkz. jobs/purgeLog.js):
//     (id, file_path, related_table, related_record_id, reason,
//     deleted_at). Hiçbir kullanıcı/aktör sütunu YOK (tanım gereği otomatik/
//     sistem işlemi) — actor sabit 'Sistem (otomatik)' metni, actor_id
//     HER ZAMAN NULL.
//   - material_stock_movements (Malzeme/Stok, bkz. routes/materials.js):
//     (id, material_id, movement_type, quantity, related_work_order_id,
//     performed_by_user_id, created_at). performed_by_user_id GERÇEK bir
//     FOREIGN KEY (users.id) — users ile JOIN edilip gerçek isim çözülür.
//
// PERFORMANS: created_at/deleted_at sütunlarına index'ler database.js'te
// eklendi (bkz. o dosyadaki "Denetim Logu Toplayıcı — Performans" notu) —
// UNION ALL'ın her bir dalı, WHERE'e gitmeden önce zaten timestamp'e göre
// sıralı/filtrelenebilir bir index kullanabilir. limit/offset HER ZAMAN
// uygulanır; tüm geçmişi tek seferde çekmek MÜMKÜN DEĞİLDİR (bkz. MAX_LIMIT).
const db = require('../database');

const VALID_CATEGORIES = [
  'giris',
  'kullanici_yonetimi',
  'cihaz_yonetimi',
  'stok',
  'kvkk',
  'dosya_temizleme',
];

const DEFAULT_LIMIT = 50;
// Bir istemcinin ?limit=999999 gibi bir değerle "tüm geçmişi tek seferde"
// çekmesini engelleyen üst sınır — bkz. dosya başı PERFORMANS notu.
const MAX_LIMIT = 200;

// Her biri TAM OLARAK AYNI 6 sütunu, AYNI SIRADA döner — UNION ALL'ın
// sütun tiplerinin/sırasının tutarlı olması için ZORUNLUDUR.
const SOURCE_QUERIES = [
  `SELECT
     dal.created_at AS timestamp,
     NULL AS actor_id,
     dal.performed_by AS actor_name,
     'cihaz_yonetimi' AS category,
     dal.action_type AS action_type,
     ('Cihaz #' || dal.device_id || ' - ' || dal.action_type) AS description
   FROM device_action_logs dal`,

  `SELECT
     ual.created_at AS timestamp,
     NULL AS actor_id,
     ual.performed_by AS actor_name,
     'kullanici_yonetimi' AS category,
     ual.action_type AS action_type,
     ('Kullanıcı #' || ual.target_user_id || ' - ' || ual.action_type) AS description
   FROM user_action_logs ual`,

  `SELECT
     la.created_at AS timestamp,
     u.id AS actor_id,
     (la.sicil_no || ' (' || CASE WHEN la.success = 1 THEN 'başarılı' ELSE 'başarısız' END || ')') AS actor_name,
     'giris' AS category,
     CASE WHEN la.success = 1 THEN 'giris_basarili' ELSE 'giris_basarisiz' END AS action_type,
     ('IP: ' || la.ip_address) AS description
   FROM login_attempts la
   LEFT JOIN users u ON u.sicil_no = la.sicil_no`,

  `SELECT
     ddr.created_at AS timestamp,
     ddr.user_id AS actor_id,
     COALESCE(u.name, 'Kullanıcı #' || ddr.user_id) AS actor_name,
     'kvkk' AS category,
     'talep_olusturuldu' AS action_type,
     ddr.request_type AS description
   FROM data_deletion_requests ddr
   LEFT JOIN users u ON u.id = ddr.user_id`,

  `SELECT
     ddr.reviewed_at AS timestamp,
     ddr.reviewed_by_user_id AS actor_id,
     COALESCE(rv.name, 'Kullanıcı #' || ddr.reviewed_by_user_id) AS actor_name,
     'kvkk' AS category,
     ddr.status AS action_type,
     ddr.request_type AS description
   FROM data_deletion_requests ddr
   LEFT JOIN users rv ON rv.id = ddr.reviewed_by_user_id
   WHERE ddr.reviewed_at IS NOT NULL`,

  `SELECT
     fpl.deleted_at AS timestamp,
     NULL AS actor_id,
     'Sistem (otomatik)' AS actor_name,
     'dosya_temizleme' AS category,
     fpl.reason AS action_type,
     COALESCE(fpl.file_path, '(dosya yolu kaydedilmemiş)') AS description
   FROM file_purge_log fpl`,

  `SELECT
     msm.created_at AS timestamp,
     msm.performed_by_user_id AS actor_id,
     COALESCE(u.name, 'Kullanıcı #' || msm.performed_by_user_id) AS actor_name,
     'stok' AS category,
     msm.movement_type AS action_type,
     ('Malzeme #' || msm.material_id || ' - ' || msm.quantity || ' birim') AS description
   FROM material_stock_movements msm
   LEFT JOIN users u ON u.id = msm.performed_by_user_id`,
];

const UNIONED_SOURCE_QUERY = SOURCE_QUERIES.join(' UNION ALL ');

function buildFilterClause({ category, actorId, fromDate, toDate }) {
  const conditions = [];
  const params = [];

  if (category) {
    conditions.push('category = ?');
    params.push(category);
  }
  if (actorId !== undefined && actorId !== null) {
    conditions.push('actor_id = ?');
    params.push(actorId);
  }
  if (fromDate) {
    conditions.push('timestamp >= ?');
    params.push(fromDate);
  }
  if (toDate) {
    conditions.push('timestamp <= ?');
    params.push(toDate);
  }

  return {
    whereClause: conditions.length ? `WHERE ${conditions.join(' AND ')}` : '',
    params,
  };
}

/**
 * Verilen filtreler için birleştirilmiş sorgunun SQL metnini/parametrelerini
 * üretir (gerçekten ÇALIŞTIRMAZ) — hem fetchAuditLog tarafından kullanılır
 * hem de test/unit seviyesinde SQL kurulumunun doğruluğunu (sütun eşleşmesi,
 * parametre sırası) bağımsız olarak doğrulamak için ayrı dışa aktarılır.
 */
function buildAuditLogQuery({ category, actorId, fromDate, toDate, limit = DEFAULT_LIMIT, offset = 0 } = {}) {
  const { whereClause, params } = buildFilterClause({ category, actorId, fromDate, toDate });

  return {
    countQuery: `SELECT COUNT(*) AS c FROM (${UNIONED_SOURCE_QUERY}) ${whereClause}`,
    countParams: params,
    dataQuery: `SELECT * FROM (${UNIONED_SOURCE_QUERY}) ${whereClause} ORDER BY timestamp DESC LIMIT ? OFFSET ?`,
    dataParams: [...params, limit, offset],
  };
}

/**
 * @param {object} [options]
 * @param {string} [options.category] - VALID_CATEGORIES'den biri.
 * @param {number} [options.actorId]
 * @param {string} [options.fromDate] - ISO 8601 (timestamp >= fromDate)
 * @param {string} [options.toDate] - ISO 8601 (timestamp <= toDate)
 * @param {number} [options.page=1] - 1 tabanlı sayfa numarası.
 * @param {number} [options.limit=DEFAULT_LIMIT]
 * @returns {{ entries: object[], totalCount: number, page: number, limit: number, hasMore: boolean }}
 */
function fetchAuditLog({ category, actorId, fromDate, toDate, page = 1, limit = DEFAULT_LIMIT } = {}) {
  const safePage = Number.isInteger(page) && page > 0 ? page : 1;
  const safeLimit = Number.isInteger(limit) && limit > 0 ? Math.min(limit, MAX_LIMIT) : DEFAULT_LIMIT;
  const offset = (safePage - 1) * safeLimit;

  const { countQuery, countParams, dataQuery, dataParams } = buildAuditLogQuery({
    category,
    actorId,
    fromDate,
    toDate,
    limit: safeLimit,
    offset,
  });

  const totalCount = db.prepare(countQuery).get(...countParams).c;
  const entries = db.prepare(dataQuery).all(...dataParams);

  return {
    entries,
    totalCount,
    page: safePage,
    limit: safeLimit,
    hasMore: offset + entries.length < totalCount,
  };
}

module.exports = { fetchAuditLog, buildAuditLogQuery, VALID_CATEGORIES, DEFAULT_LIMIT, MAX_LIMIT };
