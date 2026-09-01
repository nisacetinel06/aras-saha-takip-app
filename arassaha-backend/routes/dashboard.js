// Dashboard / Ana Sayfa modülüne ait özet istatistik endpoint'i.
const express = require('express');
const db = require('../database');

const router = express.Router();

// Hiyerarşik görünürlük kuralı (Modül 7 devamı — bkz. routes/workOrders.js
// applyVisibilityFilter ile aynı mantık): teknisyen yalnızca kendi işlerinin
// özetini görür, dispeçer yalnızca kendi ekibininkini, yönetici tümünü.
// Buradaki özet SQL'leri work_orders üzerinde çalıştığı için filtre
// "assigned_user_id" üzerinden kurulur.
function visibilityClause(req) {
  if (req.user.role === 'teknisyen') {
    return { clause: 'assigned_user_id = ?', params: [req.user.id] };
  }
  if (req.user.role === 'dispecer') {
    return {
      clause: 'assigned_user_id IN (SELECT id FROM users WHERE supervisor_id = ?)',
      params: [req.user.id],
    };
  }
  return { clause: null, params: [] };
}

function withClause(baseWhere, visibility) {
  if (!visibility.clause) return baseWhere || '';
  return baseWhere ? `${baseWhere} AND ${visibility.clause}` : `WHERE ${visibility.clause}`;
}

