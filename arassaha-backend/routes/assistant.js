// AI Asistan / Sohbet Arayüzü (Modül 16).
//
// Akış (bkz. services/assistantService.js ve services/assistantQueries.js
// başındaki "KRİTİK MİMARİ KARAR" notları):
//   kullanıcı mesajı → chat_messages'a kaydedilir
//   → parseUserIntent() ile Gemini'den SADECE bir {intent, filters} JSON'u istenir
//   → intent 'unknown' ise LLM'e TEKRAR SORULMAZ, sabit bir yanıt dönülür
//   → geçerli bir intent ise assistantQueries.js'teki RBAC'lı, parametreli
//     sorgu fonksiyonu çağrılır (GERÇEK veritabanı sonucu)
//   → formatAnswer() bu GERÇEK sonucu doğal bir Türkçe cümleye çevirir
//   → asistan yanıtı da chat_messages'a kaydedilir
//
// LLM'in kendisi hiçbir zaman SQL yazmaz, hiçbir zaman kullanıcıya gösterilen
// bir SAYIYI kendisi üretmez — yalnızca (a) soruyu niyete çevirir, (b) gerçek
// veriyi cümleye çevirir.
const express = require('express');
const db = require('../database');
const { parseUserIntent, formatAnswer, AssistantUnavailableError } = require('../services/assistantService');
const { QUERY_FUNCTIONS, AssistantForbiddenError } = require('../services/assistantQueries');
const { NAV_TARGETS } = require('../services/assistantIntents');
const { asyncHandler } = require('../utils/asyncHandler');

const router = express.Router();

const UNAVAILABLE_MESSAGE = 'Asistan şu anda yanıt veremiyor, lütfen daha sonra tekrar deneyin.';
const UNKNOWN_MESSAGE =
  'Bu soruyu şu an anlayamadım. Şunları sorabilirsiniz: "Erzurum\'da kaç açık arıza var?", "Acil iş emirlerini listele", "En riskli 3 ekipman hangisi?", "Kritik stokta ne var?", "Beni iş emirleri sayfasına götür"';

function saveMessage(userId, role, message) {
  const created_at = new Date().toISOString();
  const info = db
    .prepare('INSERT INTO chat_messages (user_id, role, message, created_at) VALUES (?, ?, ?, ?)')
    .run(userId, role, message, created_at);
  return { id: info.lastInsertRowid, user_id: userId, role, message, created_at };
}

// POST /api/assistant/query
// Body: { message: string }
router.post('/query', asyncHandler(async (req, res) => {
  const { message } = req.body;
  if (!message || typeof message !== 'string' || !message.trim()) {
    return res.status(400).json({ error: 'message alanı zorunludur.' });
  }

  try {
    saveMessage(req.user.id, 'user', message.trim());

    let parsed;
    try {
      parsed = await parseUserIntent(message.trim());
    } catch (err) {
      if (err instanceof AssistantUnavailableError) {
        const saved = saveMessage(req.user.id, 'assistant', UNAVAILABLE_MESSAGE);
        return res.status(200).json({ reply: saved });
      }
      throw err;
    }

    if (parsed.intent === 'unknown') {
      const saved = saveMessage(req.user.id, 'assistant', UNKNOWN_MESSAGE);
      return res.status(200).json({ reply: saved });
    }
    if (parsed.intent === 'navigate_to_screen') {
      const target = NAV_TARGETS[parsed.filters.screen];
      if (target.roles && !target.roles.includes(req.user.role)) {
        const saved = saveMessage(
          req.user.id,
          'assistant',
          `${target.label} sayfası şu anki rolünüzle erişiminize açık değil.`
        );
        return res.status(200).json({ reply: saved });
      }
      const saved = saveMessage(req.user.id, 'assistant', `Sizi ${target.label} sayfasına yönlendiriyorum.`);
      return res.status(200).json({
        reply: saved,
        action: { type: 'navigate', screen: parsed.filters.screen, status: parsed.filters.status ?? null },
      });
    }

    let queryResult;
    try {
      queryResult = QUERY_FUNCTIONS[parsed.intent](req.user, parsed.filters);
    } catch (err) {
      if (err instanceof AssistantForbiddenError) {
        const saved = saveMessage(req.user.id, 'assistant', err.message);
        return res.status(200).json({ reply: saved });
      }
      throw err;
    }

    let replyText;
    try {
      replyText = await formatAnswer(parsed.intent, parsed.filters, queryResult, message.trim());
    } catch (err) {
      if (err instanceof AssistantUnavailableError) {
        const saved = saveMessage(req.user.id, 'assistant', UNAVAILABLE_MESSAGE);
        return res.status(200).json({ reply: saved });
      }
      throw err;
    }

    const saved = saveMessage(req.user.id, 'assistant', replyText);
    res.status(200).json({ reply: saved, intent: parsed.intent });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Asistan sorgusu işlenirken bir hata oluştu.' });
  }
}));

// GET /api/assistant/history
// Kullanıcının kendi sohbet geçmişini (son 50 mesaj, kronolojik sırada) döner.
router.get('/history', (req, res) => {
  try {
    const rows = db
      .prepare(
        `SELECT * FROM (
           SELECT id, role, message, created_at FROM chat_messages
           WHERE user_id = ? ORDER BY id DESC LIMIT 50
         ) ORDER BY id ASC`
      )
      .all(req.user.id);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Sohbet geçmişi alınırken bir hata oluştu.' });
  }
});

module.exports = router;
