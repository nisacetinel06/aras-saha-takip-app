// Dashboard / Ana Sayfa modülüne ait özet istatistik endpoint'i.
const express = require('express');
const db = require('../database');

const router = express.Router();

// GET /api/dashboard/summary
router.get('/summary', (req, res) => {
  try {
    const openCount = db
      .prepare("SELECT COUNT(*) AS c FROM work_orders WHERE status = 'acik'")
      .get().c;

    const resolvedTodayCount = db
      .prepare(
        "SELECT COUNT(*) AS c FROM work_orders WHERE status = 'cozuldu' AND date(updated_at) = date('now')"
      )
      .get().c;

    const avgRow = db
      .prepare(
        `SELECT AVG((julianday(updated_at) - julianday(created_at)) * 24) AS avg_hours
         FROM work_orders
         WHERE status = 'cozuldu'`
      )
      .get();
    const avgResolutionHours = avgRow.avg_hours != null ? Math.round(avgRow.avg_hours * 10) / 10 : 0;

    const statusBreakdown = { acik: 0, yolda: 0, sahada: 0, cozuldu: 0 };
    db.prepare('SELECT status, COUNT(*) AS c FROM work_orders GROUP BY status')
      .all()
      .forEach((row) => {
        statusBreakdown[row.status] = row.c;
      });

    const priorityBreakdown = { acil: 0, normal: 0, dusuk: 0 };
    db.prepare('SELECT priority, COUNT(*) AS c FROM work_orders GROUP BY priority')
      .all()
      .forEach((row) => {
        priorityBreakdown[row.priority] = row.c;
      });

    const recentActivity = db
      .prepare('SELECT id, title, status, updated_at FROM work_orders ORDER BY updated_at DESC LIMIT 5')
      .all();

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
