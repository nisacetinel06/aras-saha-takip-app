// Arıza Açıklaması Otomatik Sınıflandırma (Modül 10).
//
// Bu route bir PROXY'dir: asıl sınıflandırma işini Python (FastAPI) ML
// servisindeki POST /classify-text endpoint'i yapar (bkz. arassaha-ml/app.py,
// arassaha-ml/train_text_model.py). Node burada yalnızca isteği iletir ve
// cevabı olduğu gibi döner — Modül 9'daki risk tahmini entegrasyonuyla
// (routes/risk.js) aynı mimari desen; Node bu modeli İÇE AKTARMAZ.
//
// DÜRÜSTLÜK NOTU: Metni sınıflandıran model (TF-IDF + LogisticRegression),
// gerçek bir şirket arıza kaydı metin veri seti olmadığı için SENTETİK/şablon
// tabanlı üretilmiş bir veri setiyle eğitildi — bkz.
// arassaha-ml/generate_text_training_data.py ve arassaha-ml/README.md.
const express = require('express');

const router = express.Router();

// Modül 9 (routes/risk.js) ile AYNI ortam değişkeni — ikisi de aynı Python
// servisine (tek uvicorn process) bağlanır, ayrı bir servis kurulmadı.
const ML_SERVICE_URL = process.env.ML_SERVICE_URL || 'http://localhost:8000';

// POST /api/ml/classify-description
// Body: { description }
// Rol kısıtlaması YOK — giriş yapmış (verifyToken'dan geçmiş) her kullanıcı
// "Yeni İş Emri Oluştur" formunda bu öneriyi görebilir (bkz. requireRole'ün
// hiç kullanılmadığına dikkat — bu bilinçli bir tercih).
router.post('/ml/classify-description', async (req, res) => {
  try {
    const { description } = req.body;
    if (!description || !description.trim()) {
      return res.status(400).json({ error: 'description alanı zorunludur.' });
    }

    const response = await fetch(`${ML_SERVICE_URL}/classify-text`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ description }),
    });

    if (!response.ok) {
      const text = await response.text().catch(() => '');
      throw new Error(`ML servisi hata döndü (HTTP ${response.status}): ${text}`);
    }

    const data = await response.json();
    res.json(data);
  } catch (err) {
    console.error(err);
    // ML servisi kapalıysa (örn. henüz uvicorn başlatılmadıysa) formun
    // geri kalanı çalışmaya devam etmeli — bu yüzden 503 ile nazikçe
    // dönülür, Flutter tarafı bunu "öneri yok" olarak sessizce yorumlar.
    res.status(503).json({
      error: 'Açıklama sınıflandırılamadı (ML servisine ulaşılamıyor olabilir).',
    });
  }
});

module.exports = router;
