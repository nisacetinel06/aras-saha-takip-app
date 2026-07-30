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

module.exports = router;
