// Kişiler / personel modülüne ait endpoint'ler.
// "Kişiler" listesi hiçbir zaman kodda sabit tutulmaz; her zaman bu route üzerinden
// gerçek `users` tablosundan okunur (bkz. ARCHITECTURE.md Bölüm 11.1).
const express = require('express');
const db = require('../database');

const router = express.Router();

// GET /api/users?role=teknisyen
router.get('/', (req, res) => {
  try {
    const { role } = req.query;

    let users;
    if (role) {
      users = db.prepare('SELECT id, name, role, sicil_no FROM users WHERE role = ? ORDER BY name').all(role);
    } else {
      users = db.prepare('SELECT id, name, role, sicil_no FROM users ORDER BY name').all();
    }

    res.json(users);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Kişiler listelenirken bir hata oluştu.' });
  }
});

// GET /api/users/:id
router.get('/:id', (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz kullanıcı id değeri.' });
    }

    const user = db.prepare('SELECT id, name, role, sicil_no FROM users WHERE id = ?').get(id);
    if (!user) {
      return res.status(404).json({ error: 'Kullanıcı bulunamadı.' });
    }

    res.json(user);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Kullanıcı bilgisi alınırken bir hata oluştu.' });
  }
});

module.exports = router;
