// Denetim Logu (Audit Log) — sistemdeki TÜM state-changing işlemlerin tek,
// birleşik bir okuma katmanından görülmesi. bkz. services/auditLogAggregator.js
// (gerçek SQL birleştirme mantığı ORADA — bu dosya yalnızca HTTP katmanı:
// query parametrelerini doğrular, aggregator'ı çağırır, yanıtı biçimlendirir).
const express = require('express');
const { requireRole } = require('../middleware/auth');
const { fetchAuditLog, VALID_CATEGORIES } = require('../services/auditLogAggregator');

const router = express.Router();

// GET /api/audit-log?category=&actor_id=&from=&to=&page=&limit= — yalnızca
// yönetici. Diğer hiçbir rol sistem genelindeki bu birleşik görünüme
// erişemez (bkz. görev talimatı) — modül-özel geçmişler (örn. Cihaz
// Yönetimi'nin KENDİ ekranındaki işlem geçmişi) kendi RBAC kurallarını
// korumaya devam eder, bu ayrı/ek bir kısıtlama değil.
router.get('/', requireRole('yonetici'), (req, res) => {
  try {
    const { category, actor_id: actorIdRaw, from, to, page: pageRaw, limit: limitRaw } = req.query;

    if (category && !VALID_CATEGORIES.includes(category)) {
      return res.status(400).json({
        error: `Geçersiz category değeri. Geçerli değerler: ${VALID_CATEGORIES.join(', ')}`,
      });
    }

    let actorId;
    if (actorIdRaw !== undefined) {
      actorId = Number(actorIdRaw);
      if (!Number.isInteger(actorId)) {
        return res.status(400).json({ error: 'Geçersiz actor_id değeri.' });
      }
    }

    let page = 1;
    if (pageRaw !== undefined) {
      page = Number(pageRaw);
      if (!Number.isInteger(page) || page < 1) {
        return res.status(400).json({ error: 'Geçersiz page değeri.' });
      }
    }

    let limit;
    if (limitRaw !== undefined) {
      limit = Number(limitRaw);
      if (!Number.isInteger(limit) || limit < 1) {
        return res.status(400).json({ error: 'Geçersiz limit değeri.' });
      }
    }

    const result = fetchAuditLog({
      category,
      actorId,
      fromDate: from || undefined,
      toDate: to || undefined,
      page,
      limit,
    });

    res.json({
      entries: result.entries,
      total_count: result.totalCount,
      page: result.page,
      has_more: result.hasMore,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Denetim logu alınırken bir hata oluştu.' });
  }
});

module.exports = router;