// GET /api/dashboard/summary
router.get('/summary', (req, res) => {
  try {
    const visibility = visibilityClause(req);

    const openCount = db
      .prepare(`SELECT COUNT(*) AS c FROM work_orders ${withClause("WHERE status = 'acik'", visibility)}`)
      .get(...visibility.params).c;

    const resolvedTodayCount = db
      .prepare(
        `SELECT COUNT(*) AS c FROM work_orders ${withClause(
          "WHERE status = 'cozuldu' AND date(updated_at) = date('now')",
          visibility
        )}`
      )
      .get(...visibility.params).c;

    const avgRow = db
      .prepare(
        `SELECT AVG((julianday(updated_at) - julianday(created_at)) * 24) AS avg_hours
         FROM work_orders
         ${withClause("WHERE status = 'cozuldu'", visibility)}`
      )
      .get(...visibility.params);
    const avgResolutionHours = avgRow.avg_hours != null ? Math.round(avgRow.avg_hours * 10) / 10 : 0;

    const statusBreakdown = { acik: 0, yolda: 0, sahada: 0, cozuldu: 0 };
    db.prepare(`SELECT status, COUNT(*) AS c FROM work_orders ${withClause('', visibility)} GROUP BY status`)
      .all(...visibility.params)
      .forEach((row) => {
        statusBreakdown[row.status] = row.c;
      });

    const priorityBreakdown = { acil: 0, normal: 0, dusuk: 0 };
    db.prepare(`SELECT priority, COUNT(*) AS c FROM work_orders ${withClause('', visibility)} GROUP BY priority`)
      .all(...visibility.params)
      .forEach((row) => {
        priorityBreakdown[row.priority] = row.c;
      });

    const recentActivity = db
      .prepare(
        `SELECT id, title, status, updated_at FROM work_orders ${withClause('', visibility)} ORDER BY updated_at DESC LIMIT 5`
      )
      .all(...visibility.params);

    res.json({
      open_count: openCount,
      resolved_today_count: resolvedTodayCount,
      avg_resolution_hours: avgResolutionHours,
      status_breakdown: statusBreakdown,
      priority_breakdown: priorityBreakdown,
      recent_activity: recentActivity,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Dashboard özeti alınırken bir hata oluştu.' });
  }
});

// GET /api/dashboard/my-performance
// Modül 16 — "Performansım": teknisyenin KENDİ tamamladığı iş emirleri
// üzerinden hesaplanan özet. Rol kısıtlaması gerekmez — sorgu HER ZAMAN
// req.user.id'ye göre filtrelenir (kimse başkasının performansını bu
// endpoint'ten göremez, IDOR riski yok). Yeni bir tablo/veri kaynağı
// EKLEMEZ — work_orders ve isg_reports üzerindeki var olan alanları
// yeniden sorgular.
router.get('/my-performance', (req, res) => {
  try {
    const userId = req.user.id;

    const startOfMonth = new Date();
    startOfMonth.setDate(1);
    startOfMonth.setHours(0, 0, 0, 0);

    const completedThisMonth = db
      .prepare(
        `SELECT COUNT(*) AS c FROM work_orders
         WHERE assigned_user_id = ? AND status = 'cozuldu' AND updated_at >= ?`
      )
      .get(userId, startOfMonth.toISOString()).c;

    const totalCompleted = db
      .prepare(
        `SELECT COUNT(*) AS c FROM work_orders WHERE assigned_user_id = ? AND status = 'cozuldu'`
      )
      .get(userId).c;

    // Modül 9'daki calculateMonthsSinceMaintenance'ta öğrenilen tarih hassasiyeti
    // dersi: julianday() SQLite'ta güvenilir bir tarih farkı hesaplama yöntemi —
    // yukarıdaki GET /summary'deki avgResolutionHours ile AYNI hesap.
    const avgRow = db
      .prepare(
        `SELECT AVG((julianday(updated_at) - julianday(created_at)) * 24) AS avg_hours
         FROM work_orders WHERE assigned_user_id = ? AND status = 'cozuldu'`
      )
      .get(userId);
    const avgResolutionHours =
      avgRow.avg_hours != null ? Math.round(avgRow.avg_hours * 10) / 10 : null;

    // Sabit anahtarlarla başlat, GROUP BY sonucunu üzerine yaz — yukarıdaki
    // GET /summary'nin priorityBreakdown deseniyle AYNI: aksi halde hiç
    // tamamlanmamış bir öncelik sessizce pasta grafikten düşer.
    const priorityBreakdown = { acil: 0, normal: 0, dusuk: 0 };
    db.prepare(
      `SELECT priority, COUNT(*) AS c FROM work_orders
       WHERE assigned_user_id = ? AND status = 'cozuldu'
       GROUP BY priority`
    )
      .all(userId)
      .forEach((row) => {
        priorityBreakdown[row.priority] = row.c;
      });

    const isgReportsCount = db
      .prepare('SELECT COUNT(*) AS c FROM isg_reports WHERE reported_by_user_id = ?')
      .get(userId).c;

    // Son 6 ayın aylık tamamlama trendi — routes/reports.js GET /fault-trend
    // ile AYNI "veri OLMAYAN ayları da 0 ile doldur" mantığı ve alan
    // adlandırması (year_month), Raporlar sekmesiyle tutarlılık için korundu.
    const months = 6;
    const now = new Date();
    const monthKeys = [];
    for (let i = months - 1; i >= 0; i--) {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
      monthKeys.push(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`);
    }

    const trendRows = db
      .prepare(
        `SELECT strftime('%Y-%m', updated_at) AS year_month, COUNT(*) AS completed_count
         FROM work_orders
         WHERE assigned_user_id = ? AND status = 'cozuldu' AND updated_at >= ?
         GROUP BY year_month`
      )
      .all(
        userId,
        new Date(now.getFullYear(), now.getMonth() - (months - 1), 1).toISOString()
      );
    const countByMonth = Object.fromEntries(
      trendRows.map((r) => [r.year_month, r.completed_count])
    );
    const monthlyTrend = monthKeys.map((year_month) => ({
      year_month,
      completed_count: countByMonth[year_month] ?? 0,
    }));

    res.json({
      completed_this_month: completedThisMonth,
      total_completed_all_time: totalCompleted,
      avg_resolution_hours: avgResolutionHours,
      priority_breakdown: priorityBreakdown,
      isg_reports_count: isgReportsCount,
      monthly_trend: monthlyTrend,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Performans özeti alınırken bir hata oluştu.' });
  }
});

module.exports = router;
