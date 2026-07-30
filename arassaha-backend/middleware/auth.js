// Kimlik doğrulama / yetkilendirme middleware'leri (Modül 7 — Auth + RBAC).
//
// verifyToken: Authorization: Bearer <token> header'ını okur, JWT_SECRET ile
// doğrular, geçerliyse req.user = { id, role } ekler ve next() çağırır.
// Geçersiz/eksikse 401 döner — /api/auth/login HARİÇ tüm route'lar buradan geçer
// (bkz. server.js).
//
// requireRole(...roles): verifyToken'dan SONRA kullanılan bir middleware
// fabrikası; req.user.role belirtilen rollerden biri değilse 403 döner.
const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET;

function verifyToken(req, res, next) {
  const authHeader = req.headers.authorization || '';
  const [scheme, token] = authHeader.split(' ');

  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({ error: 'Yetkisiz erişim. Lütfen giriş yapın.' });
  }

  try {
    const payload = jwt.verify(token, JWT_SECRET);
    req.user = { id: payload.id, role: payload.role };
    next();
  } catch {
    return res.status(401).json({ error: 'Oturum süresi doldu veya geçersiz. Lütfen tekrar giriş yapın.' });
  }
}

function requireRole(...allowedRoles) {
  return (req, res, next) => {
    if (!req.user || !allowedRoles.includes(req.user.role)) {
      return res.status(403).json({ error: 'Bu işlem için yetkiniz yok.' });
    }
    next();
  };
}

module.exports = { verifyToken, requireRole, JWT_SECRET };
