// SEC-05: Express 4.x (bkz. package.json), async route handler'larda
// fırlatılan hataları/reddedilen Promise'leri OTOMATİK yakalamaz — bir
// handler `async (req, res) => { throw ... }` şeklindeyse ve kendi try/catch
// bloğu yoksa, bu bir "unhandled promise rejection" olur: istek sessizce
// asılı kalabilir VEYA (Node'un sürümüne göre) tüm süreç çökebilir. Bu
// wrapper, her async handler'ı `Promise.resolve(...).catch(next)` ile sarar —
// böylece herhangi bir hata GÜVENİLİR şekilde Express'in hata işleme
// zincirine (middleware/errorHandler.js) ulaşır.
//
// (Express 5.x kullanılıyor olsaydı bu sarmalayıcıya gerek kalmazdı — orada
// async handler hataları otomatik olarak next(err)'e yönlendirilir.)
function asyncHandler(fn) {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

module.exports = { asyncHandler };
