// middleware/auth.js fonksiyonlarını gerçek bir Express sunucusu OLMADAN
// (server.js/supertest kullanmadan) doğrudan çağırabilmek için sahte
// req/res/next nesneleri. node:test'in yerleşik mock.fn() yardımcısı,
// Jest'teki jest.fn()'e denk gelir (bkz. test/unit/authMiddleware.test.js).
const { mock } = require('node:test');

function createMockReq(headers = {}) {
  return { headers, user: undefined };
}

function createMockRes() {
  const res = {};
  res.statusCode = null;
  res.jsonBody = null;
  res.status = mock.fn((code) => {
    res.statusCode = code;
    return res;
  });
  res.json = mock.fn((body) => {
    res.jsonBody = body;
    return res;
  });
  return res;
}

function createMockNext() {
  return mock.fn();
}

module.exports = { createMockReq, createMockRes, createMockNext };
